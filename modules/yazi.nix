{ pkgs, yazi-flavors, yazi-plugins, compress-yazi, eza-preview-yazi, ... }:

let
  eza-preview-patched = pkgs.runCommand "eza-preview-patched" {} ''
    cp -r ${eza-preview-yazi} $out
    chmod -R +w $out
    substituteInPlace $out/main.lua \
      --replace 'ui.Text.CENTER' 'ui.Align.CENTER'
  '';
in
{
  home.packages = with pkgs; [ yazi ];

  xdg.configFile = {
    "yazi/yazi.toml".source   = ../config/yazi/yazi.toml;
    "yazi/keymap.toml".source = ../config/yazi/keymap.toml;
    "yazi/theme.toml".source  = ../config/yazi/theme.toml;
    "yazi/init.lua".source    = ../config/yazi/init.lua;

    "yazi/flavors/catppuccin-mocha.yazi".source      = "${yazi-flavors}/catppuccin-mocha.yazi";
    "yazi/flavors/catppuccin-macchiato.yazi".source = "${yazi-flavors}/catppuccin-macchiato.yazi";

    "yazi/plugins/smart-paste.yazi".source  = "${yazi-plugins}/smart-paste.yazi";
    "yazi/plugins/toggle-pane.yazi".source  = "${yazi-plugins}/toggle-pane.yazi";
    "yazi/plugins/git.yazi".source          = "${yazi-plugins}/git.yazi";
    "yazi/plugins/smart-tab.yazi".source    = ../config/yazi/plugins/smart-tab.yazi;
    "yazi/plugins/compress.yazi".source      = compress-yazi;
    "yazi/plugins/eza-preview.yazi".source   = eza-preview-patched;
  };
}
