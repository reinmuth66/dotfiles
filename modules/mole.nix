{ inputs, pkgs, ... }:

{
  home.packages = [ inputs.mole.packages.${pkgs.stdenv.hostPlatform.system}.mole ];
}
