#include "sketchybar.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach_host.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/mount.h>
#include <sys/sysctl.h>
#include <sys/time.h>

// CPU・メモリ・スワップ・ネットワーク・ディスクの使用状況と I/Oを一定間隔で測り、
// SketchyBar の system_stats イベントに環境変数として渡す。
// 測定はカーネルの API を直接呼ぶだけで、プロセスを起動しない。
// 描画や書式は Lua (items/system.lua) が決めるので、ここでは生の値だけを送る。

#define INTERVAL 1.0
// タイマーの許容誤差 (秒)。割り込みをまとめて、省電力にする
#define TOLERANCE 0.2
// ディスクの空き容量を測るボリューム。APFS のコンテナ (ディスク全体) の空きが取れる
#define DISK_PATH "/System/Volumes/Data"
// ネットワークの interface の index の上限 (これより大きい index は数えない)
#define MAX_IFACES 256
// 数える interface (en*) の一覧を作り直す間隔 (秒)。新しく現れた interface は、最大でこの間隔だけ遅れて数え始める
#define NET_REFRESH_INTERVAL 30.0
// ストレージのドライバ (内蔵 SSD、外付けディスク、ディスクイメージ) の数の上限
#define MAX_DRIVES 32

static mach_port_t host;
static vm_size_t page_size;
static uint64_t mem_total;

static uint64_t cpu_prev_busy;
static uint64_t cpu_prev_sys;
static uint64_t cpu_prev_total;

static uint64_t net_prev_rx[MAX_IFACES];
static uint64_t net_prev_tx[MAX_IFACES];
static bool net_has_prev[MAX_IFACES];
static unsigned net_indexes[MAX_IFACES];
static int net_index_count;
static double net_indexes_at;

// ストレージのドライバごとの、前回の累計バイト数
static struct {
  uint64_t id;
  uint64_t read;
  uint64_t written;
  bool seen;
} disk_prev[MAX_DRIVES];
static int disk_prev_count;

static double prev_time;

static double now(void) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return tv.tv_sec + tv.tv_usec / 1e6;
}

// 前回からの CPU 使用率 (0〜100)。全コアの tick の合計から、busy / total を出す。
// usage は user + sys + nice の合計、sys はそのうちカーネルの処理 (system) の分。
// どちらも全 CPU 時間 (idle を含む) で割るので、sys は usage 以下になる。
static void cpu_usage(double *usage, double *sys) {
  *usage = *sys = 0;

  natural_t count;
  processor_info_array_t info;
  mach_msg_type_number_t info_count;
  if (host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info,
                          &info_count) != KERN_SUCCESS)
    return;

  processor_cpu_load_info_t load = (processor_cpu_load_info_t)info;
  uint64_t busy = 0, system_ticks = 0, total = 0;
  for (natural_t i = 0; i < count; i++) {
    uint64_t user = load[i].cpu_ticks[CPU_STATE_USER];
    uint64_t system = load[i].cpu_ticks[CPU_STATE_SYSTEM];
    uint64_t nice = load[i].cpu_ticks[CPU_STATE_NICE];
    uint64_t idle = load[i].cpu_ticks[CPU_STATE_IDLE];
    busy += user + system + nice;
    system_ticks += system;
    total += user + system + nice + idle;
  }
  vm_deallocate(mach_task_self(), (vm_address_t)info,
                info_count * sizeof(integer_t));

  if (total > cpu_prev_total && busy >= cpu_prev_busy &&
      system_ticks >= cpu_prev_sys) {
    double elapsed = (double)(total - cpu_prev_total);
    *usage = 100.0 * (busy - cpu_prev_busy) / elapsed;
    *sys = 100.0 * (system_ticks - cpu_prev_sys) / elapsed;
  }
  cpu_prev_busy = busy;
  cpu_prev_sys = system_ticks;
  cpu_prev_total = total;
}

// アクティビティモニタの「使用メモリ」と同じ内訳: アプリ + 確保済み + 圧縮
static uint64_t memory_used(void) {
  vm_statistics64_data_t vm;
  mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
  if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count) !=
      KERN_SUCCESS)
    return 0;

  uint64_t pages = (uint64_t)(vm.internal_page_count - vm.purgeable_count) +
                   vm.wire_count + vm.compressor_page_count;
  return pages * page_size;
}

