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
    nixpkgs-spotify.url = "github:nixos/nixpkgs/4fe25e12eb9f4c744966dd3de5a05246cf098601";
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs-spotify";
    };
    nix-claude-code = {
      url = "github:ryoppippi/nix-claude-code";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # skill の取得元は flake input にせず、config/agent-skills/registry で固定する
    agent-skills = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mole = {
      url = "github:tw93/mole/V1.70.0";
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

  outputs =
    inputs@{
      nixpkgs,
      nix-darwin,
      home-manager,
      ...
    }:
    let
      # pkgs/ の自前パッケージ。モジュールからは inputs.self.packages.<system>.<name> で参照する
      mkPackages = pkgs: {
        cavaviz = pkgs.callPackage ./pkgs/cavaviz { };
        media-key = pkgs.callPackage ./pkgs/media-key { };
        pdf-cli = pkgs.callPackage ./pkgs/pdf-cli { src = inputs.pdf-cli; };
        sketchybar = pkgs.callPackage ./pkgs/sketchybar { };
        zmk-battery-center = pkgs.callPackage ./pkgs/zmk-battery-center { };
      };
    in
    {
      formatter = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ] (
        system: nixpkgs.legacyPackages.${system}.nixfmt-tree
      );

      # `nix run .#skills-sources-lock` で config/agent-skills/registry の skill の取得元をまとめて更新する
      apps = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ] (
        system:
        let
          program = inputs.agent-skills.lib.agent-skills.mkSourceLockProgram {
            pkgs = nixpkgs.legacyPackages.${system};
          };
        in
        {
          skills-sources-lock = {
            type = "app";
            program = "${program}/bin/skills-sources-lock";
          };
        }
      );

      packages = {
        aarch64-darwin = mkPackages nixpkgs.legacyPackages.aarch64-darwin;
        # update-flake.yaml が ubuntu ランナーで pdf-cli の vendorHash を計算するために使う
        x86_64-linux = {
          inherit (mkPackages nixpkgs.legacyPackages.x86_64-linux) pdf-cli;
        };
      };

      darwinConfigurations."ReinmuthLaptop" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit inputs; };
        modules = [
          ./modules/darwin.nix
          ./modules/system-defaults.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "bak";
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.reinmuth = import ./modules/home.nix;
          }
        ];
      };
    };
}
