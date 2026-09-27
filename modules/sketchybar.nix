{ pkgs, ... }:

{
  programs.sketchybar = {
    enable = true;

    configType = "lua";
    config = {
      source = ../config/sketchybar;
      recursive = true;
    };

    sbarLuaPackage = pkgs.sbarlua;
    extraPackages = [ pkgs.aerospace pkgs.macism ];
  };
}
