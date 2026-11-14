{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  # 取得元は config/agent-skills/registry/sources/*.nix で固定する。
  # `nix run .#skills-sources-lock` で sources.lock.json をまとめて更新する (update-agent-skills.yaml)
  registry = ../config/agent-skills/registry;
  sources = inputs.agent-skills.lib.agent-skills.sourcesFromLock {
    manifestsDir = "${registry}/sources";
    lockFile = "${registry}/sources.lock.json";
  };

  # 指定した source の skill を、ディレクトリ名のまま並べる
  fromSource =
    from: names:
    lib.genAttrs names (_: {
      inherit from;
    });

  # SKILL.md が呼ぶ python を Nix の python3 に揃える。macOS の /usr/bin/python3 は古く、
  # `python` は PATH に無い。相対パスの scripts/ は作業ディレクトリ次第で見つからないので、
  # 配り先の絶対パスにする。プラグインでなくなると CLAUDE_PLUGIN_ROOT も設定されない。
  # references/ の Markdown は transform の対象外なので、そこに書かれたコマンドは書き換わらない
  python = lib.getExe pkgs.python3;
  usePythonFromNix =
    name: skill:
    let
      skillDir = "${config.home.homeDirectory}/.claude/skills/${name}";
    in
    skill
    // {
      transform =
        { original, ... }:
        builtins.replaceStrings
          [
            "python3 scripts/"
            "python scripts/"
            "python3 \${CLAUDE_SKILL_DIR}/"
            "python \"\${CLAUDE_PLUGIN_ROOT}/.claude/skills/${name}/"
          ]
          [
            "${python} ${skillDir}/scripts/"
            "${python} ${skillDir}/scripts/"
            "${python} \${CLAUDE_SKILL_DIR}/"
            "${python} \"${skillDir}/"
          ]
          original;
    };
in
{
  imports = [ inputs.agent-skills.homeManagerModules.default ];

  programs.agent-skills = {
    enable = true;
    inherit sources;

    skills.explicit = lib.mapAttrs usePythonFromNix (
      fromSource "yomiyasu" [ "yomiyasu" ]
      // fromSource "imozuru" [ "imozuru" ]
      // fromSource "effective-html" [
        "html"
        "big-pics-little-words"
        "one-pager"
        "design-artifact"
        "html-wireframe"
        "html-prototype"
        "html-diagram"
        "html-plan"
      ]
      // fromSource "ui-ux-pro-max" [
        "ui-ux-pro-max"
        "design"
        "banner-design"
        "ui-styling"
        "brand"
        "slides"
        "design-system"
      ]
      // {
        frontend-design = {
          from = "claude-plugins-official";
          path = "frontend-design/skills/frontend-design";
        };
        claude-automation-recommender = {
          from = "claude-plugins-official";
          path = "claude-code-setup/skills/claude-automation-recommender";
        };
      }
    );

    # link は home.file の再帰リンクなので、~/.claude/skills のほかの中身
    # (claude.ai の synced/ や home-manager の MCP プラグイン) を消さない
    targets.claude = {
      enable = true;
      dest = ".claude/skills";
      structure = "link";
    };
  };
}
