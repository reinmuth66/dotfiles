{ config, pkgs, ... }:

let
  clockHelper = pkgs.stdenv.mkDerivation {
    pname = "sketchybar-clock-helper";
    version = "0-unstable";

    src = ../config/sketchybar/helper;

    buildInputs = [ pkgs.apple-sdk_15 ];

    buildPhase = ''
      runHook preBuild
      $CC -std=c99 -O2 clock.c -framework CoreFoundation -o clock-helper
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      cp clock-helper $out/bin/sketchybar-clock-helper
      runHook postInstall
    '';
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
    extraPackages = [ pkgs.aerospace pkgs.macism pkgs.imagemagick ]; # imagemagick: spotify の色の抽出
  };

  launchd.agents.sketchybar-clock-helper = {
    enable = true;
    config = {
      ProgramArguments = [ "${clockHelper}/bin/sketchybar-clock-helper" ];
      ProcessType = "Interactive";
      KeepAlive = true;
      RunAtLoad = true;
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sketchybar/clock-helper.err.log";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/sketchybar/clock-helper.out.log";
    };
  };
}
