{
  description = "MirageOS hello-world development environment";

  # nixos-unstable dropped x86_64-darwin in the 26.11 cycle. This branch is
  # the final supported package set for the Intel macOS host used here.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

  outputs = { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          # Kept from the original flake as a small Nix sanity check.
          hello = pkgs.hello;
          default = pkgs.hello;
        });

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              git
              gnumake
              opam
              pkg-config
            ];

            buildInputs = [
              pkgs.libev
            ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.libseccomp
            ];
          };
        });
    };
}
