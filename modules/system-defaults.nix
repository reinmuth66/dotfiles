{ ... }:

{
  # sudo をパスワード入力の代わりに Touch ID で認証できるようにする
  security.pam.services.sudo_local.touchIdAuth = true;

  # Dock を画面端にカーソルを移動しても表示されにくくする (auto-hide の出現遅延を大きくする)
  system.defaults.dock.autohide = true;
  system.defaults.dock.autohide-delay = 1000.0;

  # メニューバーを自動的に隠す
  system.defaults.NSGlobalDomain._HIHideMenuBar = true;
  system.defaults.CustomUserPreferences."com.apple.controlcenter" = {
    AutoHideMenuBarOption = 0;
  };

  # Dock を左側に配置する
  system.defaults.dock.orientation = "left";

  # キーのリピート速度を最速にする / リピート入力認識までの時間を最短にする (System Settings のスライダーでの最速値)
  system.defaults.NSGlobalDomain.KeyRepeat = 2;
  system.defaults.NSGlobalDomain.InitialKeyRepeat = 15;

  # トラックパッド設定
  # 軌跡の速さ
  system.defaults.NSGlobalDomain."com.apple.trackpad.scaling" = 3.0;
  # クリック: 中
  system.defaults.trackpad.FirstClickThreshold = 1;
  system.defaults.trackpad.SecondClickThreshold = 1;
  # 副ボタンのクリック: 2本指でクリックまたはタップ
  system.defaults.trackpad.TrackpadRightClick = true;
  system.defaults.trackpad.TrackpadCornerSecondaryClick = 0;
  # タップでクリック: on
  system.defaults.trackpad.Clicking = true;
  # 3本指ドラッグ
  system.defaults.trackpad.TrackpadThreeFingerDrag = true;
  # ナチュラルなスクロール: off
  system.defaults.NSGlobalDomain."com.apple.swipescrolldirection" = false;
  # ページ間をスワイプ: 2本指で左右にスクロール
  system.defaults.NSGlobalDomain.AppleEnableSwipeNavigateWithScrolls = true;
  system.defaults.trackpad.TrackpadThreeFingerHorizSwipeGesture = 0;
  # フルスクリーンアプリケーション間をスワイプ: off
  system.defaults.trackpad.TrackpadFourFingerHorizSwipeGesture = 0;
  # Mission Control: off
  system.defaults.dock.showMissionControlGestureEnabled = false;
  # アプリ Exposé: off
  system.defaults.dock.showAppExposeGestureEnabled = false;

  # ここから下は、手で設定してあった値をそのまま書き起こしたもの (issue #52)。
  # 未設定だった項目は、macOS の既定値に任せて書かない

  # 外観: ダークモード
  system.defaults.NSGlobalDomain.AppleInterfaceStyle = "Dark";
  # スクロールバー: マウスまたはトラックパッドに基づいて自動的に表示
  system.defaults.NSGlobalDomain.AppleShowScrollBars = "Automatic";

  # 文頭を自動的に大文字にする: off
  system.defaults.NSGlobalDomain.NSAutomaticCapitalizationEnabled = false;
  # スペースバーを2回押してピリオドを入力: on
  system.defaults.NSGlobalDomain.NSAutomaticPeriodSubstitutionEnabled = true;
  # スペルを自動変換: off
  system.defaults.NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled = false;
  # F1、F2 などのキーを標準のファンクションキーとして使用: on
  system.defaults.NSGlobalDomain."com.apple.keyboard.fnState" = true;

  # Dock
  system.defaults.dock.tilesize = 30;
  # 最近使ったアプリを表示: off
  system.defaults.dock.show-recents = false;
  # ウインドウをしまうときのエフェクト: スケール
  system.defaults.dock.mineffect = "scale";
  # ウインドウをアプリアイコンにしまう: on
  system.defaults.dock.minimize-to-application = true;
  # Mission Control でウインドウをアプリごとにグループ化: on (AeroSpace の推奨設定)
  system.defaults.dock.expose-group-apps = true;
  # ホットコーナー右下: なし
  system.defaults.dock.wvous-br-corner = 1;
  # ディスプレイごとに個別の操作スペース: off (AeroSpace の推奨設定)
  system.defaults.spaces.spans-displays = true;

  # Finder
  # すべてのファイル名拡張子を表示: on
  system.defaults.NSGlobalDomain.AppleShowAllExtensions = true;
  # パスバーを表示: on / ステータスバーを表示: off
  system.defaults.finder.ShowPathbar = true;
  system.defaults.finder.ShowStatusBar = false;
  # 既定の表示: リスト
  system.defaults.finder.FXPreferredViewStyle = "Nlsv";
  # 新規ウインドウで表示: ホーム
  system.defaults.finder.NewWindowTarget = "Home";
  # デスクトップに表示する項目: 外部ディスクとリムーバブルメディアだけ
  system.defaults.finder.ShowExternalHardDrivesOnDesktop = true;
  system.defaults.finder.ShowHardDrivesOnDesktop = false;
  system.defaults.finder.ShowRemovableMediaOnDesktop = true;

  # スクリーンショット: ファイルとして ~/Pictures/screenshot に保存
  system.defaults.screencapture.location = "~/Pictures/screenshot";
  system.defaults.screencapture.target = "file";

  # メニューバーの時計の日付: スペースに余裕があるときだけ表示
  system.defaults.menuExtraClock.ShowDate = 0;

  # ステージマネージャ: off / デスクトップのウィジェットは隠さない
  system.defaults.WindowManager.GloballyEnabled = false;
  system.defaults.WindowManager.StandardHideWidgets = false;
}
