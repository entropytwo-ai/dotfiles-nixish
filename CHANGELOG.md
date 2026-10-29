# Changelog

What each round of changes added to dotfiles-nixish, newest first. Commit
hashes point to the matching commits on `main`.

## 2026-10-28: eza theme file — lighter timestamp colour

- Added `config/eza-theme.yml` with all eza defaults and the timestamp colour
  changed to a lighter shade of blue (ANSI 75 / sky blue).
- The shell-config step (1b) copies it to `~/.config/eza/theme.yml` and
  creates the directory if needed; skipped gracefully if eza is not installed.

## 2026-10-28: Dotfiles split into tools, shell config and xtree

- **Menu item 1** now has three parts: **1a Tools**, **1b Shell config** and
  **1c xtree**. `1` still selects all three (or clears them); `1a`/`1b`/`1c`
  toggle one each. Item 1 shows `[x]` for all and `[~]` for some.
- **New flags:** `--tools`, `--shell-config`, `--xtree` (only those parts,
  combinable, skip the menu) and `--no-tools`, `--no-shell-config`,
  `--no-xtree`.
- Each part runs on its own: tools-only leaves `~/.bashrc` alone,
  xtree-only installs no tools, shell-config-only notes that the aliases fall
  back while the tools are missing. The summary and "Try:" line show only the
  chosen parts.
- The prerequisites are installed whenever any part is chosen. `--zsh`
  installs zsh with the tools or the shell config.
- The automatic `en_US.UTF-8` locale for a language-less system now comes
  with the shell config (1b), whose block uses it.

## 2026-10-28: List the packages and what they do

- **`--list-packages`** (or `p` in the menu) shows every package the script
  installs on this system, grouped as Always / Dotfiles tools / Only when
  needed, with a short description, the package name this distro uses
  (`apt: fortune-mod + fortunes-min`), and `✔` for the ones already
  installed. Also lists xtree. Changes nothing; works with `--package-list`.
- Every entry in `packages/package_list.txt` now has a description: the
  `# text` after the line. Your own packages can have one too.

## 2026-10-28: Better locale search

- A leading `?` and stray spaces/punctuation are ignored, so `? gb`, `?gb` and
  `? britain` work at both prompts (and `? gb` at the Locale prompt searches
  straight away).
- Searches by country and language **names** from built-in ISO tables, so it
  works the same on every distro, plus common names (`england`, `uk`, `usa`,
  `holland`, `swiss`, `farsi`, `cantonese` ...).
- Codes match exactly (`gb`, `de`), every word must match (`english canada`),
  and small typos are forgiven (`brittain`, `germnay`).
- Results are ranked: the main locale of a country/language comes first
  (`gb` -> `en_GB`, `german` -> `de_DE`). Descriptions read
  "Language - Country". Clearer messages for no matches and out-of-range
  numbers.

## 2026-10-28: Choose the locale in the menu, with a locale finder

- **Menu item 7, "Change system locale":** shows the current locale and the
  default, `en_US.UTF-8`, which is pre-filled in the prompt (Enter keeps it).
  Not selected by default, like the other items.
- **Locale finder:** type `?` at the prompt, or a language, country or
  code (`german`, `brazil`, `fr_CA`). It lists numbered matches with
  descriptions and `(installed)` markers. On its own:
  `install.sh --find-locale [TEXT]`.
- **`--locale NAME`** sets it without the menu (`de_de` works, and is
  checked against what the system can generate). **`--keep-locale`** never
  changes it.
- Any locale, not only en_US: generated per distro, then checked that it
  really works. On NixOS it's set through `i18n.defaultLocale`.
- The shell block follows the system default instead of always using
  en_US.UTF-8.
- The default for the dotfiles is unchanged: a system with no real locale
  (C/POSIX) gets en_US.UTF-8, now listed under "Planned system changes".

## 2026-10-28: en_US.UTF-8 for the whole locale, not just the time

Before, only `LC_TIME` was set, so `locale` on a fresh VM still showed
`LANG=C.UTF-8` and `C.UTF-8` everywhere else.

- **System default:** `LANG=en_US.UTF-8` is written to
  `/etc/default/locale` (Debian/Ubuntu), `/etc/locale.conf`
  (Fedora/RHEL, Arch, openSUSE) or `/etc/profile.d` (Alpine), with a backup.
  Re-runs say "already en_US.UTF-8". `--dry-run` only shows it.
  NixOS is left to `i18n.defaultLocale`.
