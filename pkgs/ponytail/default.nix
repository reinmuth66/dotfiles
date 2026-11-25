# ponytail の Claude Code プラグイン。src は flake input (タグ固定)。
# フックは PATH の node を呼ぶが、この環境の PATH には node が無いので、nodejs の絶対パスに書き換える
{
  runCommand,
  nodejs,
  src,
}:

runCommand "ponytail-plugin" { } ''
  cp -r ${src} $out
  chmod -R u+w $out
  substituteInPlace $out/hooks/claude-codex-hooks.json \
    --replace-fail '"command": "node -e' '"command": "${nodejs}/bin/node -e'
  if grep -q '"command": "node ' $out/hooks/claude-codex-hooks.json; then
    echo "node の書き換えが漏れた" >&2
    exit 1
  fi
''
