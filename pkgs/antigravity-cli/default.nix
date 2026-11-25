{ stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation rec {
  pname = "antigravity-cli";
  version = "1.5.16";
  buildId = "5250855658717184";

  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${version}-${buildId}/darwin-arm/cli_mac_arm64.tar.gz";
    hash = "sha512-M/VhfcdP6mBtR7JIPG0nHIUMnzycVbckxmTDwNS4IQDYGfvPVXFPhRdl9mKNQpaIOsiTm0/etV1ea5zpIxNdGA==";
  };

  sourceRoot = ".";

  # 配布物は実行ファイル 1 つ。修正しない (strip などで署名を壊さない)
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 antigravity $out/bin/agy
    runHook postInstall
  '';

  meta = {
    description = "Antigravity CLI (agy)";
    mainProgram = "agy";
    platforms = [ "aarch64-darwin" ];
    # meta.license は書かない。licenses.unfree にすると、unfree を許していない perSystem の pkgs では
    # nix build .#antigravity-cli が止まる
  };
}
