{ pkgs, ... }:

let
  zmk-battery-center = pkgs.callPackage ../nix/zmk-battery-center.nix { };
in
{
  home.packages = [ zmk-battery-center ];

  launchd.agents.zmk-battery-center = {
    enable = true;
    config = {
      ProgramArguments = [
        "${zmk-battery-center}/Applications/zmk-battery-center.app/Contents/MacOS/zmk-battery-center"
      ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };
}
