{ stdenvNoCC, cava }:

# cava の SDL/GLSL 版を、sketchybar の Spotify ポップアップに重ねて表示するための .app。
#
# - cava に sdl-window.patch を当てる: 枠なし・最前面 (ウィンドウレベル 102。sketchybar のポップアップは
#   101)・クリックを通す・フォーカスを奪わない。あわせて、cava が許可の有無を事前に確認して、なければ
#   エラーで終了する処理をやめる (下記)。
# - fftw-estimate.patch: FFT の計画を FFTW_MEASURE (実測して最速の方式を探す) から FFTW_ESTIMATE にする。
#   起動時の cava_init が約 670ms から数 ms になる (結果は同じ)。起動の遅さの大半はここだった。
# - 音声の取得 (Core Audio tap) には「システムオーディオ録音」の許可が要る。許可は起動元のアプリに付くので、
#   sketchybar の子プロセスのままでは通らない。専用の .app に包んで `open` で起動し、.app に許可を付ける。
#   事前確認をやめたので、許可がないときは macOS 標準のダイアログが出る。「許可」を押せば、以後は通る
#   (ダイアログが出ている間の最初の起動は、音声の形式が取れずに終了する)。
# - 許可は署名の「指定要件」に紐づく。ad-hoc 署名の既定の要件は cdhash なので、cava を更新するたびに外れる。
#   そこで要件を identifier だけにして署名する (更新しても許可が残る。実機で確認済み)。
#   識別子を変えると、許可を付け直す必要がある (古い項目は tccutil reset AudioCapture <識別子> で消せる)。
#   許可は、システム設定の「システムオーディオ録音のみ」に CavaViz.app を手で追加しても付けられる
#   (一覧に出なくても、権限データベースには記録される)。
# - 署名には macOS 標準の /usr/bin/codesign を使う。Nix のサンドボックスが無効 (sandbox = false) なので
#   ビルド中でも使える。サンドボックスを有効にすると、このビルドは失敗する。
let
  identifier = "local.dotfiles.cavaviz";

  cavaSdl = (cava.override { withSDL2 = true; }).overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./sdl-window.patch
      ./fftw-estimate.patch
    ];
    # パッチが objc_msgSend を使うので、Objective-C のランタイムをリンクする
    env = (old.env or { }) // {
      NIX_LDFLAGS = "-lobjc";
    };
  });
in
stdenvNoCC.mkDerivation {
  pname = "cavaviz";
  version = cava.version;

  dontUnpack = true;
  # darwin の fixup は Mach-O を ad-hoc で署名し直し、下で付けた指定要件を上書きしてしまう
  dontFixup = true;

  installPhase = ''
    app=$out/Applications/CavaViz.app
    mkdir -p $app/Contents/MacOS
    cp ${cavaSdl}/bin/cava $app/Contents/MacOS/cava
    cat > $app/Contents/Info.plist <<'PLIST'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>${identifier}</string>
    <key>CFBundleName</key><string>CavaViz</string>
    <key>CFBundleExecutable</key><string>cava</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>NSAudioCaptureUsageDescription</key><string>Spotify visualizer for sketchybar</string>
    </dict></plist>
    PLIST
    /usr/bin/codesign --force --sign - -r='designated => identifier "${identifier}"' $app
  '';
}
