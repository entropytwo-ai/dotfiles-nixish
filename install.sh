#!/usr/bin/env bash
# =============================================================================
#  dotfiles-nixish installer - "make a new Linux system like I like it"
#
#  One-liner:
#    bash <(curl -fsSL https://raw.githubusercontent.com/entropytwo-ai/dotfiles-nixish/main/install.sh)
#
#  Supports apt (Debian/Ubuntu/Mint/Pop), dnf/yum (Fedora/RHEL/Rocky/Alma),
#  pacman (Arch/Manjaro/Endeavour), zypper (openSUSE), apk (Alpine) and
#  NixOS (with or without flakes: nix-env + channels, or nix profile).
#  Safe to re-run: packages already present are skipped, the shell config block
#  is replaced in place, and the xtree binary/symlink are refreshed.
#
#  Options:
#    --zsh            also install zsh (then ~/.zshrc gets configured too)
#    --no-packages    skip package installation (config + xtree only)
#    --flakes         NixOS: force `nix profile install nixpkgs#...`
#    --no-flakes      NixOS: force `nix-env -iA` with channels
#    -h, --help       show help
#  Env overrides: DOTFILES_REPO, DOTFILES_BRANCH, DOTFILES_DIR, DOTFILES_PM
# =============================================================================
set -uo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/entropytwo-ai/dotfiles-nixish.git}"
BRANCH="${DOTFILES_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/entropytwo-ai/dotfiles-nixish/${BRANCH}"
MARK_BEGIN="# dotfiles-nixish BEGIN"
MARK_END="# dotfiles-nixish END"
XTREE_BIN="/usr/local/bin/xtree"
TS="$(date +%Y%m%d-%H%M%S)"

OPT_ZSH=false
OPT_PACKAGES=true
NIX_MODE=""        # "env" (channels, no flakes) or "profile" (flakes); auto-detected if empty
for arg in "$@"; do
    case "$arg" in
        --zsh) OPT_ZSH=true ;;
        --no-packages) OPT_PACKAGES=false ;;
        --flakes) NIX_MODE=profile ;;
        --no-flakes) NIX_MODE="env" ;;
        -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//'
                   echo "See https://github.com/entropytwo-ai/dotfiles-nixish"; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------- pretty output
