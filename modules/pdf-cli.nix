{ pkgs, pdf-cli, ... }:

{
  home.packages = [ (pkgs.callPackage ../nix/pdf-cli.nix { src = pdf-cli; }) ];

  home.sessionVariables = {
    DOCVIEWER_SUPERSAMPLE = "1";
  };
}
