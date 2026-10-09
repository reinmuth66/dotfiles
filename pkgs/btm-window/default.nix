{
  stdenvNoCC,
  fetchFromGitHub,
  bottom,
}:

# sketchybar の system item から開く、btm (bottom) の窓。SwiftTerm の端末ビューに btm を載せて表示する。
# wezterm で開くより、起動が速く (約 730ms から約 210ms)、メモリが小さい (約 350MB から約 150MB)。
# 見た目は config/wezterm/wezterm.lua と揃えてある (値は main.swift の Style)。
#
# - SwiftTerm は Package.swift が swift-argument-parser などに依存するが、macOS の本体 (Sources/SwiftTerm) には不要なので、
#   SwiftPM を通さず swiftc で直接ビルドする。ビルド情報の生成 (SwiftTermBuildInfoPlugin の代わり) は、同梱の
#   生成ツールを自分でビルドして実行する。
# - SwiftTerm のビルドは 1 分以上かかる (最適化が 1 コアで走り、その間ログも出ない)。main.swift を変えるたびに
#   やり直さないよう、SwiftTerm は別の derivation (swiftterm-lib) にして、アプリ本体 (数秒) と分けている。
#   SwiftTerm の rev を変えたとき以外は、swiftterm-lib は再ビルドされない。
# - Swift の処理系は、nixpkgs のものではなく macOS 標準の /usr/bin/swiftc (Xcode Command Line Tools) を使う。
#   Nix のサンドボックスが無効 (sandbox = false) なので、ビルド中でも使える (pkgs/cavaviz の codesign と同じ)。
#   サンドボックスを有効にすると、このビルドは失敗する。
#   stdenv が設定する SDKROOT などは外し、swiftc に標準の SDK を選ばせる。
# - btm の場所はビルド時に bottom のパスへ置き換える。btm の設定 (~/.config/bottom) は btm 自身が読む (modules/bottom.nix)。
let
  swiftterm = fetchFromGitHub {
    owner = "migueldeicaza";
    repo = "SwiftTerm";
    rev = "15fed4fd7ca7b0a8c77dd380412b18a5ce8600b5"; # 2026-10-05 のコミット
    hash = "sha256-kaWDZDRfgcSNC7oOu/b94WhXyuORdNFGuwX1LXwoxlo=";
  };

  # 2 つのビルドで共通の準備。stdenv の設定を外し、swiftc に標準の SDK を選ばせる
  swiftEnv = ''
    unset SDKROOT DEVELOPER_DIR NIX_CFLAGS_COMPILE NIX_LDFLAGS NIX_CFLAGS_LINK
    export HOME=$TMPDIR
    swiftc="/usr/bin/swiftc -module-cache-path $TMPDIR/swift-module-cache"
  '';

  # SwiftTerm 本体を、静的ライブラリ (libSwiftTerm.a) と Swift のモジュール (SwiftTerm.swiftmodule) にする
  swifttermLib = stdenvNoCC.mkDerivation {
    name = "swiftterm-lib";

    dontUnpack = true;
    dontFixup = true;

    buildPhase = ''
      runHook preBuild
      ${swiftEnv}

      # ビルド情報 (git の情報と terminfo の表) を生成する。ソースは git の管理外なので、コミットは環境変数で渡す
      mkdir gen
      $swiftc -O -parse-as-library ${swiftterm}/Sources/SwiftTermBuildInfoGenerator/*.swift -o geninfo
      SWIFTTERM_BUILD_COMMIT=${swiftterm.rev} ./geninfo ${swiftterm} gen/SwiftTermBuildInfo.swift gen/SwiftTermTerminfo.swift

      $swiftc -O -wmo -swift-version 6 -module-name SwiftTerm -emit-module -emit-module-path SwiftTerm.swiftmodule \
        -parse-as-library -emit-library -static -o libSwiftTerm.a \
        $(find ${swiftterm}/Sources/SwiftTerm -name '*.swift') gen/*.swift
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib
      cp libSwiftTerm.a SwiftTerm.swiftmodule $out/lib/
      runHook postInstall
    '';
  };
in
stdenvNoCC.mkDerivation {
  name = "btm-window";

  dontUnpack = true;
  # darwin の fixup は Mach-O を署名し直す。swiftc (ld) が付けた ad-hoc 署名のままでよい
  dontFixup = true;

  buildPhase = ''
    runHook preBuild
    ${swiftEnv}

    substitute ${./main.swift} main.swift --replace-fail @btm@ ${bottom}/bin/btm
    $swiftc -O -swift-version 6 -I ${swifttermLib}/lib -L ${swifttermLib}/lib -lSwiftTerm \
      -framework AppKit -framework Metal -framework MetalKit -framework QuartzCore \
      main.swift -o btm-window
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp btm-window $out/bin/btm-window
    runHook postInstall
  '';
}
