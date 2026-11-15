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
        # デザインシステムから組み立てた marp のテーマが、値の直書きなしで作られ、marp で読めることを確かめる
        marp-theme =
          pkgs.runCommand "marp-theme-check"
            {
              nativeBuildInputs = [
                pkgs.jq
                pkgs.marp-cli
              ];
              theme = "${config.packages.marp-theme}/modern.css";
              tokens = ../config/design-system/project/tokens.json;
              sources = [
                ../config/design-system/project/components/bundle.css
                ../config/marp/layout.css
              ];
            }
            ''
              fail() { echo "marp-theme: $1" >&2; exit 1; }

              grep -q '@theme modern' "$theme" || fail "@theme modern がない"

              # @import は最初の規則より前に置かないと、黙って無視される
              first_rule=$(grep -n '{' "$theme" | head -n 1 | cut -d: -f1)
              last_import=$(grep -n '^@import' "$theme" | tail -n 1 | cut -d: -f1)
              [ -n "$last_import" ] || fail "@import がない"
              [ "$last_import" -lt "$first_rule" ] || fail "@import が規則より後ろにある"

              # 色を書いてよいのは tokens.json だけ
              for f in $sources; do
                if grep -nE '#[0-9a-fA-F]{3,8}\b|\b(rgba?|hsla?|oklch|oklab)\(' "$f"; then
                  fail "$f に色が直接書かれている"
                fi
              done

              # 全てのトークンが変数になっている
              for name in $(jq -r '[.[] | objects | .tokens? // empty | .[].name] | .[]' "$tokens"); do
                grep -q -- "^  --$name: " "$theme" || fail "--$name の宣言がない"
              done
              for key in $(jq -r '.type.families | keys[]' "$tokens"); do
                grep -q -- "^  --font-$key: " "$theme" || fail "--font-$key の宣言がない"
              done

              # 別名やテーマごとの値が、解決されないまま残っていない
              if grep -nE '^  --[^:]+: .*([{}]|\[object)' "$theme"; then
                fail "解決されていない値がある"
              fi
              # 別名は var() になる
              grep -q -- '^  --blue: var(--blue-600);' "$theme" || fail "別名が var() になっていない"

              export HOME=$TMPDIR
              printf -- '---\nmarp: true\ntheme: modern\n---\n\n# 題\n\n本文\n' > slide.md
              marp --theme "$theme" --html -o slide.html slide.md
              grep -q -- '--blue-600' slide.html || fail "変換した HTML にテーマが入っていない"

              touch "$out"
            '';
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
