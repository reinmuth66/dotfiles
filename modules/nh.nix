{ config, pkgs, ... }:

{
  programs.nh = {
    enable = true;
    darwinFlake = "/Users/reinmuth/dotfiles";
  };

  launchd.agents.nh-clean = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.nh}/bin/nh"
        "clean"
        "user"
        "--keep-since"
        "7d"
        "--keep"
        "3"
        "--no-direnv"
      ];
      EnvironmentVariables = {
        PATH = "/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/nh-clean.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/nh-clean.log";
      StartCalendarInterval = [
        { Hour = 0; Minute = 0; Weekday = 1; }
      ];
    };
  };
}
