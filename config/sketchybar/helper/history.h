#ifndef SYSTEM_HISTORY_H
#define SYSTEM_HISTORY_H

#include <stdint.h>

// system-helper が毎秒の測定値を書き込む、履歴のリングバッファのファイル (mmap して共有する)。
// 読む側は pkgs/system-monitor (Swift。値のレイアウトは History.swift に同じものを書いてある)。
// 構造体を変えたら、HISTORY_VERSION を上げ、History.swift も直す。
//
// レイアウト (すべて 8 バイト境界、ホストのバイトオーダー):
//   history_header (64 バイト) | history_sample[capacity]
// 書き込みは、サンプルを書いてから count を 1 増やす (release)。読む側は count を読み (acquire)、
// 直近のサンプルを写して、もう一度 count を読み、書き込みと重なっていないか確かめる。

#define HISTORY_MAGIC 0x3159544f4d535953ULL // "SYSMOTY1" (little endian)
#define HISTORY_VERSION 1
// 保持するサンプルの数 (1 秒間隔で 10 分。btm の retention の既定と同じ)
#define HISTORY_CAPACITY 600
// 記録するコアの数の上限
#define HISTORY_MAX_CORES 32

struct history_header {
  uint64_t magic;
  uint32_t version;
  uint32_t capacity;
  uint32_t sample_size;
  uint32_t reserved;
  uint64_t count; // これまでに書いたサンプルの総数。index = count % capacity が次の書き込み位置
  uint64_t pad[4];
};

struct history_sample {
  double time;      // 測った時刻 (CLOCK_REALTIME の秒)
  double cpu;       // 全コアの使用率の平均 (%)。f32 の値をそのまま double にしたもの
  double cores[HISTORY_MAX_CORES]; // コアごとの使用率 (%)
  uint64_t ram_used;
  uint64_t ram_total;
  uint64_t swap_used;
  uint64_t swap_total;
  uint64_t net_rx;       // 受信の速度 (bit/s)
  uint64_t net_tx;       // 送信の速度 (bit/s)
  uint64_t net_total_rx; // 受信の累計 (bit)。全 interface の合計
  uint64_t net_total_tx;
  int64_t disk_read;     // ディスク I/O の速度 (byte/s)。取れなかったときは -1
  int64_t disk_written;
  uint64_t disk_free;    // statvfs の f_bavail x f_frsize
  uint64_t disk_used;    // 総量 - f_bfree x f_frsize
  uint64_t disk_total;
  uint32_t core_count;
  uint32_t reserved;
};

#endif
