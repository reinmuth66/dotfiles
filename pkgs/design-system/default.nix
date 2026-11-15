# デザインシステム「modern」の、publish 用の一式を作る。
# config/design-system/project/ の中身に、src/ からまとめた components/bundle.js を足す。
# bundle.js はリポジトリに置かず、publish の前にここで作る。
{
  runCommand,
  esbuild,
  project ? ../../config/design-system/project,
  # callPackage が nixpkgs の同名のパッケージを渡してしまうので、src という名前は使わない
  componentsSrc ? ../../config/design-system/src,
}:
let
  # デザインシステムのページが、部品の名前と順番を読むための先頭行。
  # Row、Col、Grid は 1 つずつ並べず、components/Layout/ の説明とプレビューでまとめて見せる
  header = builtins.toJSON {
    format = 4;
    namespace = "Modern";
    components = map (name: { inherit name; }) [
      "Toc"
      "Card"
      "Box"
      "Diagram"
    ];
  };
in
runCommand "design-system-modern"
  {
    nativeBuildInputs = [ esbuild ];
    inherit project componentsSrc header;
  }
  ''
    mkdir -p "$out"
    cp -r "$project" "$out/project"
    chmod -R u+w "$out/project"

    esbuild "$componentsSrc/index.jsx" \
      --bundle \
      --format=iife \
      --global-name=Modern \
      --jsx-factory=React.createElement \
      --jsx-fragment=React.Fragment \
      --target=es2020 \
      --banner:js="/* @ds-bundle: $header */" \
      --outfile="$out/project/components/bundle.js"
  ''
