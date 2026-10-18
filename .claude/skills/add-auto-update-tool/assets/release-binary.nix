{ stdenvNoCC, fetchurl }:

# Template for a tool distributed as a built artifact attached to a GitHub release.
# Copy to nix/<tool>.nix and replace every <placeholder>.
# Assign `version` and `hash` exactly once each in this file, and do not write those assignments inside comments:
# the update workflow reads and rewrites every match with grep/sed.
# Get the real hash with: nix store prefetch-file --hash-type sha256 --json "<artifact URL>" | jq -r .hash
stdenvNoCC.mkDerivation rec {
  pname = "<tool>";
  version = "<version without the v prefix>";

  src = fetchurl {
    url = "https://github.com/<owner>/<repo>/releases/download/v${version}/<asset-name using ${version}>";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  sourceRoot = ".";

  installPhase = ''
    mkdir -p $out/Applications
    cp -r <app-name>.app $out/Applications/
  '';

  meta = {
    description = "<one-line description>";
    platforms = [ "aarch64-darwin" ];
  };
}
