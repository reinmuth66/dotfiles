{ stdenvNoCC, cava }:

# cava の SDL/GLSL 版を、sketchybar の Spotify ポップアップの下に敷いて、背景と棒グラフを描かせるための .app。
#
# - cava に sdl-window.patch を当てる: 枠なし・ウィンドウレベル 100 (sketchybar のポップアップは
#   101 なので、ポップアップの文字や画像が窓の上に描かれる)・クリックを通す・フォーカスを奪わない。あわせて、cava が許可の有無を事前に確認して、なければ
#   エラーで終了する処理をやめる (下記)。
# - sdl-transparent.patch: 窓を透明にする。nixpkgs の SDL2 は sdl2-compat (中身は SDL3) で、窓の作成時のフラグを
#   そのまま SDL3 に渡すので、SDL3 の SDL_WINDOW_TRANSPARENT (0x40000000) を足す。これがないと SDL3 が窓の
#   view の背景を黒で塗り、シェーダーのアルファが無視される。アルファつきの GL の面も要求する。
#   シェーダーがアルファ 0 で描いた所 (ポップアップの角の外) は、後ろのデスクトップが透けて見える (シェーダーは popup.frag)。
# - sdl-highdpi.patch: 窓の描画面を Retina 解像度 (1pt が 2px) にする。シェーダーは pt で描くので、角丸と枠、
#   半ポイント位置の窓が、ぼやけずに描ける。サイズ変更時の glViewport も、pt ではなく px の大きさにする。
# - sdl-fractional-position.patch: 窓の位置の指示 ("show X Y") で小数を受け付け、NSWindow の setFrameOrigin で
#   置く。SDL_SetWindowPosition は整数 pt しか指定できないが、SketchyBar のポップアップは半ポイント位置に
#   描かれることがあり (中央揃えで、項目の位置が x.5 のとき)、窓に描く背景と枠がずれて見えるため。
# - sdl-progress.patch: 再生位置 (0〜1) をシェーダーの uniform float viz_progress に渡す。値は $CAVAVIZ_PROGRESS の
#   ファイルに 10 進数で書き、cava は毎フレーム、更新時刻が変わったときだけ読む。制御ファイルは最後の指示しか
#   持たない ("show" の直後に書くと "show" が消える) ので、別のファイルにしてある。値が変わると、棒が動いて
#   いなくても (無音) 1 回描き直す。シェーダーは、再生済みの棒と未再生の棒の色を分ける (popup.frag)。
# - tap-gate.patch: 音声取得 (tap) を、起動したまま入り切りできるようにする。$CAVAVIZ_AUDIO のファイルに
#   "on" か "off" を書くと、cava は 100ms 以内に tap を作る / 解放する。"off" の間は tap がないので、システムは
#   音声を収録せず (収録のインジケーターが消える)、棒は 0 に落ちる。"off" で起動したときは、ハードウェアに触れずに、
#   既定の出力デバイスのサンプルレートと、ステレオ・32bit float の形式で始める (tap の形式と同じ)。
#   一時停止中も窓 (棒の色で示す再生位置) を出したいが、収録は止めたいため。
# - sdl-ax-subrole.patch: 窓のアクセシビリティの subrole を AXSystemFloatingWindow にする。既定の
#   AXStandardWindow だと、AeroSpace が窓を管理対象にして、終了時に workspace の先頭のウィンドウへ
#   フォーカスを移してしまう (複数ウィンドウのアプリで、作業中のウィンドウが勝手に切り替わる)。
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
      ./sdl-transparent.patch
      ./fftw-estimate.patch
      ./sdl-ax-subrole.patch
      ./sdl-highdpi.patch
      ./sdl-fractional-position.patch
      ./sdl-progress.patch
      ./tap-gate.patch
    ];
    # パッチが objc_msgSend を使うので、Objective-C のランタイムをリンクする
    env = (old.env or { }) // {
      NIX_LDFLAGS = "-lobjc";
    };
  });
in
stdenvNoCC.mkDerivation {
  name = "cavaviz";

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
