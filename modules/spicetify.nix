{ pkgs, spicetify-nix, ... }:

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
}
