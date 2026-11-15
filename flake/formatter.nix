{
  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      src = lib.cleanSource ../.;
    in
    {
      # `nix fmt` と `nix flake check` の両方がこの設定を使う
      treefmt = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
          shfmt.enable = true;
          # 設定は、整形するファイルに最も近い stylua.toml から拾われる (config/nvim だけ 2 スペース)
          stylua.enable = true;
        };
        settings.global.excludes = [
          "*.lock"
          # 外部から取ってきたファイルは整形しない
          "pkgs/sketchybar-helper/*"
        ];
      };

      # commit 前に走らせる。`nix develop` (direnv なら自動) で .git/hooks に入る
      pre-commit = {
        # フックは .git が要るので、サンドボックスでは走らせない。同じ検査は下の checks に置く
        check.enable = false;
        settings.hooks = {
          # ステージした差分だけを見る (git-hooks.nix の既定の引数)
          gitleaks.enable = true;
          treefmt = {
            enable = true;
            package = config.treefmt.build.wrapper;
          };
          deadnix.enable = true;
          statix.enable = true;
        };
      };

      # 整形の検査 (checks.treefmt) は treefmt-nix が足す
      checks = {
        statix = pkgs.runCommand "statix" { nativeBuildInputs = [ pkgs.statix ]; } ''
          statix check --config ${../statix.toml} ${src}
          touch "$out"
        '';
        deadnix = pkgs.runCommand "deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
          deadnix --fail ${src}
          touch "$out"
        '';
        gitleaks = pkgs.runCommand "gitleaks" { nativeBuildInputs = [ pkgs.gitleaks ]; } ''
          gitleaks dir --redact=100 --no-banner ${src}
          touch "$out"
        '';
      };

      devShells.default = pkgs.mkShell {
        shellHook = config.pre-commit.installationScript;
      };
    };
}
