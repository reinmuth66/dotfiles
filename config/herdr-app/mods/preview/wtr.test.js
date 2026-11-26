import { test } from "node:test";
import assert from "node:assert/strict";
import { BROWSER_START, shellIsIdle, wtrAction } from "./wtr.js";

test("starts wtr when no live terminal is named wtr", () => {
  assert.equal(wtrAction([]), "start");
  assert.equal(wtrAction([{ name: "other", state: "live", agent: "zsh" }]), "start");
  assert.equal(wtrAction([{ name: "wtr", state: "exited", agent: "herdr-wtr" }]), "start");
});

test("checks a terminal that started as a shell", () => {
  assert.equal(wtrAction([{ name: "wtr", state: "live", agent: "zsh" }]), "check");
});

test("leaves a running herdr-wtr or another program alone", () => {
  assert.equal(wtrAction([{ name: "wtr", state: "live", agent: "herdr-wtr" }]), null);
  assert.equal(wtrAction([{ name: "wtr", state: "live", agent: "wtr" }]), null);
});

test("types exec only while the shell itself is in the foreground", () => {
  assert.equal(shellIsIdle({ foreground: { name: "zsh", argv: ["/bin/zsh", "-l"] } }), true);
  // exec herdr-wtr のあと: agent は zsh のまま、foreground は herdr-wtr を動かす bash
  assert.equal(shellIsIdle({ foreground: { name: "bash", argv: ["/nix/store/x-bash/bin/bash", "/etc/profiles/per-user/u/bin/herdr-wtr"] } }), false);
  assert.equal(shellIsIdle({ foreground: { name: "wtr" } }), false);
  assert.equal(shellIsIdle(null), false);
});

test("browser のターミナルも名前で見分け、herdr-browser で起こす", () => {
  const list = [{ name: "wtr", state: "live", agent: "herdr-wtr" }];
  assert.equal(wtrAction(list, "browser"), "start");
  assert.equal(wtrAction([...list, { name: "browser", state: "live", agent: "herdr-browser" }], "browser"), null);
  assert.deepEqual(BROWSER_START.slice(-3), ["browser", "--", "herdr-browser"]);
});
