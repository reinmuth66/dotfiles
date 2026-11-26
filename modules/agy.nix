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
in
{
  home.packages = [
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli
  ];

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
  };
}