if [[ -t 1 ]]; then
    C_B=$'\e[1m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_C=$'\e[36m'; C_0=$'\e[0m'
else
    C_B=""; C_G=""; C_Y=""; C_R=""; C_C=""; C_0=""
fi
step() { printf '\n%s==> %s%s\n' "$C_B$C_C" "$*" "$C_0"; }
info() { printf '   %s\n' "$*"; }
ok()   { printf '   %s✔%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '   %s⚠ %s%s\n' "$C_Y" "$*" "$C_0"; WARNINGS+=("$*"); }
die()  { printf '%s✖ %s%s\n' "$C_R" "$*" "$C_0" >&2; exit 1; }
WARNINGS=()

have() { command -v "$1" >/dev/null 2>&1; }
# cowsay/fortune live in /usr/games on Debian/Ubuntu
export PATH="/usr/local/bin:$PATH:/usr/games"

# ---------------------------------------------------------------- sanity checks
[[ "$(uname -s)" == "Linux" ]] || die "This installer only supports Linux."

if [[ $EUID -eq 0 ]]; then
    SUDO=()
else
    have sudo || die "sudo is required (or run this script as root)."
    # Pass our PATH through: sudo's secure_path (and sudo-rs defaults) point at
    # /usr/bin:/bin, which on NixOS holds no coreutils - `sudo install` would fail.
    # (sbin dirs appended: they are in secure_path but often not in a user's PATH)
    SUDO=(sudo "$(command -v env)" "PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin")
    step "Requesting sudo (needed for package installs and /usr/local/bin)"
    sudo -v || die "Could not obtain sudo privileges."
    # keep sudo alive while we work
    ( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
    SUDO_KEEPALIVE=$!
    trap 'kill "${SUDO_KEEPALIVE:-}" 2>/dev/null' EXIT
fi

# Configure the *real* user even when invoked via `sudo bash install.sh`
if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="$SUDO_USER"
else
    TARGET_USER="$(id -un)"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)"
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || TARGET_HOME="$HOME"
TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")"

as_target() {   # run a command as the target user
    if [[ "$(id -un)" == "$TARGET_USER" ]]; then "$@"; else sudo -u "$TARGET_USER" -H env "PATH=$PATH" "$@"; fi
}
fix_owner() {   # give files back to the target user if we're root on their behalf
    [[ $EUID -eq 0 && "$TARGET_USER" != "root" ]] && chown -h "$TARGET_USER:$TARGET_GROUP" "$@" 2>/dev/null
    return 0
}

# ---------------------------------------------------------------- distro detection
OS_ID="unknown"; OS_LIKE=""; OS_VER=""; OS_NAME="Linux"
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"; OS_LIKE="${ID_LIKE:-}"; OS_VER="${VERSION_ID:-}"; OS_NAME="${PRETTY_NAME:-$OS_ID}"
fi

IS_NIXOS=false
[[ "$OS_ID" == "nixos" || -e /etc/NIXOS ]] && IS_NIXOS=true

if   [[ -n "${DOTFILES_PM:-}" ]]; then PM="$DOTFILES_PM"
elif $IS_NIXOS && have nix-env; then PM=nix
elif have apt-get; then PM=apt
elif have dnf;     then PM=dnf
elif have yum;     then PM=yum
elif have pacman;  then PM=pacman
elif have zypper;  then PM=zypper
elif have apk;     then PM=apk
else PM=none
fi

ARCH="$(uname -m)"

# ---------------------------------------------------------------- Nix / NixOS
# Without flakes: nix-env -iA against the <nixpkgs> channel.
# With flakes:    nix profile install nixpkgs#<pkg>  (used automatically when no
#                 channel exists, or when the user profile is already a
#                 `nix profile` one - nix-env refuses to touch those).
NIX_FLAGS=(--extra-experimental-features "nix-command flakes")
if [[ "$PM" == "nix" ]]; then
    # user-profile bins (classic, XDG and NixOS per-user locations)
    PATH="$TARGET_HOME/.nix-profile/bin:$TARGET_HOME/.local/state/nix/profile/bin:/etc/profiles/per-user/$TARGET_USER/bin:/run/current-system/sw/bin:$PATH"
    if [[ -z "$NIX_MODE" ]]; then
        if [[ -e "$TARGET_HOME/.nix-profile/manifest.json" || -e "$TARGET_HOME/.local/state/nix/profile/manifest.json" ]]; then
            NIX_MODE=profile
        elif as_target nix-instantiate --eval -E '<nixpkgs>' >/dev/null 2>&1; then
            NIX_MODE="env"
        else
            NIX_MODE=profile
        fi
    fi
    [[ "$NIX_MODE" == "profile" ]] && ! have nix && die "Flakes mode needs the 'nix' command, which was not found."
fi
nix_mode_label() { [[ "$NIX_MODE" == "env" ]] && echo "nix-env + channels (no flakes)" || echo "nix profile + flakes"; }

step "Detected: ${OS_NAME} (${ARCH}) - package manager: ${PM}$([[ "$PM" == nix ]] && echo " [$(nix_mode_label)]") - user: ${TARGET_USER}"

# ---------------------------------------------------------------- package manager wrappers
REFRESHED=false
pm_refresh() {
    $REFRESHED && return 0
    REFRESHED=true
    info "Refreshing package metadata..."
    case "$PM" in
        apt)    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 update -qq ;;
        dnf)    "${SUDO[@]}" dnf -y -q makecache ;;
        yum)    "${SUDO[@]}" yum -y -q makecache ;;
        pacman) "${SUDO[@]}" pacman -Syu --noconfirm ;;   # Arch: never partial-upgrade
        zypper) "${SUDO[@]}" zypper --non-interactive --quiet refresh ;;
        apk)    "${SUDO[@]}" apk update -q ;;
        nix)    true ;;   # never auto-update channels / flake registry behind your back
    esac >/dev/null 2>&1 || warn "Package metadata refresh reported errors (continuing)."
}

pm_install() {  # pm_install pkg... ; returns non-zero on failure, never aborts
    case "$PM" in
        apt)    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 \
                    install -y -qq --no-install-recommends "$@" ;;
        dnf)    "${SUDO[@]}" dnf install -y -q "$@" ;;
        yum)    "${SUDO[@]}" yum install -y -q "$@" ;;
        pacman) "${SUDO[@]}" pacman -S --noconfirm --needed "$@" ;;
        zypper) "${SUDO[@]}" zypper --non-interactive --quiet install --no-recommends "$@" ;;
        apk)    "${SUDO[@]}" apk add -q "$@" ;;
        nix)    nix_install "$@" ;;
        *)      return 1 ;;
    esac >/dev/null 2>&1
}

