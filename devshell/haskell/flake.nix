{
  description = "Haskell development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      supportedSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          haskellPackages = pkgs.haskellPackages;
        in
        {
          default = pkgs.mkShell {
            packages = [
              haskellPackages.cabal-fmt
              haskellPackages.cabal-install
              haskellPackages.fourmolu
              haskellPackages.ghc
              haskellPackages.ghcid
              haskellPackages.haskell-language-server
              haskellPackages.hlint
              pkgs.nil
              pkgs.nixfmt
            ];
          };
        }
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);
    };
}
