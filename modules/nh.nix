{ pkgs, ... }:

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
      ];
      StartCalendarInterval = [
        { Hour = 0; Minute = 0; Weekday = 1; }
      ];
    };
  };
}