# Nix installs go into the *target user's* profile (no sudo needed)
nix_install() {
    local a refs=()
    if [[ "$NIX_MODE" == "env" ]]; then
        as_target nix-env -f '<nixpkgs>' -iA "$@" && return 0
        for a in "$@"; do refs+=("nixos.$a"); done      # root channel named "nixos"
        as_target nix-env -iA "${refs[@]}"
    else
        for a in "$@"; do refs+=("nixpkgs#$a"); done
        as_target nix "${NIX_FLAGS[@]}" profile install "${refs[@]}"
    fi
}

# Nix evaluates nixpkgs once per call, so install everything missing in one go
nix_batch() {  # nix_batch <logical-tool>...
    [[ "$PM" == "nix" ]] || return 0
    local t p miss=()
    for t in "$@"; do
        tool_present "$t" && continue
        p="$(candidates "$t" | awk '{print $1}')"; [[ -n "$p" ]] && miss+=("$p")
    done
    [[ ${#miss[@]} -gt 0 ]] || return 0
    info "Installing via $(nix_mode_label): ${miss[*]}"
    info "(first run downloads from the Nix binary cache - this can take a few minutes)"
    pm_install "${miss[@]}" || info "Batch install failed - retrying one package at a time..."
}

# Package candidates per logical tool (first one that installs wins)
candidates() {
    local tool="$1"
    case "$PM:$tool" in
        nix:gpg)         echo "gnupg" ;;
        nix:certs)       echo "cacert" ;;
        nix:lsb)         echo "lsb-release" ;;
        nix:tar)         echo "gnutar" ;;
        nix:fortune)     echo "fortune" ;;
        nix:tldr)        echo "tldr tealdeer" ;;
        *:git|*:curl|*:wget|*:tar|*:acl|*:nmap|*:ncdu|*:btop|*:fzf|*:glances|*:duf|*:cowsay|*:eza|*:fastfetch|*:bat|*:zsh)
                         echo "$tool" ;;
        apt:gpg)         echo "gnupg" ;;
        *:gpg)           echo "gnupg2 gnupg" ;;
        apt:certs|dnf:certs|yum:certs|zypper:certs|apk:certs|pacman:certs) echo "ca-certificates" ;;
        apt:lsb)         echo "lsb-release" ;;
        dnf:lsb|yum:lsb) echo "redhat-lsb-core lsb_release" ;;
        pacman:lsb)      echo "lsb-release" ;;
        zypper:lsb)      echo "lsb-release" ;;
        apk:lsb)         echo "lsb-release-minimal lsb-release" ;;
        zypper:fortune|apk:fortune) echo "fortune" ;;
        *:fortune)       echo "fortune-mod" ;;
        pacman:tldr|apk:tldr|zypper:tldr) echo "tealdeer tldr" ;;
        *:tldr)          echo "tldr tealdeer" ;;
        *)               echo "$tool" ;;
    esac
}

# Command used to decide whether a tool is already present
tool_cmd() {
    case "$1" in
        fortune) echo fortune ;;  certs) echo "" ;;  lsb) echo lsb_release ;;
        acl) echo getfacl ;;      gpg) echo gpg ;;    *) echo "$1" ;;
    esac
}

tool_present() {
    local t="$1" c
    c="$(tool_cmd "$t")"
    case "$t" in
        certs) [[ -s /etc/ssl/certs/ca-certificates.crt || -s /etc/pki/tls/certs/ca-bundle.crt || -d /etc/ssl/certs ]] && return 0; return 1 ;;
        bat)   have bat || have batcat ;;
        *)     have "$c" ;;
    esac
}

ensure_tool() {  # ensure_tool <logical-name> [quiet]
    local tool="$1" pkg
    if tool_present "$tool"; then ok "$tool (already installed)"; return 0; fi
    pm_refresh
    for pkg in $(candidates "$tool"); do
        if pm_install "$pkg" && tool_present "$tool"; then ok "$tool (via $PM: $pkg)"; return 0; fi
    done
    # tool-specific fallbacks
    if declare -F "fallback_$tool" >/dev/null && "fallback_$tool" && tool_present "$tool"; then
        return 0
    fi
    warn "Could not install '$tool' on this system - skipped."
    return 1
}

