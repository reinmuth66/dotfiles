import Darwin
import Foundation

// プロセスの収集。btm が使う sysinfo クレート (0.39、macOS) の処理を、同じ式で移したもの
// (sysinfo の src/unix/apple/macos/process.rs と system.rs、btm の src/collection/processes)。
// 名前・CPU%・メモリ・状態・ユーザー・経過時間が、btm の表と同じ値になるようにしている。
// 毎秒の更新で、プロセスごとに前回の値を持つ (CPU% は、前回からの増分で出す)。

struct ProcessHarvest {
    var pid: Int32
    var parentPid: Int32?
    var name: String
    var cpuPercent: Float
    var memory: UInt64
    /// "Runnable"、"Sleeping" など (btm の表示)
    var state: String
    var user: String?
    /// 経過時間 (秒)。btm の Time 列
    var time: UInt64
}

private enum ProcStatus: Equatable {
    case idle, run, sleep, stop, zombie, dead, parked
    case unknown

    /// pbi_status (SIDL = 1、SRUN = 2、SSLEEP = 3、SSTOP = 4、SZOMB = 5)
    init(bsd status: UInt32) {
        switch status {
        case 1: self = .idle
        case 2: self = .run
        case 3: self = .sleep
        case 4: self = .stop
        case 5: self = .zombie
        default: self = .unknown
        }
    }

    /// スレッドの状態 (TH_STATE_RUNNING = 1、STOPPED = 2、WAITING = 3、UNINTERRUPTIBLE = 4、HALTED = 5)
    init(thread state: Int32) {
        switch state {
        case 1: self = .run
        case 2: self = .stop
        case 3: self = .sleep
        case 4: self = .dead
        case 5: self = .parked
        default: self = .unknown
        }
    }

    /// btm (macOS) の process_status_str
    var text: String {
        switch self {
        case .idle: return "Idle"
        case .run: return "Runnable"
        case .sleep: return "Sleeping"
        case .stop: return "Stopped"
        case .zombie: return "Zombie"
        default: return "Unknown"
        }
    }
}

private struct Entry {
    var pid: Int32
    var parent: Int32?
    var name: String
    var startTime: UInt64
    var runTime: UInt64
    var processStatus: ProcStatus
    /// スレッドの状態。権限が無いなどで読めていないときは nil
    var threadStatus: ProcStatus?
    var uid: UInt32?
    var memory: UInt64
    var cpu: Float
    /// 前回の user + system の時間 (mach の時間の単位)
    var oldTime: UInt64
    var updated: Bool

    /// sysinfo の status()。pbi_status が Run のときは、それが当てにならないので、スレッドの状態を使う
    var status: ProcStatus {
        if processStatus == .run, let thread = threadStatus { return thread }
        return processStatus
    }
}

/// sysinfo の SystemTimeInfo。全コアの tick の増分から、プロセスの CPU 時間を割る「経過時間」を、mach の時間の単位で出す
private final class ClockInfo {
    private static let minimumInterval = 0.2  // MINIMUM_CPU_UPDATE_INTERVAL (秒)
    private let timebaseToNs: Double
    private let clockPerSec: Double
    private var old: [[UInt32]]
    private var lastUpdate: Date?
    private var previousInterval: Double = 0

