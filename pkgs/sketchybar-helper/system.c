#include "sketchybar.h"
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_host.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/statvfs.h>
#include <sys/sysctl.h>

// Measures CPU, memory, and disk usage at fixed intervals and
// passes them as environment variables to SketchyBar's system_stats event.
// Measurement only calls kernel APIs directly and does not launch processes.
// Drawing and formatting are decided by the Lua in items/system.lua, so only raw values are sent here.
//
// How values are measured follows bottom's btm so that the popup's numbers match btm. btm is shown by pkgs/btm-window.
// The same formula as the macOS implementation of the sysinfo crate that btm uses.

#define INTERVAL 1.0
// Seconds. Coalesce wakeups to save power
#define TOLERANCE 0.2
// btm's disk widget is configured to show only "/". The free space of the APFS container, i.e. the whole disk, can be obtained.
#define DISK_PATH "/"
#define MAX_CPUS 256

static mach_port_t host;
static vm_size_t page_size;
static uint64_t mem_total;

// Like sysinfo, add i32 ticks as i64
static int64_t cpu_prev_busy[MAX_CPUS];
static int32_t cpu_prev_idle[MAX_CPUS];
static bool cpu_has_prev;

// Like sysinfo's global_cpu_usage, compute each core's usage as an f32 busy / (busy + idle) and take their average.
// This differs slightly from summing the ticks of all cores and dividing.
// A core whose total is 0 and whose usage would be NaN is treated as 0 without being added.
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
      if (usage == usage)
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

// The same breakdown as Activity Monitor's "Memory Used": app + wired + compressed.
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

// Memory pressure is 1 for normal, 2 for warn, 4 for critical. The same kernel value as the memory_pressure command, readable without launching a process.
// 0 if it could not be read.
static int memory_pressure(void) {
  int level = 0;
  size_t length = sizeof(level);
  if (sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &length, NULL, 0) != 0)
    return 0;
  return level;
}

// The same value as btm's disk widget Free and Total: statvfs's free block count x block size.
// macOS's "purgeable cache" is not included in free.
static void disk_usage(uint64_t *free_bytes, uint64_t *total_bytes) {
  struct statvfs fs;
  *free_bytes = *total_bytes = 0;
  if (statvfs(DISK_PATH, &fs) != 0)
    return;
  *free_bytes = (uint64_t)fs.f_bavail * fs.f_frsize;
  *total_bytes = (uint64_t)fs.f_blocks * fs.f_frsize;
}

// CPU sends the f32 value as is. %.9g does not lose digits. When rounding in Lua, round from the same value as btm.
static void sample(CFRunLoopTimerRef timer, void *info) {
  float cpu = cpu_usage();
  uint64_t mem_used = memory_used();
  int pressure = memory_pressure();
  uint64_t disk_free, disk_total;
  disk_usage(&disk_free, &disk_total);

  char message[256];
  snprintf(message, sizeof(message),
           "--trigger system_stats CPU=%.9g "
           "RAM_USED=%llu RAM_TOTAL=%llu "
           "MEM_PRESSURE=%d "
           "DISK_FREE=%llu DISK_TOTAL=%llu",
           (double)cpu, mem_used, mem_total, pressure, disk_free, disk_total);
  sketchybar(message);
}

// The first cpu_usage only takes the baseline. CPU, which needs a delta, is meaningful from the second time.
int main(void) {
  host = mach_host_self();
  host_page_size(host, &page_size);
  size_t length = sizeof(mem_total);
  sysctlbyname("hw.memsize", &mem_total, &length, NULL, 0);

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