# ---------------------------------------------------------------- download helper
fetch() {  # fetch URL DEST
    if have curl; then curl -fsSL --retry 3 -o "$2" "$1"
    elif have wget; then wget -q -O "$2" "$1"
    else return 1; fi
}

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-nixish.XXXXXX")"
trap 'rm -rf "$WORKDIR"; kill "${SUDO_KEEPALIVE:-}" 2>/dev/null' EXIT

is_musl() { ldd --version 2>&1 | grep -qi musl || [[ -e /lib/ld-musl-x86_64.so.1 || -e /lib/ld-musl-aarch64.so.1 ]]; }

# ---------------------------------------------------------------- eza fallbacks
fallback_eza() {
    [[ "$PM" == "nix" ]] && return 1   # foreign binaries don't belong on NixOS
    if [[ "$PM" == "apt" ]]; then
        info "eza not in your apt repos - adding the official eza repo (deb.gierens.de)..."
        ensure_tool gpg >/dev/null; ensure_tool wget >/dev/null
        if "${SUDO[@]}" mkdir -p /etc/apt/keyrings \
            && fetch https://raw.githubusercontent.com/eza-community/eza/main/deb.asc "$WORKDIR/eza.asc" \
            && "${SUDO[@]}" gpg --batch --yes --dearmor -o /etc/apt/keyrings/gierens.gpg "$WORKDIR/eza.asc" \
            && echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
               | "${SUDO[@]}" tee /etc/apt/sources.list.d/gierens.list >/dev/null \
            && "${SUDO[@]}" chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list \
            && REFRESHED=false && pm_refresh && pm_install eza && have eza; then
            ok "eza (via deb.gierens.de)"; return 0
        fi
        warn "eza apt repo setup failed - trying the GitHub release binary."
    fi
    local asset=""
    case "$ARCH" in
        x86_64)         asset="eza_x86_64-unknown-linux-musl.tar.gz" ;;   # static, works on glibc + musl
        aarch64|arm64)  asset="eza_aarch64-unknown-linux-gnu.tar.gz" ;;
        armv7l|armv6l)  asset="eza_arm-unknown-linux-gnueabihf.tar.gz" ;;
        *) return 1 ;;
    esac
    info "Downloading eza release binary ($asset)..."
    fetch "https://github.com/eza-community/eza/releases/latest/download/$asset" "$WORKDIR/eza.tgz" \
        && tar -xzf "$WORKDIR/eza.tgz" -C "$WORKDIR" \
        && "${SUDO[@]}" install -m 0755 "$WORKDIR/eza" /usr/local/bin/eza \
        && ok "eza (GitHub release -> /usr/local/bin/eza)"
}

# ---------------------------------------------------------------- fastfetch fallbacks
fallback_fastfetch() {
    [[ "$PM" == "nix" ]] && return 1
    local a=""
    case "$ARCH" in
        x86_64) a="amd64" ;; aarch64|arm64) a="aarch64" ;; armv7l) a="armv7l" ;;
        i686|i386) a="i686" ;; riscv64|ppc64le|s390x|loongarch64) a="$ARCH" ;;
        *) return 1 ;;
    esac
    local base="https://github.com/fastfetch-cli/fastfetch/releases/latest/download"
    # "polyfilled" builds target older glibc (e.g. Ubuntu 20.04 / Debian 11 / RHEL 8)
    local poly=""; [[ "$a" == "amd64" || "$a" == "aarch64" ]] && poly="-polyfilled"
    if [[ "$PM" == "apt" ]]; then
        info "Installing fastfetch from the official GitHub .deb..."
        if fetch "$base/fastfetch-linux-$a$poly.deb" "$WORKDIR/fastfetch.deb" \
            && pm_install "$WORKDIR/fastfetch.deb" && have fastfetch; then
            ok "fastfetch (GitHub .deb)"; return 0
        fi
    elif [[ "$PM" == "dnf" || "$PM" == "yum" || "$PM" == "zypper" ]] && ! is_musl; then
        info "Installing fastfetch from the official GitHub .rpm..."
        if fetch "$base/fastfetch-linux-$a$poly.rpm" "$WORKDIR/fastfetch.rpm"; then
            if [[ "$PM" == "zypper" ]]; then
                "${SUDO[@]}" zypper --non-interactive --no-gpg-checks install "$WORKDIR/fastfetch.rpm" >/dev/null 2>&1
            else
                pm_install "$WORKDIR/fastfetch.rpm"
            fi
            have fastfetch && { ok "fastfetch (GitHub .rpm)"; return 0; }
        fi
    fi
    # generic tarball -> /usr/local
    local tb="fastfetch-linux-$a$poly"
    is_musl && { [[ "$a" == "amd64" ]] && tb="fastfetch-musl-amd64" || return 1; }
    info "Installing fastfetch from the GitHub tarball ($tb)..."
    fetch "$base/$tb.tar.gz" "$WORKDIR/fastfetch.tgz" \
        && tar -xzf "$WORKDIR/fastfetch.tgz" -C "$WORKDIR" \
        && "${SUDO[@]}" install -m 0755 "$WORKDIR/$tb/usr/bin/fastfetch" /usr/local/bin/fastfetch \
        && ok "fastfetch (GitHub tarball -> /usr/local/bin/fastfetch)"
}

