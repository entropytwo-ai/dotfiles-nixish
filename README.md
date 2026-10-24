# dotfiles-nixish 🐧✨

![bash](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![zsh](https://img.shields.io/badge/bonus-zsh-F15A24?logo=zsh&logoColor=white)
![distros](https://img.shields.io/badge/distros-Debian%20%7C%20Ubuntu%20%7C%20Fedora%20%7C%20RHEL%20%7C%20Arch%20%7C%20openSUSE%20%7C%20Alpine-blue)
![idempotent](https://img.shields.io/badge/re--run-safe-success)

> Set up a fresh Linux box the way I like it, with **one command**. No Nix needed.

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
```
