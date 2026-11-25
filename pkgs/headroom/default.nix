# headroom (PyPI の headroom-ai) を uvx で起動する。nixpkgs になく、依存が重いので Nix ではビルドしない。
# 版はここで固定し、update-headroom.yaml が PyPI の新しい版で PR を作る。初回の実行時に uv が依存を取る
{
  writeShellApplication,
  uv,
}:

let
  version = "0.45.0";
in
writeShellApplication {
  name = "headroom";
  runtimeInputs = [ uv ];
  text = ''
    exec uvx --python 3.13 --from "headroom-ai[proxy]==${version}" headroom "$@"
  '';
}
