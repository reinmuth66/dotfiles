{ stdenvNoCC }:

# 音量と mute のメディアキーを合成して送る小さなコマンドで、実体は main.swift。sketchybar の volume item のスクロールが使う。
# OS が音量キーとして処理するので、標準の音量ポップアップが出る。osascript の set volume では出ない。
#
# Swift の処理系は、nixpkgs のものではなく macOS 標準の /usr/bin/swiftc を使う。Xcode Command Line Tools のもの。
# pkgs/btm-window と同じ。Nix のサンドボックスが無効、つまり sandbox = false なので、ビルド中でも使える。
#
# darwin の fixup は Mach-O を署名し直す。swiftc の ld が付けた ad-hoc 署名のままでよいので、dontFixup にする。
stdenvNoCC.mkDerivation {
  name = "media-key";

  dontUnpack = true;
  dontFixup = true;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    unset SDKROOT DEVELOPER_DIR NIX_CFLAGS_COMPILE NIX_LDFLAGS NIX_CFLAGS_LINK
    export HOME=$TMPDIR
    mkdir -p $out/bin
    /usr/bin/swiftc -module-cache-path $TMPDIR/swift-module-cache -O -swift-version 6 \
      -framework AppKit ${./main.swift} -o $out/bin/media-key
    runHook postInstall
  '';
}
