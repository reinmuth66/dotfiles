{ config, lib, pkgs, spicetify-nix, ... }:

let
  spicePkgs = spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ spicetify-nix.homeManagerModules.default ];

  programs.spicetify = {
    enable = true;
    theme = spicePkgs.themes.catppuccin;
    colorScheme = "macchiato";
    enabledExtensions = with spicePkgs.extensions; [
      shuffle
      allOfArtist
      adblockify
    ];

    enabledSnippets = [
      ''
        :root .view-homeShortcutsGrid-equaliser,
        :root .main-trackList-playingIcon {
          background-image: none !important;
          padding-left: 0 !important;
        }
        :root .view-homeShortcutsGrid-equaliserImage,
        :root .main-trackList-playingIcon img {
          filter: hue-rotate(126deg) saturate(0.7) brightness(1.15);
        }
      ''
    ];
  };

  # Spotify の自動更新を止める。更新が走ると Nix ストア内の Spicetify 適用済みアプリが
  # 素の Spotify に置き換わり、テーマが消えて nix-store --verify-path も壊れる。
  # spicetify 公式 CLI の `spicetify spotify-updates block` (macOS) と同じ方式:
  # 更新の展開先 PersistentCache/Update を空のディレクトリにして uchg (ユーザー
  # イミュータブル) を付け、Spotify から書き込み・削除・改名をできなくする。
  # 解除するには `chflags nouchg` が要る。
  home.activation.blockSpotifyUpdate = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cache="$HOME/Library/Application Support/Spotify/PersistentCache"
    update="$cache/Update"
    # 設定済み (ディレクトリで uchg 付き) なら何もしない
    if [ -d "$update" ] && [ ! -L "$update" ] && /bin/ls -ldO "$update" | grep -qw uchg; then
      :
    else
      # 以前のファイル版や、ダウンロード途中の更新が残っていれば消して作り直す
      if [ -e "$update" ] || [ -L "$update" ]; then
        run /usr/bin/chflags -R nouchg "$update" || true
      fi
      run rm -rf "$update"
      run mkdir -p "$update"
      run /usr/bin/chflags uchg "$update"
    fi
  '';

  # ログイン時に Spotify をバックグラウンドで起動する (-g: 前面に出さない、-j: 隠して起動)。
  # sketchybar の再生表示は Spotify が動いていないと機能しないため。
  # バンドル ID ではなく Home Manager Apps のパスで指定する
  # (ID だと Spotify 自身の更新用の一時コピーに解決されることがある)。
  # KeepAlive は付けない。付けるとユーザーが終了しても再起動される。
  launchd.agents.spotify-autostart = {
    enable = true;
    config = {
      ProgramArguments = [
        "/usr/bin/open"
        "-g"
        "-j"
        "${config.home.homeDirectory}/Applications/Home Manager Apps/Spotify.app"
      ];
      RunAtLoad = true;
    };
  };
}
