{ ... }:

{
  # sudo をパスワード入力の代わりに Touch ID で認証できるようにする
  security.pam.services.sudo_local.touchIdAuth = true;

  # Dock を画面端にカーソルを移動しても表示されにくくする (auto-hide の出現遅延を大きくする)
  system.defaults.dock.autohide = true;
  system.defaults.dock.autohide-delay = 1000.0;

  # メニューバーを自動的に隠す
  system.defaults.NSGlobalDomain._HIHideMenuBar = true;

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
}
