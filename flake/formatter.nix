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
        # React の部品をまとめた bundle.js が、デザインシステムの決まりを守り、部品が class を正しく出すことを確かめる
        design-system =
          pkgs.runCommand "design-system-check"
            {
              nativeBuildInputs = [ pkgs.nodejs ];
              bundle = "${config.packages.design-system}/project/components/bundle.js";
            }
            ''
              fail() { echo "design-system: $1" >&2; exit 1; }

              # デザインシステムはこのスクリプトをページに埋め込むので、これらの文字列があると壊れる
              if grep -nE '^\s*import\s|</script|<!--' "$bundle"; then
                fail "bundle.js に import、</script、<!-- のどれかがある"
              fi
              head -n 1 "$bundle" | grep -q '@ds-bundle: {' || fail "先頭行に @ds-bundle がない"

              node -e '
                const assert = require("node:assert/strict");
                // createElement の引数をそのまま返す、にせの React
                globalThis.React = {
                  createElement: (type, props, ...children) => ({ type, props: props || {}, children }),
                  Fragment: "fragment",
                  useRef: () => ({ current: null }),
                  useEffect: () => {},
                };
                new Function(require("node:fs").readFileSync(process.argv[1], "utf8") + "; globalThis.Modern = Modern;")();
                const M = globalThis.Modern;
                for (const name of ["Toc", "Card", "Box", "Row", "Col", "Grid", "Diagram", "draw"]) {
                  assert.equal(typeof M[name], "function", name + " がない");
                }
                assert.equal(M.Card({ variant: "accent" }).props.className, "card accent");
                assert.equal(M.Card({}).props.className, "card");
                assert.equal(M.Box({ variant: "dark", id: "model" }).props.className, "box dark");
                assert.equal(M.Box({ id: "model" }).props.id, "model");
                assert.equal(M.Card({ variant: "accent", square: true }).props.className, "card accent square");
                assert.equal(M.Box({ square: true }).props.className, "box square");
                assert.equal(M.Row({ center: true }).props.className, "row center");
                assert.equal(M.Grid({ columns: 3 }).props.className, "grid3");
                assert.equal(M.Grid({}).props.className, "grid2");
                assert.equal(M.Toc({ items: ["a", "b"] }).props.className, "toc");
                const diagram = M.Diagram({ edges: ["in.right -> model.left", "これは線ではない"] });
                assert.equal(diagram.props.className, "diagram");
                const edges = JSON.parse(diagram.props["data-edges"]);
                assert.equal(edges.length, 1);
                assert.equal(edges[0].toSide, "left");
                // 線を描く場所は、部品が自分で出す
                const svg = diagram.children.find((child) => child && child.type === "svg");
                assert.equal(svg.props.className, "diagram-edges");
              ' "$bundle"

              touch "$out"
            '';

        # tokens.json の色が、法則 (meta.colorRule) から計算した値と一致することを確かめる
        design-system-colors =
          pkgs.runCommand "design-system-colors-check" { nativeBuildInputs = [ pkgs.python3 ]; }
            ''
              python3 ${../config/design-system/tools/color.py} check ${../config/design-system/project/tokens.json}
              touch "$out"
            '';

        # marp のエンジンの拡張と、図の線を描くスクリプトの試験
        marp-engine =
          pkgs.runCommand "marp-engine-check"
            {
              nativeBuildInputs = [ pkgs.nodejs ];
              engine = config.packages.marp-engine;
              # 試験は、marp-cli に入っている marp-core をそのまま使う
              NODE_PATH = "${pkgs.marp-cli}/lib/node_modules/@marp-team/marp-cli/node_modules";
            }
            ''
              # 配る形 (拡張と connector.js が同じディレクトリ) に試験を足して走らせる。試験そのものは配らない
              cp -r "$engine" engine
              chmod -R u+w engine
              if [ -n "$(find engine -name '*.test.js')" ]; then
                echo "marp-engine: 試験のファイルが配られている" >&2
                exit 1
              fi
              cp ${../config/marp/engine}/*.test.js ${../config/design-system/src}/connector.test.js engine/
              node --test engine/*.test.js
              touch "$out"
            '';

        # herdr アプリの設定と mod の、herdr に依存しない部分 (logic.js、keys.json) の試験
        herdr-mods = pkgs.runCommand "herdr-mods-check" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
          cp -r ${../config/herdr-app} herdr-app
          chmod -R u+w herdr-app
          tests=$(find herdr-app -name '*.test.js' | sort)
          if [ -z "$tests" ]; then
            echo "herdr-mods: 試験のファイルがない" >&2
            exit 1
          fi
          # shellcheck disable=SC2086
          node --test $tests
          touch "$out"
        '';

        # marp コマンドが、関数を通らない呼び方 (timeout 越し、標準入力が端末でない) でも、設定を読んで止まらずに変換する
        marp-command =
          pkgs.runCommand "marp-command-check"
            {
              nativeBuildInputs = [
                config.packages.marp
                pkgs.coreutils
              ];
              theme = "${config.packages.marp-theme}/modern.css";
              engine = "${config.packages.marp-engine}/index.js";
            }
            ''
              fail() { echo "marp-command: $1" >&2; exit 1; }
              export HOME=$TMPDIR
              printf 'theme: %s\nengine: %s\nhtml: true\n' "$theme" "$engine" > "$HOME/.marprc.yml"
              mkdir work && cd work
              printf -- '---\nmarp: true\ntheme: modern\n---\n\n::: box\n中身\n:::\n' > slide.md

              # 標準入力を開いたままにする。--no-stdin が足されなければ、ここで止まる
              sleep 30 | timeout 20 marp slide.md -o slide.html || fail "変換が止まった、または失敗した"
              grep -q '<div class="box">' slide.html || fail "拡張が効いていない (::: が変換されていない)"
              grep -q -- '--blue-600' slide.html || fail "テーマが効いていない"

              # --stdin を付ければ、標準入力から原稿を渡せる
              timeout 20 marp --stdin -o stdin.html < slide.md || fail "--stdin で標準入力を読めない"
              grep -q '<div class="box">' stdin.html || fail "--stdin の変換で拡張が効いていない"

              touch "$out"
            '';

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
              # type のスタイルと font-size-* のトークンをわざとずらすと、テーマの組み立てが止まること
              styleMismatchCaught =
                let
                  original = builtins.fromJSON (builtins.readFile ../config/design-system/project/tokens.json);
                  shifted = original // {
                    type = original.type // {
                      groups = map (
                        group:
                        group
                        // {
                          styles = map (style: style // { fontSize = "999px"; }) group.styles;
                        }
                      ) original.type.groups;
                    };
                  };
                  shiftedTheme = pkgs.callPackage ../pkgs/marp-theme {
                    tokensFile = builtins.toFile "shifted-tokens.json" (builtins.toJSON shifted);
                  };
                  built = builtins.tryEval shiftedTheme.outPath;
                in
                if built.success then "no" else "yes";
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
                # 色の名前 (white、red など) も書かない。値として書かれたものだけを見る
                if grep -nE ':[^;{]*[ :,(](white|black|gray|grey|silver|red|orange|yellow|green|blue|purple|pink|navy|teal|aqua|cyan|magenta|maroon|olive|lime|fuchsia|brown|gold|indigo|violet)[ ,);!]' "$f" \
                  | grep -vE '^[0-9]+:\s*(/\*|\*|[^:]*\{\s*$)'; then
                  fail "$f に色の名前が直接書かれている"
                fi
                # 大きさ (px) も tokens.json にだけ書く
                if grep -nE '[0-9]px\b' "$f" | grep -vE '^[0-9]+:\s*(/\*|\*)'; then
                  fail "$f に px の値が直接書かれている"
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
              # 部品の規則が入っている
              for selector in ".box {" ".box.dark," ".card {" ".card.accent {" ".card.square {" ".row {" ".grid2 {" ".arrow > p,"; do
                grep -qF -- "$selector" "$theme" || fail "部品の規則 $selector がない"
              done

              [ "$styleMismatchCaught" = yes ] || fail "type のスタイルと font-size-* の食い違いを検出できていない"

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
