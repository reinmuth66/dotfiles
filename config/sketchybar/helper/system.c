#include "sketchybar.h"
#include "history.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOBSD.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach_host.h>
#include <math.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <fcntl.h>
#include <pwd.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/statvfs.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

// CPU・メモリ・スワップ・ネットワーク・ディスクの使用状況と I/Oを一定間隔で測り、
// SketchyBar の system_stats イベントに環境変数として渡す。
// 測定はカーネルの API を直接呼ぶだけで、プロセスを起動しない。
// 描画や書式は Lua (items/system.lua) が決めるので、ここでは生の値だけを送る。
//
// 値の測り方は bottom (btm) に合わせて、popup の数字が btm と一致するようにしている
// (btm が使う sysinfo クレートの macOS 実装と同じ式)。
// 同じ値を、履歴のファイルにも書く (history.h)。pkgs/system-monitor は、これを読んでグラフの履歴を描く。

#define INTERVAL 1.0
// タイマーの許容誤差 (秒)。割り込みをまとめて、省電力にする
#define TOLERANCE 0.2
// ディスクの空き容量と I/O を測るボリューム (btm の disk widget は "/" だけを表示する設定)。APFS のコンテナ (ディスク全体) の空きが取れる
#define DISK_PATH "/"
// CPU のコアの数の上限
#define MAX_CPUS 256

static mach_port_t host;
static vm_size_t page_size;
static uint64_t mem_total;

// コアごとの、前回の tick (busy は user + system + nice)。sysinfo と同じく i32 の tick を i64 で足す
static int64_t cpu_prev_busy[MAX_CPUS];
static int32_t cpu_prev_idle[MAX_CPUS];
static bool cpu_has_prev;
// 直近の測定のコアごとの使用率 (履歴に書く)
static float cpu_core_usage[MAX_CPUS];
static natural_t cpu_core_count;

// 全 interface の送受信の累計 (bit) の、前回の合計と、直近の合計
static uint64_t net_prev_rx;
static uint64_t net_prev_tx;
static uint64_t net_total_rx;
static uint64_t net_total_tx;

// btm の disk I/O は、"/" のディスク (disk3s1s1 なら disk3) の親の Statistics を読む。前回の累計バイト数
static bool io_has_prev;
static uint64_t io_prev_read;
static uint64_t io_prev_written;

static double prev_time;

static double now(void) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return tv.tv_sec + tv.tv_usec / 1e6;
}

// 前回からの CPU 使用率 (0〜100)。sysinfo の global_cpu_usage と同じく、コアごとの使用率
// (busy / (busy + idle)。f32) を出して、その平均を取る。全コアの tick を合計して割るのとは、わずかに値が違う。
static float cpu_usage(void) {
  natural_t count;
  processor_info_array_t info;
  mach_msg_type_number_t info_count;
  if (host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info,
                          &info_count) != KERN_SUCCESS)
    return 0;

  processor_cpu_load_info_t load = (processor_cpu_load_info_t)info;
  float sum = 0;
  natural_t used = count < MAX_CPUS ? count : MAX_CPUS;
  cpu_core_count = used;
  for (natural_t i = 0; i < used; i++) {
    int64_t busy = (int64_t)(int32_t)load[i].cpu_ticks[CPU_STATE_USER] +
                   (int32_t)load[i].cpu_ticks[CPU_STATE_SYSTEM] +
                   (int32_t)load[i].cpu_ticks[CPU_STATE_NICE];
    int32_t idle = (int32_t)load[i].cpu_ticks[CPU_STATE_IDLE];
    if (cpu_has_prev) {
      int64_t in_use = busy - cpu_prev_busy[i];
      int64_t total = in_use + ((int64_t)idle - cpu_prev_idle[i]);
      float usage = (float)in_use / (float)total * 100.0f;
      if (usage != usage) // NaN (total が 0) は 0 にする
        usage = 0;
      sum += usage;
      cpu_core_usage[i] = usage;
    }
    cpu_prev_busy[i] = busy;
    cpu_prev_idle[i] = idle;
  }
  cpu_has_prev = true;
  vm_deallocate(mach_task_self(), (vm_address_t)info,
                info_count * sizeof(integer_t));
  return sum / (float)count;
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
  *used = swap.xsu_total - swap.xsu_avail; // sysinfo の used_swap と同じ
  *total = swap.xsu_total;
}

