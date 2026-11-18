{ pkgs, inputs, ... }:

{
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "none";
    };

    casks = [
      "affinity"
      "bambu-studio"
      "blender"
      "discord"
      "freecad"
      "google-drive"
      "google-chrome"
      "google-japanese-ime"
      "herdr-app"
      "karabiner-elements"
      "kicad"
      "microsoft-excel"
      "microsoft-powerpoint"
      "microsoft-teams"
      "microsoft-word"
      "raycast"
      "tailscale-app"
      "thebrowsercompany-dia"
      {
        name = "wezterm@nightly";
        greedy = true;
      }
      "zed"
    ];
  };

  # ユーザー設定 (home-manager がホームディレクトリを正しく認識するために必要)
  users.users.reinmuth = {
    home = "/Users/reinmuth";
  };

  # プライマリユーザーの指定 (homebrew 等のオプションに必要)
  system.primaryUser = "reinmuth";

  # Google 日本語入力のメニューバーアイコンをモノクロ版に差し替える。
  # アプリの更新で元に戻るので、switch のたびに中身を比べ、違えばコピーし直す。
  system.activationScripts.postActivation.text = ''
    icon="/Library/Input Methods/GoogleJapaneseInput.app/Contents/Resources/hiragana.tiff"
    if [ -f "$icon" ] && ! /usr/bin/cmp -s ${../assets/hiragana_mono.tiff} "$icon"; then
      echo "restoring Google Japanese Input icon..." >&2
      /bin/cp ${../assets/hiragana_mono.tiff} "$icon"
    fi

    # カーソル近くに出る入力ソースと Caps Lock の表示 (CursorUIViewService) を消す。
    # 文書化されていない UIKit のフラグで、カーソルの幅やアニメーションも元に戻る。反映には再起動が要る。
    # この行を消しても元には戻らない。戻すときは次を実行して再起動する:
    #   sudo defaults delete /Library/Preferences/FeatureFlags/Domain/UIKit.plist redesigned_text_cursor
    /bin/mkdir -p /Library/Preferences/FeatureFlags/Domain
    /usr/bin/defaults write /Library/Preferences/FeatureFlags/Domain/UIKit.plist \
      redesigned_text_cursor -dict-add Enabled -bool NO
  '';

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "spotify"
      "claude"
    ];

  # pkgs.claude-code を nix-claude-code の公式ネイティブバイナリ版に差し替える
  nixpkgs.overlays = [ inputs.nix-claude-code.overlays.default ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.gc = {
    automatic = true;
    interval = [
      {
        Weekday = 1;
        Hour = 0;
        Minute = 0;
      }
    ];
    options = "--delete-older-than 7d";
  };
  launchd.daemons.nix-gc.serviceConfig = {
    StandardOutPath = "/var/log/nix-gc.log";
    StandardErrorPath = "/var/log/nix-gc.log";
  };

  # nix-darwin の options.json 生成を無効化 (Nix 2.33+ の builtins.derivation 警告を抑制)
  documentation.enable = false;

  # system.stateVersion は変更しない
  system.stateVersion = 6;
}