# ---------------------------------------------------------------- extra repos (RHEL family)
enable_epel() {
    [[ "$PM" == "dnf" || "$PM" == "yum" ]] || return 0
    [[ "$OS_ID" == "fedora" ]] && return 0
    [[ " $OS_ID $OS_LIKE " == *" rhel "* || " $OS_ID $OS_LIKE " == *" centos "* ]] || return 0
    rpm -q epel-release >/dev/null 2>&1 && { ok "EPEL (already enabled)"; return 0; }
    info "Enabling EPEL (needed for btop, glances, fastfetch, duf... on RHEL-family)..."
    "${SUDO[@]}" "$PM" config-manager --set-enabled crb >/dev/null 2>&1 \
        || "${SUDO[@]}" "$PM" config-manager --set-enabled powertools >/dev/null 2>&1 || true
    if pm_install epel-release \
        || pm_install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_VER%%.*}.noarch.rpm"; then
        ok "EPEL enabled"; REFRESHED=false
    else
        warn "Could not enable EPEL - some packages may be unavailable."
    fi
}

# =============================================================================
#  1. Prerequisites
# =============================================================================
if $OPT_PACKAGES; then
    [[ "$PM" == "none" ]] && warn "No supported package manager found - skipping package installs."
    if [[ "$PM" != "none" ]]; then
        step "Installing prerequisites"
        enable_epel
        nix_batch certs curl wget git tar gpg acl lsb
        for t in certs curl wget git tar gpg acl lsb; do ensure_tool "$t" || true; done
    fi
fi

# =============================================================================
#  2. Get the repo files (local checkout, or clone/update ~/.dotfiles-nixish)
# =============================================================================
step "Fetching dotfiles-nixish"
SELF="${BASH_SOURCE[0]:-}"
SELF_DIR=""
[[ -n "$SELF" && -f "$SELF" ]] && SELF_DIR="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)"

if [[ -n "$SELF_DIR" && -f "$SELF_DIR/scripts/xtree.sh" && -f "$SELF_DIR/config/bashrc_append.sh" ]]; then
    SRC_DIR="$SELF_DIR"
    ok "Using local checkout: $SRC_DIR"
else
    SRC_DIR="${DOTFILES_DIR:-$TARGET_HOME/.dotfiles-nixish}"
    if have git && [[ -d "$SRC_DIR/.git" ]]; then
        if as_target git -C "$SRC_DIR" pull --ff-only -q; then ok "Updated $SRC_DIR"
        else warn "git pull failed in $SRC_DIR - using the existing copy."; fi
    elif have git && [[ ! -e "$SRC_DIR" ]] \
         && as_target git clone -q --depth=1 -b "$BRANCH" "$REPO_URL" "$SRC_DIR"; then
        ok "Cloned into $SRC_DIR"
    else
        info "git unavailable (or $SRC_DIR is not a git checkout) - downloading files directly..."
        mkdir -p "$SRC_DIR/scripts" "$SRC_DIR/config" "$SRC_DIR/packages"
        for f in install.sh scripts/xtree.sh config/bashrc_append.sh config/zshrc_append.sh packages/package_list.txt; do
            fetch "$RAW_BASE/$f" "$SRC_DIR/$f" || die "Failed to download $f from $RAW_BASE"
        done
        chmod +x "$SRC_DIR/install.sh" "$SRC_DIR/scripts/xtree.sh"
        [[ $EUID -eq 0 && "$TARGET_USER" != "root" ]] && chown -R "$TARGET_USER:$TARGET_GROUP" "$SRC_DIR"
        ok "Downloaded into $SRC_DIR"
    fi
fi
[[ -f "$SRC_DIR/scripts/xtree.sh" ]] || die "scripts/xtree.sh missing in $SRC_DIR"

