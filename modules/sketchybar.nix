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

  # Opens and closes the btm window of the system item. btm runs in a wezterm process of its own, separate from the everyday WezTerm,
  # and is told apart by --class. wezterm is a Homebrew cask, so it is not in Nix. See modules/darwin.nix.
  # - AeroSpace makes the window floating when it is detected, by the on-window-detected rule in modules/aerospace.nix, and this script
  #   makes it full screen, so it overlays the current workspace at the full size of the visible area, with AeroSpace's gap as the margin.
  #   The workspace does not switch.
  # - The tab bar is hidden. Everything else in wezterm.lua, such as font, color, and transparency, is applied as it is.
  # - toggle: if not running, launch. If frontmost, close. Otherwise bring it to the current workspace and focus it.
  # - state: prints front, background, or none. Used by items/system.lua for the color of the pill.
  btmToggle = pkgs.writeShellApplication {
    name = "btm-toggle";
    runtimeInputs = [
      pkgs.aerospace
      pkgs.coreutils
    ];
    text = ''
      class="btm-monitor"
      btm=${lib.getExe pkgs.bottom}
      wezterm_gui=/opt/homebrew/bin/wezterm-gui

      # The pattern's [-] keeps pgrep from matching its own command line.
      find_pid() { /usr/bin/pgrep -f -- "[-]-class $class" | head -n1 || true; }
      window_id() { aerospace list-windows --monitor all --pid "$1" --format '%{window-id}' | head -n1 || true; }
      focused_pid() { aerospace list-windows --focused --format '%{app-pid}' 2>/dev/null || true; }

      launch() {
        nohup "$wezterm_gui" --config enable_tab_bar=false \
          start --always-new-process --class "$class" -- "$btm" >/dev/null 2>&1 &
        local pid=$! id=""
        for _ in $(seq 1 100); do
          id=$(window_id "$pid")
          [ -n "$id" ] && break
          sleep 0.05
        done
        [ -n "$id" ] || return 0
        aerospace fullscreen --window-id "$id"
        aerospace focus --window-id "$id"
      }

      case "''${1:-toggle}" in
        state)
          pid=$(find_pid)
          if [ -z "$pid" ]; then
            echo none
          elif [ "$(focused_pid)" = "$pid" ]; then
            echo front
          else
            echo background
          fi
          ;;
        toggle)
          pid=$(find_pid)
          if [ -z "$pid" ]; then
            launch
          elif [ "$(focused_pid)" = "$pid" ]; then
            kill "$pid"
          else
            id=$(window_id "$pid")
            aerospace move-node-to-workspace --window-id "$id" "$(aerospace list-workspaces --focused)" 2>/dev/null
            aerospace focus --window-id "$id"
          fi
          ;;
      esac
    '';
  };
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
      btmToggle # opens and closes the btm window of the system item
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
