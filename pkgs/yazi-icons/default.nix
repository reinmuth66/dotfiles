# yazi の [icon] の表 (ファイル名、拡張子、ディレクトリごとの文字と色) を JSON にする。
# herdr のツリーの mod が読む。表は使っている yazi と同じ nixpkgs の版から来る
{ writeText, yazi-unwrapped }:
let
  theme = builtins.fromTOML (
    builtins.readFile "${yazi-unwrapped.srcs.code_src}/yazi-config/preset/theme-dark.toml"
  );
in
writeText "yazi-icons.json" (builtins.toJSON theme.icon)
