{ stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation rec {
  pname = "zmk-battery-center";
  version = "0.12.0";

  src = fetchurl {
    url = "https://github.com/kot149/zmk-battery-center/releases/download/v${version}/zmk-battery-center_${version}_aarch64.app.tar.gz";
    hash = "sha256-pwFuniHAZviQQn9djxGcTuJvuUt02jd3XQA93HiE8y4=";
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
