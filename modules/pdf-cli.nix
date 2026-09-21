{ pkgs, ... }:

{
  home.packages = [ (pkgs.callPackage ../nix/pdf-cli.nix {}) ];

  home.sessionVariables = {
    DOCVIEWER_SUPERSAMPLE = "1";
  };
}
