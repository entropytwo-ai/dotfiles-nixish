# dotfiles-nixish 🐧✨

![bash](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![zsh](https://img.shields.io/badge/bonus-zsh-F15A24?logo=zsh&logoColor=white)
![distros](https://img.shields.io/badge/distros-Debian%20%7C%20Ubuntu%20%7C%20Fedora%20%7C%20RHEL%20%7C%20Arch%20%7C%20openSUSE%20%7C%20Alpine%20%7C%20NixOS-blue)
![nixos](https://img.shields.io/badge/NixOS-flakes%20%26%20no%20flakes-5277C3?logo=nixos&logoColor=white)
![idempotent](https://img.shields.io/badge/re--run-safe-success)

> Set up a fresh Linux box the way I like it, with **one command**. Works on regular distros *and* NixOS (with or without flakes).

## 🚀 One-liner install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/entropytwo-ai/dotfiles-nixish/main/install.sh)
```

Options: `--zsh` also installs zsh and configures `~/.zshrc`. `--no-packages` sets up only the config and xtree.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/entropytwo-ai/dotfiles-nixish/main/install.sh) --zsh
```

After it finishes, run `source ~/.bashrc` or open a new terminal.

## 📦 What it installs

| Tool | What it is |
|------|------------|
| `eza` | modern `ls` (if it's not in your distro's repos, it comes from the official eza apt repo or a GitHub release binary) |
| `duf` | nicer `df` |
| `cowsay` + `fortune-mod` | 🐮 wisdom |
| `fastfetch` | system info banner (if it's not in your repos, it comes from the official GitHub .deb, .rpm or tarball) |
| `tldr` | simplified man pages (or `tealdeer`) |
| `nmap`, `ncdu`, `btop`, `fzf`, `glances`, `curl`, `bat` | everyday tools (on Debian/Ubuntu, `bat` is also linked from `batcat`) |

Prerequisites: git, wget, gnupg, ca-certificates, lsb-release, tar, and `acl` (xtree's `-A` option needs it). On RHEL/Rocky/Alma, **EPEL** is turned on automatically. On Arch, the script runs `pacman -Syu`, because Arch doesn't support partial upgrades.
See [`packages/package_list.txt`](packages/package_list.txt) for the package name each distro uses.

Packages that fail to install only produce a warning. The installer keeps going.

## ⚙️ What it configures

- **`xtree`**: [`scripts/xtree.sh`](scripts/xtree.sh) is installed to `/usr/local/bin/xtree`, with a symlink at `~/xtree`. It's a tree view with color themes (`-s default|alternative|christmas|halloween`, `-r` for a random theme), permissions, owner, dates, ACLs and CSV export.
- **`~/.bashrc`**: a block between `# dotfiles-nixish BEGIN` and `# dotfiles-nixish END` containing:
  - History: `HISTCONTROL=ignoreboth:erasedups`, `histappend`, 10000 entries, timestamps (`%m/%d/%y %T`), and `LC_TIME=en_US.UTF-8` (the locale is generated if it's missing)
  - Aliases: `l` and `ll` (eza, falling back to exa, then ls), `la`, `cowsays`, `xtree`, and `bat` on Debian
  - A greeting in every interactive shell: `fastfetch` with a `fortune | cowsay` logo 🐄
- **`~/.zshrc`** (only if zsh is installed): the same settings in zsh syntax (`setopt APPEND_HISTORY`, `SAVEHIST`, and so on)
- Before an rc file is changed, a backup is saved as `*.dotfiles-nixish.bak.<timestamp>`.
- **Every setting exists only once.** Lines outside the block that set something the block sets again (e.g. Ubuntu's stock `HISTSIZE=1000`, `HISTCONTROL=ignoreboth`, `alias ll='ls -alF'`) are removed and listed in the installer output. Only simple top-level one-line statements are touched. Lines inside `if`/`case` blocks, `PATH` and `HISTFILE` are left alone. If the result would not pass `bash -n`/`zsh -n`, the file is left unchanged. The originals stay in the `.bak` file.

## ❄️ NixOS (with or without flakes)

The same one-liner works on NixOS. NixOS already ships `curl`; the installer adds `git` itself. Packages go into **your user profile**, so no `nixos-rebuild` is needed. The installer picks the method automatically:

| Your setup | What the installer runs |
|---|---|
| Channels, no flakes (the default NixOS install) | `nix-env -f '<nixpkgs>' -iA eza duf ...` |
| Flakes (no `<nixpkgs>` channel, or your profile is already a `nix profile` one) | `nix profile install nixpkgs#eza nixpkgs#duf ...` (with `--extra-experimental-features 'nix-command flakes'`, so you don't need flakes turned on in `nix.conf`) |

To choose the method yourself, add `--no-flakes` or `--flakes` to the one-liner. `xtree` still goes to `/usr/local/bin/xtree` with the `~/xtree` link, and the `~/.bashrc` / `~/.zshrc` block is the same as on other distros. On NixOS the installer doesn't change the system: no channel updates and no locale generation. `en_US.UTF-8` is the NixOS default locale. If you've removed it, add `i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];` to your configuration.

### Declarative option (configuration.nix)

If you'd rather manage the tools through your NixOS configuration, the repo includes a NixOS module. Enabling it installs all the tools plus `xtree` system-wide.

**Without flakes**: in `/etc/nixos/configuration.nix`:

```nix
{
  imports = [
    "${builtins.fetchTarball "https://github.com/entropytwo-ai/dotfiles-nixish/archive/main.tar.gz"}/nix/module.nix"
  ];
  programs.dotfiles-nixish.enable = true;
  # programs.dotfiles-nixish.shellConfig = true;  # also apply the bash/zsh block system-wide
}
```

**With flakes**: in `/etc/nixos/flake.nix`:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.dotfiles-nixish.url = "github:entropytwo-ai/dotfiles-nixish";
  inputs.dotfiles-nixish.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, dotfiles-nixish, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        dotfiles-nixish.nixosModules.default
        { programs.dotfiles-nixish.enable = true; }
      ];
    };
  };
}
```

Then run `sudo nixos-rebuild switch`. After that, either run the one-liner with `--no-packages`, which only adds the shell block and the `/usr/local/bin/xtree` link, or set `shellConfig = true` and skip the installer entirely. Don't do both, or the greeting will show twice.

**Just the tools, no config**:

```bash
nix-env -if https://github.com/entropytwo-ai/dotfiles-nixish/archive/main.tar.gz   # no flakes
nix profile install github:entropytwo-ai/dotfiles-nixish                           # flakes
```

> 💡 For zsh as your login shell on NixOS, use `programs.zsh.enable = true;` and `users.users.<you>.shell = pkgs.zsh;`. A zsh installed into your user profile isn't listed in `/etc/shells`, so it can't be set as your login shell.

## 🔄 Updating

```bash
git -C ~/.dotfiles-nixish pull && bash ~/.dotfiles-nixish/install.sh
```

Running the one-liner again does the same thing. The managed block is **replaced in place**, never duplicated. Put your own customizations outside the BEGIN/END markers.

## 🧩 Manual / partial use

```bash
git clone https://github.com/entropytwo-ai/dotfiles-nixish.git ~/.dotfiles-nixish
source ~/.dotfiles-nixish/config/bashrc_append.sh     # just try the config in this shell
source ~/.dotfiles-nixish/config/zshrc_append.sh      # zsh flavor
sudo install -m 755 ~/.dotfiles-nixish/scripts/xtree.sh /usr/local/bin/xtree   # just xtree
```

## 🗂 Layout

```
install.sh                 # the bootstrap script
scripts/xtree.sh           # xtree
config/bashrc_append.sh    # ~/.bashrc block
config/zshrc_append.sh     # ~/.zshrc block
packages/package_list.txt  # package names for each distro
flake.nix / flake.lock     # flake: nixosModules.default + packages (default, xtree)
default.nix                # non-flake entry point (nix-env -if / nix-shell)
nix/module.nix             # NixOS module (programs.dotfiles-nixish.*)
nix/packages.nix           # tool list as nixpkgs attributes
nix/xtree.nix              # xtree as a Nix package
```
