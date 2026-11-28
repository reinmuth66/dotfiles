import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const keys = JSON.parse(
  readFileSync(new URL("./keys.json", import.meta.url), "utf8"),
);
const global = keys.global ?? {};
const terminal = keys.terminal ?? {};

const expected = {
  "cmd-h": "pane.go:left", "cmd-j": "pane.go:down", "cmd-k": "pane.go:up", "cmd-l": "pane.go:right",
  "cmd-ctrl-h": "pane.swap:left", "cmd-ctrl-j": "pane.swap:down", "cmd-ctrl-k": "pane.swap:up", "cmd-ctrl-l": "pane.swap:right",
  "cmd-d": "pane.split:right", "cmd-shift-d": "pane.split:down", "cmd-shift-w": "pane.close", "cmd-shift-enter": "pane.zoom",
  "cmd-shift-j": "workspace.next", "cmd-shift-k": "workspace.prev", "cmd-shift-h": "workspace.close", "cmd-shift-l": "workspace.open",
  "cmd-alt-j": "workspace.next-group", "cmd-alt-k": "workspace.prev-group", "cmd-alt-h": "workspace.close-group", "cmd-alt-l": "workspace.open-group",
  "cmd-ctrl-shift-j": "workspace.move-down", "cmd-ctrl-shift-k": "workspace.move-up",
  "cmd-ctrl-alt-j": "workspace.move-group-down", "cmd-ctrl-alt-k": "workspace.move-group-up",
  "cmd-t": "tab.new", "cmd-w": "tab.close", "cmd-n": "space.new", "f2": "tab.rename", "shift-f2": "space.rename",
  "cmd-b": "layout.toggle:sidebar", "cmd-shift-b": "resize-mode.cycle-sidebar", "cmd-u": "workspace.toggle-view",
  "cmd-p": "resize-mode.wtr", "cmd-r": "resize-mode.start", "cmd-e": "layout.switch",
  "cmd-o": "mod.open:picker", "cmd-shift-p": "app.palette", "cmd-,": "app.settings", "cmd-/": "app.help",
  "cmd-=": "app.zoom_in", "cmd--": "app.zoom_out", "cmd-0": "app.zoom_reset", "cmd-q": "app.quit", "cmd-m": "window.minimize",
};

const digits = Object.fromEntries(
  Array.from({ length: 9 }, (_, i) => [`cmd-${i + 1}`, `tab.select:${i + 1}`]),
);

const macOSReserved = [
  "cmd-ctrl-f",
  "cmd-ctrl-q",
  "cmd-ctrl-space",
  "cmd-shift-3",
  "cmd-shift-4",
  "cmd-shift-5",
  "cmd-alt-d",
  "cmd-alt-esc",
  "cmd-space",
  "cmd-tab",
];

const expectedTerminal = {
  "cmd-f": "terminal.search",
  "cmd-a": "terminal.select_all",
  "cmd-c": "terminal.copy",
  "cmd-v": "terminal.paste",
  "ctrl-v": "terminal.paste_image",
  "alt-left": "send:\u001bb",
  "alt-right": "send:\u001bf",
  "alt-backspace": "send:\u0017",
  "cmd-left": "send:\u0001",
  "cmd-right": "send:\u0005",
  "cmd-backspace": "send:\u0015",
};

test("cmd-1 から cmd-9 でタブを選ぶ", () => {
  for (let i = 1; i <= 9; i++) {
    assert.equal(global[`cmd-${i}`], `tab.select:${i}`, `cmd-${i}`);
  }
});

test("global は決めた表と cmd-1〜9 だけ", () => {
  assert.deepEqual(global, { ...expected, ...digits });
});

test("global のキーは cmd を含むか F キー", () => {
  for (const key of Object.keys(global)) {
    assert.ok(
      /(^|-)cmd-/.test(key) || /^(shift-)?f\d+$/.test(key),
      `unexpected key: ${key}`,
    );
  }
});

test("macOS のキーを使わない", () => {
  for (const key of macOSReserved) {
    assert.equal(key in global, false, `reserved macOS key used: ${key}`);
  }
});

test("1 つの動きに 2 つのキーを付けない", () => {
  const values = Object.values(global);
  assert.equal(new Set(values).size, values.length);
});

test("terminal の節は変えない", () => {
  assert.deepEqual(terminal, expectedTerminal);
});
