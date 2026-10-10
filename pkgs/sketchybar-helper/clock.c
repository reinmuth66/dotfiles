#include "sketchybar.h"
#include <CoreFoundation/CoreFoundation.h>
#include <sys/time.h>
#include <time.h>

#define FIRE_OFFSET 0.05

static void callback(CFRunLoopTimerRef timer, void *info);

static void arm(void) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  double now = tv.tv_sec + tv.tv_usec / 1e6;
  double next = (double)(tv.tv_sec + 1) + FIRE_OFFSET;

  CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
      kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + (next - now), 0, 0, 0,
      callback, NULL);
  CFRunLoopTimerSetTolerance(timer, 0);
  CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopDefaultMode);
  CFRelease(timer);
}

static void callback(CFRunLoopTimerRef timer, void *info) {
  time_t current_time;
  time(&current_time);

  char buffer[64];
  strftime(buffer, sizeof(buffer), "%m/%d %a %H:%M:%S",
           localtime(&current_time));

  char message[128];
  snprintf(message, sizeof(message), "--set clock label=\"%s\"", buffer);
  sketchybar(message);

  arm();
}

int main(void) {
  arm();
  CFRunLoopRun();
  return 0;
}