// btm の disk widget の Free / Total と同じ値 (statvfs の空きブロック数 x ブロックサイズ)。
// macOS の「消せるキャッシュ」は空きに含めない
// 使用量 (Used) は、btm と同じく総量 - f_bfree x f_frsize
static void disk_usage(uint64_t *free_bytes, uint64_t *used_bytes, uint64_t *total_bytes) {
  struct statvfs fs;
  *free_bytes = *used_bytes = *total_bytes = 0;
  if (statvfs(DISK_PATH, &fs) != 0)
    return;
  *free_bytes = (uint64_t)fs.f_bavail * fs.f_frsize;
  *total_bytes = (uint64_t)fs.f_blocks * fs.f_frsize;
  *used_bytes = *total_bytes - (uint64_t)fs.f_bfree * fs.f_frsize;
}

// すべての interface (lo0 や VPN の utun も含む) の送受信バイト数の合計。btm (sysinfo) と同じ。
// 1 つずつ sysctl (IFMIB) で読む。全 interface を一括で取る方法 (NET_RT_IFLIST2) は、interface が多いと
// 重く (19 個で約 200 us。IFMIB は 1 つ約 0.5 us)、IFMIB の統計は 64 ビットなので折り返さない。
static void network_totals(uint64_t *rx, uint64_t *tx) {
  *rx = *tx = 0;

  struct if_nameindex *list = if_nameindex();
  if (!list)
    return;
  for (struct if_nameindex *p = list; p->if_index != 0; p++) {
    struct ifmibdata data;
    size_t length = sizeof(data);
    int mib[6] = {CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA,
                  (int)p->if_index, IFDATA_GENERAL};
    if (sysctl(mib, 6, &data, &length, NULL, 0) != 0)
      continue;
    *rx += data.ifmd_data.ifi_ibytes;
    *tx += data.ifmd_data.ifi_obytes;
  }
  if_freenameindex(list);
}

// 前回からの、受信・送信の速度 (bit/s。小数点以下は切り捨て)。btm と同じく、合計 (bit) の増分を経過時間で割る。
// 合計が減ったとき (interface が取り外されたときなど) は 0
static void network_rate(double elapsed, uint64_t *rx, uint64_t *tx) {
  uint64_t total_rx, total_tx;
  network_totals(&total_rx, &total_tx);
  total_rx *= 8;
  total_tx *= 8;
  *rx = total_rx > net_prev_rx ? (uint64_t)((total_rx - net_prev_rx) / elapsed) : 0;
  *tx = total_tx > net_prev_tx ? (uint64_t)((total_tx - net_prev_tx) / elapsed) : 0;
  net_prev_rx = net_total_rx = total_rx;
  net_prev_tx = net_total_tx = total_tx;
}

static uint64_t cf_number(CFDictionaryRef dict, CFStringRef key) {
  int64_t value = 0;
  CFNumberRef number = CFDictionaryGetValue(dict, key);
  if (number)
    CFNumberGetValue(number, kCFNumberSInt64Type, &value);
  return value > 0 ? (uint64_t)value : 0;
}

