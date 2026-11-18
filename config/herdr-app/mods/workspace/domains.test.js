import { test } from "node:test";
import assert from "node:assert/strict";
import { DOMAIN_RULES, describe, domainTag } from "./domains.js";

const a = (kind, path = null, command = null) => ({ kind, path, command, tool: "x", at: 0 });
test("domainTag", () => {
  assert.equal(domainTag([a("edit", "/r/docs/x.txt"), a("edit", "/r/a.nix"), a("write", "/r/README.md")]), "docs");
  assert.equal(domainTag([a("bash", null, "nix flake check")]), "test");
  assert.equal(domainTag([a("read", "/r/a"), a("search"), a("web")]), "research");
  assert.equal(domainTag([a("read", "/r/a")]), null);
  assert.equal(domainTag([a("edit", "/r/config/design-system/x.css")]), "design");
});
test("domainTag: 同数なら新しいほう、見るのは新しい 8 件だけ", () => {
  assert.equal(domainTag([a("edit", "/r/a.nix"), a("edit", "/r/b.md")]), "nix");
  const old = Array.from({ length: 5 }, () => a("edit", "/r/x.md"));
  const recent = [a("edit", "/r/a.nix"), a("edit", "/r/b.nix"), a("edit", "/r/c.nix"), a("read", "/r/d"), a("read", "/r/e")];
  assert.equal(domainTag([...recent, ...old]), "nix"); // 8 件の中は md 3、nix 3、同数で新しい nix
  assert.equal(domainTag([]), null);
  assert.equal(domainTag(null), null);
});
test("domainTag: research は新しい 3 件以上がすべて読むだけのとき", () => {
  assert.equal(domainTag([a("read", "/r/a"), a("search")]), null);
  assert.equal(domainTag([a("read", "/r/a"), a("search"), a("bash", null, "ls")]), null);
  assert.equal(domainTag([a("read", "/r/a"), a("search"), a("web"), a("other")]), "research");
  assert.equal(domainTag([a("other"), a("read", "/r/a"), a("search"), a("web")]), null);
});
test("domainTag: 表を差し替えられる", () => {
  const rules = [{ tag: "lua", test: (x) => x.kind === "edit" && x.path.endsWith(".lua") }];
  assert.equal(domainTag([a("edit", "/r/a.lua")], rules), "lua");
  assert.equal(domainTag([a("edit", "/r/a.nix")], rules), null);
  assert.equal(DOMAIN_RULES.map((r) => r.tag).join(","), "design,docs,nix,test");
});
test("domainTag: path や command がなくても落ちない", () => {
  assert.equal(domainTag([a("edit"), a("bash")]), null);
});
test("describe", () => {
  assert.equal(describe(a("edit", "/r/README.md")), "README.md を編集");
  assert.equal(describe(a("bash", null, "nix flake check")), "nix flake check を実行");
  assert.equal(describe(a("web")), "Web を検索");
  assert.equal(describe(null), null);
});
test("describe: そのほかの種類", () => {
  assert.equal(describe(a("write", "/r/a/b.nix")), "b.nix を編集");
  assert.equal(describe(a("read", "/r/x/日本 語.md")), "日本 語.md を読む");
  assert.equal(describe(a("search")), "ファイルを検索");
  assert.equal(describe(a("other")), null);
  assert.equal(describe(a("bash", null, "x".repeat(50))), `${"x".repeat(40)} を実行`);
  assert.equal(describe(a("edit")), null);
  assert.equal(describe(a("bash")), null);
});
test("describe: 複数行のコマンドは 1 行にしてから切り詰める", () => {
  assert.equal(describe(a("bash", null, "cd /r &&\n  nix   flake\tcheck\n")), "cd /r && nix flake check を実行");
  assert.equal(describe(a("bash", null, `${"y".repeat(30)}\n\n${"z".repeat(30)}`)), `${"y".repeat(30)} ${"z".repeat(9)} を実行`);
});
