# Non-flake entry point: the whole tool set + xtree as one package.
#   nix-env -if https://github.com/entropytwo-ai/dotfiles-nixish/archive/main.tar.gz
#   nix-shell https://github.com/entropytwo-ai/dotfiles-nixish/archive/main.tar.gz -A shell
{ pkgs ? import <nixpkgs> { } }:
let
  xtree = pkgs.callPackage ./nix/xtree.nix { };
  env = pkgs.buildEnv {
    name = "dotfiles-nixish";
    paths = (import ./nix/packages.nix pkgs) ++ [ xtree ];
  };
in
env // {
  inherit xtree;
  shell = pkgs.mkShell { packages = [ env ]; };
}
