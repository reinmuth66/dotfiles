#include "sketchybar.h"
#include <CoreFoundation/CoreFoundation.h>
#include <time.h>

static void callback(CFRunLoopTimerRef timer, void *info) {
  time_t current_time;
  time(&current_time);

  char buffer[64];
  strftime(buffer, sizeof(buffer), "%m/%d %a %H:%M:%S", localtime(&current_time));

  char message[128];
  snprintf(message, sizeof(message), "--set clock label=\"%s\"", buffer);
  sketchybar(message);
}

int main(void) {
  CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
      kCFAllocatorDefault, (int64_t)CFAbsoluteTimeGetCurrent() + 1.0, 1.0, 0, 0,
      callback, NULL);
  CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopDefaultMode);
  CFRunLoopRun();
  return 0;
}
