{ config, pkgs, ... }:

let
  # config/sketchybar/helper/<name>.c をビルドして sketchybar-<name>-helper にする
  mkHelper =
    name:
    pkgs.stdenv.mkDerivation {
      pname = "sketchybar-${name}-helper";
      version = "0-unstable";

      src = ../config/sketchybar/helper;

      buildInputs = [ pkgs.apple-sdk_15 ];

      buildPhase = ''
        runHook preBuild
        $CC -std=c99 -O2 ${name}.c -framework CoreFoundation -framework IOKit -o ${name}-helper
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp ${name}-helper $out/bin/sketchybar-${name}-helper
        runHook postInstall
      '';
    };

  mkHelperAgent = name: helper: {
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

  clockHelper = mkHelper "clock";
  systemHelper = mkHelper "system";
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
    extraPackages = [ pkgs.aerospace pkgs.macism pkgs.imagemagick ]; # imagemagick: spotify の色の抽出
  };

  launchd.agents.sketchybar-clock-helper = mkHelperAgent "clock" clockHelper;
  launchd.agents.sketchybar-system-helper = mkHelperAgent "system" systemHelper;
}
