{
  description = "NixOS configuration for Microsoft Surface Pro 7";

  inputs = {
    # Keep this aligned with the custom installer.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak/v0.7.0";
  };

  outputs =
    {
      home-manager,
      nix-flatpak,
      nixos-hardware,
      nixpkgs,
      ...
    }:
    {
      nixosConfigurations.surface = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nixos-hardware.nixosModules.microsoft-surface-pro-intel
          nix-flatpak.nixosModules.nix-flatpak
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ];
      };

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
    };
}
