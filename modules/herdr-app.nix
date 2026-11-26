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
in
{
  home.packages = [
    wtr
    herdr-wtr
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
