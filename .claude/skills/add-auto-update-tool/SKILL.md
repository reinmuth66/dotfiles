---
name: add-auto-update-tool
description: "Add a tool or source missing from nixpkgs, pinned, with an auto-update PR workflow: release binary (fetchurl), tag-pinned flake input, or flake = false input. Use for pinning versions or revs, update-*.yaml workflows, or replacing fetchFromGitHub rev pins, even if this skill is not named."
---

# 固定 + 自動更新 PR 付きでツール・ソースを追加

nixpkgs にないツールやソースを固定して追加し、新しいリリースやコミットが出たら週次で PR が作られる状態にする。
nixpkgs にあるツールには不要 (週次の `update-flake.yaml` が nixpkgs ごと更新する)。

引数は `<owner/repo> [tool-name]`。

## なぜ自動化が要るか

flake は「最新のリリースタグに追従する」仕組みを持たない。`nix flake update` が行うのは、指定された ref (ブランチやタグ) が指す commit の再解決だけである。

- タグに固定したいなら、タグ文字列そのものを書き換える仕組みが別に要る (方式 A、B のワークフロー)
- ブランチの最新コミットに追従するなら、ref を指定しない `flake = false` の input にするだけでよい。`update-flake.yaml` の `nix flake update` が rev と hash を更新する (方式 C)

自動化されるのは PR の作成までで、実機への反映は PR のマージ後にユーザーが `nh darwin switch` を実行する。

## 方式の選び方

upstream の形と、何に追従させたいかで決まる。上から順に確認し、最初に当てはまるものを使う。

| 条件 | 方式 | 追従先 |
|---|---|---|
| ビルド済みの成果物 (`.app.tar.gz` など) が release に添付されている | A: release バイナリ (`fetchurl`) | 最新 Release |
| そのタグ時点で `flake.nix` があり、`packages.<system>.<name>` を出力している | B: タグ固定 flake input | 最新 Release |
| 上記に当てはまらない (Release がない、成果物がない、flake がない、自分でビルドする、パッチを当てる) | C: `flake = false` の input でソースを追従 | デフォルトブランチの最新コミット |

雛形は `assets/` にある。プレースホルダ (`<tool>`、`<owner>/<repo>` など) を埋めて使う。何を埋めるかは、各ファイルの先頭の注釈に書いてある。

- A: `assets/release-binary.nix` (`nix/<tool>.nix` にコピー) と `assets/update-release-binary.yaml` (`.github/workflows/update-<tool>.yaml` にコピー)
- B: `assets/update-tag-pinned.yaml` (`.github/workflows/update-<tool>.yaml` にコピー)
- C: 雛形は要らない。既存の実例は `grep -n 'flake = false' flake.nix` で見つかる

補足:

- A と B の両方に当てはまる場合は、A の方がビルド不要で軽い。ただし B は `vendorHash` などを upstream が保守してくれる利点がある。
- C は Release ではなく**ブランチの最新コミット**を取り込む。未リリースの変更も入るので、安定性が要るなら A か B を選ぶ。
- C の派生 hash (Go の `vendorHash` など) は flake input では追従できない。「C の派生 hash」の節を参照する。
- 意図的に特定の rev で止めたいもの (互換性を確認した rev に固定している input など) は、自動更新の対象にしない。URL に rev を書いたまま手動で管理する。

### B の前提確認 (忘れやすい)

- タグ時点の flake の有無を確認する。flake が main にしかなく、タグには存在しないことがある (Nix 対応が途中のバージョンで追加されたリポジトリでは、それ以前のタグに `flake.nix` がない)。

  ```bash
  gh api "repos/<owner>/<repo>/contents/flake.nix?ref=<tag>" --jq .name
  ```

