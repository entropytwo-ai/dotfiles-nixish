# NixOS module for dotfiles-nixish - works WITH or WITHOUT flakes.
#
#   Without flakes (/etc/nixos/configuration.nix):
#     imports = [
#       "${builtins.fetchTarball "https://github.com/entropytwo-ai/dotfiles-nixish/archive/main.tar.gz"}/nix/module.nix"
#     ];
#     programs.dotfiles-nixish.enable = true;
#
#   With flakes: add the input and use  dotfiles-nixish.nixosModules.default
#   (see README).
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.dotfiles-nixish;
  xtree = pkgs.callPackage ./xtree.nix { };
in
{
  options.programs.dotfiles-nixish = {
    enable = lib.mkEnableOption "the dotfiles-nixish tool set (eza, duf, cowsay, fortune, fastfetch, ...) and xtree";

    shellConfig = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also apply the dotfiles-nixish bash/zsh settings (history, aliases,
        fastfetch + cowsay greeting) system-wide via interactiveShellInit.
        Leave this off if you run install.sh, which writes the same block to
        ~/.bashrc / ~/.zshrc (otherwise the greeting shows twice).
      '';
    };

    starship = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also turn on the starship prompt (programs.starship) for bash and zsh -
        the same as menu item 8 / --starship of install.sh.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = (import ./packages.nix pkgs { }) ++ [ xtree ];

    # NixOS defines l = "ls -alh" and ll = "ls -l" (mkDefault) and applies them
    # after interactiveShellInit, which would undo our eza aliases - drop them.
    environment.shellAliases = lib.mkIf cfg.shellConfig { l = null; ll = null; };

    programs.bash.interactiveShellInit = lib.mkIf cfg.shellConfig
      (builtins.readFile ../config/bashrc_append.sh);
    # only takes effect when programs.zsh.enable = true
    programs.zsh.interactiveShellInit = lib.mkIf cfg.shellConfig
      (builtins.readFile ../config/zshrc_append.sh);

    programs.starship.enable = lib.mkIf cfg.starship true;
  };
}
