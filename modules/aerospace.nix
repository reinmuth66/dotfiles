{ ... }:

{
  programs.aerospace = {
    enable = true;

    launchd.enable = true;

    settings = {
      config-version = 2;

      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;

      default-root-container-layout = "tiles";
      default-root-container-orientation = "auto";

      # モニタ移動時、マウスカーソルをフォーカス先のモニタ中央に移動する
      on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];

      # 空でも維持しておくワークスペース
      persistent-workspaces = [ "1" "2" "3" "4" "5" "6" "7" "8" "9" ];

      focus-follows-mouse.enabled = false;

      key-mapping.preset = "qwerty";

      # ウィンドウ間のギャップ
      gaps = {
        inner.horizontal = 4;
        inner.vertical = 4;
        outer.left = 4;
        outer.bottom = 4;
        outer.top = 4;
        outer.right = 4;
      };

      # 'main' モード: 通常時のキーバインド
      mode.main.binding = {
        # レイアウト切り替え
        alt-slash = "layout tiles horizontal vertical";
        alt-period = "layout accordion horizontal vertical";

        # フォーカス移動
        alt-j = "focus left";
        alt-k = "focus down";
        alt-i = "focus up";
        alt-l = "focus right";

        # ウィンドウ移動
        alt-shift-j = "move left";
        alt-shift-k = "move down";
        alt-shift-i = "move up";
        alt-shift-l = "move right";

        # ウィンドウを指定方向のノードと共通コンテナにまとめる
        alt-ctrl-j = "join-with left";
        alt-ctrl-k = "join-with down";
        alt-ctrl-i = "join-with up";
        alt-ctrl-l = "join-with right";

        # リサイズ
        alt-u = "resize smart -10";
        alt-o = "resize smart +10";
        alt-y = "balance-sizes";

        # フルスクリーン切り替え
        alt-h = "fullscreen";

        # ワークスペース切り替え
        alt-1 = "workspace 1";
        alt-2 = "workspace 2";
        alt-3 = "workspace 3";
        alt-4 = "workspace 4";
        alt-5 = "workspace 5";
        alt-6 = "workspace 6";
        alt-7 = "workspace 7";
        alt-8 = "workspace 8";
        alt-9 = "workspace 9";

        # ウィンドウを別ワークスペースへ移動
        alt-shift-1 = "move-node-to-workspace 1";
        alt-shift-2 = "move-node-to-workspace 2";
        alt-shift-3 = "move-node-to-workspace 3";
        alt-shift-4 = "move-node-to-workspace 4";
        alt-shift-5 = "move-node-to-workspace 5";
        alt-shift-6 = "move-node-to-workspace 6";
        alt-shift-7 = "move-node-to-workspace 7";
        alt-shift-8 = "move-node-to-workspace 8";
        alt-shift-9 = "move-node-to-workspace 9";

        # 直前のワークスペースに戻る
        alt-tab = "workspace-back-and-forth";

        # サービスモードへ切り替え
        alt-shift-semicolon = "mode service";
      };

      # 'service' モード: 設定リロードやレイアウトリセットなどの補助操作
      mode.service.binding = {
        esc = [ "reload-config" "mode main" ];
        r = [ "flatten-workspace-tree" "mode main" ];
        f = [ "layout floating tiling" "mode main" ];
        backspace = [ "close-all-windows-but-current" "mode main" ];
      };
    };
  };
}
