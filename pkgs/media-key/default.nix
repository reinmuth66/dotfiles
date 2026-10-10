{ stdenvNoCC }:

# A small command that synthesizes and sends media keys for volume and mute; the implementation is main.swift. Used by scrolling on sketchybar's volume item.
# The OS handles it as a volume key, so the standard volume popup appears. It does not appear with osascript's set volume.
#
# For the Swift toolchain, use macOS's standard /usr/bin/swiftc, from the Xcode Command Line Tools, not nixpkgs's.
# Same as pkgs/btm-window. The Nix sandbox is disabled, i.e. sandbox = false, so it can be used during the build.
#
# Darwin's fixup re-signs Mach-O. The ad-hoc signature that swiftc's ld applied is fine as it is, so use dontFixup.
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
