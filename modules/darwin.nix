{ ... }:

{
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "none";
    };

    casks = [
      "adobe-acrobat-reader"
      "affinity"
      "bambu-studio"
      "discord"
      "dockdoor"
      "freecad"
      "google-drive"
      "google-chrome"
      "google-japanese-ime"
      "karabiner-elements"
      "kicad"
      "microsoft-excel"
      "microsoft-powerpoint"
      "microsoft-teams"
      "microsoft-word"
      "raycast"
      "tailscale-app"
      "thaw"
      "thebrowsercompany-dia"
      { name = "wezterm@nightly"; greedy = true; }
      "zed"
    ];
  };

  # ユーザー設定 (home-manager がホームディレクトリを正しく認識するために必要)
  users.users.reinmuth = {
    home = "/Users/reinmuth";
  };

  # プライマリユーザーの指定 (homebrew 等のオプションに必要)
  system.primaryUser = "reinmuth";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # sudo をパスワード入力の代わりに Touch ID で認証できるようにする
  security.pam.services.sudo_local.touchIdAuth = true;

  # nix-darwin の options.json 生成を無効化 (Nix 2.33+ の builtins.derivation 警告を抑制)
  documentation.enable = false;

  # system.stateVersion は変更しない
  system.stateVersion = 6;
}
