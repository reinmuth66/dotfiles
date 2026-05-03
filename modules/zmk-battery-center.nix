{ pkgs, ... }:

{
  home.packages = [ (pkgs.callPackage ../nix/zmk-battery-center.nix {}) ];
}