    init() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        timebaseToNs = Double(tb.numer) / Double(tb.denom)
        clockPerSec = 1_000_000_000 / Double(sysconf(_SC_CLK_TCK))
        old = ClockInfo.ticks()
    }

    private static func ticks() -> [[UInt32]] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
            == KERN_SUCCESS, let info
        else { return [] }
        let states = Int(CPU_STATE_MAX)
        var out: [[UInt32]] = []
        for i in 0..<Int(count) {
            out.append((0..<states).map { UInt32(bitPattern: info[i * states + $0]) })
        }
        vm_deallocate(
            mach_task_self_, vm_address_t(bitPattern: info),
            vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        return out
    }

    func interval() -> Double {
        let needUpdate = lastUpdate.map { Date().timeIntervalSince($0) >= Self.minimumInterval } ?? true
        if !needUpdate { return previousInterval }
        let new = Self.ticks()
        if new.isEmpty { return 0 }
        let cpuCount = min(old.count, new.count)
        var total: UInt64 = 0
        for i in 0..<cpuCount {
            for (n, o) in zip(new[i], old[i]) where n > o { total += UInt64(n - o) }
        }
        old = new
        lastUpdate = Date()
        let base = Double(total) / Double(max(cpuCount, 1)) * clockPerSec
        let smallest = Self.minimumInterval * 1_000_000_000
        previousInterval = base < smallest ? smallest : base / timebaseToNs
        return previousInterval
    }
}

final class ProcessCollector {
    private var entries: [Int32: Entry] = [:]
    private let clock = ClockInfo()
    private let cpuCount: Int
    private var users: [UInt32: String?] = [:]

    init() {
        cpuCount = ProcessInfo.processInfo.processorCount
    }

    // MARK: - OS の呼び出し

    private func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    private func taskInfo(_ pid: Int32) -> proc_taskinfo {
        var info = proc_taskinfo()
        _ = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
        return info
    }

    /// 実行ファイルのファイル名 (sysinfo の name)。KERN_PROCARGS2 の exec_path から取る
    private func nameFromArgs(_ pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) == -1 || size <= MemoryLayout<Int32>.size { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        if sysctl(&mib, 3, &buffer, &size, nil, 0) == -1 { return nil }
        let path = buffer[MemoryLayout<Int32>.size..<size].prefix { $0 != 0 }
        return fileName(String(decoding: path, as: UTF8.self))
    }

