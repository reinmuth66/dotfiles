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
    nixpkgs-spotify.url = "github:nixos/nixpkgs/8c6b39505383e6d5dcb431f00cb3597b71f8045c";
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs-spotify";
    };
    mole = {
      url = "github:tw93/mole/V1.59.1";
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
    catppuccin-bat = {
      url = "github:catppuccin/bat";
      flake = false;
    };
    zeno-zsh = {
      url = "github:yuki-yano/zeno.zsh";
      flake = false;
    };
    swiftterm = {
      url = "github:migueldeicaza/SwiftTerm";
      flake = false;
    };
    pdf-cli = {
      url = "github:Yujonpradhananga/pdf-cli";
      flake = false;
    };
  };

  outputs = inputs@{ nix-darwin, home-manager, ... }: {
    darwinConfigurations."ReinmuthLaptop" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        ./modules/darwin.nix
        ./modules/system-defaults.nix
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";
          home-manager.extraSpecialArgs = {
            inherit (inputs) nixpkgs-spotify spicetify-nix mole yazi-flavors yazi-plugins compress-yazi eza-preview-yazi catppuccin-bat zeno-zsh swiftterm pdf-cli;
          };
          home-manager.users.reinmuth = import ./modules/home.nix;
        }
      ];
    };
  };
}
