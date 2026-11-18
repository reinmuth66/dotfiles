import { test } from "node:test";
import assert from "node:assert/strict";
import {
  LANGUAGE,
  MAX_TEXT_BYTES,
  extOf,
  fileKind,
  follow,
  formatSize,
  imagePlan,
  initialTabState,
  languageOf,
  moveHistory,
  pin,
  previewCachePath,
  pruneTargets,
  toggleView,
  tooLargeMessage,
} from "./logic.js";

test("fileKind", () => {
  assert.equal(fileKind("/r/README.md"), "markdown");
  assert.equal(fileKind("/r/flake.nix"), "code");
  assert.equal(fileKind("/r/Makefile"), "code");
  assert.equal(fileKind("/r/x.PNG"), "image");
  assert.equal(fileKind("/r/仕様 書.docx"), "document");
  assert.equal(fileKind("/r/case.3mf"), "model");
  assert.equal(fileKind("/r/a.zip"), "other");
});
test("fileKind: 表の言語、拡張子のない名前、決めた拡張子は code", () => {
  assert.equal(fileKind("/r/main.rs"), "code");
  assert.equal(fileKind("/r/a.tsx"), "code");
  assert.equal(fileKind("/r/notes.txt"), "code");
  assert.equal(fileKind("/r/.gitignore"), "code"); // 先頭の . は拡張子ではない
  assert.equal(fileKind("/r/board.kicad_pcb"), "model");
  assert.equal(fileKind("/r/a.markdown"), "markdown");
  assert.equal(fileKind("/r/a.HEIC"), "image");
  assert.equal(fileKind("/r/a.key"), "document");
});
test("LANGUAGE と languageOf", () => {
  assert.equal(LANGUAGE.nix, "nix");
  assert.equal(LANGUAGE.tsx, "js");
  assert.equal(LANGUAGE.cjs, "js");
  assert.equal(LANGUAGE.zsh, "bash");
  assert.equal(LANGUAGE.py, "python");
  assert.equal(languageOf("/r/a.ts"), "js");
  assert.equal(languageOf("/r/Makefile"), "text");
  assert.equal(languageOf("/r/a.txt"), "text");
});
test("extOf", () => {
  assert.equal(extOf("/r/x.PNG"), "png");
  assert.equal(extOf("/r/Makefile"), "");
  assert.equal(extOf("/r/.zshrc"), "");
  assert.equal(extOf("/r.d/file"), "");
});
test("previewCachePath は同じ入力で同じ、mtime が変われば別", () => {
  const p = previewCachePath("/h/.config/herdr-app", "/r/a.png", 1, "png");
  assert.match(p, /^\/h\/\.config\/herdr-app\/data\/preview\/[0-9a-f]+\.png$/);
  assert.equal(p, previewCachePath("/h/.config/herdr-app", "/r/a.png", 1, "png"));
  assert.notEqual(p, previewCachePath("/h/.config/herdr-app", "/r/a.png", 2, "png"));
  assert.notEqual(p, previewCachePath("/h/.config/herdr-app", "/r/b.png", 1, "png"));
});
test("imagePlan: heic と tiff は PNG に直し、文書は縮小画像、ほかの画像はそのまま写す", () => {
  assert.deepEqual(imagePlan("/r/a.png"), { method: "copy", ext: "png" });
  assert.deepEqual(imagePlan("/r/a.JPG"), { method: "copy", ext: "jpg" });
  assert.deepEqual(imagePlan("/r/a.HEIC"), { method: "convert", ext: "png" });
  assert.deepEqual(imagePlan("/r/a.tiff"), { method: "convert", ext: "png" });
  assert.deepEqual(imagePlan("/r/仕様 書.docx"), { method: "thumbnail", ext: "png" });
  assert.equal(imagePlan("/r/a.md"), null);
});
test("上限と文言", () => {
  assert.equal(MAX_TEXT_BYTES, 1024 * 1024);
  assert.equal(tooLargeMessage, "大きすぎて差分を出せません");
});
test("formatSize", () => {
  assert.equal(formatSize(512), "512 B");
  assert.equal(formatSize(2048), "2.0 KB");
  assert.equal(formatSize(3 * 1024 * 1024), "3.0 MB");
  assert.equal(formatSize(null), "?");
});
test("pruneTargets は上限を超えた分を古い順に返す", () => {
  const entries = [
    { name: "c", mtime: 3 },
    { name: "a", mtime: 1 },
    { name: "b", mtime: 2 },
  ];
  assert.deepEqual(pruneTargets(entries, 2), ["a"]);
  assert.deepEqual(pruneTargets(entries, 3), []);
  assert.deepEqual(pruneTargets(entries, 1), ["a", "b"]);
});
test("タブの状態", () => {
  let s = initialTabState();
  assert.deepEqual(s, { mode: "follow", pinned: null, view: "diff", historyIndex: 0 });
  s = pin(s, "/r/a.md");
  assert.deepEqual([s.mode, s.pinned, s.view], ["pinned", "/r/a.md", "full"]);
  s = toggleView(s);
  assert.equal(s.view, "diff");
  assert.equal(toggleView(s).view, "full");
  s = follow(s);
  assert.deepEqual([s.mode, s.view, s.historyIndex], ["follow", "diff", 0]);
  assert.equal(moveHistory(s, 5, 3).historyIndex, 2);
  assert.equal(moveHistory(s, -1, 3).historyIndex, 0);
  assert.equal(moveHistory(s, 1, 0).historyIndex, 0);
});
