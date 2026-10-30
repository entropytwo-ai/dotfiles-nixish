# dotfiles-nixish 🐧✨

![bash][badge-bash] ![zsh][badge-zsh] ![distros][badge-distros]
![nixos][badge-nixos] ![re-run safe][badge-safe]

> Set up a fresh Linux box the way I like it, with **one command**.
> Works on regular distros *and* NixOS (with or without flakes).

<table><tr>
<td><img src=".github/donate-bitcoin-qr.png" width="96" alt="Bitcoin donation QR code"></td>
<td><sub>💛 If you find this project useful, I'd be grateful for any donation. Thank you!<br>
<b>Bitcoin:</b> <code>bc1qu6dkcchurnutgc40y6n53s3zm588z9nnkm2ygq</code></sub></td>
</tr></table>

---

## Table of Contents

- [🚀 One-liner install](#-one-liner-install)
- [🛠 System settings](#-system-settings)
- [📦 What it installs](#-what-it-installs)
- [➕ Adding your own packages](#-adding-your-own-packages)
- [⚙️ What it configures](#️-what-it-configures)
  - [Locale](#locale)
  - [xtree](#xtree)
  - [~/.bashrc](#bashrc)
  - [~/.zshrc](#zshrc)
  - [Aliases](#aliases)
  - [History timestamps](#history-timestamps)
  - [Safety](#safety)
- [❄️ NixOS (with or without flakes)](#️-nixos-with-or-without-flakes)
  - [Declarative option (configuration.nix)](#declarative-option-configurationnix)
- [🔄 Updating](#-updating)
- [✂️ Only the files your OS needs](#️-only-the-files-your-os-needs)
- [🧩 Manual / partial use](#-manual--partial-use)
- [🗂 Layout](#-layout)

---

## 🚀 One-liner install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/entropytwo-ai/dotfiles-nixish/main/install.sh)
```

In a terminal it first shows a menu with nothing selected - type numbers
to toggle (e.g. `1` for all the dotfiles, `1c` for just xtree), Enter to start:

```
   1) [ ] Dotfiles: all of 1a-1c (tools, shell config, xtree)
      1a) [ ] Tools        packages from the [tools] list (p shows them)
      1b) [ ] Shell config ~/.bashrc (and ~/.zshrc) block: aliases, history, greeting
      1c) [ ] xtree        tree viewer -> /usr/local/bin/xtree + ~/xtree
   2) [ ] Create a user with sudo access
   3) [ ] Enable SSH access for non-root users
   4) [ ] Change hostname          now: web-01
   5) [ ] Change IP / subnet / gw  now: eth0 192.168.1.11/24 (dhcp) ...
   6) [ ] Change DNS servers       now: 192.168.1.1
   7) [ ] Change system locale     now: C.UTF-8  (default: en_US.UTF-8)
```

`1` selects all three dotfiles parts (or clears them if all were on);
`1a`, `1b` and `1c` toggle one part each. Item 1 shows `[x]` when all three
are on and `[~]` when only some are. Type `p` to see the packages.

Details are asked next, then you see the planned changes and confirm.
See [System settings](#-system-settings) for doing the same with flags.

Add options to the end of the one-liner:

| Option             | What it does                                              |
|--------------------|-----------------------------------------------------------|
| `--tools`          | only the tools (menu 1a)                                  |
| `--shell-config`   | only the shell config (menu 1b)                           |
| `--xtree`          | only xtree (menu 1c)                                      |
| `--no-tools`, `--no-shell-config`, `--no-xtree` | skip that part               |
| `--zsh`            | also install zsh and configure `~/.zshrc`                 |
| `--no-packages`    | no package installs at all (implies `--no-tools`)         |
| `--keep-all`       | keep every repo file, not just the ones your OS needs     |
| `--package-list F` | use this package list (file or URL) instead of the repo's |
| `--flakes`         | NixOS: force `nix profile install` (flakes)               |
| `--no-flakes`      | NixOS: force `nix-env -iA` (channels)                     |
| `--no-dotfiles`    | skip the dotfiles (system settings only)                  |
| `--menu`           | always show the menu (`--no-menu`: never)                 |
| `--dry-run`        | show the system changes without making them               |
| `-y`               | don't ask "Go ahead?"                                     |

`--tools`, `--shell-config` and `--xtree` can be combined
(`--tools --xtree`); without any of them all three parts are done. Like the
system options, they skip the menu. Only the shell config (1b) switches a
language-less system locale (`C.UTF-8`, `POSIX`) to `en_US.UTF-8`, because
its block uses the system locale; tools-only and xtree-only runs leave the
locale alone.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/entropytwo-ai/dotfiles-nixish/main/install.sh) --zsh
```

When it finishes, run `source ~/.bashrc` or open a new terminal.

<sub>[↑ Back to contents](#table-of-contents)</sub>


## 🛠 System settings

Pick them in the menu, or pass flags (flags skip the menu):

| Flag                 | What it does                                    |
|----------------------|-------------------------------------------------|
| `--add-user NAME`    | create a user with sudo rights; the password is |
|                      | typed twice (hidden)                            |
| `--ssh`              | enable SSH for non-root users, root login off   |
| `--ssh-key KEY`      | authorize a key: text, a file or `gh:<user>`    |
| `--ssh-keys-only`    | turn password logins off (needs a key)          |
| `--hostname NAME`    | change the hostname                             |
| `--ip ADDR[/PFX]`    | static IPv4 address, or `dhcp`                  |
| `--subnet MASK`      | `255.255.255.0` or `/24` (if not in `--ip`)     |
| `--gateway ADDR`     | default gateway                                 |
| `--dns "A B"`        | DNS servers                                     |
| `--iface NAME`       | interface (default: the one with the route)     |
| `--locale NAME`      | system locale (default: `en_US.UTF-8`) - see [Locale](#locale) |
| `--keep-locale`      | never change the system locale                  |
| `--find-locale [TEXT]` | search locales by language/country/code, then exit |
| `--list-packages` | show the packages it installs here, what each does and which are installed, then exit |

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/entropytwo-ai/dotfiles-nixish/main/install.sh) \
  --no-dotfiles --add-user ops --ssh-key gh:octocat --hostname web-01 \
  --ip 192.168.1.50/24 --gateway 192.168.1.1 --dns "1.1.1.1 9.9.9.9"
```

How each one is applied:

| Setting  | Distros                  | How                                    |
|----------|--------------------------|----------------------------------------|
| User     | Debian, Ubuntu           | `useradd` + group `sudo`, `chpasswd`   |
|          | Fedora, Arch, SUSE, ...  | group `wheel` (+ sudoers rule if off)  |
|          | Alpine                   | `adduser` + `wheel`, installs sudo     |
| SSH      | all but NixOS            | `sshd_config.d/10-dotfiles-nixish.conf`|
| Hostname | all but NixOS            | `hostnamectl` or `/etc/hostname`       |
| Locale   | all but NixOS            | generate it + `/etc/default/locale` or `/etc/locale.conf` |
| Network  | NetworkManager           | `nmcli connection modify`              |
|          | netplan (Ubuntu server)  | `netplan set` + `netplan apply`        |
|          | systemd-networkd         | `00-dotfiles-nixish-<iface>.network`   |
|          | ifupdown (Debian)        | `/etc/network/interfaces`              |
|          | wicked (openSUSE)        | `ifcfg-<iface>`                        |
| All      | NixOS                    | `/etc/nixos/dotfiles-nixish-system.nix`|
|          |                          | + `nixos-rebuild switch`               |

Safety:

- Every changed file gets a backup: `<file>.dotfiles-nixish.bak.<time>`.
- Configs are checked before use (`sshd -t`, `visudo -c`,
  `netplan generate`, `nixos-rebuild`); on failure they are undone.
- Password logins stay on when you have no SSH key (no lock-out).
- Passwords go to `chpasswd` on stdin - never on a command line or disk.
  Non-interactive: set `DOTFILES_USER_PASSWORD`.
- Over SSH, a network change is applied 5 s later in the background, so
  your session ends cleanly. Reconnect on the new address.
- NixOS: the generated module is imported into `configuration.nix`
  (and `git add`ed for flakes). The new user is also created at once, so
  the password works; it lasts unless `users.mutableUsers = false`.
- NixOS + systemd-networkd (e.g. Incus/LXD images): network settings go
  into `systemd.network.networks."10-dotfiles-nixish-<iface>"`, which
  wins over the image's `50-eth0` DHCP unit.
- NixOS: a missing imported file such as `./incus.nix` (Incus images on
  Proxmox) is recreated as a small stub so `nixos-rebuild` can run.
- NixOS: settings from earlier runs stay in the generated module; a run
  only replaces what it changes. (NixOS deletes a user that is no longer
  declared, so dropping one would remove the account.)
- NixOS rollback only undoes this run: files it created are removed,
  files it changed are restored, other files are never touched. It also
  tells you if the config was already broken before this run, or if a
  setting saved by an earlier run is the cause, and names the likely
  reason (missing channel, flake name, full disk, network).
- NixOS + flakes: the build always names the configuration
  (`--flake /etc/nixos#<name>`), so a hostname change can't break later
  rebuilds. With several configurations and none named like the host, set
  `DOTFILES_FLAKE_ATTR=<name>`.
- NixOS without flakes: if root has no `nixos` channel (common in Proxmox
  LXC containers), the channel matching your release is added first,
  because `nixos-rebuild` can't find `<nixpkgs>` without it.

<sub>[↑ Back to contents](#table-of-contents)</sub>


## 📦 What it installs

| Tool                     | What it is                           |
|--------------------------|--------------------------------------|
| `eza`                    | modern `ls`                          |
| `duf`                    | nicer `df`                           |
| `cowsay` + `fortune-mod` | 🐮 wisdom                            |
| `fastfetch`              | system info banner                   |
| `tldr`                   | simplified man pages (or `tealdeer`) |
| `nmap`                   | network scanner                      |
| `ncdu`                   | disk usage browser                   |
| `btop`, `glances`        | system monitors                      |
| `fzf`                    | fuzzy finder                         |
| `bat`                    | `cat` with syntax highlighting       |

This is the `[tools]` section of
[`packages/package_list.txt`](packages/package_list.txt), the one package
list used on every OS (see [Adding your own packages](#-adding-your-own-packages)).

**See the full list for your system** - every package, what it does, the
package name your distro uses, and whether it's already installed. Nothing
is changed:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/entropytwo-ai/dotfiles-nixish/main/install.sh) --list-packages
```

In the menu, type `p`. Example (Debian):

```text
  Dotfiles tools (menu item 1a)
   ✔ eza        Modern ls with colors, icons and git status (the l / ll
                aliases); falls back to the eza repo or GitHub
   ✔ duf        Disk usage/free space as a colorful table (a better df)
   · fortune    Random quotes for the cow to say, with the quote database
                apt: fortune-mod + fortunes-min
   ...
  Only when needed for a chosen option
   · zsh        The Z shell (only with --zsh)
   · openssh    SSH server (only for "Enable SSH" when none is installed)
                apt: openssh-server
```

`✔` = already installed, `·` = would be installed. The descriptions come
from the `# text` after each line in the package list.

Notes:

- If `eza` is not in your distro's repos, it comes from the official eza
  apt repo or a GitHub release binary.
- If `fastfetch` is not in your repos, it comes from the official GitHub
  `.deb`, `.rpm` or tarball.
- On Debian/Ubuntu, `bat` is also linked from `batcat`.
- Prerequisites (`[prerequisites]` in the list): ca-certificates, curl,
  wget, git, tar, gnupg, `acl` (needed by `xtree -A`) and lsb-release.
- RHEL/Rocky/Alma: **EPEL** is turned on automatically.
- Arch: the script runs `pacman -Syu`, because Arch doesn't support
  partial upgrades.
- A package that fails to install only gives a warning; the installer
  keeps going.

<sub>[↑ Back to contents](#table-of-contents)</sub>


## ➕ Adding your own packages

Every package the installer can install is in **one file**:
[`packages/package_list.txt`](packages/package_list.txt). It covers
the prerequisites, the tools, zsh, the SSH server, sudo and the locale
package. It is used on **every OS**: apt, dnf/yum, pacman, zypper, apk
and NixOS (installer, NixOS module, `default.nix` and flake).

Add a line under `[tools]`:

```
[tools]
...
htop                                       # Interactive process viewer
ripgrep  cmd=rg                            # Very fast text search (rg)
fd       cmd=fd,fdfind apt=fd-find dnf=fd-find   # Simple, fast alternative to find
```

Line format: `name [apt= dnf= yum= pacman= zypper= apk= nix=] [cmd=] [path=]`

| Part            | Meaning                                                             |
|-----------------|---------------------------------------------------------------------|
| `name`          | package name, also the command checked for "already installed"      |
| `apt=`...`nix=` | the name for that package manager, if different (`yum` uses `dnf=`) |
| `a,b`           | try `a`, then `b`                                                   |
| `a+b`           | install `a` and `b` together                                        |
| `-`             | skip on that package manager                                        |
| `cmd=a,b`       | command(s) that prove it's installed                                |
| `path=a,b`      | file(s) that prove it's installed                                   |
| `# text`        | after an entry: its description, shown by `--list-packages`; on its own line: a comment |

Sections: `[prerequisites]` (always), `[zsh]` (with `--zsh`), `[ssh]`
(when SSH is enabled and no server is installed), `[sudo]` (when a user
is created and sudo is missing), `[locale]` (when the chosen locale must be generated)
and `[tools]`. The NixOS module uses `[prerequisites]` and `[tools]`.

A name that doesn't exist on your distro gets a warning and is skipped
(shown as missing in the summary). The run carries on.

Three ways to use your own list:

- **Edit your checkout:** `~/.dotfiles-nixish/packages/package_list.txt`,
  then re-run `bash ~/.dotfiles-nixish/install.sh`. The local list wins
  over the downloaded one.
- **Pass a list:** `... install.sh) --package-list ~/my_list.txt` (a file
  or an `https://` URL).
- **Fork the repo**, edit the list there, and point the one-liner at your
  fork: `DOTFILES_REPO=https://github.com/you/dotfiles-nixish.git bash <(curl -fsSL https://raw.githubusercontent.com/you/dotfiles-nixish/main/install.sh)`.

<sub>[↑ Back to contents](#table-of-contents)</sub>


## ⚙️ What it configures

### Locale

The system locale is **en_US.UTF-8 by default**. Cloud and VM images usually
start with `C.UTF-8`.

- **Menu item 7, "Change system locale"**, shows the current locale and the
  default. When you pick it, the prompt is pre-filled with `en_US.UTF-8`:
  press Enter to keep it, type another name (`de_DE.UTF-8`, or just
  `de_de`), or type `?` to search.
- **Search (locale finder):** type `?` (or `? gb` straight away), then any
  of these - every word must match, best matches come first:
  - a **country**: `britain`, `germany`, `united states`, or common names
    like `england`, `uk`, `usa`, `holland`, `swiss`
  - a **language**: `german`, `english`, `farsi`, `cantonese`
  - a **code**: `gb`, `de`, `fr_CA`, `de_DE.UTF-8`
  - **both**, to narrow it down: `english canada`, `french swiss`

  Small typos are forgiven (`brittain`, `germnay`). Pick a number, or type a
  new search. `(installed)` marks locales that are already set up.
  ```text
     Search by language, country or code (e.g. german, britain, gb, fr_CA; Enter = back): england

     5 matches for "england" (best first):
       1) en_GB.UTF-8            English - United Kingdom
       2) cy_GB.UTF-8            Welsh - United Kingdom
       3) gd_GB.UTF-8            Scottish Gaelic - United Kingdom
       4) gv_GB.UTF-8            Manx - United Kingdom
       5) kw_GB.UTF-8            Cornish - United Kingdom
  ```
  If you type a name the system doesn't know, it searches for it.
- **On its own**, without changing anything:
  `bash install.sh --find-locale german` (or `--find-locale` with no text
  for the interactive search). Then use the result with `--locale NAME`.
- **Without the menu:** `--locale de_DE.UTF-8`.
- **Dotfiles default:** if the system has no real locale (`C`,
  `C.UTF-8`, `POSIX` or nothing) and you install the dotfiles, it is set to
  en_US.UTF-8 and listed under "Planned system changes". `--keep-locale`
  skips this. A locale you chose earlier is never changed by this.

What it does:

1. Generates the locale if it's missing: `locales` + `/etc/locale.gen` +
   `locale-gen` (Debian/Ubuntu, Arch), `glibc-langpack-<lang>`
   (Fedora/RHEL), `glibc-locale` (openSUSE), or `localedef` as a last
   resort. It then checks that the locale really works
   (`LC_ALL=<name> locale charmap`).
2. Makes it the default for new logins, with a backup of the old file. Only
   `LANG` is written, so no `LC_*` or `LANGUAGE` lines keep parts of the old
   locale:

   | Distro                         | Where                                        |
   |--------------------------------|----------------------------------------------|
   | Debian / Ubuntu                | `/etc/default/locale`                        |
   | Fedora / RHEL, Arch, openSUSE  | `/etc/locale.conf` (+ `localectl set-locale`) |
   | Alpine                         | `/etc/profile.d/00-dotfiles-nixish-locale.sh` |
   | NixOS                          | `i18n.defaultLocale` in the generated module, then `nixos-rebuild switch` |

3. The bash/zsh block reads that default and exports `LANG` and `LC_TIME`,
   so an SSH client's own `LANG`/`LC_*` can't override it.

It takes effect at the **next login**. Log out and back in, then check with
`locale`: every line should show the chosen locale.

### xtree

[`scripts/xtree.sh`](scripts/xtree.sh) is installed to
`/usr/local/bin/xtree`, with a symlink at `~/xtree`.

It's a tree view with:

- color themes: `-s default|alternative|christmas|halloween`
  (`-r` picks one at random)
- permissions, owner, dates and ACLs
- CSV export

### ~/.bashrc

A block between `# dotfiles-nixish BEGIN` and `# dotfiles-nixish END`:

- **History:** `HISTCONTROL=ignoreboth:erasedups`, `histappend`,
  10000 entries, timestamps (`%m/%d/%y %T`)
- **Locale:** `LANG=en_US.UTF-8` and `LC_TIME=en_US.UTF-8`, set only if
  the locale exists, so programs never warn "cannot change locale"
- **Aliases:** `l` and `ll` (eza, falling back to exa, then ls), `la`,
  `cowsays`, `xtree`, and `bat` on Debian - see [Aliases](#aliases)
- **eza theme:** `~/.config/eza/theme.yml` (from `config/eza-theme.yml`) -
  eza's default colours with lighter sky-blue timestamps; copied only when
  eza is installed
- **Greeting:** every interactive shell shows `fastfetch` with a
  `fortune | cowsay` logo 🐄

### ~/.zshrc

Only if zsh is installed. The same settings in zsh syntax
(`setopt APPEND_HISTORY`, `SAVEHIST`, and so on).

### Aliases

Set in both `~/.bashrc` and `~/.zshrc` (and by the NixOS module when its
shell settings are enabled):

| Alias     | Runs                                                        | Notes |
|-----------|-------------------------------------------------------------|-------|
| `l`       | `eza -la --color=always --group-directories-first`          | Long list, hidden files included, folders first. Uses `exa`, then `ls`, if eza is missing |
| `ll`      | `eza -a --color=always --group-directories-first`           | Short (grid) list, hidden files included. Same fallback as `l` |
| `la`      | `ls -A`                                                     | Plain `ls`, hidden files without `.` and `..` |
| `bat`     | `batcat`                                                    | Only where bat is installed as `batcat` (Debian/Ubuntu) |
| `cowsays` | MOTD, then `fastfetch --logo <(fortune \| cowsay -W 30)`    | The login greeting on demand. The MOTD part runs only where `/etc/update-motd.d` exists (Ubuntu) |
| `xtree`   | `/usr/local/bin/xtree`                                      | Only when installed there. Otherwise `xtree` comes from `PATH` (`~/.local/bin` or the NixOS module) |
| `history` | `fc -t "%m/%d/%y %T" -l 1`                                  | **zsh only:** whole history with timestamps, like bash's `history` |

Check what is active in your shell with `alias`.

### History timestamps

Every command is saved with the date and time it ran, shown as
`MM/DD/YY HH:MM:SS` (24-hour, `%m/%d/%y %T`). Example `history` output:

```text
    1  10/26/26 16:02:02 cd ~/projects
    2  10/26/26 16:02:21 git status
    3  10/26/26 16:03:30 sudo apt update
```

- **bash:** `HISTTIMEFORMAT='%m/%d/%y %T '`. In `~/.bash_history`, each
  command has a `#<unix-time>` line above it (for example `#1793030522`).
- **zsh:** `setopt EXTENDED_HISTORY` stores the time
  (`: 1793030522:0;cd ~/projects` in `~/.zsh_history`). The `history`
  alias above prints the same format as bash.
- Commands typed before the installer ran have no saved time, so they all
  show the time the history file was loaded.
- `history 20` shows the last 20 commands in bash. In zsh, use
  `fc -t "%m/%d/%y %T" -l -20`.

### Safety

- Before an rc file is changed, a backup is saved as
  `*.dotfiles-nixish.bak.<timestamp>`.
- **Every setting exists only once.** Lines outside the block that set
  something the block sets again are removed and listed in the output.
  Examples: Ubuntu's stock `HISTSIZE=1000`, `HISTCONTROL=ignoreboth`,
  `alias ll='ls -alF'`.
- Only simple one-line statements at the top level are removed.
  These are never touched:
  - lines inside `if` / `case` blocks
  - `PATH`
  - `HISTFILE`
- If the result would fail `bash -n` / `zsh -n`, the file is left
  unchanged.

<sub>[↑ Back to contents](#table-of-contents)</sub>


## ❄️ NixOS (with or without flakes)

The same one-liner works on NixOS. NixOS already ships `curl`, and the
installer adds `git` itself.

Packages go into **your user profile**, so no `nixos-rebuild` is needed.
The installer picks the method automatically:

| Your setup         | What the installer runs                           |
|--------------------|---------------------------------------------------|
| Channels (default) | `nix-env -f '<nixpkgs>' -iA eza duf ...`          |
| Flakes             | `nix profile install nixpkgs#eza nixpkgs#duf ...` |

- "Flakes" is used when there is no `<nixpkgs>` channel, or when your
  profile is already a `nix profile` one.
- Flakes mode passes `--extra-experimental-features 'nix-command flakes'`,
  so flakes don't need to be turned on in `nix.conf`.
- To choose the method yourself, add `--no-flakes` or `--flakes`.
- `xtree` and the `~/.bashrc` / `~/.zshrc` block are the same as on
  other distros.
- The installer doesn't change the system: no channel updates and no
  locale generation.
- `en_US.UTF-8` is the NixOS default locale. If you've removed it, add
  this to your configuration:

  ```nix
  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];
  ```

### Declarative option (configuration.nix)

The repo includes a NixOS module. Enabling it installs all the tools plus
`xtree` system-wide.

**Without flakes:** in `/etc/nixos/configuration.nix`

```nix
{
  imports = [
    "${builtins.fetchTarball "https://github.com/entropytwo-ai/dotfiles-nixish/archive/main.tar.gz"}/nix/module.nix"
  ];
  programs.dotfiles-nixish.enable = true;
  # also apply the bash/zsh block system-wide:
  # programs.dotfiles-nixish.shellConfig = true;
}
```

**With flakes:** in `/etc/nixos/flake.nix`

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

Then run `sudo nixos-rebuild switch`. After that, pick **one** of:

1. Run the one-liner with `--no-packages` (adds only the shell block and
   the `/usr/local/bin/xtree` link), **or**
2. Set `shellConfig = true` and skip the installer.

Don't do both, or the greeting shows twice.

**Just the tools, no config:**

```bash
# no flakes
nix-env -if https://github.com/entropytwo-ai/dotfiles-nixish/archive/main.tar.gz
# flakes
nix profile install github:entropytwo-ai/dotfiles-nixish
```

> 💡 **zsh as your NixOS login shell:** use `programs.zsh.enable = true;`
> and `users.users.<you>.shell = pkgs.zsh;`. A zsh installed into your
> user profile isn't in `/etc/shells`, so it can't be your login shell.

<sub>[↑ Back to contents](#table-of-contents)</sub>


## 🔄 Updating

```bash
git -C ~/.dotfiles-nixish pull && bash ~/.dotfiles-nixish/install.sh
```

Running the one-liner again does the same thing. The managed block is
**replaced in place**, never duplicated. Put your own customizations
outside the BEGIN/END markers.

<sub>[↑ Back to contents](#table-of-contents)</sub>


## ✂️ Only the files your OS needs

After detecting the OS, the installer removes the repo files that OS
doesn't use from `~/.dotfiles-nixish`, and says so in its output:

| Detected OS     | Removed as unnecessary                           |
|-----------------|--------------------------------------------------|
| Not NixOS       | `flake.nix`, `flake.lock`, `default.nix`, `nix/` |
| NixOS           | nothing: every file is used (`packages/` too)    |

How it's done:

- **Git checkout (the normal case):** git sparse-checkout. The files
  leave the disk, `git status` stays clean and `git pull` keeps working.
- **No git (direct download):** the unneeded files are never downloaded.
- **Unzipped copy:** the unneeded files are deleted.
- **You edited a file that would be removed:** nothing is removed, and
  you get a warning.
- **Copy inside another git repo:** never touched.

To get every file back, re-run with `--keep-all`. GitHub always keeps the
full repo.

<sub>[↑ Back to contents](#table-of-contents)</sub>


## 🧩 Manual / partial use

```bash
git clone https://github.com/entropytwo-ai/dotfiles-nixish.git ~/.dotfiles-nixish

# just try the config in this shell
source ~/.dotfiles-nixish/config/bashrc_append.sh
source ~/.dotfiles-nixish/config/zshrc_append.sh     # zsh flavor

# just xtree
sudo install -m 755 ~/.dotfiles-nixish/scripts/xtree.sh /usr/local/bin/xtree
```

<sub>[↑ Back to contents](#table-of-contents)</sub>


## 🗂 Layout

`[nixos]` files are removed locally on other distros. Everything else is
used on every OS.

```
install.sh                  the bootstrap script
scripts/xtree.sh            xtree
scripts/system-setup.sh     user, SSH, hostname, IP, DNS
config/bashrc_append.sh     ~/.bashrc block
config/zshrc_append.sh      ~/.zshrc block
packages/package_list.txt   THE package list (every OS)
flake.nix, flake.lock       flake: NixOS module + packages [nixos]
default.nix                 entry point without flakes     [nixos]
nix/module.nix              NixOS module                   [nixos]
nix/packages.nix            reads the list for Nix         [nixos]
nix/xtree.nix               xtree as a Nix package         [nixos]
CHANGELOG.md                what each change added
```


[badge-bash]: .github/badges/bash.svg
[badge-zsh]: .github/badges/zsh.svg
[badge-distros]: .github/badges/distros.svg
[badge-nixos]: .github/badges/nixos.svg
[badge-safe]: .github/badges/safe.svg

<sub>[↑ Back to contents](#table-of-contents)</sub>
