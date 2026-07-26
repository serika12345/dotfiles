{
  description = "NixOS configuration for Microsoft Surface Pro 7";

  inputs = {
    # Keep this aligned with the custom installer.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Updated independently by .github/workflows/update-codex.yml.
    codex-nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      codex-nixpkgs,
      home-manager,
      nixos-hardware,
      nixpkgs,
      ...
    }:
    let
      system = "x86_64-linux";
      codexPackage = codex-nixpkgs.legacyPackages.${system}.codex;
    in
    {
      nixosConfigurations.surface = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit codexPackage; };
        modules = [
          nixos-hardware.nixosModules.microsoft-surface-pro-intel
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ];
      };

      packages.${system}.codex = codexPackage;
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
