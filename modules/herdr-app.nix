{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  # herdr アプリの設定フォルダ。herdr 自身も同じフォルダに書く (AGENTS.md、*.d.ts、view.json、
  # shared.json、data/ など) ので、フォルダごとではなく、自分のファイルだけを 1 つずつ配る
  src = "${config.home.homeDirectory}/dotfiles/config/herdr-app";
  link = path: config.lib.file.mkOutOfStoreSymlink "${src}/${path}";

  # herdr が設定画面から書き換えるファイルと、自分のレイアウト、テーマ
  files = [
    "settings.json"
    "keys.json"
    "themes/catppuccin-macchiato.json"
    "layouts/workbench.json"
  ];

  # 自分の mod。フォルダごと配る (herdr は mod のフォルダに jsconfig.json と gpui-kit.d.ts を書く。
  # これらは .gitignore で外す)
  mods = [
    "quiet-toast"
    "resize-mode"
    "usage"
    "workspace"
    "tree"
    "preview"
    "pane-header"
  ];

  wtr = inputs.wtr.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # workbench.json の wtr の枠 ("terminal": "wtr") が映すターミナルで動かす。wtr が終わっても起こし直し、
  # ターミナルは終わらせない (ターミナルが終わると、herdr はその枠を落としてレイアウトを保存し直し、
  # mkOutOfStoreSymlink の先の dotfiles を書き換える)。wtr は子として動かす (ターミナルのプログラムが signal で
  # 死ぬと、core がシェルに差し替えて枠のつながりが切れる)。wtr を入れ替えるときは `pkill -x wtr` で止める。
  # 起動は preview の mod が受け持つ (mods/preview/wtr.js)。wtr は PATH から引き、switch 後の版を使う
  herdr-wtr = pkgs.writeShellScriptBin "herdr-wtr" ''
    while :; do
      wtr --state "$HOME/.config/herdr-app/data/wtr/state.json"
      sleep 1
    done
  '';

  # workbench.json の browser の枠 ("terminal": "browser") で動かす。herdr-wtr と同じ理由で、terminal-browser は子として動かす
  herdr-browser = pkgs.writeShellScriptBin "herdr-browser" ''
    while :; do
      terminal-browser
      sleep 1
    done
  '';

  # herdr の中で `terminal-browser action` の代わりに使う (引数は同じ。例: herdr-browser-action -- snapshot)。
  # terminal-browser は環境変数で外側の端末を判断し、herdr が引き継ぐ Ghostty の変数を見て Ghostty の窓を探して
  # 失敗する (herdr 用の判定は別の製品の herdr 向け)。そこで Ghostty の変数を外し、browser のターミナルと
  # 同じ tty で動く browser を --browser で指す
  herdr-browser-action = pkgs.writeShellApplication {
    name = "herdr-browser-action";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      tb() { env -u TERM_PROGRAM -u GHOSTTY_RESOURCES_DIR terminal-browser "$@"; }
      pid=$(hc get browser 2>/dev/null | jq -r '.pid // empty' || true)
      if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
        echo "herdr-browser-action: browser のターミナルがない" >&2
        exit 1
      fi
      tty=$(ps -o tty= -p "$pid" | tr -d ' ')
      key=$(tb ls --all --json | jq -r --arg tty "/dev/$tty" 'first(.browsers[] | select(.tty == $tty) | .key) // empty')
      if [ -z "$key" ]; then
        echo "herdr-browser-action: browser のターミナル ($tty) で動く terminal-browser がない" >&2
        exit 1
      fi
      tb action --browser "$key" "$@"
    '';
  };
in
{
  home.packages = [
    wtr
    herdr-wtr
    herdr-browser
    herdr-browser-action
  ];

  # dotfiles のファイルを直接指すので、switch なしで編集がその場で反映される
  xdg.configFile =
    lib.genAttrs (map (f: "herdr-app/${f}") files) (name: {
      source = link (lib.removePrefix "herdr-app/" name);
    })
    // lib.genAttrs (map (m: "herdr-app/mods/${m}") mods) (name: {
      source = link (lib.removePrefix "herdr-app/" name);
    })
    // {
      # ツリーの mod が使うファイルのアイコンの表 (yazi の [icon])。data/ には herdr も書くので、
      # フォルダではなく、このファイルだけを配る
      "herdr-app/data/yazi-icons.json".source =
        inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.yazi-icons;
    };
}