- **Shell block:** exports `LANG` and `LC_TIME`, only when the locale exists.
  An older `export LANG=...` line outside the block is removed like other
  duplicates.
- Takes effect at the next login.

## 2026-10-28: README contents, alias list, history example

- Table of contents at the top of the README.
- **Aliases** section: every alias with what it runs and when it is set.
- **History timestamps** section: example `history` output
  (`10/26/26 16:02:02 git status`) and how bash and zsh store the times.

## 2026-10-26: NixOS rebuilds that failed for reasons outside your config

Fixes "nixos-rebuild failed to build" followed by "Your NixOS configuration
did not build before this run either" when changing the hostname.

- **Flakes + hostname (bug):** plain `nixos-rebuild` builds
  `nixosConfigurations.<running hostname>`. Once a run renamed the host,
  that name no longer existed, so every later rebuild failed, and the
  installer blamed your config. Now the configuration is always named
  explicitly (`--flake /etc/nixos#<name>`): the one matching the current or
  old hostname, or the only one. `DOTFILES_FLAKE_ATTR=<name>` picks one
  when there are several.
- **No root channel (Proxmox LXC):** when `<nixpkgs>` can't be found and
  root has no channel, the `nixos` channel matching the running release is
  added before building (`--dry-run` only shows it).
- **Checked before anything changes:** if nixos-rebuild can't run at all,
  nothing is written, and the warning says so.
- **Better blame:** when the old config doesn't build either, the
  installer tries it once without its own generated module. If that builds,
  it says a setting saved by an EARLIER dotfiles-nixish run is the cause,
  instead of "your configuration".
- **Plain-language causes** for failed builds: missing channel, unknown
  flake configuration, untracked file in a flake, full disk,
  network/DNS, invalid hostname.

## 2026-10-25: One package list for every OS

- **`packages/package_list.txt` is now the single real package list.** It
  used to be for reference only: the tools were hard-coded in `install.sh`
  and `nix/packages.nix`. Now every OS reads the same file: Debian/Ubuntu,
  Fedora/RHEL, Arch, openSUSE, Alpine and NixOS (with or without flakes).
- **All packages are in the list.** That covers the prerequisites (CA
  certificates, curl, wget, git, tar, gpg, acl, lsb-release), zsh, the
  OpenSSH server, sudo, the locale package and the tool set.
- **Sections:** `[prerequisites]`, `[zsh]` (only with `--zsh`), `[ssh]` (only
  when SSH is enabled and no server is installed), `[sudo]` (only when a user
  is created and sudo is missing), `[locale]` (only when en_US.UTF-8 is
  missing) and `[tools]`.
- **Simple line format:** `name [apt= dnf= yum= pacman= zypper= apk= nix=]
  [cmd=] [path=]`.
  - `a,b` means try a, then b.
  - `a+b` means install both together.
  - `-` means skip on that package manager.
  - `yum` falls back to the `dnf=` name.
  - `#` starts a comment. Windows (CRLF) line endings are accepted.
- **Add your own packages** by adding a line under `[tools]`. An unknown or
  mistyped package is a warning and gets skipped. It never stops the run,
  and the summary shows it as missing.
- **New option `--package-list FILE|URL`** uses another list without
  forking the repo.
- **Your edited list wins.** If `~/.dotfiles-nixish/packages/package_list.txt`
  has local changes, the next run uses it instead of the copy downloaded at
  the start.
- **Forks work:** files are downloaded from the repo set in `DOTFILES_REPO`,
  not always from the original GitHub repo.
- **NixOS now reads the list too:**
  - `install.sh` installs the `nix=` names with `nix-env` / `nix profile`.
  - `nix/packages.nix` reads the list in pure Nix, so the NixOS module,
    `default.nix` and the flake install the same packages.
  - Names that don't exist in nixpkgs are skipped with an evaluation
    warning.
- **File trimming:** `packages/` is kept on every OS now. NixOS installs
  where an older version had hidden it get it back on the next run.
- The summary checks each tool with the same rule the installer uses: the
  `cmd=`/`path=` checks from the list, or the installed package.

## 2026-10-25: NixOS system settings made safe (`7d4b24c`)

- Settings from earlier runs are never dropped. The generated NixOS module is
  merged instead of overwritten. Before, NixOS deleted the user declared by
  the previous run.
- Declared users are checked after `nixos-rebuild switch`.
- The running hostname is set right away, because `switch` only changes
  `/etc/hostname`.
- Added a hint for Proxmox LXC containers.