- upstream が `package.nix` を別ファイルに分離していても、flake の出力 (`packages.<system>.<name>`) が同じなら、利用側とワークフローは変更不要。
- `inputs.<name>.inputs.nixpkgs.follows = "nixpkgs"` を付けると手元の nixpkgs でビルドされ、flake.lock が肥大化しない。upstream が要求するビルダー (新しい言語バージョン用のビルダー関数など) が手元の nixpkgs になければビルドが失敗する。その場合は `follows` を外す。
- `gh release view` は「Latest」に指定された release を返す。複数系統のタグを持つリポジトリ (`-windows` のような接尾辞付きのタグが混在するものなど) でも、Latest が正しい系統を指すか `gh release list` で確認する。
- A と B は `gh release view` で検知するので、Release を持たない (タグだけのリポジトリを含む) upstream には使えない。その場合は C にする。

## 手順 A: リリースバイナリ

1. `assets/release-binary.nix` を `nix/<tool>.nix` にコピーし、プレースホルダを埋める (`version` と `hash` を 1 箇所ずつ持つ形)。`hash` は、次のコマンドで取った値に置き換える。

   ```bash
   nix store prefetch-file --hash-type sha256 --json "<成果物の URL>" | jq -r .hash
   ```

2. `modules/<tool>.nix` で `pkgs.callPackage ../nix/<tool>.nix { }` を呼び、`home.packages` に追加する。`modules/home.nix` の `imports` に加える。
3. `assets/update-release-binary.yaml` を `.github/workflows/update-<tool>.yaml` にコピーし、プレースホルダ (`<tool>`、`<owner>/<repo>`、アセット名) を埋める。
4. タグの接頭辞に注意する。雛形は、タグの `v` (例: `v1.2.3`) を外して `version` に入れ、URL で付け直している。upstream のタグが `v` で始まらない場合は、`sed 's/^v//'` と URL の `v${VERSION}` を調整する。
5. 雛形のワークフローは、`version = "..."` と `hash = "..."` の全一致を `sed` で書き換える。`nix/<tool>.nix` では、`version` と `hash` を 1 回ずつだけ代入し、コメントの中にも、その形の文字列を書かない。

## 手順 B: タグ固定 flake input

1. `flake.nix` の `inputs` に追加する。タグは現在の最新リリースにする。

   ```nix
   <name> = {
     url = "github:<owner>/<repo>/<tag>";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```

2. `outputs` の `home-manager.extraSpecialArgs` の `inherit (inputs) ...` に `<name>` を足す。
3. `modules/<tool>.nix` を作り、`home.nix` の `imports` に追加する。

   ```nix
   { <name>, pkgs, ... }:
   {
     home.packages = [ <name>.packages.${pkgs.stdenv.hostPlatform.system}.<name> ];
   }
   ```

   `overlays.default` に頼らず `packages.<system>` を使う。overlay はタグ時点の flake に存在しないことがある。

4. `assets/update-tag-pinned.yaml` を `.github/workflows/update-<tool>.yaml` にコピーし、プレースホルダを埋める。
   - `<gh-repo>`: GitHub 上の表記のリポジトリ (`gh release view --repo` に渡す)
   - `<flake-url-prefix>`: flake の input の URL のタグの手前まで (例: `github:<owner>/<repo>/`)。大文字小文字が `<gh-repo>` と違うことがある
   - `<name>`: flake の input 名 (`nix flake update <name>`)
   - `<tool>`: ブランチ名、コミット/タイトル文言
5. タグに数字とドット以外 (`-beta`、`-rc1` など) が入りうるなら、雛形のタグの正規表現を広げる。雛形は、タグの先頭の `v` / `V` があってもなくても動く。

## 手順 C: `flake = false` の input でソースを追従

`pkgs.fetchFromGitHub { rev, hash }` で固定していたものを、flake の input に置き換える。新しいワークフローは要らない。`update-flake.yaml` が毎週 `nix flake update` を実行し、rev と hash を `flake.lock` で更新する。

1. `flake.nix` の `inputs` に追加する。ref は付けない (付けるとその ref に固定される)。

   ```nix
   <name> = {
     url = "github:<owner>/<repo>";
     flake = false;
   };
   ```

