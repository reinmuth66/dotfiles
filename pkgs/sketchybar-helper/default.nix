{ stdenv, apple-sdk_15 }:

# SketchyBar に値を送る常駐の C ヘルパー。name を渡すと、<name>.c をビルドして sketchybar-<name>-helper にする。
# clock.c は clock item に時計を、system.c は system item に CPU、メモリ、ディスクの使用状況を送る。
# launchd の agent にするのは modules/sketchybar.nix。
name:

stdenv.mkDerivation {
  name = "sketchybar-${name}-helper";

  src = ./.;

  buildInputs = [ apple-sdk_15 ];

  buildPhase = ''
    runHook preBuild
    $CC -std=c99 -O2 ${name}.c -framework CoreFoundation -o sketchybar-${name}-helper
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp sketchybar-${name}-helper $out/bin/
    runHook postInstall
  '';
}
