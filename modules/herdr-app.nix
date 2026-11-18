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
in
{
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
