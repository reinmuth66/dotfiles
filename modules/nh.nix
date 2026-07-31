{ pkgs, ... }:

{
  programs.nh = {
    enable = true;
    darwinFlake = "/Users/reinmuth/dotfiles";
  };

  # programs.nh.clean.extraArgs は launchd 上で複数フラグをまとめて
  # 1つの引数として渡してしまい nh 側でパースエラーになるため、
  # launchd.agents で ProgramArguments を直接組み立てる
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
