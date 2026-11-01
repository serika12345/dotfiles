{
  description = "My nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Updated independently by .github/workflows/update-codex.yml.
    codex-nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      codex-nixpkgs,
      nixpkgs,
      nix-darwin,
      home-manager,
    }:
    let
      system = "aarch64-darwin";
      codexPackage = codex-nixpkgs.legacyPackages.${system}.codex;
    in
    {
      darwinConfigurations."macbook-air" = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = {
          inherit self inputs codexPackage;
        };

        modules = [
          ./modules/darwin.nix

          home-manager.darwinModules.home-manager

          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";

            home-manager.users.masato = import ./modules/home.nix;
          }
        ];
      };

      packages.${system}.codex = codexPackage;
    };
}
