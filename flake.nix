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
    nixpkgs-spotify.url = "github:nixos/nixpkgs/d3b13ad75cc492690728f9307e443dec9ef9a20e";
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs-spotify";
    };
    mole = {
      url = "github:tw93/mole/V1.64.0";
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
            inherit (inputs) nixpkgs-spotify spicetify-nix mole yazi-flavors yazi-plugins compress-yazi eza-preview-yazi catppuccin-bat zeno-zsh pdf-cli;
          };
          home-manager.users.reinmuth = import ./modules/home.nix;
        }
      ];
    };
  };
}
