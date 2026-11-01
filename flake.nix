{
  description = "dotfiles-nixish - make a new Linux system like I like it";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in
    {
      # imports = [ dotfiles-nixish.nixosModules.default ];
      nixosModules.default = import ./nix/module.nix;
      nixosModules.dotfiles-nixish = self.nixosModules.default;

      # nix profile install github:entropytwo-ai/dotfiles-nixish
      packages = forAll (pkgs: rec {
        xtree = pkgs.callPackage ./nix/xtree.nix { };
        default = pkgs.buildEnv {
          name = "dotfiles-nixish";
          paths = (import ./nix/packages.nix pkgs { }) ++ [ xtree ];
        };
      });

      # nix flake check: boots a NixOS VM with the module (needs KVM) - see tests/
      checks.x86_64-linux.nixos-module = import ./tests/nixos-vm.nix {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        module = self.nixosModules.default;
      };
    };
}
