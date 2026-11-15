# marp のエンジンの拡張を 1 つのディレクトリにまとめる。
# ファイルを 1 つずつ配ると、実体が Nix ストアの別々の場所になり、相対パスの require が解決できない。
{
  runCommand,
  engineSrc ? ../../config/marp/engine,
  # 図の線を描くスクリプト。正本はデザインシステムの側にあり、React の部品と共有する
  connectorSrc ? ../../config/design-system/src/connector.js,
}:
runCommand "marp-engine" { inherit engineSrc connectorSrc; } ''
  mkdir -p "$out"
  cp "$engineSrc"/*.js "$out"/
  cp "$connectorSrc" "$out"/connector.js
''
