import Darwin
import Foundation

// sketchybar-system-helper (config/sketchybar/helper/system.c) が毎秒書く、履歴のファイルの読み取り側。
// ファイルのレイアウトは helper/history.h と同じ (構造体を変えたら、両方を直して、version を上げる)。
// ファイルを mmap して、直近のサンプルを写す。helper が書いている最中に読んでも壊れないよう、
// count を読んで、写して、もう一度 count を読み、書き込みと重なっていないか確かめる。

struct Sample {
    var time: Double
    /// 全コアの使用率の平均 (%)
    var cpu: Double
    var cores: [Double]
    var ramUsed: UInt64
    var ramTotal: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    /// 速度 (bit/s)
    var netRx: UInt64
    var netTx: UInt64
    /// 累計 (bit)
    var netTotalRx: UInt64
    var netTotalTx: UInt64
    /// ディスク I/O の速度 (byte/s)。取れなかったときは負
    var diskRead: Int64
    var diskWritten: Int64
    var diskFree: UInt64
    var diskUsed: UInt64
    var diskTotal: UInt64
}

final class History {
    private static let magic: UInt64 = 0x3159_544f_4d53_5953
    private static let version: UInt32 = 1
    private static let headerSize = 64
    private static let sampleSize = 384
    private static let maxCores = 32

    private let base: UnsafeRawPointer
    private let capacity: Int

    /// 履歴のファイルを開く。無いとき、形式が合わないときは nil
    init?() {
        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return nil }
        let path = home + "/Library/Caches/sketchybar/system/history.bin"
        let fd = open(path, O_RDONLY)
        if fd < 0 { return nil }
        defer { close(fd) }
        var info = stat()
        if fstat(fd, &info) != 0 || Int(info.st_size) < Self.headerSize { return nil }
        guard let map = mmap(nil, Int(info.st_size), PROT_READ, MAP_SHARED, fd, 0), map != MAP_FAILED
        else { return nil }
        let raw = UnsafeRawPointer(map)
        guard raw.load(fromByteOffset: 0, as: UInt64.self) == Self.magic,
            raw.load(fromByteOffset: 8, as: UInt32.self) == Self.version,
            raw.load(fromByteOffset: 16, as: UInt32.self) == UInt32(Self.sampleSize)
        else {
            munmap(map, Int(info.st_size))
            return nil
        }
        let capacity = Int(raw.load(fromByteOffset: 12, as: UInt32.self))
        if Self.headerSize + capacity * Self.sampleSize > Int(info.st_size) {
            munmap(map, Int(info.st_size))
            return nil
        }
        base = raw
        self.capacity = capacity
    }

    private func count() -> UInt64 {
        OSMemoryBarrier()
        return base.load(fromByteOffset: 24, as: UInt64.self)
    }

    private func sample(at index: Int) -> Sample {
        let p = base + Self.headerSize + index * Self.sampleSize
        func u64(_ o: Int) -> UInt64 { p.load(fromByteOffset: o, as: UInt64.self) }
        let coreCount = min(Int(p.load(fromByteOffset: 376, as: UInt32.self)), Self.maxCores)
        let cores = (0..<coreCount).map { p.load(fromByteOffset: 16 + $0 * 8, as: Double.self) }
        return Sample(
            time: p.load(fromByteOffset: 0, as: Double.self),
            cpu: p.load(fromByteOffset: 8, as: Double.self),
            cores: cores,
            ramUsed: u64(272), ramTotal: u64(280), swapUsed: u64(288), swapTotal: u64(296),
            netRx: u64(304), netTx: u64(312), netTotalRx: u64(320), netTotalTx: u64(328),
            diskRead: Int64(bitPattern: u64(336)), diskWritten: Int64(bitPattern: u64(344)),
            diskFree: u64(352), diskUsed: u64(360), diskTotal: u64(368))
    }

    /// 直近 limit 個までのサンプル (古い順)。空のとき (helper を起動した直後など) は空の配列
    func recent(limit: Int) -> [Sample] {
        let n = min(limit, capacity - 8)
        for _ in 0..<4 {
            let before = count()
            let available = min(Int(before), n)
            var out: [Sample] = []
            out.reserveCapacity(available)
            for i in 0..<available {
                let index = Int((before - UInt64(available) + UInt64(i)) % UInt64(capacity))
                out.append(sample(at: index))
            }
            // 読んでいる間に、書き込みが読んだ範囲に追いついていなければ、そのまま使える
            let after = count()
            if after >= before && after - before < 4 { return out }
        }
        return []
    }
}
