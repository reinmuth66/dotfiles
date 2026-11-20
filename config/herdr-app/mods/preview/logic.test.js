import { test } from "node:test";
import assert from "node:assert/strict";
import {
  LANGUAGE,
  MAX_TEXT_BYTES,
  agentTerminalFor,
  cutToLastLine,
  extOf,
  fileKind,
  formatJson,
  formatSize,
  imagePlan,
  isCacheFile,
  initialTabState,
  languageOf,
  separatorOf,
  previewCachePath,
  pruneTargets,
  readPlan,
  readmeName,
  thumbnailCommand,
  thumbnailOutput,
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
test("languageOf は herdr の files の mod の表に nix を足したもの", () => {
  assert.equal(languageOf("/a/b.ts"), "js");
  assert.equal(languageOf("/a/b.tsx"), "js");
  assert.equal(languageOf("/a/b.mts"), "js");
  assert.equal(languageOf("/a/b.toml"), "yaml");
  assert.equal(languageOf("/a/b.jsonc"), "json");
  assert.equal(languageOf("/a/b.vue"), "html");
  assert.equal(languageOf("/a/b.nix"), "ruby");
  assert.equal(languageOf("/a/b.py"), "py");
  assert.equal(languageOf("/a/b.dtsi"), "dtsi");
  assert.equal(languageOf("/a/Makefile"), "text");
});
test("LANGUAGE は表の値だけを持つ", () => {
  assert.equal(LANGUAGE.nix, "ruby");
  assert.equal(LANGUAGE.cts, "js");
  assert.equal(LANGUAGE.svelte, "html");
  assert.equal(LANGUAGE.py, undefined);
});
test("fileKind は csv、tsv、json を分ける", () => {
  assert.equal(fileKind("/a/b.csv"), "csv");
  assert.equal(fileKind("/a/b.tsv"), "csv");
  assert.equal(fileKind("/a/b.json"), "json");
  assert.equal(fileKind("/a/b.md"), "markdown");
  assert.equal(fileKind("/a/b.nix"), "code");
  assert.equal(fileKind("/a/b.dtsi"), "code");
  assert.equal(separatorOf("/a/b.tsv"), "\t");
  assert.equal(separatorOf("/a/b.csv"), ",");
});
test("fileKind: 画像、文書、モデル、圧縮ファイル以外の拡張子は code", () => {
  assert.equal(fileKind("/a/b.zip"), "other");
  assert.equal(fileKind("/a/b.tar"), "other");
  assert.equal(fileKind("/a/b.gz"), "other");
  assert.equal(fileKind("/a/b.unknownext"), "code");
});
test("extOf", () => {
  assert.equal(extOf("/r/x.PNG"), "png");
  assert.equal(extOf("/r/Makefile"), "");
  assert.equal(extOf("/r/.zshrc"), "");
  assert.equal(extOf("/r.d/file"), "");
});
test("previewCachePath は同じ入力で同じ、mtime が変われば別", () => {
  const p = previewCachePath("/h/.config/herdr-app", "/r/a.png", 1, "png");
  assert.match(p, /^\/h\/\.config\/herdr-app\/data\/preview-cache\/[0-9a-f]{16}\.png$/);
  assert.equal(isCacheFile(p.split("/").pop()), true);
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
test("imagePlan: 縮小画像を作れるモデルは model、作れないものは null", () => {
  assert.deepEqual(imagePlan("/r/a.3mf"), { method: "model", ext: "png" });
  assert.deepEqual(imagePlan("/r/a.FCStd"), { method: "model", ext: "png" });
  assert.deepEqual(imagePlan("/r/a.kicad_pcb"), { method: "model", ext: "svg" });
  assert.deepEqual(imagePlan("/r/a.kicad_sch"), { method: "model", ext: "svg" });
  assert.equal(imagePlan("/r/a.stl"), null);
  assert.equal(imagePlan("/r/a.step"), null);
  assert.equal(imagePlan("/r/a.kicad_pro"), null);
});
const KICAD = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli";
test("thumbnailCommand: 3MF は Metadata/thumbnail.png、なければ Metadata/plate_1.png をシェルでファイルに書く", () => {
  assert.deepEqual(thumbnailCommand("/r/x.3mf", "/o/t.png"), {
    cmd: "sh",
    args: [
      "-c",
      'unzip -p "$1" Metadata/thumbnail.png > "$2" 2>/dev/null || unzip -p "$1" Metadata/plate_1.png > "$2"',
      "sh",
      "/r/x.3mf",
      "/o/t.png",
    ],
    timeout: 5000,
  });
});
test("thumbnailCommand: FreeCAD は thumbnails/Thumbnail.png", () => {
  assert.deepEqual(thumbnailCommand("/r/x.FCStd", "/o/t.png"), {
    cmd: "sh",
    args: ["-c", 'unzip -p "$1" thumbnails/Thumbnail.png > "$2"', "sh", "/r/x.FCStd", "/o/t.png"],
    timeout: 5000,
  });
});
test("thumbnailCommand: KiCad の基板は層を指定して 1 枚の SVG に書く", () => {
  assert.deepEqual(thumbnailCommand("/r/x.kicad_pcb", "/o/t.svg"), {
    cmd: KICAD,
    args: [
      "pcb",
      "export",
      "svg",
      "--mode-single",
      "--layers",
      "F.Cu,B.Cu,F.SilkS,Edge.Cuts",
      "--exclude-drawing-sheet",
      "--fit-page-to-board",
      "--output",
      "/o/t.svg",
      "/r/x.kicad_pcb",
    ],
    timeout: 15000,
  });
});
test("thumbnailCommand: KiCad の回路図はフォルダに書き、ファイル名は元の名前", () => {
  assert.deepEqual(thumbnailCommand("/r/x.kicad_sch", "/o/t.svg"), {
    cmd: KICAD,
    args: ["sch", "export", "svg", "--output", "/o", "/r/x.kicad_sch"],
    timeout: 15000,
  });
  assert.equal(thumbnailOutput("/r/my board.kicad_sch", "/o/t.svg"), "/o/my board.svg");
  assert.equal(thumbnailOutput("/r/x.kicad_pcb", "/o/t.svg"), "/o/t.svg");
  assert.equal(thumbnailOutput("/r/x.3mf", "/o/t.png"), "/o/t.png");
});
test("thumbnailCommand: f3d が入らない STL と STEP、ほかの種類は null", () => {
  for (const ext of ["stl", "step", "stp", "kicad_pro", "png", "md"]) {
    assert.equal(thumbnailCommand(`/r/x.${ext}`, "/o"), null);
  }
});
test("上限と文言", () => {
  assert.equal(MAX_TEXT_BYTES, 1024 * 1024);
});
test("readPlan: 上限を超えても CSV と TSV は先頭だけ読む", () => {
  assert.equal(readPlan("code", MAX_TEXT_BYTES), "full");
  assert.equal(readPlan("csv", MAX_TEXT_BYTES), "full");
  assert.equal(readPlan("csv", MAX_TEXT_BYTES + 1), "head");
  for (const kind of ["code", "json", "markdown"]) assert.equal(readPlan(kind, MAX_TEXT_BYTES + 1), "too-large");
});
test("cutToLastLine: 途中で切れた最後の行を落とす", () => {
  assert.equal(cutToLastLine("a,b\n1,2\n3,"), "a,b\n1,2\n");
  assert.equal(cutToLastLine("a,b\n"), "a,b\n");
  assert.equal(cutToLastLine("abc"), "abc");
  assert.equal(cutToLastLine(""), "");
});
test("formatSize", () => {
  assert.equal(formatSize(512), "512 B");
  assert.equal(formatSize(2048), "2.0 KB");
  assert.equal(formatSize(3 * 1024 * 1024), "3.0 MB");
  assert.equal(formatSize(null), "?");
});
test("pruneTargets は上限を超えた分を古い順に返す", () => {
  const a = "0000000000000000.png";
  const b = "1111111111111111.svg";
  const c = "2222222222222222.png";
  const entries = [
    { name: c, mtime: 3 },
    { name: a, mtime: 1 },
    { name: b, mtime: 2 },
  ];
  assert.deepEqual(pruneTargets(entries, 2), [a]);
  assert.deepEqual(pruneTargets(entries, 3), []);
  assert.deepEqual(pruneTargets(entries, 1), [a, b]);
});
test("pruneTargets は自分が作った写しだけを数え、ほかのファイルは消さない", () => {
  const entries = [
    { name: "store.json", mtime: 0 },
    { name: "store-b30492047b252f01.json", mtime: 0 },
    { name: ".tmp", mtime: 0 },
    { name: "0000000000000000.png", mtime: 1 },
    { name: "1111111111111111.png", mtime: 2 },
  ];
  assert.deepEqual(pruneTargets(entries, 2), []);
  assert.deepEqual(pruneTargets(entries, 1), ["0000000000000000.png"]);
  assert.equal(isCacheFile("store.json"), false);
});
test("タブの状態は、ファイルの表示でファイルなしから始まる", () => {
  assert.deepEqual(initialTabState(), { view: "file", file: null });
  assert.notEqual(initialTabState(), initialTabState());
});

test("agentTerminalFor: 今のタブのエージェント。複数なら focused().terminal、なければ最初", () => {
  const list = [
    { address: "t1", tab: "a" },
    { address: "t2", tab: "b" },
    { address: "t3", tab: "b" },
  ];
  assert.equal(agentTerminalFor(list, { tab: "a", terminal: null }), "t1");
  assert.equal(agentTerminalFor(list, { tab: "b", terminal: "t3" }), "t3");
  assert.equal(agentTerminalFor(list, { tab: "b", terminal: "t9" }), "t2");
  assert.equal(agentTerminalFor(list, { tab: "c", terminal: "t1" }), null);
  assert.equal(agentTerminalFor(list, null), null);
});
test("formatJson", () => {
  assert.equal(formatJson('{"a":1,"b":[2]}'), '{\n  "a": 1,\n  "b": [\n    2\n  ]\n}');
  assert.equal(formatJson("{broken"), "{broken");
});
test("readmeName", () => {
  assert.equal(readmeName(["a.nix", "README.md"]), "README.md");
  assert.equal(readmeName(["Readme.MD"]), "Readme.MD");
  assert.equal(readmeName(["README", "README.md"]), "README.md");
  assert.equal(readmeName(["a.txt"]), null);
});
