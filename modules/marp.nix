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

    # テーマ modern と拡張の記法を、AI エージェントに伝える skill。
    # これ 1 つで足りるように書いてある (人が読む説明は config/marp/README.md)
    ".claude/skills/marp-modern/SKILL.md".source = ../config/marp/skill/SKILL.md;
    # 必要なときだけ読む資料 (手書きの HTML からの対応表など)
    ".claude/skills/marp-modern/references".source = ../config/marp/skill/references;
  };
}
