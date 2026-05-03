{ pkgs, ... }:

let
  zmk-battery-center = pkgs.callPackage ../nix/zmk-battery-center.nix {};
in
{
  imports = [
    ./zsh.nix
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
  ];

  home.username = "reinmuth";
  home.homeDirectory = "/Users/reinmuth";
  home.stateVersion = "24.11";

  home.packages = with pkgs; [
    # ファイル操作
    eza fd dust rm-improved sd mcat

    # 検索
    ripgrep

    # システム監視
    bottom

    # ネットワーク / セキュリティ
    gnupg

    # メディア処理
    ffmpeg imagemagick resvg

    # データ処理
    jq poppler xan

    # アーカイブ
    p7zip

    # コンテナ
    colima docker

    # フォント
    moralerspace-hw

    # アプリ
    zmk-battery-center
  ];

  home.file.".markdownlint-cli2.yaml".text = ''
    config:
      MD012: false
      MD013: false
  '';

  programs.home-manager.enable = true;
}
