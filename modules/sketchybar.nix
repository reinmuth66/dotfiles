{
  config,
  lib,
  pkgs,
  swiftterm,
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

  btmWindow = pkgs.callPackage ../pkgs/btm-window { inherit swiftterm; };
  mediaKey = pkgs.callPackage ../pkgs/media-key { };

  # The .app that launchd starts, which execs the sketchybar wrapper that programs.sketchybar builds.
  # It makes the Accessibility permission stay attached even when the store path changes. See pkgs/sketchybar-app.
  sketchybarApp = pkgs.callPackage ../pkgs/sketchybar-app {
    target = lib.getExe config.programs.sketchybar.finalPackage;
  };
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

  launchd.agents =
    lib.listToAttrs (
      map (name: {
        name = "sketchybar-${name}-helper";
        value = mkHelperAgent name;
      }) helperNames
    )
    // {
      # Replaces the Program that programs.sketchybar sets. Launching the wrapper directly would make the Nix store's bash
      # the target of the Accessibility permission, which would then have to be attached again on every update.
      sketchybar.config.Program = lib.mkForce "${sketchybarApp}/Applications/Sketchybar.app/Contents/MacOS/sketchybar-launcher";
    };
}
