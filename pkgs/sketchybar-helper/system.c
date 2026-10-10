#include "sketchybar.h"
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_host.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/statvfs.h>
#include <sys/sysctl.h>

// CPU・メモリ・ディスクの使用状況を一定間隔で測り、
// SketchyBar の system_stats イベントに環境変数として渡す。
// 測定はカーネルの API を直接呼ぶだけで、プロセスを起動しない。
// 描画や書式は Lua (items/system.lua) が決めるので、ここでは生の値だけを送る。
//
// 値の測り方は bottom (btm。pkgs/btm-window が表示する) に合わせて、popup の数字が btm と一致するようにしている
// (btm が使う sysinfo クレートの macOS 実装と同じ式)。

#define INTERVAL 1.0
// 秒。割り込みをまとめて、省電力にする
#define TOLERANCE 0.2
// btm の disk widget は "/" だけを表示する設定。APFS のコンテナ (ディスク全体) の空きが取れる
#define DISK_PATH "/"
#define MAX_CPUS 256

static mach_port_t host;
static vm_size_t page_size;
static uint64_t mem_total;

// sysinfo と同じく i32 の tick を i64 で足す
static int64_t cpu_prev_busy[MAX_CPUS];
static int32_t cpu_prev_idle[MAX_CPUS];
static bool cpu_has_prev;

// sysinfo の global_cpu_usage と同じく、コアごとの使用率 (busy / (busy + idle)。f32) を出して、その平均を取る。
// 全コアの tick を合計して割るのとは、わずかに値が違う。
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
  for (natural_t i = 0; i < used; i++) {
    int64_t busy = (int64_t)(int32_t)load[i].cpu_ticks[CPU_STATE_USER] +
                   (int32_t)load[i].cpu_ticks[CPU_STATE_SYSTEM] +
                   (int32_t)load[i].cpu_ticks[CPU_STATE_NICE];
    int32_t idle = (int32_t)load[i].cpu_ticks[CPU_STATE_IDLE];
    if (cpu_has_prev) {
      int64_t in_use = busy - cpu_prev_busy[i];
      int64_t total = in_use + ((int64_t)idle - cpu_prev_idle[i]);
      float usage = (float)in_use / (float)total * 100.0f;
      if (usage == usage) // NaN (total が 0) は 0 にする
        sum += usage;
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

// btm の disk widget の Free / Total と同じ値 (statvfs の空きブロック数 x ブロックサイズ)。
// macOS の「消せるキャッシュ」は空きに含めない
static void disk_usage(uint64_t *free_bytes, uint64_t *total_bytes) {
  struct statvfs fs;
  *free_bytes = *total_bytes = 0;
  if (statvfs(DISK_PATH, &fs) != 0)
    return;
  *free_bytes = (uint64_t)fs.f_bavail * fs.f_frsize;
  *total_bytes = (uint64_t)fs.f_blocks * fs.f_frsize;
}

static void sample(CFRunLoopTimerRef timer, void *info) {
  float cpu = cpu_usage();
  uint64_t mem_used = memory_used();
  int pressure = memory_pressure();
  uint64_t disk_free, disk_total;
  disk_usage(&disk_free, &disk_total);

  // CPU は f32 の値をそのまま (%.9g で桁を失わない) 送る。Lua で丸めるときに、btm と同じ値から丸める
  char message[256];
  snprintf(message, sizeof(message),
           "--trigger system_stats CPU=%.9g "
           "RAM_USED=%llu RAM_TOTAL=%llu "
           "MEM_PRESSURE=%d "
           "DISK_FREE=%llu DISK_TOTAL=%llu",
           (double)cpu, mem_used, mem_total, pressure, disk_free, disk_total);
  sketchybar(message);
}

int main(void) {
  host = mach_host_self();
  host_page_size(host, &page_size);
  size_t length = sizeof(mem_total);
  sysctlbyname("hw.memsize", &mem_total, &length, NULL, 0);

  // 最初の測定は基準値を取るだけ (増分が要る CPU は、2 回目から意味を持つ)
  cpu_usage();

  CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
      kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + INTERVAL, INTERVAL, 0,
      0, sample, NULL);
  CFRunLoopTimerSetTolerance(timer, TOLERANCE);
  CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopDefaultMode);
  CFRelease(timer);
  CFRunLoopRun();
  return 0;
}
