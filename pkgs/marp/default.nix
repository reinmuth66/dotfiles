# marp コマンド。どこから呼んでも、テーマ modern とエンジンの拡張が効くようにする。
# シェルの関数にすると、timeout やスクリプト、AI エージェントから呼んだときに関数を通らず、
# 拡張が効かないまま (::: が文字のまま) 変換が成功してしまう。
{
  writeShellApplication,
  marp-cli,
}:
writeShellApplication {
  name = "marp";
  text = ''
    config="$HOME/.marprc.yml"
    has_config=false
    has_stdin=false
    for arg in "$@"; do
      case "$arg" in
        -c | --config | --config=* | --config-file | --config-file=* | --no-config | --no-config-file) has_config=true ;;
        --stdin | --no-stdin) has_stdin=true ;;
      esac
    done

    extra=()
    # marp は、ホームより下の階層で設定を探すのをやめるので、~/.marprc.yml を明示する
    if [ "$has_config" = false ] && [ -f "$config" ]; then
      extra+=(--config "$config")
    fi
    # 端末以外 (スクリプト、エージェント) から呼ぶと、marp は標準入力を待って止まる。
    # 標準入力から原稿を渡したいときは、--stdin を付ける
    if [ "$has_stdin" = false ] && [ ! -t 0 ]; then
      extra+=(--no-stdin)
    fi

    exec ${marp-cli}/bin/marp "''${extra[@]}" "$@"
  '';
}
