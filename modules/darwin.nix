{ ... }:

{
  # nix-darwin が管理する Homebrew の設定
  # brew install / brew install --cask を手動で叩く必要はなくなる
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "none";
    };

    # GUI アプリ
    casks = [
      "adobe-acrobat-reader"
      "affinity"
      "copilot-cli"
      "discord"
      "google-drive"
      "google-chrome"
      "google-japanese-ime"
      "karabiner-elements"
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

  # Determinate Nix インストーラーを使用しているため nix-darwin の Nix 管理を無効化
  nix.enable = false;

  # darwin-rebuild をパスワードなしで sudo できるようにする
  security.sudo.extraConfig = ''
    reinmuth ALL=(ALL:ALL) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild
  '';

  # nix-darwin の options.json 生成を無効化 (Nix 2.33+ の builtins.derivation 警告を抑制)
  documentation.enable = false;

  # system.stateVersion は変更しない
  system.stateVersion = 6;
}
