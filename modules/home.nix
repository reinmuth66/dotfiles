{ pkgs, inputs, ... }:

{
  imports = [
    ./zsh.nix
    ./zeno.nix
    ./yazi.nix
    ./git.nix
    ./bat.nix
    ./bottom.nix
    ./eza.nix
    ./fd.nix
    ./gpg.nix
    ./jq.nix
    ./uv.nix
    ./ripgrep.nix
    ./atuin.nix
    ./gh.nix
    ./gh-dash.nix
    ./starship.nix
    ./zed.nix
    ./wezterm.nix
    ./nvim.nix
    ./nh.nix
    ./claude.nix
    ./herdr-app.nix
    ./agent-skills.nix
    ./zmk-battery-center.nix
    ./mole.nix
    ./ax.nix
    ./headroom.nix
    ./omnigraph.nix
    ./ollama.nix
    ./zettelist.nix
    ./czg.nix
    ./marp.nix
    ./pdf-cli.nix
    ./aerospace.nix
    ./karabiner.nix
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
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli
    colima
    csvlens
    docker
    dust
    ffmpeg
    fx
    ghq
    imagemagick
    moralerspace-hw
    nerd-fonts.hack
    poppler
    p7zip
    resvg
    sd
    sketchybar-app-font
    switchaudio-osx
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
