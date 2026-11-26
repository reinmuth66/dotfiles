import { test } from "node:test";
import assert from "node:assert/strict";
import { GLYPH, PALETTE } from "./ui.js";
import { headerFor } from "./logic.js";

const pane = (extra) => ({ pane: "p1", terminal: "t1", cwd: "/Users/x/dotfiles", status: null, program: { key: "shell", name: "zsh", shell: true, agent: false }, ...extra });
const claude = { key: "claude", name: "Claude Code", shell: false, agent: true };

test("エージェントの見出し", () => {
  const h = headerFor({ pane: pane({ status: "working", program: claude }), session: { model: "Opus 5.5", effort: "high", context: { used: 46600, size: 200000 } }, repoRoot: null, home: "/Users/x" });
  assert.deepEqual([h.kind, h.label, h.effort, h.tokens], ["agent", "Opus 5.5", "high", "123.4K"]);
  assert.equal(h.program, claude);
  assert.equal(h.tokensColor, PALETTE.green);
  assert.equal(h.ringColor, PALETTE.green);
  assert.ok(Math.abs(h.ring - 0.233) < 1e-9);
});
test("セッションのファイルがなければプログラム名だけ", () => {
  const h = headerFor({ pane: pane({ status: "idle", program: claude }), session: null, repoRoot: null, home: "/Users/x" });
  assert.deepEqual([h.label, h.effort, h.tokens, h.ring], ["Claude Code", null, null, null]);
});
test("シェルの見出しは paneLabel と同じ", () => {
  assert.deepEqual(headerFor({ pane: pane({ cwd: "/Users/x/dotfiles/modules" }), session: null, repoRoot: "/Users/x/dotfiles", home: "/Users/x" }), { kind: "plain", icon: GLYPH.shell, text: "dotfiles/modules" });
});
test("effort と context が null なら出さない、輪は 1 で止める", () => {
  const h = headerFor({ pane: pane({ program: claude }), session: { model: "Opus 5.5", effort: null, context: null }, repoRoot: null, home: "/Users/x" });
  assert.deepEqual([h.kind, h.label, h.effort, h.tokens, h.tokensColor, h.ring, h.ringColor], ["agent", "Opus 5.5", null, null, null, null, null]);
  const full = headerFor({ pane: pane({ program: claude }), session: { model: "m", effort: "low", context: { used: 210000, size: 200000 } }, repoRoot: null, home: "/Users/x" });
  assert.deepEqual([full.ring, full.tokens, full.ringColor], [1, "0.0K", PALETTE.red]);
});
test("モデルが空ならプログラムの名前", () => {
  assert.equal(headerFor({ pane: pane({ program: claude }), session: { model: null }, repoRoot: null, home: "/Users/x" }).label, "Claude Code");
});
test("シェル以外のプログラムは名前と記号", () => {
  assert.deepEqual(headerFor({ pane: pane({ program: { key: "program", name: "yazi", shell: false, agent: false } }), session: null, repoRoot: null, home: "/Users/x" }), { kind: "plain", icon: GLYPH.yazi, text: "yazi" });
});
test("mod の枠は枠の名前", () => {
  assert.deepEqual(headerFor({ pane: { pane: "p2", terminal: null, mod: "preview", title: "preview", status: null }, session: null, repoRoot: null, home: "/Users/x" }), { kind: "plain", icon: GLYPH.terminal, text: "preview" });
});
