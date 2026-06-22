{ stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation rec {
  pname = "zmk-battery-center";
  version = "0.10.0";

  src = fetchurl {
    url = "https://github.com/kot149/zmk-battery-center/releases/download/v${version}/zmk-battery-center_aarch64.app.tar.gz";
    hash = "sha256-ORYU6KUgi57I7FHNolSa8yhs00FfRK35V68gy+VZ/iU=";
  };

  sourceRoot = ".";

  installPhase = ''
    mkdir -p $out/Applications
    cp -r zmk-battery-center.app $out/Applications/
  '';

  meta = {
    description = "System tray app for monitoring ZMK keyboard battery levels";
    platforms = [ "aarch64-darwin" ];
  };
}
