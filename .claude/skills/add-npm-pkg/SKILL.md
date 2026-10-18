---
name: add-npm-pkg
description: "Add an npm CLI missing from nixpkgs via importNpmLock (pkgs/<tool>/ lockfile, modules/<tool>.nix wrapper). Use whenever asked to install or Nix-manage an npm package, replace `npm install -g`, or add a node tool nixpkgs lacks, even if this skill is not named."
---

# npm パッケージを Nix 環境に追加

nixpkgs に存在しない npm パッケージを `importNpmLock` で nix-darwin 環境に追加する。
`npm install -g` は環境の再現性を壊すので使わず、lock ファイルをリポジトリに持たせて Nix にビルドさせる。

引数は `<tool> [version]`。`version` を省略したら `nix shell nixpkgs#nodejs -c npm view <tool> version` の結果を使う。
実例は、同じ方式で入っている既存のパッケージ (`grep -l importNpmLock modules/*.nix` で見つかるモジュールと、その `pkgs/<tool>/`)。迷ったら、それを雛形にコピーして書き換える。

名前は 2 種類を区別する。
- `<tool>`: npm の正式なパッケージ名 (レジストリ上の名前)。`pkgs/<tool>/` と `modules/<tool>.nix` の名前にも、この正式名称をそのまま使う。スコープ付き (`@scope/name`) はディレクトリ名に使えないので、`name` の部分を使う。
- `<bin>`: コマンド名。`package.json` の `bin` のキーで、パッケージ名と一致するとは限らない (名前に `-cli` が付くパッケージで、コマンドには付かない、など)。wrapper の名前と呼び出し先に使う。

## npm は一時的に使う

この環境の PATH に `npm` はない (Nix で管理するので、グローバルには入れない)。
手順の `npm` は、`nix shell nixpkgs#nodejs -c npm ...` で一時的に使う。`npm install -g` や `nix profile` で恒久的に入れると、環境の再現性が崩れる。

## 手順

1. **package.json を作る。** `name` は他と衝突しない `<tool>-nix` にする。`private: true` で、対象を `dependencies` に入れる。
   CLI が追加のプラグインや peer 依存を実行時に読み込むなら、それも `dependencies` に並べる (既存の実例の `package.json` に、本体とプラグインを並べている例がある)。
   あわせて、コマンド名 `<bin>` を `nix shell nixpkgs#nodejs -c npm view <tool> bin` で調べておく (手順 3 と 6 で使う)。

   ```bash
   mkdir -p pkgs/<tool>
   cat > pkgs/<tool>/package.json <<EOF
   {
     "name": "<tool>-nix",
     "version": "1.0.0",
     "private": true,
     "dependencies": {
       "<tool>": "<確認したバージョン>"
     }
   }
   EOF
   ```

2. **package-lock.json を作る。** `importNpmLock` は lock のハッシュからビルドするので、lock が必須。
   `--package-lock-only` を付けると node_modules を作らずに済む。

   ```bash
   cd pkgs/<tool> && nix shell nixpkgs#nodejs -c npm install --package-lock-only
   ```

3. **modules/<tool>.nix を作る。** `buildNodeModules` の出力を wrapper から呼ぶ。
   `NODE_PATH` を渡すのは、CLI が依存を `require` で解決できるようにするため。

   ```nix
   { pkgs, ... }:
   let
     nodeModules = pkgs.importNpmLock.buildNodeModules {
       npmRoot = ../pkgs/<tool>;
       nodejs = pkgs.nodejs;
     };
     <bin> = pkgs.writeShellScriptBin "<bin>" ''
       export NODE_PATH="${nodeModules}/node_modules"
       exec ${pkgs.nodejs}/bin/node ${nodeModules}/node_modules/.bin/<bin> "$@"
     '';
   in
   {
     home.packages = [ <bin> ];
   }
   ```

   `<bin>` が `<tool>` と違う場合も、wrapper の名前と `.bin/` の呼び先は `<bin>` にする。`<tool>` のままにすると、ビルドは通っても、実行時に `No such file or directory` で失敗する。

4. **modules/home.nix の imports に `./<tool>.nix` を足す。**

5. **flake から見えるようにする。** flake は git が追跡しているファイルしか読まない。新規ファイルは intent-to-add にする。

   ```bash
   git add -N pkgs/<tool> modules/<tool>.nix
   ```

6. **ビルドして、コマンドを実際に実行する。** ビルドが通るだけでは、次の 2 つの失敗を見逃す。
   - モジュールを `home.nix` の imports に足し忘れても、ビルドは通る。
   - wrapper が呼ぶ bin 名を間違えても、ビルドは通る。wrapper はシェルスクリプトなので、中身は実行するまで検証されない。

   そこで、まずシステム全体をビルドし、次にユーザーの環境に入る `home.path` を作って、コマンドを実行する。

   ```bash
   nix build --no-link .#darwinConfigurations.ReinmuthLaptop.system
   out=$(nix build --no-link --print-out-paths '.#darwinConfigurations.ReinmuthLaptop.config.home-manager.users.reinmuth.home.path')
   $out/bin/<bin> --version
   ```

   `--version` が無いツールは `--help` など、副作用のない引数にする。
   どちらも何も出力しないツールがある。出力が無いと、動いたのか判断できない。
   その場合は、無害な引数を渡して、そのツール固有の出力で確認する (例: ポートを閉じるツールなら、使われていないポート番号を渡すと、該当するプロセスが無いことを示すメッセージが出る)。
   `No such file or directory` が出たら、bin 名か wrapper を直す。`ls $out/bin/` で存在を見るだけでは足りない (bin 名を間違えた wrapper も存在する)。

## 実機への反映

`nh darwin switch ~/dotfiles` はユーザーが実行する。Claude は実行しない。コミットもユーザーが頼んだときだけ行う。
切り替え後に `<bin> --version` など副作用のないコマンドで起動を確認するよう、ユーザーに伝える。

## 更新

バージョンを上げるときは `pkgs/<tool>/package.json` を書き換えて、手順 2 の lock 生成と手順 6 のビルド確認をやり直す。
