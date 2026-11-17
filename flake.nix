{
  description = "StillDeadcode's radiance inference engine for RDNA4, packaged for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        radiance = pkgs.callPackage ./package.nix { };
        default = self.packages.${system}.radiance;
      };

      nixosModules.default = import ./module.nix self;

      devShells.${system}.default = pkgs.mkShell {
        inputsFrom = [ self.packages.${system}.radiance ];
      };
    };
}
