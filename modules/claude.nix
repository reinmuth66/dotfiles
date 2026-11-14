{
  config,
  lib,
  pkgs,
  ...
}:

let
  claudeDir = "${config.home.homeDirectory}/.claude";
  claudeDotfilesDir = "${config.home.homeDirectory}/dotfiles/config/claude";
  jq = lib.getExe pkgs.jq;

  # Nix で決めるキーだけを書く。permissions.allow、enabledPlugins、
  # extraKnownMarketplaces など、Claude Code 自身が書き込むものは実ファイルに任せる
  settings = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    model = "opus";
    permissions.defaultMode = "default";
    statusLine = {
      type = "command";
      command = "~/.claude/statusline.sh";
    };
    # コミットと PR に Claude の関与を書かない
    attribution = {
      commit = "";
      pr = "";
    };
    hooks.Stop = [
      {
        hooks = [
          {
            type = "command";
            command = "/usr/bin/afplay /System/Library/Sounds/Glass.aiff";
          }
        ];
      }
    ];
  };
  settingsFile = (pkgs.formats.json { }).generate "claude-settings.json" settings;
in
{
  # 本体の pkgs.claude-code は、darwin.nix の overlay で nix-claude-code のものに差し替わっている。
  # MCP サーバーは home-manager が生成する個人プラグインとして配られる。
  programs.claude-code = {
    enable = true;
    configDir = ".claude";
    mcpServers.playwright = {
      command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
    };
  };

  # settings.json は Claude Code も /permissions や /plugin で書き込むので、丸ごと置き換えずにマージする。
  # 上の settings のキーが勝ち、それ以外は実ファイルのまま残す。
  # hooks だけは上の settings からしか来ないので、ここで消した hook は実ファイルからも消える
  home.activation.writeClaudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    SETTINGS_FILE="${claudeDir}/settings.json"
    run mkdir -p "${claudeDir}"
    if [ -f "$SETTINGS_FILE" ]; then
      TEMP_FILE="$(mktemp "${claudeDir}/.settings.json.XXXXXX")"
      if ! ${jq} -s '(.[0] | del(.hooks)) * .[1]' "$SETTINGS_FILE" ${settingsFile} > "$TEMP_FILE"; then
        rm -f "$TEMP_FILE"
        echo "claude settings.json のマージに失敗した" >&2
        exit 1
      fi
      run mv "$TEMP_FILE" "$SETTINGS_FILE"
      # dry-run では mv されないので、残った一時ファイルを消す
      rm -f "$TEMP_FILE"
    else
      run cp ${settingsFile} "$SETTINGS_FILE"
    fi
    run chmod 644 "$SETTINGS_FILE"
  '';

  # スキーマはネットワークから取るので、失敗しても switch は止めない
  home.activation.validateClaudeSettings = lib.hm.dag.entryAfter [ "writeClaudeSettings" ] ''
    if ! ${lib.getExe pkgs.check-jsonschema} --schemafile "${settings."$schema"}" "${claudeDir}/settings.json" >/dev/null 2>&1; then
      echo "warning: claude settings.json がスキーマ検証を通らなかった (スキーマが取れなかった可能性もある)" >&2
    fi
  '';

  # dotfiles の実体を直接指すので、編集すれば switch しなくても反映される
  home.file = {
    ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${claudeDotfilesDir}/CLAUDE.md";
    ".claude/statusline.sh".source =
      config.lib.file.mkOutOfStoreSymlink "${claudeDotfilesDir}/statusline.sh";
  };
}