    /// proc_pidpath から取る名前 (sysinfo の get_exe_and_name_backup)
    private func nameFromPath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))  // PROC_PIDPATHINFO_MAXSIZE
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if n <= 0 { return nil }
        return fileName(String(cString: buffer))
    }

    private func fileName(_ path: String) -> String? {
        let name = path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init)
        return name
    }

    private func userName(_ uid: UInt32) -> String? {
        if let cached = users[uid] { return cached }
        var name: String?
        if let pw = getpwuid(uid) { name = String(cString: pw.pointee.pw_name) }
        users[uid] = name
        return name
    }

    // MARK: - 更新 (sysinfo の update_process / create_new_process)

    private func create(_ pid: Int32, now: UInt64, info: proc_bsdinfo?) -> Entry? {
        guard let info else {
            // BSD の情報が読めないプロセス (権限が無い)。名前だけでも取れれば、残す
            guard let name = nameFromPath(pid) else { return nil }
            return Entry(
                pid: pid, parent: nil, name: name, startTime: 0, runTime: 0, processStatus: .unknown,
                threadStatus: nil, uid: nil, memory: 0, cpu: 0, oldTime: 0, updated: true)
        }
        let startTime = UInt64(info.pbi_start_tvsec)
        guard let name = nameFromArgs(pid) ?? nameFromPath(pid) else { return nil }
        let task = taskInfo(pid)
        return Entry(
            pid: pid, parent: info.pbi_ppid == 0 ? nil : Int32(bitPattern: info.pbi_ppid), name: name,
            startTime: startTime, runTime: now >= startTime ? now - startTime : 0,
            processStatus: ProcStatus(bsd: info.pbi_status), threadStatus: nil, uid: info.pbi_ruid,
            memory: task.pti_resident_size, cpu: 0, oldTime: task.pti_total_system &+ task.pti_total_user,
            updated: true)
    }

    private func update(_ entry: inout Entry, now: UInt64, interval: Double) -> Bool {
        let pid = entry.pid
        if let info = bsdInfo(pid) {
            if UInt64(info.pbi_start_tvsec) != entry.startTime {
                // pid が別のプロセスに使い回された。作り直す
                guard let fresh = create(pid, now: now, info: info) else { return false }
                entry = fresh
                return true
            }
            entry.parent = info.pbi_ppid == 0 ? nil : Int32(bitPattern: info.pbi_ppid)
        } else if nameFromPath(pid) == nil {
            return false  // もう存在しない
        }

        var thread = proc_threadinfo()
        if proc_pidinfo(pid, PROC_PIDTHREADINFO, 0, &thread, Int32(MemoryLayout<proc_threadinfo>.size)) != 0 {
            entry.threadStatus = ProcStatus(thread: thread.pth_run_state)
        } else {
            entry.threadStatus = .run
        }
        entry.runTime = now >= entry.startTime ? now - entry.startTime : 0

        let task = taskInfo(pid)
        let existing = entry.oldTime
        if interval > 0.000001 && existing > 0 {
            let current = task.pti_total_system &+ task.pti_total_user
            let diff = current > existing ? current - existing : 0
            if diff > 0 { entry.cpu = Float(Double(diff) / interval * 100) }
        }
        entry.oldTime = task.pti_total_system &+ task.pti_total_user
        entry.memory = task.pti_resident_size
        return true
    }

    /// 全プロセスを更新する
    func refresh() {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return }
        var pids = [Int32](repeating: 0, count: Int(count))
        let filled = proc_listallpids(&pids, count * Int32(MemoryLayout<Int32>.size))
        guard filled > 0, Int(filled) < pids.count else { return }
        pids = Array(pids.prefix(Int(filled)))

        let now = UInt64(Date().timeIntervalSince1970)
        let interval = clock.interval()
        var next: [Int32: Entry] = [:]
        next.reserveCapacity(pids.count)
        for pid in pids {
            if var entry = entries[pid] {
                if update(&entry, now: now, interval: interval) { next[pid] = entry }
            } else if let entry = create(pid, now: now, info: bsdInfo(pid)) {
                next[pid] = entry
            }
        }
        entries = next
    }

    // MARK: - btm の ProcessHarvest

    /// sysctl (kern.proc.pid) から読む親の pid。sysinfo が親を取れなかったときの、btm の代替
    private func fallbackParent(_ pid: Int32) -> Int32? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        if sysctl(&mib, 4, &info, &size, nil, 0) != 0 || size == 0 { return nil }
        return info.kp_eproc.e_ppid
    }

    /// 状態が Unknown のプロセスの CPU% は、btm と同じく ps の pcpu から取る
    private func psCpu(_ pids: [Int32]) -> [Int32: Float] {
        if pids.isEmpty { return [:] }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "pid=,pcpu=", "-p", pids.map(String.init).joined(separator: ",")]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let fields = String(decoding: data, as: UTF8.self).split(whereSeparator: { $0 == " " || $0 == "\n" })
        var out: [Int32: Float] = [:]
        var i = 0
        while i + 1 < fields.count {
            if let pid = Int32(fields[i]), let usage = Float(fields[i + 1]) { out[pid] = usage }
            i += 2
        }
        return out
    }

    func harvest() -> [ProcessHarvest] {
        let processors = Float(max(cpuCount, 1))
        var list: [ProcessHarvest] = []
        list.reserveCapacity(entries.count)
        for entry in entries.values {
            list.append(
                ProcessHarvest(
                    pid: entry.pid, parentPid: entry.parent ?? fallbackParent(entry.pid), name: entry.name,
                    cpuPercent: entry.cpu / processors, memory: entry.memory, state: entry.status.text,
                    user: entry.uid.flatMap(userName), time: entry.startTime == 0 ? 0 : entry.runTime))
        }
        let unknown = list.filter { $0.state == "Unknown" }.map(\.pid)
        let usages = psCpu(unknown)
        for i in list.indices {
            if let usage = usages[list[i].pid] { list[i].cpuPercent = usage / processors }
        }
        return list
    }
}