// DISK_PATH の device (/dev/disk3s1s1) から、btm と同じく正規表現 disk\d+ で最初に合う部分 (disk3) を取り出す
static bool root_disk_name(char *out, size_t size) {
  struct statfs fs;
  if (statfs(DISK_PATH, &fs) != 0)
    return false;
  const char *base = strrchr(fs.f_mntfromname, '/');
  base = base ? base + 1 : fs.f_mntfromname;
  for (const char *p = strstr(base, "disk"); p; p = strstr(p + 1, "disk")) {
    const char *end = p + 4;
    while (*end >= '0' && *end <= '9')
      end++;
    if (end > p + 4) {
      size_t length = (size_t)(end - p);
      if (length >= size)
        return false;
      memcpy(out, p, length);
      out[length] = '\0';
      return true;
    }
  }
  return false;
}

// btm の disk I/O と同じ累計バイト数: DISK_PATH のディスク (IOMedia) の親 (APFS のコンテナ) の Statistics。
// 値はデバイスに届いた量で、アプリの read / write の量ではない (ページキャッシュを通った分は含まない)。
// 取れなかったときは false (btm は N/A と表示する)
static bool disk_io_counters(uint64_t *read, uint64_t *written) {
  char name[32];
  if (!root_disk_name(name, sizeof(name)))
    return false;

  io_service_t media = IOServiceGetMatchingService(
      kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, name));
  if (!media)
    return false;

  bool ok = false;
  io_registry_entry_t parent;
  if (IORegistryEntryGetParentEntry(media, kIOServicePlane, &parent) ==
      KERN_SUCCESS) {
    CFDictionaryRef stats = IORegistryEntryCreateCFProperty(
        parent, CFSTR("Statistics"), kCFAllocatorDefault, 0);
    if (stats) {
      *read = cf_number(stats, CFSTR("Bytes (Read)"));
      *written = cf_number(stats, CFSTR("Bytes (Write)"));
      CFRelease(stats);
      ok = true;
    }
    IOObjectRelease(parent);
  }
  IOObjectRelease(media);
  return ok;
}

// 前回からの、読み・書きの速度 (byte/s。btm と同じく四捨五入)。取れなかったときは -1。
// 最初の測定は 0 (btm と同じ)
static void disk_io_rate(double elapsed, long long *read, long long *written) {
  uint64_t in, out;
  if (!disk_io_counters(&in, &out)) {
    io_has_prev = false;
    *read = *written = -1;
    return;
  }
  *read = *written = 0;
  if (io_has_prev) {
    *read = llround((in > io_prev_read ? in - io_prev_read : 0) / elapsed);
    *written = llround((out > io_prev_written ? out - io_prev_written : 0) / elapsed);
  }
  io_prev_read = in;
  io_prev_written = out;
  io_has_prev = true;
}

// 履歴のファイル (history.h)。~/Library/Caches/sketchybar/system/history.bin を mmap する。
// 開けなかったときは、履歴を書かない (popup のイベントは、これとは関係なく送る)
static struct history_header *history;
static struct history_sample *history_samples;

static void make_directory(const char *path) { mkdir(path, 0755); }

static void history_open(void) {
  const char *home = getenv("HOME");
  if (!home) {
    struct passwd *entry = getpwuid(getuid());
    home = entry ? entry->pw_dir : NULL;
  }
  if (!home)
    return;

  char path[1024];
  snprintf(path, sizeof(path), "%s/Library/Caches/sketchybar", home);
  make_directory(path);
  snprintf(path, sizeof(path), "%s/Library/Caches/sketchybar/system", home);
  make_directory(path);
  snprintf(path, sizeof(path), "%s/Library/Caches/sketchybar/system/history.bin", home);

  size_t size = sizeof(struct history_header) +
                HISTORY_CAPACITY * sizeof(struct history_sample);
  int fd = open(path, O_RDWR | O_CREAT, 0644);
  if (fd < 0)
    return;
  // 同じファイルを使い回す (読んでいる側の mmap が、helper の再起動後も有効なまま)。空から始める
  if (ftruncate(fd, (off_t)size) != 0) {
    close(fd);
    return;
  }
  void *map = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  close(fd);
  if (map == MAP_FAILED)
    return;

  struct history_header *header = map;
  __atomic_store_n(&header->count, 0, __ATOMIC_RELEASE);
  header->magic = HISTORY_MAGIC;
  header->version = HISTORY_VERSION;
  header->capacity = HISTORY_CAPACITY;
  header->sample_size = sizeof(struct history_sample);
  history = header;
  history_samples = (struct history_sample *)((char *)map + sizeof(*header));
}

