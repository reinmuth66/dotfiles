{
  stdenvNoCC,
  bottom,
  swiftterm,
}:

# The btm window opened from sketchybar's system item. btm is bottom. It shows btm in a SwiftTerm terminal view.
# Compared with opening in wezterm, startup is faster (about 730ms to about 210ms) and memory is smaller (about 350MB to about 150MB).
# The appearance matches config/wezterm/wezterm.lua. The values are in Style in main.swift.
#
# - SwiftTerm's Package.swift depends on swift-argument-parser and others, but they are not needed for macOS's main Sources/SwiftTerm,
#   so build directly with swiftc without going through SwiftPM. Build info is generated, instead of by SwiftTermBuildInfoPlugin,
#   by building and running the bundled generator tool ourselves.
# - Building SwiftTerm takes about 30 seconds even with the threads below. No log is output in the meantime.
#   So that it is not redone every time main.swift changes, SwiftTerm is a separate derivation, swiftterm-lib,
#   split from the app itself, which takes a few seconds.
# - swiftterm-lib is made with builtins.derivation and the system's /bin/bash, not stdenv. Everything stdenv gives, such as bash,
#   is part of a derivation's hash, so with stdenv it would be rebuilt whenever a nixpkgs update changes bash,
#   though nothing in this build uses it. Now it is not rebuilt except when SwiftTerm's rev or this script changes.
#   The tools it needs are all given as absolute paths of macOS. Same reason as /usr/bin/swiftc below.
# - The Swift toolchain is macOS's standard /usr/bin/swiftc, from the Xcode Command Line Tools, not nixpkgs's.
#   Because the Nix sandbox is disabled (sandbox = false), it can be used during the build. Same as codesign in pkgs/cavaviz.
#   With the sandbox enabled, this build would fail.
#   Remove SDKROOT and the like that stdenv sets, and let swiftc choose the standard SDK.
# - The location of btm is replaced with bottom's path at build time. btm's config in ~/.config/bottom is read by btm itself. See modules/bottom.nix.
let
  # Preparation common to both builds. Remove stdenv's settings and let swiftc choose the standard SDK
  swiftEnv = ''
    unset SDKROOT DEVELOPER_DIR NIX_CFLAGS_COMPILE NIX_LDFLAGS NIX_CFLAGS_LINK
    export HOME=$TMPDIR
    swiftc="/usr/bin/swiftc -module-cache-path $TMPDIR/swift-module-cache"
  '';

  # Make SwiftTerm itself into the static library libSwiftTerm.a and the Swift module SwiftTerm.swiftmodule.
  # First generate the build info, i.e. git info and the terminfo table. The source is outside git's management, so the commit is passed via an environment variable.
  # -num-threads parallelizes only the LLVM code generation and keeps the whole-module optimization. It took about 54 seconds
  # on one core, and about 33 seconds with 10 threads on the actual device. Without -wmo, building per file in parallel takes about 17 seconds,
  # but optimization does not cross files, so it is not used for a terminal's parsing loop.
  swifttermLib = builtins.derivation {
    name = "swiftterm-lib";
    inherit (stdenvNoCC.hostPlatform) system;
    builder = "/bin/bash";
    args = [
      "-ec"
      ''
        export HOME=$TMPDIR
        swiftc="/usr/bin/swiftc -module-cache-path $TMPDIR/swift-module-cache"

        /bin/mkdir gen
        $swiftc -O -parse-as-library ${swiftterm}/Sources/SwiftTermBuildInfoGenerator/*.swift -o geninfo
        SWIFTTERM_BUILD_COMMIT=${swiftterm.rev} ./geninfo ${swiftterm} gen/SwiftTermBuildInfo.swift gen/SwiftTermTerminfo.swift

        $swiftc -O -wmo -num-threads "$(/usr/sbin/sysctl -n hw.ncpu)" -swift-version 6 \
          -module-name SwiftTerm -emit-module -emit-module-path SwiftTerm.swiftmodule \
          -parse-as-library -emit-library -static -o libSwiftTerm.a \
          $(/usr/bin/find ${swiftterm}/Sources/SwiftTerm -name '*.swift') gen/*.swift

        /bin/mkdir -p $out/lib
        /bin/cp libSwiftTerm.a SwiftTerm.swiftmodule $out/lib/
      ''
    ];
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
