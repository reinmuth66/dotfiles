{ pkgs, ... }:

let
  czgNodeModules = pkgs.importNpmLock.buildNodeModules {
    npmRoot = ../pkgs/czg;
    nodejs = pkgs.nodejs;
  };

  czg = pkgs.writeShellScriptBin "czg" ''
    export NODE_PATH="${czgNodeModules}/node_modules"
    exec ${pkgs.nodejs}/bin/node ${czgNodeModules}/node_modules/.bin/czg "$@"
  '';
in {
  home.packages = [ czg ];

  home.file."commitlint.config.js".source = ../config/czg/commitlint.config.js;
}
