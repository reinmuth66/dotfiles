{ inputs, ... }:

{
  flake.darwinConfigurations."ReinmuthLaptop" = inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    specialArgs = { inherit inputs; };
    modules = [
      ../modules/darwin.nix
      ../modules/system-defaults.nix
      inputs.home-manager.darwinModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "bak";
        home-manager.extraSpecialArgs = { inherit inputs; };
        home-manager.users.reinmuth = import ../modules/home.nix;
      }
    ];
  };
}
