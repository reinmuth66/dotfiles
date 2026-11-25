---
name: wrap-app-permission
description: "Stop macOS permissions (Accessibility, Screen/Audio Recording) from resetting after each flake update by wrapping a Nix-store process in an .app with a fixed-identifier signature. Use for repeated permission prompts after updates, TCC issues, or launchd agents that keep losing their grants, even if this skill is not named."
---

# 更新のたびに外れる macOS 権限を .app で維持する

Nix で入れたプログラムに macOS の権限を与えても、flake を更新するたびに許可が外れて再びプロンプトが出る。
この問題を、プログラムを `.app` に包んで直す。

引数は `<対象のプログラムまたは launchd agent>`。

## 背景: なぜ外れるのか (実機で確認済み)

手順の各判断は、次の仕組みに基づく。

- TCC は、許可を「責任プロセス」に紐づける。責任プロセスは、launchd の `/bin/sh` の次に exec された最初の非 Apple 実行ファイルで、
  一度決まると後続の exec では変わらない。子プロセス (osascript や補助コマンド) の権限要求も、この責任プロセスに帰属する。
- 責任プロセスが `.app` の main executable でなければ、許可は実行ファイルの「パス」で記録される。
  Nix ストアのパスは更新で変わるので、そのたびに別物になる。
- シェルスクリプトの wrapper (`makeWrapper` や `wrapProgram` の産物) は shebang の bash が責任プロセスになる。
  実体のバイナリではなく、nixpkgs 更新で変わる bash のパスに許可が付く。wrapper 経由で起動するプログラムで、実際にこれが起きていた。
- `.app` の main executable なら、tccd はバンドル ID に帰属させる (ログの `BUNDLE_ATTRIBUTION`)。
  署名の designated requirement を identifier だけにすれば、中身が変わっても同じものとして扱われる。
  ad-hoc 署名の既定の requirement は cdhash で、更新のたびに変わる。

## 手順

### 0. 本当に権限が必要かを先に確認する

権限を使わずに済むなら、それが最も安い。使っていない機能のために、起動時に権限確認の API (`AXIsProcessTrusted()` など) を呼ぶプログラムがあり、macOS がストアパスごとに拒否の行を記録する。
パッチでその呼び出しを外せば、権限そのものが不要になる (既存の実例は `grep -rl AXIsProcessTrusted modules/` で見つかる)。

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

| 対象 | 型 | 雛形 / 実例 |
|---|---|---|
| 単体の Mach-O | 本体を .app に入れ、`open` か launchd で起動する | 雛形なし。既存の実例は `grep -l 'designated => identifier' pkgs/*/default.nix` のうち、`main.c` を持たないもの |
| shell script の wrapper を経由する (`programs.*` の wrapper など) | 小さなランチャーだけを .app に入れ、wrapper を exec させる | 雛形 `assets/launcher/` (`main.c` と `default.nix`) |
| すでに .app で、launchd がその実行ファイルを直接起動する | その .app を複製し、requirement を identifier だけにして再署名する (ランチャーは要らない) | 下の「再署名型の実装」 |

まず対象が .app かを確かめる (`ls <パッケージ>/Applications`)。.app なら再署名型が最も簡単で、ランチャーは要らない。
wrapper がある場合はランチャー型を選ぶ。実体のバイナリを .app にコピーする型は、wrapper が整えていた PATH などの環境変数を
launchd の `EnvironmentVariables` で再現しなければならない。ランチャー型なら wrapper がそのまま環境を作る。

### 2. ランチャー型の実装

雛形 `assets/launcher/` の `main.c` と `default.nix` を `pkgs/<tool>-app/` にコピーし、2 つのファイルの `<tool>` (小文字の名前) と `<Tool>` (.app の表示名) をすべて置き換える。これで `identifier` は `local.dotfiles.<tool>` になる。

`default.nix` の次の点は、書き換えずに残す。外すと、許可が維持されなくなる。

- `dontFixup = true`: Darwin の fixup が Mach-O を再署名し、designated requirement を上書きするため。
- `/usr/bin/codesign --force --sign - -r='designated => identifier "${identifier}"' $app`: requirement を identifier だけにするため。
  macOS 標準の codesign は `nix.settings.sandbox = false` のおかげでビルド中に呼べる。サンドボックスを有効にするとビルドは失敗する。
- `Info.plist` の `CFBundleIdentifier` と `CFBundleExecutable`: バンドル ID への帰属に要る。`LSUIElement` は Dock やメニューバーに出さないため。
- 必要な権限が TCC の説明文を要求するものなら、`NSAudioCaptureUsageDescription` のようなキーを足す。

`target` には wrapper のパスだけを渡す。署名の requirement は identifier のみなので、wrapper のストアパスが更新で変わっても許可は維持される。

### 2'. 再署名型の実装

nixpkgs の .app は ad-hoc 署名で、requirement が cdhash になっている。更新のたびに cdhash が変わるので、許可が外れる。
.app を複製し、識別子だけの requirement で署名し直すと、中身が変わっても同じものとして扱われる。`pkgs/<tool>-app/default.nix` に置く。

```nix
{ stdenvNoCC, <tool> }:

let
  identifier = "<元の CFBundleIdentifier>"; # Info.plist を書き換えないよう、元の値に合わせる
in
stdenvNoCC.mkDerivation {
  name = "<tool>-app";
  dontUnpack = true;
  dontFixup = true; # Darwin の fixup が再署名し、requirement を上書きするため
  installPhase = ''
    mkdir -p $out/Applications
    app=$out/Applications/<Tool>.app
    cp -R --no-preserve=mode ${<tool>}/Applications/<Tool>.app $app
    /usr/bin/codesign --force --sign - --identifier ${identifier} -r='designated => identifier "${identifier}"' $app
  '';
}
```

- 元の `CFBundleIdentifier` は、`plutil -p <.app>/Contents/Info.plist` で読む。
- コピーするのは .app だけ。CLI など .app 以外は、元のパッケージのものをそのまま使う。
- 署名には macOS 標準の codesign を使う。ランチャー型と同じく、`nix.settings.sandbox = false` が前提である。

### 3. launchd agent を差し替える

`modules/<tool>.nix` で、wrapper を直接ではなくランチャーを起動させる。再署名型では、`Program` を再署名した .app の実行ファイル (`.../Contents/MacOS/<元の実行ファイル名>`) にする。
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

- `/usr/bin/log show` で、`responsible_path` が `<Tool>.app/Contents/MacOS/<tool>-launcher` (再署名型では `<Tool>.app/Contents/MacOS/<元の実行ファイル名>`) になっていること。
- 初回だけプロンプトが出る。許可すれば、以降の flake 更新では出ない。

### 5. 後始末 (ユーザーが行う)

- システム設定の権限一覧に残った旧 `bash` や旧ストアパスの項目は、手動で「−」で削除できる。
- `tccutil reset <Service>` は、サービス全体の許可を消すので他のアプリのものまで消える。bundle identifier を渡せば、そのアプリだけを消せる。

## 注意

- identifier を変えると許可は付け直しになる。identifier は決めたら変えない。
- パスが変わらない限り、この手順は不要。`/Applications` や Homebrew cask の .app は、すでに署名とバンドル ID で扱われる。
