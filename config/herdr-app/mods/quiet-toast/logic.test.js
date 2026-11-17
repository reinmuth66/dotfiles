import test from "node:test";
import assert from "node:assert/strict";
import { shouldSuppress } from "./logic.js";

// herdr が実際に出した通知 (2026-11-18 に集めたもの)
const done = {
  title: "Claude Code finished",
  body: "dotfiles / toast-done",
  level: "info",
  action: { name: "agent.focus", args: { terminal: "t15" } },
  overlay: "o149",
};
const blocked = {
  title: "Claude Code needs you",
  body: "dotfiles / toast-ask",
  level: "error",
  action: { name: "agent.focus", args: { terminal: "t17" } },
  overlay: "o151",
};

test("エージェントの終了の通知を消す", () => {
  assert.equal(shouldSuppress(done), true);
});

test("エージェントの入力待ちの通知を消す (level は error だが、エージェントへ移る通知)", () => {
  assert.equal(shouldSuppress(blocked), true);
});

test("エラーの通知は消さない", () => {
  assert.equal(shouldSuppress({ title: "Command failed", body: "exit 1", level: "error", overlay: "o1" }), false);
});

test("更新の通知は消さない", () => {
  assert.equal(shouldSuppress({ title: "Update available", level: "info", overlay: "o2" }), false);
});

test("mod の notify() の通知は消さない (エージェントへ移る action がない)", () => {
  assert.equal(
    shouldSuppress({ title: "Saved", level: "info", action: { name: "space.select", args: {} }, overlay: "o3" }),
    false,
  );
});

test("props が欠けていても落ちない", () => {
  assert.equal(shouldSuppress({}), false);
  assert.equal(shouldSuppress(undefined), false);
});
