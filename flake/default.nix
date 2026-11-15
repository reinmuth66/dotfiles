{ inputs, ... }:

{
  imports = [
    inputs.treefmt-nix.flakeModule
    inputs.git-hooks.flakeModule

    ./apps.nix
    ./formatter.nix
    ./hosts.nix
    ./packages.nix
  ];

  # x86_64-linux は CI の ubuntu ランナー用
  systems = [
    "aarch64-darwin"
    "x86_64-linux"
  ];
}