2. `outputs` の `home-manager.extraSpecialArgs` の `inherit (inputs) ...` に `<name>` を足す。
3. 使う側で `fetchFromGitHub` を input に置き換える。

   - モジュールなら引数に `<name>` を足し、`src = <name>;` とする
   - `callPackage` するパッケージなら、引数 (`src` など) として渡す
   - `${<name>}` はストアパスになる。`<name>.rev`、`<name>.shortRev`、`<name>.lastModifiedDate` も使える (version の組み立てなど)

   実例は、`flake.nix` の既存の `flake = false` の input 名を `grep -rn '<input 名>' modules nix` で引くと見つかる。

4. 既存の固定コミットから移す場合は、同じコミットのままロックする。何もしないと、ロック時点の最新コミットまで進んでしまう。

   1. いったん URL に `/<現在の rev>` を付けて `nix flake lock` する。ロックされた `narHash` が元の `fetchFromGitHub` の hash と一致すれば、ソースは同一である。
   2. URL から rev を外す。
   3. `flake.lock` の該当 node から `original.rev` を消す。

      ```bash
      jq 'del(.nodes["<name>"].original.rev)' flake.lock > flake.lock.new && mv flake.lock.new flake.lock
      ```

   4. `nix flake lock` を実行し、`flake.lock` に差分が出ない (rev が動かない) ことを確認する。

   `--override-input` は `flake.lock` に書かれないので、この目的には使えない。

### C の派生 hash (vendorHash など)

ソースから導出される hash (Go の `vendorHash`、npm の `npmDepsHash`、Rust の `cargoHash`) は `go.sum` などに依存するため、flake input では追従できない。ソースを C にしたら、`update-flake.yaml` の `nix flake update` の後に、hash を再計算する step を足す。実例は `update-flake.yaml` の、`vendorHash` を再計算する step (`grep -n vendorHash .github/workflows/update-flake.yaml`)。

1. hash をダミー (`sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=`) に `sed` で置換する。
2. パッケージ全体ではなく、hash を持つ中間 derivation だけをビルドする。Go なら `.goModules` である。`nix build --impure --expr` で、`builtins.getFlake (toString ./.)` から input を渡す。ubuntu ランナーでも動くよう、`system = builtins.currentSystem` を使う。
3. 失敗出力の `got:` 行から正しい hash を取り、`sed` で書き戻す。
4. 取得できなかった場合は `git checkout` で戻し、`continue-on-error: true` で PR 作成は止めない。

注意点:

- GitHub Actions の `run:` は `bash -eo pipefail` で動く。`HASH=$(grep ... | head -1)` は、一致なしでも `|| true` を付けないと if に到達せず終了する。
- `.goModules` 以外 (`npmDeps` など) の attr は、この環境では未検証。上記と同じ手順で通るかを、ローカルで確認してから使う。
- 手順 4 の同一コミットでの移行で、再計算した hash が元の hash と一致することを確認できる (既存の実例で、一致を確認済み)。

## 共通の仕上げ

- 雛形のアクションのバージョン (`checkout`、`nix-installer-action`、`create-pull-request`) は、雛形を作った時点のもの。既存の `update-*.yaml` (`ls .github/workflows/update-*.yaml`) と揃える。
- **失敗の通知を付ける。** PR が作られないことは、「更新なし」と「失敗」を区別できない。雛形のワークフローには、次の step と `issues: write` の `permissions` が、すでに入っている。別のワークフローに足すときは、ジョブの末尾に次の step を置き、`permissions` に `issues: write` を足す。
  同じ失敗が続く間は、open な Issue にコメントが追記され、直してクローズしたあとの再発は、新しい Issue になる。

  ```yaml
  - name: Report failure
    if: failure()
    uses: ./.github/actions/notify-failure
    with:
      key: 'failure:<workflow 名>'
  ```

  `continue-on-error: true` の step は、`failure()` に引っかからない。その step に `id` を付け、`if: steps.<id>.outcome == 'failure'` で通知する (実例は `grep -n 'continue-on-error' .github/workflows/*.yaml` で見つかる)。
