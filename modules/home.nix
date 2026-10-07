{ pkgs, ... }:

{
  imports = [
    ./zsh.nix
    ./zeno.nix
    ./yazi.nix
    ./git.nix
    ./bat.nix
    ./bottom.nix
    ./atuin.nix
    ./gh.nix
    ./starship.nix
    ./zed.nix
    ./wezterm.nix
    ./nvim.nix
    ./nh.nix
    ./claude.nix
    ./zmk-battery-center.nix
    ./czg.nix
    ./marp.nix
    ./pdf-cli.nix
    ./aerospace.nix
    ./jankyborders.nix
    ./sketchybar.nix
    ./cavaviz.nix
    ./spicetify.nix
  ];

  home = {
    username = "reinmuth";
    homeDirectory = "/Users/reinmuth";
    stateVersion = "24.11";
  };

  home.packages = with pkgs; [
    colima
    docker
    dust
    eza
    fd
    ffmpeg
    gnupg
    imagemagick
    jq
    marp-cli
    moralerspace-hw
    nerd-fonts.hack
    poppler
    p7zip
    resvg
    ripgrep
    sd
    sketchybar-app-font
    texlab
  ];

  home.file.".markdownlint-cli2.yaml".source = ../config/markdownlint-cli2.yaml;
  home.file.".clang-format".source = ../config/clang-format;

  programs.home-manager.enable = true;

  xdg.configFile."nix/nix.conf".text = ''
    warn-dirty = false
  '';

  manual.manpages.enable = false;
  manual.html.enable = false;
}
