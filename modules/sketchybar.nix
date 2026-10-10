{
  config,
  lib,
  pkgs,
  ...
}:

let
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
      pkgs.imagemagick # spotify: color extraction, wallpaper: thumbnail creation
      pkgs.switchaudio-osx # output destination of the volume item
      btmWindow # the btm window of the system item
      mediaKey # shows the standard volume popup when scrolling on the volume item
    ];
  };

  launchd.agents = lib.listToAttrs (
    map (name: {
      name = "sketchybar-${name}-helper";
      value = mkHelperAgent name;
    }) helperNames
  );
}
