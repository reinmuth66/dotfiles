{ ... }:

{
    # sudo をパスワード入力の代わりに Touch ID で認証できるようにする
  security.pam.services.sudo_local.touchIdAuth = true;

  # Dock を画面端にカーソルを移動しても表示されにくくする (auto-hide の出現遅延を大きくする)
  system.defaults.dock.autohide = true;
  system.defaults.dock.autohide-delay = 1000.0;

  # メニューバーを自動的に隠す
  system.defaults.NSGlobalDomain._HIHideMenuBar = true;
}
