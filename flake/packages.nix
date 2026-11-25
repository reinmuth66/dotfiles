{ inputs, ... }:

{
  perSystem =
    { pkgs, lib, ... }:
    {
      # pkgs/ の自前パッケージ。モジュールからは inputs.self.packages.<system>.<name> で参照する
      packages = {
        # update-flake.yaml が ubuntu ランナーで vendorHash を計算するので、Linux にも出す
        pdf-cli = pkgs.callPackage ../pkgs/pdf-cli { src = inputs.pdf-cli; };
        # デザインシステムのトークンから組み立てる marp のテーマ
        marp-theme = pkgs.callPackage ../pkgs/marp-theme { };
        # デザインシステムの publish 用の一式 (React の部品をまとめた bundle.js つき)
        design-system = pkgs.callPackage ../pkgs/design-system { };
        # marp に短い記法を足すエンジンの拡張
        marp-engine = pkgs.callPackage ../pkgs/marp-engine { };
        # 設定 (~/.marprc.yml) を必ず読み、端末以外から呼んでも止まらない marp コマンド
        marp = pkgs.callPackage ../pkgs/marp { };
        # yazi の [icon] の表。herdr のツリーの mod がファイルのアイコンに使う
        yazi-icons = pkgs.callPackage ../pkgs/yazi-icons { };
        # フックの python3 を絶対パスにした last30days の Claude Code プラグイン
        last30days = pkgs.callPackage ../pkgs/last30days { src = inputs.last30days; };
        # 版を固定して uvx で起動する headroom
        headroom = pkgs.callPackage ../pkgs/headroom { };
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        antigravity-cli = pkgs.callPackage ../pkgs/antigravity-cli { };
        cavaviz = pkgs.callPackage ../pkgs/cavaviz { };
        media-key = pkgs.callPackage ../pkgs/media-key { };
        sketchybar = pkgs.callPackage ../pkgs/sketchybar { };
        zmk-battery-center = pkgs.callPackage ../pkgs/zmk-battery-center { };
      };
    };
}
