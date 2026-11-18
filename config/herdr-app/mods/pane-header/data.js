// mod が共有する、ファイルと git の読み込み。正本は config/herdr-app/shared/data.js。
// ui.js と同じく、使う mod のフォルダに cp で写す。
import * as fs from "fs/promises";
import { appHome, checking, exec, readTextFile, watchFolder } from "herdr";

async function readJsonDir(dir) {
  let names;
  try {
    names = await fs.readdir(dir);
  } catch {
    return {}; // フォルダがまだない
  }
  const files = {};
  for (const name of names) {
    if (!name.endsWith(".json")) continue;
    try {
      const text = await readTextFile(`${dir}/${name}`);
      if (text != null) files[name.slice(0, -".json".length)] = JSON.parse(text);
    } catch {
      // 壊れた JSON、書きかけのファイルは飛ばす
    }
  }
  return files;
}

// appHome()/data/<subdir> の *.json を全部読み、変わるたびに全体を読み直して onChange を呼ぶ。
// キーはファイル名から .json を除いたもので、このコンピューターの端末の ID。
// 別のコンピューターの端末 (isRemoteAddress) をこの表で引かないこと。
export function watchJsonDir(cx, subdir, onChange) {
  const dir = `${appHome()}/data/${subdir}`;
  let stopped = false;
  let pending = null;
  cx.spawn(async (cx) => {
    if (checking()) {
      const files = await readJsonDir(dir);
      if (!stopped) onChange(files);
      return;
    }
    while (!stopped) {
      // 先に見張りを始めてから読む。読んでから見張ると、その間の書き込みを取りこぼす
      let failed = false;
      try {
        pending = watchFolder(dir);
        pending.catch(() => {}); // 読んでいる間に失敗しても、未処理の拒否にしない
      } catch {
        pending = null;
        failed = true; // フォルダがまだない
      }
      const files = await readJsonDir(dir);
      if (stopped) break;
      onChange(files);
      try {
        if (failed) throw new Error("no watch");
        const changed = await pending;
        // フォルダがなくて即座に返るときに、空回りしない
        if (!stopped && changed.length === 0) await cx.sleep(2000);
      } catch {
        if (!stopped) await cx.sleep(2000); // フォルダが作られるのを待つ
      }
    }
  });
  return {
    cancel() {
      stopped = true;
      pending?.cancel();
    },
  };
}

const roots = new Map();

// cwd の git のルート。cwd ごとに覚える。別のコンピューターの space と枠では呼ばない
export function repoRoot(cwd) {
  if (!cwd) return Promise.resolve(null);
  if (!roots.has(cwd)) {
    roots.set(
      cwd,
      exec("git", ["rev-parse", "--show-toplevel"], { cwd, timeout: 3000 })
        .then((r) => (r.code === 0 ? r.stdout.trim() || null : null))
        .catch(() => null),
    );
  }
  return roots.get(cwd);
}
