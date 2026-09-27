{ config, pkgs, ... }:

let
  zmk-battery-center = pkgs.callPackage ../nix/zmk-battery-center.nix { };
  batteryStatePath = "${config.home.homeDirectory}/Library/Application Support/com.zmk-battery-center.app/external/battery-state-v1.json";
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

  launchd.agents.zmk-battery-center-watch = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.sketchybar}/bin/sketchybar"
        "--trigger"
        "zmk_battery_update"
      ];
      WatchPaths = [ batteryStatePath ];
      ThrottleInterval = 0;
    };
  };
}