# =============================================================================
#  3. Packages
# =============================================================================
TOOLS=(eza duf cowsay fortune fastfetch tldr nmap ncdu btop fzf glances curl bat)
$OPT_ZSH && TOOLS+=(zsh)

if $OPT_PACKAGES && [[ "$PM" != "none" ]]; then
    step "Installing packages"
    nix_batch "${TOOLS[@]}"
    for t in "${TOOLS[@]}"; do ensure_tool "$t" || true; done

    # The fortune binary can exist without any quote database ("No fortunes found"):
    # apt's --no-install-recommends skips 'fortunes-min'/'fortunes'. Verify and fix.
    if have fortune && ! fortune >/dev/null 2>&1; then
        case "$PM" in
            apt)            fdb="fortunes-min fortunes" ;;
            dnf|yum|pacman) fdb="fortune-mod" ;;
            zypper|apk)     fdb="fortune" ;;
            *)              fdb="" ;;
        esac
        for p in $fdb; do pm_install "$p" || true; done
        if fortune >/dev/null 2>&1; then ok "fortune quote database installed"
        else warn "fortune has no quote database - install your distro's fortunes package manually."; fi
    fi

    # Debian/Ubuntu name the bat binary "batcat" - provide a real `bat` command too
    if ! have bat && have batcat; then
        "${SUDO[@]}" ln -sfn "$(command -v batcat)" /usr/local/bin/bat && ok "bat -> batcat symlink in /usr/local/bin"
    fi

    # tealdeer/tldr need a page cache before first use
    if have tldr; then
        if as_target timeout 90 tldr --update >/dev/null 2>&1; then ok "tldr page cache updated"
        else info "(tldr cache update skipped - run 'tldr --update' later if needed)"; fi
    fi
fi

# =============================================================================
#  4. Locale for LC_TIME=en_US.UTF-8
# =============================================================================
if $OPT_PACKAGES && ! locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
    step "Generating en_US.UTF-8 locale (used by LC_TIME)"
    case "$PM" in
        apt)    pm_install locales
                "${SUDO[@]}" sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen 2>/dev/null
                grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen 2>/dev/null \
                    || echo 'en_US.UTF-8 UTF-8' | "${SUDO[@]}" tee -a /etc/locale.gen >/dev/null
                "${SUDO[@]}" locale-gen >/dev/null 2>&1 ;;
        pacman) "${SUDO[@]}" sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen && "${SUDO[@]}" locale-gen >/dev/null 2>&1 ;;
        dnf|yum) pm_install glibc-langpack-en || pm_install glibc-locale-source ;;
        zypper) pm_install glibc-locale ;;
        nix)    info "NixOS locales are declarative - add to /etc/nixos/configuration.nix:"
                info '  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];  # then: sudo nixos-rebuild switch' ;;
    esac
    if locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then ok "en_US.UTF-8 available"
    else warn "en_US.UTF-8 locale not available - LC_TIME may fall back to C."; fi
fi

# =============================================================================
#  5. xtree -> /usr/local/bin/xtree  +  ~/xtree symlink
# =============================================================================
step "Installing xtree"
XT_TEST_DIR="$(mktemp -d)"
XT_OUT=""
xtree_works() {   # actually run it (tiny dir; capture first - grep -q + pipefail = SIGPIPE false negatives)
    [[ -f "$1" && -x "$1" ]] || { XT_OUT="$1 not found"; return 1; }
    XT_OUT="$(TERM=dumb "$1" -L 1 "$XT_TEST_DIR" 2>&1)"
    [[ "$XT_OUT" == *Name* ]]
}

"${SUDO[@]}" mkdir -p /usr/local/bin \
    && "${SUDO[@]}" install -m 0755 "$SRC_DIR/scripts/xtree.sh" "$XTREE_BIN"
if xtree_works "$XTREE_BIN"; then
    ok "$XTREE_BIN (self-test passed)"
else
    # Fall back to a user-owned location that is always writable and on PATH
    USER_XTREE="$TARGET_HOME/.local/bin/xtree"
    warn "Could not install $XTREE_BIN - using $USER_XTREE instead"
    mkdir -p "$TARGET_HOME/.local/bin" && install -m 0755 "$SRC_DIR/scripts/xtree.sh" "$USER_XTREE"
    fix_owner "$TARGET_HOME/.local" "$TARGET_HOME/.local/bin" "$USER_XTREE"
    XTREE_BIN="$USER_XTREE"
    if xtree_works "$XTREE_BIN"; then ok "$XTREE_BIN (self-test passed)"
    else warn "xtree self-test FAILED: $(printf '%s' "$XT_OUT" | head -2 | tr '\n' ' ')"; fi
