{ inputs, pkgs, ... }:

let
  packages = inputs.self.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  # marp-cli を包んだコマンド。設定を必ず読むので、シェルの関数は要らない
  home.packages = [ packages.marp ];

  xdg.configFile = {
    # テーマは、デザインシステム (config/design-system) のトークンから pkgs/marp-theme が組み立てる
    "marp/modern.css".source = "${packages.marp-theme}/modern.css";
    # 短い記法 (:::)、章名のフッター、図の線を足すエンジンの拡張
    "marp/engine".source = packages.marp-engine;
    "marp/.marprc.yml".source = ../config/marp/.marprc.yml;
  };

  home.file = {
    ".marprc.yml".source = ../config/marp/.marprc.yml;

    # modern テーマでスライドを書くときに、AI エージェントが読む skill。
    # 記法の説明の正本は config/marp/README.md で、skill からは syntax.md として読める
    ".claude/skills/marp-modern/SKILL.md".source = ../config/marp/skill/SKILL.md;
    ".claude/skills/marp-modern/syntax.md".source = ../config/marp/README.md;
  };
}
