---
name: wrap-app-permission
description: "Stop macOS permissions (Accessibility, Screen/Audio Recording) from resetting after each flake update by wrapping a Nix-store process in an .app with a fixed-identifier signature. Use for repeated permission prompts, TCC issues, or launchd agents such as sketchybar and cava, even if this skill is not named."
---

# 更新のたびに外れる macOS 権限を .app で維持する

Nix で入れたプログラムに macOS の権限を与えても、flake を更新するたびに許可が外れて再びプロンプトが出る。
この問題を、プログラムを `.app` に包んで直す。

引数は `<対象のプログラムまたは launchd agent>`。例: `sketchybar`。

## 背景: なぜ外れるのか (実機で確認済み)

手順の各判断は、次の仕組みに基づく。

- TCC は、許可を「責任プロセス」に紐づける。責任プロセスは、launchd の `/bin/sh` の次に exec された最初の非 Apple 実行ファイルで、
  一度決まると後続の exec では変わらない。子プロセス (osascript や補助コマンド) の権限要求も、この責任プロセスに帰属する。
- 責任プロセスが `.app` の main executable でなければ、許可は実行ファイルの「パス」で記録される。
  Nix ストアのパスは更新で変わるので、そのたびに別物になる。
- シェルスクリプトの wrapper (`makeWrapper` や `wrapProgram` の産物) は shebang の bash が責任プロセスになる。
  実体のバイナリではなく、nixpkgs 更新で変わる bash のパスに許可が付く。これが sketchybar で起きていたこと。
- `.app` の main executable なら、tccd はバンドル ID に帰属させる (ログの `BUNDLE_ATTRIBUTION`)。
  署名の designated requirement を identifier だけにすれば、中身が変わっても同じものとして扱われる。
  ad-hoc 署名の既定の requirement は cdhash で、更新のたびに変わる。

## 手順

### 0. 本当に権限が必要かを先に確認する

権限を使わずに済むなら、それが最も安い。`borders` (JankyBorders) は、使っていない機能のために起動時に
`AXIsProcessTrusted()` を呼び、macOS がストアパスごとに拒否の行を記録していた。
`modules/jankyborders.nix` のように、パッチで呼び出しを外して解決した。

誰が権限を要求しているかは tccd のログで見る。`log` は zsh のビルトインと衝突するので絶対パスで呼ぶ。

```bash
/usr/bin/log show --last 1h --info --debug --style compact \
  --predicate 'process == "tccd" AND eventMessage CONTAINS "AttributionChain"' | grep -v apple | head
```

- `responsible_path` が許可の付く対象、`accessing` が実際に要求した子プロセス。
- 現在の許可は、システム側の TCC データベースで読める (端末に Full Disk Access がある場合)。

  ```bash
  sqlite3 -readonly "/Library/Application Support/com.apple.TCC/TCC.db" \
    "select service, client, client_type, auth_value, datetime(last_modified,'unixepoch','localtime') from access where service like 'kTCCService%' order by last_modified"
  ```

  `client_type` が 1 ならパス単位、0 ならバンドル ID 単位。パス単位の行が `/nix/store/...` なら、この手順の対象。
  ユーザー領域の許可 (Microphone、Automation など) は `~/Library/Application Support/com.apple.TCC/TCC.db` にある。

### 1. 型を選ぶ

| 対象 | 型 | 実例 |
|---|---|---|
| 単体の Mach-O (cava など) | 本体を .app に入れ、`open` か launchd で起動する | `pkgs/cavaviz/default.nix` |
| shell script の wrapper を経由する (`programs.*` の wrapper など) | 小さなランチャーだけを .app に入れ、wrapper を exec させる | `pkgs/sketchybar-app/` |

wrapper がある場合はランチャー型を選ぶ。実体のバイナリを .app にコピーする型は、wrapper が整えていた PATH や LUA_PATH を
launchd の `EnvironmentVariables` で再現しなければならない。ランチャー型なら wrapper がそのまま環境を作る。

### 2. ランチャー型の実装

`pkgs/sketchybar-app/` の `main.c` と `default.nix` を `pkgs/<tool>-app/` にコピーし、次を書き換える。

- `default.nix` の `identifier` (`local.dotfiles.<tool>`)、`name`、`.app` 名、ランチャーの実行ファイル名、`CFBundleName`、`CFBundleExecutable`
- `main.c` の `perror` のメッセージ

`default.nix` の次の点は、書き換えずに残す。外すと、許可が維持されなくなる。

- `dontFixup = true`: Darwin の fixup が Mach-O を再署名し、designated requirement を上書きするため。
- `/usr/bin/codesign --force --sign - -r='designated => identifier "${identifier}"' $app`: requirement を identifier だけにするため。
  macOS 標準の codesign は `nix.settings.sandbox = false` のおかげでビルド中に呼べる。サンドボックスを有効にするとビルドは失敗する。
- `Info.plist` の `CFBundleIdentifier` と `CFBundleExecutable`: バンドル ID への帰属に要る。`LSUIElement` は Dock やメニューバーに出さないため。
- 必要な権限が TCC の説明文を要求するものなら、`NSAudioCaptureUsageDescription` のようなキーを足す。

`target` には wrapper のパスだけを渡す。署名の requirement は identifier のみなので、wrapper のストアパスが更新で変わっても許可は維持される。

### 3. launchd agent を差し替える

`modules/<tool>.nix` で、wrapper を直接ではなくランチャーを起動させる。実例は `modules/sketchybar.nix`。
`programs.*` が `Program` を設定しているので、`lib.mkForce` が要る。

```nix
let
  app = pkgs.callPackage ../pkgs/<tool>-app {
    target = lib.getExe config.programs.<tool>.finalPackage; # 既存の wrapper
  };
in
{
  launchd.agents.<tool>.config.Program =
    lib.mkForce "${app}/Applications/<Tool>.app/Contents/MacOS/<tool>-launcher";
}
```

- home-manager は `ProgramArguments` を `/bin/sh -c "wait4path && exec <Program>"` に変換する。`sh` は Apple のバイナリなので責任プロセスにならず、ランチャーが責任プロセスになる。
- 新しいファイルは `git add -N pkgs/<tool>-app` で flake から見えるようにする。

### 4. ビルドと検証

```bash
nix build --no-link '.#darwinConfigurations.ReinmuthLaptop.config.home-manager.users.reinmuth.home.activationPackage'
app=<出力された .app>
codesign -d -r- $app                 # designated => identifier "local.dotfiles.<tool>" と出ること
codesign --verify --strict $app
```

適用は、ユーザーが `nh darwin switch ~/dotfiles` で行う。Claude は実行しない。切り替え後に、ユーザーへ次を確かめるよう伝える。

- `/usr/bin/log show` で、`responsible_path` が `<Tool>.app/Contents/MacOS/<tool>-launcher` になっていること。
- 初回だけプロンプトが出る。許可すれば、以降の flake 更新では出ない。

### 5. 後始末 (ユーザーが行う)

- システム設定の権限一覧に残った旧 `bash` や旧ストアパスの項目は、手動で「−」で削除できる。
- `tccutil reset <Service>` は、サービス全体の許可を消すので他のアプリのものまで消える。bundle identifier を渡せば、そのアプリだけを消せる。

## 注意

- identifier を変えると許可は付け直しになる。identifier は決めたら変えない。
- パスが変わらない限り、この手順は不要。`/Applications` や Homebrew cask の .app は、すでに署名とバンドル ID で扱われる。