fi
rm -rf "$XT_TEST_DIR"
LINK="$TARGET_HOME/xtree"
if [[ -e "$LINK" && ! -L "$LINK" ]]; then
    mv "$LINK" "$LINK.bak.$TS" && info "Existing ~/xtree moved to ~/xtree.bak.$TS"
fi
if [[ -x "$XTREE_BIN" ]]; then
    ln -sfn "$XTREE_BIN" "$LINK" && fix_owner "$LINK" && ok "$LINK -> $XTREE_BIN"
else
    [[ -L "$LINK" && ! -e "$LINK" ]] && rm -f "$LINK"   # never leave a dangling ~/xtree
fi

# =============================================================================
#  6. Shell config (idempotent BEGIN/END block)
# =============================================================================
# Remove lines OUTSIDE our block that set something the block sets again
# (e.g. Ubuntu's stock HISTSIZE=1000 or alias ll='ls -alF'), so every setting
# exists only once. The keys are read from the snippet itself. Only simple
# top-level (column 0) one-line statements are touched - nothing inside if/case
# blocks - and the result must still pass `bash -n`/`zsh -n`, otherwise nothing
# is removed. The full original is kept in the timestamped .bak file.
dedupe_rc() {  # dedupe_rc <rcfile> <snippet> <file-to-filter-in-place>
    local rc="$1" snippet="$2" f="$3" vars aliases opts pat removed shell_chk
    # PATH is built up incrementally and HISTFILE's default must not clobber a user value
    vars=$(grep -oE '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' "$snippet" \
           | sed -E 's/^[[:space:]]*(export[[:space:]]+)?//; s/=$//' | grep -vxE 'PATH|HISTFILE' | sort -u | paste -sd'|' -)
    aliases=$(grep -oE '^[[:space:]]*alias[[:space:]]+[A-Za-z0-9_.-]+=' "$snippet" \
           | sed -E 's/^[[:space:]]*alias[[:space:]]+//; s/=$//' | sort -u | paste -sd'|' -)
    opts=$(grep -oE '^[[:space:]]*(shopt[[:space:]]+-[su]|setopt)[[:space:]]+[A-Za-z_]+' "$snippet" \
           | awk '{print $NF}' | sort -u | paste -sd'|' -)
    pat='^('
    [[ -n "$vars" ]]    && pat+="(export[[:space:]]+)?($vars)=|"
    [[ -n "$aliases" ]] && pat+="alias[[:space:]]+($aliases)=|"
    [[ -n "$opts" ]]    && pat+="(shopt[[:space:]]+-[su]|setopt)[[:space:]]+($opts)([[:space:]]*(#.*)?)$|"
    pat="${pat%|})"
    [[ "$pat" == '^()' ]] && return 0

    awk -v p="$pat" '$0 ~ p && $0 !~ /\\$/ {next} {print}' "$f" > "$f.dd"
    removed=$(awk -v p="$pat" '$0 ~ p && $0 !~ /\\$/' "$f")
    [[ -z "$removed" ]] && { rm -f "$f.dd"; return 0; }

    case "$rc" in *zshrc*) shell_chk=zsh ;; *) shell_chk=bash ;; esac
    if have "$shell_chk" && ! "$shell_chk" -n "$f.dd" 2>/dev/null; then
        warn "$rc: could not safely remove settings duplicated by the dotfiles-nixish block - left as-is."
        rm -f "$f.dd"; return 0
    fi
    mv "$f.dd" "$f"
    info "Removed from $rc (now set once, in the dotfiles-nixish block):"
    printf '%s\n' "$removed" | sed 's/^/        - /'
}

