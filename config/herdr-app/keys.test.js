import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const keys = JSON.parse(
  readFileSync(new URL("./keys.json", import.meta.url), "utf8"),
);
const global = keys.global ?? {};

// WezTerm (config/wezterm/keybinds.lua) で使っていたものだけを割り当てる
const expected = {
  "ctrl-shift-i": "pane.go:up",
  "ctrl-shift-j": "pane.go:left",
  "ctrl-shift-k": "pane.go:down",
  "ctrl-shift-l": "pane.go:right",
  "ctrl-shift-,": "pane.split:down",
  "ctrl-shift-.": "pane.split:right",
  "ctrl-shift-m": "pane.close",
  "ctrl-shift-p": "pane.zoom",
  "ctrl-shift-d": "tab.next",
  "ctrl-shift-s": "tab.prev",
  "ctrl-shift-e": "tab.new",
  "ctrl-shift-w": "tab.close",
  "ctrl-shift-h": "resize-mode.start",
  "ctrl-shift-b": "resize-mode.cycle-sidebar",
  "ctrl-shift-n": "pane.swap:right",
  "ctrl-shift-v": "workspace.toggle-view",
  "ctrl-shift-u": "usage.cycle-mode",
  "ctrl-shift-z": "preview.toggle-view",
  "ctrl-shift-o": "layout.toggle:preview-area",
  "ctrl-shift-up": "preview.history-prev",
  "ctrl-shift-down": "preview.history-next",
};

const expectedObjects = {
  "ctrl-shift-c": { command: "tab.move", args: { by: 1 } },
  "ctrl-shift-x": { command: "tab.move", args: { by: -1 } },
};

// WezTerm には無い、herdr の preview の欄の切り替え
const expectedSelects = {
  "ctrl-shift-f": { command: "layout.select", args: { stack: "preview-area", child: "preview" } },
  "ctrl-shift-g": { command: "layout.select", args: { stack: "preview-area", child: "wtr" } },
  "ctrl-shift-r": { command: "layout.select", args: { stack: "preview-area", child: "browser" } },
};

test("WezTerm と同じ ctrl-shift のキーが割り当てられている", () => {
  for (const [key, action] of Object.entries(expected)) {
    assert.equal(global[key], action, key);
  }
});

test("ctrl-shift-c と ctrl-shift-x でタブを動かす", () => {
  for (const [key, action] of Object.entries(expectedObjects)) {
    assert.deepEqual(global[key], action, key);
  }
});

test("ctrl-shift-f、g、r で preview の欄の表示を選ぶ", () => {
  for (const [key, action] of Object.entries(expectedSelects)) {
    assert.deepEqual(global[key], action, key);
  }
});

test("cmd-1 から cmd-8 でタブを選ぶ", () => {
  for (let i = 1; i <= 8; i++) {
    assert.equal(global[`cmd-${i}`], `tab.select:${i}`, `cmd-${i}`);
  }
});

test("ctrl-shift + 1 文字のキーは、決めた一覧のものだけ", () => {
  const actual = Object.keys(global)
    .filter((key) => /^ctrl-shift-.$/.test(key))
    .sort();
  const allowed = [
    ...Object.keys(expected),
    ...Object.keys(expectedObjects),
    ...Object.keys(expectedSelects),
  ]
    .filter((key) => /^ctrl-shift-.$/.test(key))
    .sort();
  assert.deepEqual(actual, allowed);
});

test("shift なしの ctrl + 英字か数字 1 文字を割り当てない", () => {
  const offending = Object.keys(global).filter((key) =>
    /^ctrl-[a-z0-9]$/i.test(key),
  );
  assert.deepEqual(offending, []);
});
