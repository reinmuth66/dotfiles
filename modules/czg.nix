{ pkgs, ... }:

let
  czgNodeModules = pkgs.importNpmLock.buildNodeModules {
    npmRoot = ../pkgs/czg;
    nodejs = pkgs.nodejs;
  };

  czg = pkgs.writeShellScriptBin "czg" ''
    exec ${pkgs.nodejs}/bin/node ${czgNodeModules}/node_modules/.bin/czg "$@"
  '';
in {
  home.packages = [ czg ];
}
