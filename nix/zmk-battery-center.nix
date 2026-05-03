{ stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation rec {
  pname = "zmk-battery-center";
  version = "0.7.1";

  src = fetchurl {
    url = "https://github.com/kot149/zmk-battery-center/releases/download/v${version}/zmk-battery-center_aarch64.app.tar.gz";
    hash = "sha256-G5wFamaJF7bwEFly3Xip2gcgS0A5UUhBgqCpXjOukYQ=";
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
