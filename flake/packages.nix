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
        # marp に短い記法を足すエンジンの拡張
        marp-engine = pkgs.callPackage ../pkgs/marp-engine { };
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        cavaviz = pkgs.callPackage ../pkgs/cavaviz { };
        media-key = pkgs.callPackage ../pkgs/media-key { };
        sketchybar = pkgs.callPackage ../pkgs/sketchybar { };
        zmk-battery-center = pkgs.callPackage ../pkgs/zmk-battery-center { };
      };
    };
}
