import { test } from "node:test";
import assert from "node:assert/strict";
import { wtrAction } from "./wtr.js";

test("starts wtr when no live terminal is named wtr", () => {
  assert.equal(wtrAction([]), "start");
  assert.equal(wtrAction([{ name: "other", state: "live", agent: "zsh" }]), "start");
  assert.equal(wtrAction([{ name: "wtr", state: "exited", agent: "herdr-wtr" }]), "start");
});

test("runs herdr-wtr in the shell left by --keep", () => {
  assert.equal(wtrAction([{ name: "wtr", state: "live", agent: "zsh" }]), "exec");
});

test("leaves a running herdr-wtr or another program alone", () => {
  assert.equal(wtrAction([{ name: "wtr", state: "live", agent: "herdr-wtr" }]), null);
  assert.equal(wtrAction([{ name: "wtr", state: "live", agent: "wtr" }]), null);
});
