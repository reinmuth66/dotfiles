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
    ./starship.nix
    ./zed.nix
    ./wezterm.nix
    ./nvim.nix
    ./claude.nix
    ./zmk-battery-center.nix
    ./czg.nix
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
    marp-cli
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
  home.file.".clang-format".source = ../config/clang-format;

  programs.home-manager.enable = true;

  manual.manpages.enable = false;
  manual.html.enable = false;
}
