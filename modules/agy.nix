{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  agyDir = "${config.home.homeDirectory}/.gemini/antigravity-cli";
  claudeDotfilesDir = "${config.home.homeDirectory}/dotfiles/config/claude";
  jq = lib.getExe pkgs.jq;

  # agy 自身が書き込むキー (model、trustedWorkspaces など) を残すため、Nix で決めるキーだけを書く
  settings = {
    statusLine = {
      type = "command";
      command = "~/.gemini/antigravity-cli/statusline.sh";
    };
  };
  settingsFile = (pkgs.formats.json { }).generate "agy-settings.json" settings;

  herdrRecordHook = {
    type = "command";
    command = "${pkgs.nodejs}/bin/node ${config.home.homeDirectory}/.claude/hooks/herdr-record.mjs";
  };
  hooks = {
    herdr-record = {
      SessionStart = [ herdrRecordHook ];
      PostToolUse = [
        {
          matcher = "*";
          hooks = [ herdrRecordHook ];
        }
      ];
    };
  };
  # Claude Code の skill (agent-skills.nix と home.file で ~/.claude/skills に置いたもの) を agy にも見せる。
  # path は ~/ だと読まれないので絶対パスで書く。1 段しか探さないので synced/ の中は入らない
  skillsConfig = {
    entries = [
      {
        path = "${config.home.homeDirectory}/.claude/skills";
        # Claude Code の設定を扱う skill は agy では使えない
        exclude = [ "claude-automation-recommender" ];
      }
    ];
  };
in
{
  # settings.json は下の activation でマージするので、ここでは settings を書かない。
  # MCP サーバーは mcp.nix の programs.mcp から取り、~/.gemini/config/mcp_config.json (読み取り専用のリンク) に書く
  programs.antigravity-cli = {
    enable = true;
    package = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli;
    enableMcpIntegration = true;
  };

  # settings.json は agy も /model や /config で書き込むので、丸ごと置き換えずにマージする
  home.activation.writeAgySettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    SETTINGS_FILE="${agyDir}/settings.json"
    run mkdir -p "${agyDir}"
    if [ -f "$SETTINGS_FILE" ]; then
      TEMP_FILE="$(mktemp "${agyDir}/.settings.json.XXXXXX")"
      if ! ${jq} -s '.[0] * .[1]' "$SETTINGS_FILE" ${settingsFile} > "$TEMP_FILE"; then
        rm -f "$TEMP_FILE"
        echo "agy settings.json のマージに失敗した" >&2
        exit 1
      fi
      run mv "$TEMP_FILE" "$SETTINGS_FILE"
      rm -f "$TEMP_FILE"
    else
      run cp ${settingsFile} "$SETTINGS_FILE"
    fi
    run chmod 600 "$SETTINGS_FILE"
  '';

  home.file = {
    ".gemini/antigravity-cli/statusline.sh".source =
      config.lib.file.mkOutOfStoreSymlink "${claudeDotfilesDir}/statusline.sh";
    ".gemini/config/hooks.json".text = builtins.toJSON hooks;
    ".gemini/config/skills.json".text = builtins.toJSON skillsConfig;
    # 共通の個人設定。Claude Code は ~/.claude/CLAUDE.md から @ で同じファイルを読む
    ".gemini/AGENTS.md".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/agents/AGENTS.md";
  };
}
