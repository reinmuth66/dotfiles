{ inputs, pkgs, ... }:

{
  home.packages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pdf-cli ];

  home.sessionVariables = {
    DOCVIEWER_SUPERSAMPLE = "1";
  };
}
