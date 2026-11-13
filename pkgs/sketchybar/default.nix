{ sketchybar }:

# nixpkgs の sketchybar に、画像を回転できるようにするパッチを当てる。Spotify のアルバムアートの回転に使う。
sketchybar.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./image-rotation.patch ];
})
