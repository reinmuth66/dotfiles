{ stdenvNoCC }:

# sketchybar の system item から開く、システムの状態の窓。btm (bottom) の画面を再現して、CPU・メモリ・ネットワークのグラフ、
# ディスクとプロセスの表を、文字セルの格子に描く (閲覧のみ)。ソースは同じディレクトリの *.swift。
#
# グラフの履歴は、sketchybar-system-helper (config/sketchybar/helper/system.c) が常に貯めていて、この窓は、開いた時に読む。
# なので、窓は常駐させなくてよく、開いている間だけ動く。btm 自身を動かさないので、btm の収集の負荷も無い。
# 数字は btm と同じ式・同じ書式 (値の測り方は helper と Processes.swift が、sysinfo クレートの macOS 実装に合わせてある)。
# 見た目は config/wezterm/wezterm.lua と揃えてある (値は Grid.swift の Theme)。
#
# - Swift の処理系は、nixpkgs のものではなく macOS 標準の /usr/bin/swiftc (Xcode Command Line Tools) を使う。
#   Nix のサンドボックスが無効 (sandbox = false) なので、ビルド中でも使える (pkgs/cavaviz の codesign と同じ)。
#   サンドボックスを有効にすると、このビルドは失敗する。
#   stdenv が設定する SDKROOT などは外し、swiftc に標準の SDK を選ばせる。
stdenvNoCC.mkDerivation {
  pname = "system-monitor";
  version = "0";

  src = ./.;

  # darwin の fixup は Mach-O を署名し直す。swiftc (ld) が付けた ad-hoc 署名のままでよい
  dontFixup = true;

  buildPhase = ''
    runHook preBuild
    unset SDKROOT DEVELOPER_DIR NIX_CFLAGS_COMPILE NIX_LDFLAGS NIX_CFLAGS_LINK
    export HOME=$TMPDIR
    /usr/bin/swiftc -O -swift-version 5 -module-cache-path $TMPDIR/swift-module-cache \
      -framework AppKit *.swift -o system-monitor
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp system-monitor $out/bin/system-monitor
    runHook postInstall
  '';
}