static void history_write(const struct history_sample *sample) {
  if (!history)
    return;
  uint64_t count = __atomic_load_n(&history->count, __ATOMIC_RELAXED);
  history_samples[count % HISTORY_CAPACITY] = *sample;
  __atomic_store_n(&history->count, count + 1, __ATOMIC_RELEASE);
}

static void sample(CFRunLoopTimerRef timer, void *info) {
  double current = now();
  double elapsed = current - prev_time;
  prev_time = current;
  if (elapsed <= 0)
    elapsed = INTERVAL;

  float cpu = cpu_usage();
  uint64_t mem_used = memory_used();
  uint64_t swap_used, swap_total;
  swap_usage(&swap_used, &swap_total);
  int pressure = memory_pressure();
  uint64_t rx, tx;
  network_rate(elapsed, &rx, &tx);
  long long disk_read, disk_written;
  disk_io_rate(elapsed, &disk_read, &disk_written);
  uint64_t disk_free, disk_used, disk_total;
  disk_usage(&disk_free, &disk_used, &disk_total);

  struct history_sample record;
  memset(&record, 0, sizeof(record));
  record.time = current;
  record.cpu = (double)cpu;
  record.core_count = cpu_core_count < HISTORY_MAX_CORES ? cpu_core_count : HISTORY_MAX_CORES;
  for (uint32_t i = 0; i < record.core_count; i++)
    record.cores[i] = (double)cpu_core_usage[i];
  record.ram_used = mem_used;
  record.ram_total = mem_total;
  record.swap_used = swap_used;
  record.swap_total = swap_total;
  record.net_rx = rx;
  record.net_tx = tx;
  record.net_total_rx = net_total_rx;
  record.net_total_tx = net_total_tx;
  record.disk_read = disk_read;
  record.disk_written = disk_written;
  record.disk_free = disk_free;
  record.disk_used = disk_used;
  record.disk_total = disk_total;
  history_write(&record);

  // CPU は f32 の値をそのまま (%.9g で桁を失わない) 送る。Lua で丸めるときに、btm と同じ値から丸める
  char message[640];
  snprintf(message, sizeof(message),
           "--trigger system_stats CPU=%.9g "
           "RAM_USED=%llu RAM_TOTAL=%llu SWAP_USED=%llu SWAP_TOTAL=%llu "
           "MEM_PRESSURE=%d "
           "NET_RX=%llu NET_TX=%llu DISK_READ=%lld DISK_WRITE=%lld "
           "DISK_FREE=%llu DISK_TOTAL=%llu",
           (double)cpu, mem_used, mem_total, swap_used, swap_total, pressure,
           rx, tx, disk_read, disk_written, disk_free, disk_total);
  sketchybar(message);
}

int main(void) {
  host = mach_host_self();
  host_page_size(host, &page_size);
  size_t length = sizeof(mem_total);
  sysctlbyname("hw.memsize", &mem_total, &length, NULL, 0);

  // 最初の測定は基準値を取るだけ (増分が要る CPU・ネットワーク・ディスク I/O は、2 回目から意味を持つ)
  cpu_usage();
  uint64_t rx, tx;
  network_rate(INTERVAL, &rx, &tx);
  long long disk_read, disk_written;
  disk_io_rate(INTERVAL, &disk_read, &disk_written);
  prev_time = now();
  history_open();

  CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
      kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + INTERVAL, INTERVAL, 0,
      0, sample, NULL);
  CFRunLoopTimerSetTolerance(timer, TOLERANCE);
  CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopDefaultMode);
  CFRelease(timer);
  CFRunLoopRun();
  return 0;
}