## 2026-10-25: SSH on LXC/Proxmox NixOS (`3eba8af`)

- The SSH check understands socket activation (`sshd.socket`,
  `services.openssh.startWhenNeeded` in LXC/Proxmox images). It waits up to
  20 s for host keys to be generated.
- Known harmless LXC mount failures (e.g. `sys-kernel-debug.mount`) are shown
  as info, not as warnings.
- Rebuild logs are saved where they survive the run.

## 2026-10-25: Menu with nothing pre-selected (`0cdb15e`)

- The first-run menu no longer ticks "Dotfiles" (option 1) by default.

## 2026-10-25: nixos-rebuild partial success (`aaeb904`)

- `switch-to-configuration` exit code 4 means "activated, but some units
  failed". The config is kept and the failed units are reported, instead of
  rolling back.
- The dry-build log is saved.

## 2026-10-25: NixOS fixes (`f04e887`)

- Missing imports such as `incus.nix` are recreated as stubs, so an existing
  broken config can still build.
- Added a systemd-networkd backend for NixOS networking
  (`10-dotfiles-nixish-<iface>`).
- Rollback only undoes the changes from this run.
- Clearer errors when the existing config was already broken.
- `install.sh` puts `/run/wrappers/bin` first in PATH (for sudo on NixOS),
  detects the init system, and counts warnings.

## 2026-10-25: System settings (`d80673b`)

- A first-run menu, plus flags, for system settings:
  - create a sudo user (hidden password, typed twice);
  - SSH for non-root users (root login off, keys, lock-out guard);
  - hostname, static IP/subnet/gateway or DHCP, and DNS.
- Per-distro backends: nmcli, netplan, systemd-networkd, ifupdown, wicked and
  a NixOS module.
- Backups, config validation and `--dry-run`.

## 2026-10-25: Clear file-trimming messages (`ba22d81`)

- Says which OS-specific files were removed and why ("unnecessary on
  <OS>"), with a short description of each and a line in the summary.
- README rewrapped to 80 columns, so it reads well in nano.

## 2026-10-25: Keep only the files this OS needs (`80915bb`)

- Non-NixOS systems drop `flake.nix`, `flake.lock`, `default.nix` and
  `nix/`, using git sparse-checkout (so `git status` stays clean and
  `git pull` still works).
- `--keep-all` brings every file back.

## 2026-10-25: Step-by-step output (`56c28f0`)

- While the dotfiles are edited, the output shows each file, its backup, the
  duplicate options removed (line, old value → new value), lines kept or left
  alone, and the syntax-check result.

## 2026-10-25: No duplicate shell settings (`f392d8e`)

- Settings outside the managed block that the block sets again are removed,
  so each option exists only once in `~/.bashrc` / `~/.zshrc`. The result is
  syntax-checked and the original is backed up.

## 2026-10-24: xtree colours (`4886838`)

- Colours work on terminals whose terminfo lacks them (vt102/vt220), using an
  ANSI fallback.
- 256-colour orange is downgraded on 8-colour consoles (TERM=linux).
- `NO_COLOR` is honoured.

## 2026-10-24: xtree install hardening (`d3ab762`)

- Works when sudo's secure_path lacks coreutils (NixOS).
- xtree is self-tested after install. If that fails, it falls back to
  `~/.local/bin`, and a dangling `~/xtree` link is never left behind.

## 2026-10-24: Login shells (`a1961ae`)

- Login shells (console, SSH) now load `~/.bashrc`: `~/.bash_profile` or
  `~/.profile` is created or patched as needed.
- Nix profile directories are added to PATH in the shell block.

## 2026-10-24: NixOS support (`c023f08`)

- NixOS with or without flakes:
  - the installer uses `nix-env` (channels) or `nix profile` (flakes);
  - there is a NixOS module, a flake and a `default.nix`.

## 2026-10-24: fortune quotes (`294cabd`)

- Installs the fortune quote database (fortunes-min/fortunes), so the cowsay
  greeting no longer says "No fortunes found".

## 2026-10-24: First version (`ae67ba4`)

- A one-line `curl | bash` installer for Debian/Ubuntu, Fedora/RHEL, Arch,
  openSUSE and Alpine.
- Installs the tool set (eza, duf, cowsay, fortune, fastfetch, tldr, nmap,
  ncdu, btop, fzf, glances, curl, bat) and xtree.
- Adds an idempotent BEGIN/END block to `~/.bashrc` (history, aliases, and a
  fastfetch + cowsay greeting).
