# last30days の Claude Code プラグイン。src は flake input (タグ固定)。
# Stop フックは PATH の python3 を呼ぶが、macOS の /usr/bin/python3 は 3.12 未満なので、Nix の python3 の絶対パスに書き換える
{
  runCommand,
  python3,
  src,
}:

runCommand "last30days-plugin" { } ''
  cp -r ${src} $out
  chmod -R u+w $out
  substituteInPlace $out/.claude-plugin/hooks.json \
    --replace-fail '"command": "python3 ' '"command": "${python3}/bin/python3 '
  if grep -q '"command": "python3 ' $out/.claude-plugin/hooks.json; then
    echo "python3 の書き換えが漏れた" >&2
    exit 1
  fi
''