// メモリ圧力 (1: normal、2: warn、4: critical)。memory_pressure コマンドと同じカーネルの値で、プロセスを起動せずに読める。
// 読めなかったときは 0
static int memory_pressure(void) {
  int level = 0;
  size_t length = sizeof(level);
  if (sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &length, NULL, 0) != 0)
    return 0;
  return level;
}

static void swap_usage(uint64_t *used, uint64_t *total) {
  struct xsw_usage swap;
  size_t length = sizeof(swap);
  *used = *total = 0;
  if (sysctlbyname("vm.swapusage", &swap, &length, NULL, 0) != 0)
    return;
  *used = swap.xsu_used;
  *total = swap.xsu_total;
}

// df と同じ値 (空きブロック数 x ブロックサイズ)。macOS の「消せるキャッシュ」は空きに含めない
static void disk_usage(uint64_t *free_bytes, uint64_t *total_bytes) {
  struct statfs fs;
  *free_bytes = *total_bytes = 0;
  if (statfs(DISK_PATH, &fs) != 0)
    return;
  *free_bytes = (uint64_t)fs.f_bavail * fs.f_bsize;
  *total_bytes = (uint64_t)fs.f_blocks * fs.f_bsize;
}

// 数える interface (en*) の index の一覧を作り直す。
// VPN (utun) やブリッジは、同じ通信を二重に数えるので除く。稼働中かどうかは、測るときに見る。
static void refresh_net_indexes(double current) {
  net_indexes_at = current;
  net_index_count = 0;
  struct if_nameindex *list = if_nameindex();
  if (!list)
    return;
  for (struct if_nameindex *p = list; p->if_index != 0; p++) {
    if (p->if_index < MAX_IFACES && strncmp(p->if_name, "en", 2) == 0 &&
        net_index_count < MAX_IFACES)
      net_indexes[net_index_count++] = p->if_index;
  }
  if_freenameindex(list);
}

// 稼働中の物理 interface (en*) の送受信バイト数の、前回からの増分を足す。
// interface ごとに前回値を持ち、途中で現れた interface の累計値が急増分にならないようにする。
// 1 つずつ sysctl (IFMIB) で読む。全 interface を一括で取る方法 (NET_RT_IFLIST2) は、interface が多いと
// 重く (19 個で約 200 us。IFMIB は 1 つ約 0.5 us)、IFMIB の統計は 64 ビットなので折り返さない。
static void network_delta(uint64_t *rx, uint64_t *tx) {
  *rx = *tx = 0;

  double current = now();
  if (net_indexes_at == 0 || current - net_indexes_at >= NET_REFRESH_INTERVAL)
    refresh_net_indexes(current);

  for (int i = 0; i < net_index_count; i++) {
    unsigned index = net_indexes[i];
    struct ifmibdata data;
    size_t length = sizeof(data);
    int mib[6] = {CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, (int)index,
                  IFDATA_GENERAL};
    // 取り外された interface や、index が別の interface に使い回されたものは、前回値を捨てる
    if (sysctl(mib, 6, &data, &length, NULL, 0) != 0 ||
        strncmp(data.ifmd_name, "en", 2) != 0 || !(data.ifmd_flags & IFF_UP)) {
      net_has_prev[index] = false;
      continue;
    }

    uint64_t in = data.ifmd_data.ifi_ibytes;
    uint64_t out = data.ifmd_data.ifi_obytes;
    if (net_has_prev[index]) {
      if (in >= net_prev_rx[index])
        *rx += in - net_prev_rx[index];
      if (out >= net_prev_tx[index])
        *tx += out - net_prev_tx[index];
    }
    net_prev_rx[index] = in;
    net_prev_tx[index] = out;
    net_has_prev[index] = true;
  }
}

static uint64_t cf_number(CFDictionaryRef dict, CFStringRef key) {
  int64_t value = 0;
  CFNumberRef number = CFDictionaryGetValue(dict, key);
  if (number)
    CFNumberGetValue(number, kCFNumberSInt64Type, &value);
  return value > 0 ? (uint64_t)value : 0;
}

