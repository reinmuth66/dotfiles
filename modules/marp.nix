{ inputs, pkgs, ... }:

let
  packages = inputs.self.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  xdg.configFile = {
    # テーマは、デザインシステム (config/design-system) のトークンから pkgs/marp-theme が組み立てる
    "marp/modern.css".source = "${packages.marp-theme}/modern.css";
    # 短い記法 (:::)、章名のフッター、図の線を足すエンジンの拡張
    "marp/engine".source = packages.marp-engine;
    "marp/.marprc.yml".source = ../config/marp/.marprc.yml;
  };

  home.file.".marprc.yml".source = ../config/marp/.marprc.yml;
}
