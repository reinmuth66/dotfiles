{ inputs, pkgs, ... }:

let
  # テーマは、デザインシステム (config/design-system) のトークンから pkgs/marp-theme が組み立てる
  theme = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.marp-theme;
in
{
  xdg.configFile = {
    "marp/modern.css".source = "${theme}/modern.css";
    "marp/.marprc.yml".source = ../config/marp/.marprc.yml;
  };

  home.file.".marprc.yml".source = ../config/marp/.marprc.yml;
}