// ストレージのドライバ (IOBlockStorageDriver) すべての、読み書きのバイト数の、前回からの増分を足す
// (内蔵 SSD のほか、外付けディスクやディスクイメージも合計に入る)。
// 値はデバイスに届いた量で、アプリの read / write の量ではない (ページキャッシュを通った分は含まない)。
// ドライバごとに前回値を持ち、途中で現れたドライバの累計値が急増分にならないようにする。
static void disk_io_delta(uint64_t *read, uint64_t *written) {
  *read = *written = 0;

  io_iterator_t iterator;
  if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                   IOServiceMatching("IOBlockStorageDriver"),
                                   &iterator) != KERN_SUCCESS)
    return;

  for (int i = 0; i < disk_prev_count; i++)
    disk_prev[i].seen = false;

  io_object_t driver;
  while ((driver = IOIteratorNext(iterator))) {
    uint64_t id;
    CFDictionaryRef stats = IORegistryEntryCreateCFProperty(
        driver, CFSTR("Statistics"), kCFAllocatorDefault, 0);
    if (stats && IORegistryEntryGetRegistryEntryID(driver, &id) == KERN_SUCCESS) {
      uint64_t in = cf_number(stats, CFSTR("Bytes (Read)"));
      uint64_t out = cf_number(stats, CFSTR("Bytes (Write)"));
      int slot = -1;
      for (int i = 0; i < disk_prev_count; i++) {
        if (disk_prev[i].id == id) {
          slot = i;
          break;
        }
      }
      if (slot >= 0) {
        if (in >= disk_prev[slot].read)
          *read += in - disk_prev[slot].read;
        if (out >= disk_prev[slot].written)
          *written += out - disk_prev[slot].written;
      } else if (disk_prev_count < MAX_DRIVES) {
        slot = disk_prev_count++;
        disk_prev[slot].id = id;
      }
      if (slot >= 0) {
        disk_prev[slot].read = in;
        disk_prev[slot].written = out;
        disk_prev[slot].seen = true;
      }
    }
    if (stats)
      CFRelease(stats);
    IOObjectRelease(driver);
  }
  IOObjectRelease(iterator);

  // なくなったドライバ (取り外したディスクなど) の前回値を捨てる
  int kept = 0;
  for (int i = 0; i < disk_prev_count; i++) {
    if (disk_prev[i].seen)
      disk_prev[kept++] = disk_prev[i];
  }
  disk_prev_count = kept;
}

static void sample(CFRunLoopTimerRef timer, void *info) {
  double current = now();
  double elapsed = current - prev_time;
  prev_time = current;
  if (elapsed <= 0)
    elapsed = INTERVAL;

  double cpu, cpu_sys;
  cpu_usage(&cpu, &cpu_sys);
  uint64_t mem_used = memory_used();
  uint64_t swap_used, swap_total;
  swap_usage(&swap_used, &swap_total);
  int pressure = memory_pressure();
  uint64_t rx, tx;
  network_delta(&rx, &tx);
  uint64_t disk_read, disk_written;
  disk_io_delta(&disk_read, &disk_written);
  uint64_t disk_free, disk_total;
  disk_usage(&disk_free, &disk_total);

  char message[640];
  snprintf(message, sizeof(message),
           "--trigger system_stats CPU=%.1f CPU_SYS=%.1f RAM=%.1f "
           "RAM_USED=%llu RAM_TOTAL=%llu SWAP_USED=%llu SWAP_TOTAL=%llu "
           "MEM_PRESSURE=%d "
           "NET_RX=%.0f NET_TX=%.0f DISK_READ=%.0f DISK_WRITE=%.0f "
           "DISK_FREE=%llu DISK_TOTAL=%llu",
           cpu, cpu_sys, mem_total ? 100.0 * mem_used / mem_total : 0.0,
           mem_used,
           mem_total, swap_used, swap_total, pressure, rx / elapsed, tx / elapsed,
           disk_read / elapsed, disk_written / elapsed, disk_free, disk_total);
  sketchybar(message);
}

int main(void) {
  host = mach_host_self();
  host_page_size(host, &page_size);
  size_t length = sizeof(mem_total);
  sysctlbyname("hw.memsize", &mem_total, &length, NULL, 0);

  // 最初の測定は基準値を取るだけ (増分が要る CPU・ネットワーク・ディスク I/O は、2 回目から意味を持つ)
  double cpu_first, cpu_sys_first;
  cpu_usage(&cpu_first, &cpu_sys_first);
  uint64_t rx, tx;
  network_delta(&rx, &tx);
  uint64_t disk_read, disk_written;
  disk_io_delta(&disk_read, &disk_written);
  prev_time = now();

  CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
      kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + INTERVAL, INTERVAL, 0,
      0, sample, NULL);
  CFRunLoopTimerSetTolerance(timer, TOLERANCE);
  CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopDefaultMode);
  CFRelease(timer);
  CFRunLoopRun();
  return 0;
}
