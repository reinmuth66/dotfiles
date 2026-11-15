# marp のエンジンの拡張を 1 つのディレクトリにまとめる。
# ファイルを 1 つずつ配ると、実体が Nix ストアの別々の場所になり、相対パスの require が解決できない。
{
  runCommand,
  engineSrc ? ../../config/marp/engine,
}:
runCommand "marp-engine" { inherit engineSrc; } ''
  mkdir -p "$out"
  cp "$engineSrc"/*.js "$out"/
''
