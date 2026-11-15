{ inputs, ... }:

{
  perSystem =
    { pkgs, lib, ... }:
    {
      # pkgs/ の自前パッケージ。モジュールからは inputs.self.packages.<system>.<name> で参照する
      packages = {
        # update-flake.yaml が ubuntu ランナーで vendorHash を計算するので、Linux にも出す
        pdf-cli = pkgs.callPackage ../pkgs/pdf-cli { src = inputs.pdf-cli; };
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        cavaviz = pkgs.callPackage ../pkgs/cavaviz { };
        media-key = pkgs.callPackage ../pkgs/media-key { };
        sketchybar = pkgs.callPackage ../pkgs/sketchybar { };
        zmk-battery-center = pkgs.callPackage ../pkgs/zmk-battery-center { };
      };
    };
}
