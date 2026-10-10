{
  stdenvNoCC,
  fetchFromGitHub,
  bottom,
}:

# The btm window opened from sketchybar's system item. btm is bottom. It shows btm in a SwiftTerm terminal view.
# Compared with opening in wezterm, startup is faster (about 730ms to about 210ms) and memory is smaller (about 350MB to about 150MB).
# The appearance matches config/wezterm/wezterm.lua. The values are in Style in main.swift.
#
# - SwiftTerm's Package.swift depends on swift-argument-parser and others, but they are not needed for macOS's main Sources/SwiftTerm,
#   so build directly with swiftc without going through SwiftPM. Build info is generated, instead of by SwiftTermBuildInfoPlugin,
#   by building and running the bundled generator tool ourselves.
# - Building SwiftTerm takes more than a minute. Optimization runs on one core and no log is output in the meantime.
#   So that it is not redone every time main.swift changes, SwiftTerm is a separate derivation, swiftterm-lib,
#   split from the app itself, which takes a few seconds. swiftterm-lib is not rebuilt except when SwiftTerm's rev changes.
# - The Swift toolchain is macOS's standard /usr/bin/swiftc, from the Xcode Command Line Tools, not nixpkgs's.
#   Because the Nix sandbox is disabled (sandbox = false), it can be used during the build. Same as codesign in pkgs/cavaviz.
#   With the sandbox enabled, this build would fail.
#   Remove SDKROOT and the like that stdenv sets, and let swiftc choose the standard SDK.
# - The location of btm is replaced with bottom's path at build time. btm's config in ~/.config/bottom is read by btm itself. See modules/bottom.nix.
let
  swiftterm = fetchFromGitHub {
    owner = "migueldeicaza";
    repo = "SwiftTerm";
    rev = "15fed4fd7ca7b0a8c77dd380412b18a5ce8600b5"; # commit of 2026-10-05
    hash = "sha256-kaWDZDRfgcSNC7oOu/b94WhXyuORdNFGuwX1LXwoxlo=";
  };

  # Preparation common to both builds. Remove stdenv's settings and let swiftc choose the standard SDK
  swiftEnv = ''
    unset SDKROOT DEVELOPER_DIR NIX_CFLAGS_COMPILE NIX_LDFLAGS NIX_CFLAGS_LINK
    export HOME=$TMPDIR
    swiftc="/usr/bin/swiftc -module-cache-path $TMPDIR/swift-module-cache"
  '';

  # Make SwiftTerm itself into the static library libSwiftTerm.a and the Swift module SwiftTerm.swiftmodule.
  # First generate the build info, i.e. git info and the terminfo table. The source is outside git's management, so the commit is passed via an environment variable.
  swifttermLib = stdenvNoCC.mkDerivation {
    name = "swiftterm-lib";

    dontUnpack = true;
    dontFixup = true;

    buildPhase = ''
      runHook preBuild
      ${swiftEnv}

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
# Darwin's fixup re-signs Mach-O. The ad-hoc signature that swiftc's ld applied is fine as it is, so use dontFixup.
stdenvNoCC.mkDerivation {
  name = "btm-window";

  dontUnpack = true;
  dontFixup = true;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    ${swiftEnv}

    substitute ${./main.swift} main.swift --replace-fail @btm@ ${bottom}/bin/btm
    mkdir -p $out/bin
    $swiftc -O -swift-version 6 -I ${swifttermLib}/lib -L ${swifttermLib}/lib -lSwiftTerm \
      -framework AppKit -framework Metal -framework MetalKit -framework QuartzCore \
      main.swift -o $out/bin/btm-window
    runHook postInstall
  '';
}
