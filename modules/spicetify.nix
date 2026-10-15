{ config, lib, pkgs, nixpkgs-spotify, spicetify-nix, ... }:

let
  inherit (pkgs.stdenv.hostPlatform) system;
  spicePkgs = spicetify-nix.legacyPackages.${system};

  pkgsSpotify = import nixpkgs-spotify {
    inherit system;
    config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "spotify" ];
  };
in
{
  imports = [ spicetify-nix.homeManagerModules.default ];

  programs.spicetify = {
    enable = true;
    spotifyPackage = pkgsSpotify.spotify;
    spicetifyPackage = pkgsSpotify.spicetify-cli;
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

  home.activation.blockSpotifyUpdate = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cache="$HOME/Library/Application Support/Spotify/PersistentCache"
    update="$cache/Update"
    if [ -d "$update" ] && [ ! -L "$update" ] && /bin/ls -ldO "$update" | grep -qw uchg; then
      :
    else
      if [ -e "$update" ] || [ -L "$update" ]; then
        run /usr/bin/chflags -R nouchg "$update" || true
      fi
      run rm -rf "$update"
      run mkdir -p "$update"
      run /usr/bin/chflags uchg "$update"
    fi
  '';

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
