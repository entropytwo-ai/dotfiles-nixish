# The dotfiles-nixish tool set as nixpkgs attributes (shared by module.nix,
# default.nix and flake.nix). Keep in sync with TOOLS in install.sh.
pkgs: with pkgs; [
  eza duf cowsay fortune fastfetch tldr nmap ncdu btop fzf glances curl bat
  # prerequisites / helpers
  git wget gnupg acl
]
