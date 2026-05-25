{
  description = "reinmuth's dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yazi-flavors = {
      url = "github:yazi-rs/flavors";
      flake = false;
    };
    yazi-plugins = {
      url = "github:yazi-rs/plugins";
      flake = false;
    };
    compress-yazi = {
      url = "github:KKV9/compress.yazi";
      flake = false;
    };
    eza-preview-yazi = {
      url = "github:ahkohd/eza-preview.yazi";
      flake = false;
    };
  };

  outputs = inputs@{ nix-darwin, home-manager, ... }: {
    darwinConfigurations."ReinmuthLaptop" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        ./modules/darwin.nix
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";
          home-manager.extraSpecialArgs = {
            inherit (inputs) yazi-flavors yazi-plugins compress-yazi eza-preview-yazi;
          };
          home-manager.users.reinmuth = import ./modules/home.nix;
        }
      ];
    };
  };
}
