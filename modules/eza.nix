{ config, inputs, ... }:

{
  programs.eza = {
    enable = true;
    enableZshIntegration = false;
  };

  # yazi の flavor (config/yazi/theme.toml) と揃える。yazi の eza プレビューも、この色で出る。
  # programs.eza.theme は attrset しか受け付けないので、テーマのファイルを直接置く
  xdg.configFile."eza/theme.yml".source = "${inputs.eza-themes}/themes/catppuccin-macchiato.yml";

  # macOS の eza は既定で ~/Library/Application Support/eza を見るので、置き場所を明示する
  home.sessionVariables.EZA_CONFIG_DIR = "${config.xdg.configHome}/eza";
}
