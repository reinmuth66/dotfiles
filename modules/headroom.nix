{ inputs, pkgs, ... }:

{
  # 使うときだけ `headroom wrap claude` で起動する (作業ディレクトリの .claude/settings.local.json を一時的に書き換える)
  home.packages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.headroom ];
}
