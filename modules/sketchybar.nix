{
  config,
  lib,
  pkgs,
  ...
}:

let
  # pkgs/sketchybar-helper/<name>.c をビルドして sketchybar-<name>-helper にする
  mkHelper = pkgs.callPackage ../pkgs/sketchybar-helper { };

  mkHelperAgent =
    name:
    let
      helper = mkHelper name;
    in
    {
      enable = true;
      config = {
        ProgramArguments = [ "${helper}/bin/sketchybar-${name}-helper" ];
        ProcessType = "Interactive";
        KeepAlive = true;
        RunAtLoad = true;
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sketchybar/${name}-helper.err.log";
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/sketchybar/${name}-helper.out.log";
      };
    };

  # pkgs/sketchybar-helper/<name>.c の名前。それぞれ launchd の agent になる
  helperNames = [
    "clock"
    "system"
  ];

  btmWindow = pkgs.callPackage ../pkgs/btm-window { };
  mediaKey = pkgs.callPackage ../pkgs/media-key { };
in
{
  programs.sketchybar = {
    enable = true;

    package = pkgs.sketchybar.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../pkgs/sketchybar/image-rotation.patch ];
    });

    configType = "lua";
    config = {
      source = ../config/sketchybar;
      recursive = true;
    };

    sbarLuaPackage = pkgs.sbarlua;
    extraPackages = [
      pkgs.aerospace
      pkgs.macism
      pkgs.imagemagick # spotify: 色の抽出、wallpaper: サムネイルの作成
      pkgs.switchaudio-osx # volume item の出力先
      btmWindow # system item の btm の窓
      mediaKey # volume item のスクロールで標準の音量ポップアップを出す
    ];
  };

  launchd.agents = lib.listToAttrs (
    map (name: {
      name = "sketchybar-${name}-helper";
      value = mkHelperAgent name;
    }) helperNames
  );
}
