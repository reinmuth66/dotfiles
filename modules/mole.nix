{ mole, pkgs, ... }:

{
  home.packages = [ mole.packages.${pkgs.stdenv.hostPlatform.system}.mole ];
}