- **黙って空振りさせない。** 現在の版と最新の版を取る step では、書式を正規表現で検証し、想定外なら `exit 1` する。書き換えの step の最後には、差分が出たことを確認する。
  `git diff --quiet X && { ...; exit 1; }` を最後の行に置くと、差分がある正常時に終了コード 1 を返す。`if git diff --quiet X; then ...; exit 1; fi` と書く。
- 判定が複雑なら、ワークフローに直接書かず、`scripts/` に切り出し、模擬の `gh` / `nix` を PATH に置いて、`DRY_RUN=1` で全分岐を検証する (実例は `grep -l DRY_RUN scripts/*` で見つかるスクリプト)。
- `nix flake lock` で lock に追加する (他の input は動かない)。新規ファイルは `git add -N` で flake から見えるようにしてから評価する。未追跡ファイルは flake に見えない。
- 週次の `update-flake.yaml` と競合しない。A と B のタグ固定の input は `nix flake update` を実行しても同じタグのままである。C の input は `update-flake.yaml` が更新する。
- コミットはユーザーが依頼した時だけ行う。`nh darwin switch` もユーザーが実行する。

## 検証

実機への反映前に、次の順で確認する。

1. ビルド単体 (B の場合)

   ```bash
   nix build --impure --no-link --print-out-paths --expr \
     'let f = builtins.getFlake (toString ./.); in f.inputs.<name>.packages.aarch64-darwin.<name>'
   ```

2. 全体の評価

   ```bash
   nix eval --raw .#darwinConfigurations.ReinmuthLaptop.system.drvPath
   ```

   C で `fetchFromGitHub` を置き換えた場合は、評価だけでなく全体をビルドして確認する。パッチを当てるパッケージや、macOS 標準のツールチェーン (`/usr/bin/` 配下のコンパイラなど) を使うパッケージは、評価では通っても、ビルド時にしか分からない失敗がある。

   ```bash
   nix build --no-link --print-out-paths .#darwinConfigurations.ReinmuthLaptop.system
   ```

3. 成果物のスモークテスト。副作用のないコマンド (`--version` など) だけを実行する。
4. ワークフローの動作確認は、push 後に GitHub の Actions 画面で `workflow_dispatch` を実行する。PR を作るには、リポジトリ設定の「Allow GitHub Actions to create pull requests」が有効である必要がある (既存ワークフローが動いているなら有効)。
5. ワークフロー自体は、現在のバージョンが最新と一致する間は「更新なし」で終わる。更新処理を試したいときは、`flake.nix` (または `nix/<tool>.nix`) のタグを一つ古いものに戻した状態で実行する。C は、`flake.lock` の rev が最新と一致する間は差分が出ない。

## 既知の制約

- 自動 PR はビルドを検証しない (ubuntu ランナーでは Darwin 向けをビルドできない)。壊れた更新はマージ後、`nh darwin switch` のビルドで初めて分かる。必要なら `macos-latest` ランナーで `nix build` するジョブを足す。
- C は最新コミットを追うので、upstream の破壊的変更がそのまま PR になる。`update-flake.yaml` は全 input を 1 つの PR にまとめるため、1 つが壊れると他の更新も巻き込まれる。壊れた input だけ止めたい場合は、URL に `/<rev>` を付けて固定し、PR から `flake.lock` の該当部分を戻す。
- C の input は、サブモジュールを取得しない (`fetchFromGitHub` も同様)。サブモジュールが要る場合は `git+https://...?submodules=1` の URL を使う。
- ツールが自分で更新する機能を持つ場合 (自己アップデートのコマンドなど) は、Nix 管理下で無効になることを確認する。
