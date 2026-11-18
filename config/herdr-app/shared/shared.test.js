import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import {
  GLYPH,
  PROCESS_ICONS,
  STATUS,
  PALETTE,
  mostUrgent,
  contextColor,
  tokensToCompact,
  formatTokens,
  formatDuration,
  ringArc,
  mark,
  paneLabel,
  isRemoteSpace,
  isRemoteAddress,
} from "./ui.js";

test("GLYPH と STATUS の番号は glyphnames.json の値", () => {
  assert.equal(GLYPH.spaceClosed.codePointAt(0), 0xf003c);
  assert.equal(GLYPH.rootOpen.codePointAt(0), 0xf0dcf);
  assert.equal(STATUS.working.glyph.codePointAt(0), 0xf07c3);
  assert.equal(PROCESS_ICONS.yazi, GLYPH.yazi);
});
test("mostUrgent", () => {
  assert.equal(mostUrgent(["working", "blocked", "done"]), "blocked");
  assert.equal(mostUrgent(["idle", null]), "idle");
  assert.equal(mostUrgent([]), null);
});
test("contextColor と formatTokens", () => {
  assert.equal(contextColor(49.9), PALETTE.green);
  assert.equal(contextColor(50), PALETTE.peach);
  assert.equal(contextColor(80), PALETTE.red);
  assert.equal(tokensToCompact({ used: 46600, size: 200000 }), 123400);
  assert.equal(formatTokens(123456), "123.4K");
  assert.equal(tokensToCompact({ used: 190000, size: 200000 }), 0);
});
test("formatDuration", () => {
  assert.equal(formatDuration(42_000), "0m");
  assert.equal(formatDuration(192_000), "3m");
  assert.equal(formatDuration(12 * 60_000 + 5_000), "12m");
  assert.equal(formatDuration(60 * 60_000 - 1000), "59m");
  assert.equal(formatDuration(60 * 60_000), "1h00m");
  assert.equal(formatDuration(125 * 60_000), "2h05m");
});
test("ringArc", () => {
  assert.equal(ringArc(0, 22, 2), null);
  assert.equal(ringArc(1, 22, 2).full, true);
  const half = ringArc(0.5, 22, 2);
  assert.deepEqual(half.start, [11, 1]); // r = (22 - 2) / 2 = 10、中心 (11, 11)
  assert.deepEqual(half.end.map(Math.round), [11, 21]);
  assert.equal(ringArc(0.75, 22, 2).largeArc, true);
});
test("mark", () => {
  assert.deepEqual(mark("Mocha 2"), { letter: "M", color: PALETTE.flamingo });
  assert.equal(mark("Zzz").color, PALETTE.overlay2);
});
test("paneLabel", () => {
  const home = "/Users/x";
  assert.deepEqual(paneLabel({ programKey: "program", processName: "yazi", shell: false, cwd: "/a", repoRoot: null, home }), { icon: GLYPH.yazi, text: "yazi" });
  assert.deepEqual(paneLabel({ programKey: "shell", processName: "zsh", shell: true, cwd: "/Users/x/dotfiles/modules", repoRoot: "/Users/x/dotfiles", home }), { icon: GLYPH.shell, text: "dotfiles/modules" });
  assert.deepEqual(paneLabel({ programKey: "shell", processName: "zsh", shell: true, cwd: "/Users/x/Downloads", repoRoot: null, home }), { icon: GLYPH.shell, text: "Downloads" });
  assert.equal(paneLabel({ programKey: "shell", processName: "zsh", shell: true, cwd: home, repoRoot: null, home }).text, "~");
  assert.equal(paneLabel({ programKey: "program", processName: "htop", shell: false, cwd: null, repoRoot: null, home }).icon, GLYPH.terminal);
});
test("別のコンピューターの判断", () => {
  // Review Focus 6
  assert.equal(isRemoteSpace({ machine: null }), false);
  assert.equal(isRemoteSpace({ machine: "laptop" }), true);
  assert.equal(isRemoteAddress("t1"), false);
  assert.equal(isRemoteAddress("laptop/t1"), true);
});
// mod は自分のフォルダの外を import できないので、正本を写して使う。写しがずれていないこと
test("ui.js と data.js の写しは正本と同じ", () => {
  for (const name of ["ui.js", "data.js"]) {
    const original = readFileSync(new URL(`./${name}`, import.meta.url), "utf8");
    for (const mod of readdirSync(new URL("../mods/", import.meta.url))) {
      const copy = new URL(`../mods/${mod}/${name}`, import.meta.url);
      if (existsSync(copy)) assert.equal(readFileSync(copy, "utf8"), original, `mods/${mod}/${name}`);
    }
  }
});
