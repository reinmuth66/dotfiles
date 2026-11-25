{ sketchybar }:

# nixpkgs の sketchybar にパッチを当てる。
# - image-rotation: 画像を回転できるようにする。Spotify のアルバムアートの回転に使う。
# - topmost-above-menubar: topmost=on のバーの層を kCGStatusWindowLevel (25) から 1 つ上げる。
#   macOS 27 では、メニューバーを自動で隠していても、MenuBarAgent が画面上端に層 25 の透明なウィンドウを置いたままにする。
#   同じ層だと、MenuBarAgent がウィンドウを作り直すたびにバーより手前に来て、hover もクリックも奪う (Issue #112)。
#   ポップアップは層 101 (kCGPopUpMenuWindowLevel) なので、バーより手前のまま。
sketchybar.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./image-rotation.patch
    ./topmost-above-menubar.patch
  ];
})
