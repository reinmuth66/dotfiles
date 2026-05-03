{ pkgs, ... }:

{
  imports = [
    ./zsh.nix
    ./zeno.nix
    ./yazi.nix
    ./git.nix
    ./bat.nix
    ./atuin.nix
    ./gh.nix
    ./ghostty.nix
    ./starship.nix
    ./zed.nix
    ./wezterm.nix
    ./nvim.nix
    ./claude.nix
    ./zmk-battery-center.nix
  ];

  home = {
    username = "reinmuth";
    homeDirectory = "/Users/reinmuth";
    stateVersion = "24.11";
  };

  home.packages = with pkgs; [
    bottom
    colima
    docker
    dust
    eza
    fd
    ffmpeg
    gnupg
    imagemagick
    jq
    mcat
    moralerspace-hw
    poppler
    p7zip
    resvg
    ripgrep
    rm-improved
    sd
    xan
  ];

  home.file.".markdownlint-cli2.yaml".source = ../config/markdownlint-cli2.yaml;

  programs.home-manager.enable = true;
}
