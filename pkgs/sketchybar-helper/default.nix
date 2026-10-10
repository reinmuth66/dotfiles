{ stdenv, apple-sdk_15 }:

# A resident C helper that sends values to SketchyBar. Given name, it builds <name>.c into sketchybar-<name>-helper.
# clock.c sends the time to the clock item, and system.c sends CPU, memory, and disk usage to the system item.
# modules/sketchybar.nix makes it a launchd agent.
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
