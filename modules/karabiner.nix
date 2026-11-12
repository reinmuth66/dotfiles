{ config, ... }:

{
  # Karabiner-Elements は GUI での変更時に karabiner.json を書き換え、automatic_backups/ も作るため、
  # 読み取り専用の Nix ストアではなくリポジトリの実体を直接指す。
  # karabiner.json 単体を symlink すると書き換え時に通常ファイルへ置き換わるので、ディレクトリごと張る。
  xdg.configFile."karabiner".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/karabiner";
}
