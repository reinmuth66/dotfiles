{ inputs, pkgs, ... }:

{
  # The flake exports only packages.<system>.default (omnigraph, omnigraph-server, omnigraph-azure-admission).
  home.packages = [ inputs.omnigraph.packages.${pkgs.stdenv.hostPlatform.system}.default ];
}
