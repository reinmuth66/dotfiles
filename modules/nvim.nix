{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    withRuby = false;
    withPython3 = false;
    extraPackages = with pkgs; [ nil statix ];
  };

  xdg.configFile."nvim".source = ../config/nvim;
}