install_block() {  # install_block <rcfile> <snippet>
    local rc="$1" snippet="$2" tmp nb ne
    [[ -f "$snippet" ]] || { warn "Snippet $snippet missing"; return 1; }
    if [[ ! -e "$rc" ]]; then touch "$rc" && fix_owner "$rc"; fi
    nb=$(grep -cxF "$MARK_BEGIN" "$rc" || true); ne=$(grep -cxF "$MARK_END" "$rc" || true)
    if [[ "$nb" != "$ne" ]]; then
        warn "$rc has unbalanced dotfiles-nixish markers - fix it manually; not modified."
        return 1
    fi
    tmp="$WORKDIR/rc.$$"
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
        $0==b {skip=1; next}  $0==e {skip=0; next}  !skip {print}' "$rc" > "$tmp.base"
    dedupe_rc "$rc" "$snippet" "$tmp.base"
    # drop trailing blank lines left behind by a previous block
    sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp.base" > "$tmp"
    { [[ -s "$tmp" ]] && echo; cat "$snippet"; } >> "$tmp"
    if cmp -s "$tmp" "$rc"; then
        ok "$rc already up to date"
    else
        [[ -s "$rc" ]] && cp -p "$rc" "$rc.dotfiles-nixish.bak.$TS" && fix_owner "$rc.dotfiles-nixish.bak.$TS"
        cat "$tmp" > "$rc"   # keep inode/permissions
        if [[ "$nb" -gt 0 ]]; then ok "$rc updated (previous block replaced)"; else ok "$rc configured"; fi
    fi
}

step "Configuring shells"
install_block "$TARGET_HOME/.bashrc" "$SRC_DIR/config/bashrc_append.sh"

# Login shells (console, SSH) read only the FIRST of ~/.bash_profile,
# ~/.bash_login, ~/.profile - never ~/.bashrc. Ubuntu's skel ~/.profile sources
# ~/.bashrc, but NixOS (no /etc/skel) and minimal installs start with an empty
# home, so without this the whole block is ignored in login shells.
LOGIN_RC=""
for f in .bash_profile .bash_login .profile; do
    [[ -f "$TARGET_HOME/$f" ]] && { LOGIN_RC="$TARGET_HOME/$f"; break; }
done
if [[ -z "$LOGIN_RC" ]]; then
    LOGIN_RC="$TARGET_HOME/.bash_profile"
    # shellcheck disable=SC2016
    printf '# Created by dotfiles-nixish: login shells (console/SSH) should load ~/.bashrc\n[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' > "$LOGIN_RC"
    fix_owner "$LOGIN_RC"
    ok "$LOGIN_RC created (login shells now load ~/.bashrc)"
elif ! grep -qE '(\.|source)[[:space:]]+.*\.bashrc' "$LOGIN_RC"; then
    # ~/.profile is also read by sh/dash/ash, so only source bashrc from bash
    # shellcheck disable=SC2016
    printf '\n# dotfiles-nixish: load ~/.bashrc in bash login shells\nif [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi\n' >> "$LOGIN_RC"
    fix_owner "$LOGIN_RC"
    ok "$LOGIN_RC now sources ~/.bashrc"
else
    ok "$LOGIN_RC already sources ~/.bashrc"
fi

ZSH_DONE=false
if have zsh; then
    install_block "$TARGET_HOME/.zshrc" "$SRC_DIR/config/zshrc_append.sh" && ZSH_DONE=true
else
    info "zsh not installed - skipping ~/.zshrc (re-run with --zsh to install it)."
fi

# =============================================================================
#  7. Summary
# =============================================================================
step "Summary"
for t in "${TOOLS[@]}" xtree; do
    case "$t" in
        bat)   c=bat; have bat || c=batcat ;;
        xtree) c="$XTREE_BIN" ;;
        *)     c="$t" ;;
    esac
    if have "$c" || [[ -x "$c" ]]; then printf '   %s✔%s %s\n' "$C_G" "$C_0" "$t"
    else printf '   %s✖%s %s %s(missing)%s\n' "$C_R" "$C_0" "$t" "$C_Y" "$C_0"; fi
done

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '\n%sWarnings:%s\n' "$C_Y" "$C_0"
    printf '   - %s\n' "${WARNINGS[@]}"
fi

cat <<EOF

${C_B}${C_G}🎉 dotfiles-nixish is installed!${C_0}

   Activate it now:   ${C_B}source ~/.bashrc${C_0}$($ZSH_DONE && printf '   (zsh: %ssource ~/.zshrc%s)' "$C_B" "$C_0")
   ...or simply open a new terminal.

   Try:  ${C_C}l${C_0}  ${C_C}ll${C_0}  ${C_C}cowsays${C_0}  ${C_C}xtree -f -L 2 .${C_0}  ${C_C}xtree -r -p -u -t ~${C_0}  ${C_C}duf${C_0}  ${C_C}btop${C_0}
   Update later:  bash ${SRC_DIR}/install.sh   (after: git -C ${SRC_DIR} pull)
EOF
exit 0
