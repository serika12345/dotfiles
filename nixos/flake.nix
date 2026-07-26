{
  description = "NixOS system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Updated independently by .github/workflows/update-codex.yml.
    codex-nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      codex-nixpkgs,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      system = "x86_64-linux";
      codexPackage = codex-nixpkgs.legacyPackages.${system}.codex;
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit codexPackage; };
        modules = [
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ];
      };

      packages.${system}.codex = codexPackage;
    };
}
