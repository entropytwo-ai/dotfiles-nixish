#!/usr/bin/env bash
# =============================================================================
#  dotfiles-nixish installer - "make a new Linux system like I like it"
#
#  One-liner:
#    bash <(curl -fsSL https://raw.githubusercontent.com/entropytwo-ai/dotfiles-nixish/main/install.sh)
#
#  Run it in a terminal and it first shows a menu: dotfiles, SSH access for
#  non-root users, hostname, IP address/subnet/gateway, DNS. Every choice can
#  also be given as an option (see --help) for unattended installs.
#
#  Supports apt (Debian/Ubuntu/Mint/Pop), dnf/yum (Fedora/RHEL/Rocky/Alma),
#  pacman (Arch/Manjaro/Endeavour), zypper (openSUSE), apk (Alpine) and
#  NixOS (with or without flakes: nix-env + channels, or nix profile).
#  Safe to re-run: packages already present are skipped, the shell config block
#  is replaced in place, and the xtree binary/symlink are refreshed.
#  Packages: packages/package_list.txt (one list for every OS; --package-list F).
#  Env overrides: DOTFILES_REPO, DOTFILES_BRANCH, DOTFILES_DIR, DOTFILES_PM,
#                 DOTFILES_NET_BACKEND (nm|netplan|networkd|ifupdown|wicked|nixos)
# =============================================================================
set -uo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/entropytwo-ai/dotfiles-nixish.git}"
BRANCH="${DOTFILES_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/entropytwo-ai/dotfiles-nixish/${BRANCH}"
# a GitHub fork given in DOTFILES_REPO: download single files from it as well
if [[ "$REPO_URL" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
    RAW_BASE="https://raw.githubusercontent.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}/${BRANCH}"
fi
PKG_LIST_REL=packages/package_list.txt   # the one package list for every OS
MARK_BEGIN="# dotfiles-nixish BEGIN"
MARK_END="# dotfiles-nixish END"
XTREE_BIN="/usr/local/bin/xtree"
TS="$(date +%Y%m%d-%H%M%S)"

OPT_ZSH=false
OPT_PACKAGES=true
OPT_KEEP_ALL=false
OPT_DOTFILES=true      # tools + shell config + xtree
OPT_MENU=auto          # auto: show the menu when run in a terminal without system options
OPT_YES=false
OPT_DRY=false
OPT_PKG_LIST=""       # --package-list FILE|URL
DIRECT_DL=false
NIX_MODE=""        # "env" (channels, no flakes) or "profile" (flakes); auto-detected if empty
# system settings (applied by scripts/system-setup.sh)
DO_SSH=false; SSH_KEY=""; SSH_PASSWORDS=true
DO_USER=false; NEW_USER=""; NEW_USER_PW=""
NEW_HOSTNAME=""; NET_IFACE=""; NET_IP=""; NET_MASK=""; NET_GW=""; NET_DNS=""
SYS_FLAGS=false

usage() {
    cat <<'EOF'
dotfiles-nixish installer

  bash <(curl -fsSL https://raw.githubusercontent.com/entropytwo-ai/dotfiles-nixish/main/install.sh) [options]

Run in a terminal, it first shows a menu. Giving system options skips the menu.

Dotfiles:
  --zsh                 also install zsh and configure ~/.zshrc
  --no-packages         skip package installs (shell config + xtree only)
  --no-dotfiles         skip tools, shell config and xtree (system settings only)
  --flakes | --no-flakes   NixOS: force nix profile (flakes) / nix-env (channels)
  --keep-all            keep every repo file (default: only what this OS needs)
  --package-list F      use this package list (file or URL) instead of
                        packages/package_list.txt from the repo

System settings:
  --add-user NAME       create a user with sudo rights (asks for the password)
  --ssh                 enable SSH access for non-root users (root login off)
  --ssh-key KEY         also authorize a public key for you: the key text,
                        a file, or gh:<github-user>   (implies --ssh)
  --ssh-keys-only       turn password logins off (only if you have a key)
  --hostname NAME       change the hostname
  --ip ADDR[/PREFIX]    static IPv4 address, e.g. 192.168.1.50/24 - or "dhcp"
  --subnet MASK         subnet as 255.255.255.0 or /24 (if not given in --ip)
  --gateway ADDR        default gateway
  --dns "A B"           DNS servers (space or comma separated)
  --iface NAME          network interface (default: the one with the default route)

Other:
  --menu | --no-menu    always / never show the menu
  -y, --yes             don't ask for confirmation
  --dry-run             show the system changes without making them
  -h, --help            show this help
EOF
}

need_val() { [[ $# -ge 2 && -n "$2" ]] || { echo "Option $1 needs a value (try --help)" >&2; exit 2; }; }
while [[ $# -gt 0 ]]; do
    [[ "$1" == --*=* ]] && set -- "${1%%=*}" "${1#*=}" "${@:2}"
    case "$1" in
        --zsh) OPT_ZSH=true ;;
        --no-packages) OPT_PACKAGES=false ;;
        --no-dotfiles) OPT_DOTFILES=false ;;
        --flakes) NIX_MODE=profile ;;
        --no-flakes) NIX_MODE="env" ;;
        --keep-all) OPT_KEEP_ALL=true ;;
        --package-list) need_val "$@"; OPT_PKG_LIST="$2"; shift ;;
        --add-user) need_val "$@"; NEW_USER="$2"; SYS_FLAGS=true; shift ;;
        --ssh) DO_SSH=true; SYS_FLAGS=true ;;
        --ssh-key) need_val "$@"; SSH_KEY="$2"; DO_SSH=true; SYS_FLAGS=true; shift ;;
        --ssh-keys-only) SSH_PASSWORDS=false; DO_SSH=true; SYS_FLAGS=true ;;
        --hostname) need_val "$@"; NEW_HOSTNAME="$2"; SYS_FLAGS=true; shift ;;
        --ip) need_val "$@"; NET_IP="$2"; SYS_FLAGS=true; shift ;;
        --subnet|--netmask) need_val "$@"; NET_MASK="$2"; SYS_FLAGS=true; shift ;;
        --gateway) need_val "$@"; NET_GW="$2"; SYS_FLAGS=true; shift ;;
        --dns) need_val "$@"; NET_DNS="$2"; SYS_FLAGS=true; shift ;;
        --iface|--interface) need_val "$@"; NET_IFACE="$2"; shift ;;
        --menu) OPT_MENU=yes ;;
        --no-menu) OPT_MENU=no ;;
        -y|--yes) OPT_YES=true ;;
        --dry-run) OPT_DRY=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
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

# --- progress output helpers for dotfile/repo edits
disp()  { local p="$1"; [[ "$p" == "$TARGET_HOME"/* ]] && p="~${p#"$TARGET_HOME"}"; printf '%s' "$p"; }
sub()   { printf '   %s→%s %s\n' "$C_C" "$C_0" "$*"; }
short() { local s="$1" n="${2:-46}"; (( ${#s} > n )) && s="${s:0:n-1}…"; printf '%s' "$s"; }
ltrim() { local s="$1"; printf '%s' "${s#"${s%%[![:space:]]*}"}"; }


have() { command -v "$1" >/dev/null 2>&1; }
# cowsay/fortune live in /usr/games on Debian/Ubuntu
export PATH="/usr/local/bin:$PATH:/usr/games"

# ---------------------------------------------------------------- sanity checks
[[ "$(uname -s)" == "Linux" ]] || die "This installer only supports Linux."

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
    # NixOS: setuid programs (sudo, su, ping...) only work through the wrappers,
    # so /run/wrappers/bin must come first - the store copy of sudo is not setuid
    [[ -d /run/wrappers/bin ]] && PATH="/run/wrappers/bin:$PATH"
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

# =============================================================================
#  0. What should this run do? (menu, or the system options given on the command line)
# =============================================================================
valid_ipv4() {
    local o; local -a p
    [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS=. read -ra p <<<"$1"
    for o in "${p[@]}"; do (( 10#$o <= 255 )) || return 1; done
}
valid_ipv6() { [[ "$1" == *:* && "$1" =~ ^[0-9A-Fa-f:.]+$ ]]; }
valid_hostname() {
    [[ ${#1} -le 253 && "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]
}
ip2int() { local a b c d; IFS=. read -r a b c d <<<"$1"; echo $(( (10#$a << 24) | (10#$b << 16) | (10#$c << 8) | 10#$d )); }
int2ip() { echo "$(( ($1 >> 24) & 255 )).$(( ($1 >> 16) & 255 )).$(( ($1 >> 8) & 255 )).$(( $1 & 255 ))"; }
prefix2mask() { int2ip $(( (0xFFFFFFFF << (32 - $1)) & 0xFFFFFFFF )); }
mask2prefix() {   # 255.255.255.0, 24 or /24 -> 24
    local m="${1#/}" v inv n=0
    if [[ "$m" =~ ^[0-9]{1,2}$ ]]; then (( m >= 1 && m <= 32 )) && { echo "$m"; return 0; }; return 1; fi
    valid_ipv4 "$m" || return 1
    v=$(ip2int "$m"); inv=$(( ~v & 0xFFFFFFFF ))
    (( (inv & (inv + 1)) == 0 )) || return 1          # mask bits must be contiguous
    while (( v & 0x80000000 )); do n=$((n + 1)); v=$(( (v << 1) & 0xFFFFFFFF )); done
    (( n >= 1 )) && echo "$n"
}
same_subnet() { local m; m=$(( (0xFFFFFFFF << (32 - $3)) & 0xFFFFFFFF )); (( ($(ip2int "$1") & m) == ($(ip2int "$2") & m) )); }

# current state (read-only)
cur_iface() { ip -o -4 route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") {print $(i+1); exit}}'; }
cur_addr()  { ip -o -4 addr show dev "$1" scope global 2>/dev/null | awk '{print $4; exit}'; }
cur_gw()    { ip -4 route show default dev "$1" 2>/dev/null | awk '{print $3; exit}'; }
cur_mode()  { ip -o -4 addr show dev "$1" 2>/dev/null | grep -q dynamic && echo DHCP || echo static; }
cur_dns() {
    local d
    d="$(awk '$1 == "nameserver" {print $2}' /etc/resolv.conf 2>/dev/null | grep -v '^127\.' | tr '\n' ' ')"
    if [[ -z "${d// }" ]] && have resolvectl; then
        d="$(resolvectl dns 2>/dev/null | sed 's/^[^:]*://' | tr ' ' '\n' | grep -E '^[0-9a-fA-F:.]+$' | grep -v '^127\.' | awk '!s[$0]++' | tr '\n' ' ')"
    fi
    echo "${d% }"
}
list_ifaces() { local i o=(); for i in /sys/class/net/*; do [[ "${i##*/}" == lo ]] || o+=("${i##*/}"); done; echo "${o[*]}"; }

DO_HOST=false; DO_NET=false; DO_DNS=false; sel=""
NET_MODE=static; NET_ADDR=""; NET_PREFIX=""; DNS_LIST=""

# Check/complete the network choices. Sets PLAN_ERR on failure.
plan_network() {
    local cur p
    PLAN_ERR=""
    NET_IFACE="${NET_IFACE:-$(cur_iface)}"
    [[ -n "$NET_IFACE" ]] || { PLAN_ERR="no default network interface found - use --iface"; return 1; }
    [[ -e "/sys/class/net/$NET_IFACE" ]] || { PLAN_ERR="network interface '$NET_IFACE' does not exist (have: $(list_ifaces))"; return 1; }
    cur="$(cur_addr "$NET_IFACE")"
    if [[ "${NET_IP,,}" == dhcp ]]; then NET_MODE=dhcp; NET_ADDR=""; NET_PREFIX=""; NET_GW=""; return 0; fi
    NET_MODE=static
    NET_ADDR="${NET_IP:-${cur%/*}}"; NET_ADDR="${NET_ADDR%%/*}"
    valid_ipv4 "$NET_ADDR" || { PLAN_ERR="'$NET_ADDR' is not a valid IPv4 address"; return 1; }
    if [[ "$NET_IP" == */* ]]; then p="${NET_IP#*/}"; elif [[ -n "$NET_MASK" ]]; then p="$NET_MASK"; else p="${cur#*/}"; [[ "$cur" == */* ]] || p=""; fi
    [[ -n "$p" ]] || { PLAN_ERR="no subnet given - use e.g. 192.168.1.50/24 or --subnet 255.255.255.0"; return 1; }
    NET_PREFIX="$(mask2prefix "$p")" || { PLAN_ERR="'$p' is not a valid subnet mask or prefix"; return 1; }
    if [[ -z "$NET_GW" ]]; then
        NET_GW="$(cur_gw "$NET_IFACE")"
        [[ -n "$NET_GW" ]] && ! same_subnet "$NET_ADDR" "$NET_GW" "$NET_PREFIX" && NET_GW=""
        [[ -n "$NET_GW" ]] || { PLAN_ERR="no gateway given - use --gateway"; return 1; }
    fi
    valid_ipv4 "$NET_GW" || { PLAN_ERR="'$NET_GW' is not a valid gateway address"; return 1; }
    same_subnet "$NET_ADDR" "$NET_GW" "$NET_PREFIX" || { PLAN_ERR="gateway $NET_GW is not inside $NET_ADDR/$NET_PREFIX"; return 1; }
    [[ "$NET_ADDR" != "$NET_GW" ]] || { PLAN_ERR="the address and the gateway are the same"; return 1; }
}
plan_dns() {   # normalise NET_DNS into DNS_LIST
    local d out=()
    PLAN_ERR=""
    for d in ${NET_DNS//,/ }; do
        valid_ipv4 "$d" || valid_ipv6 "$d" || { PLAN_ERR="'$d' is not a valid DNS server address"; return 1; }
        [[ " ${out[*]} " == *" $d "* ]] || out+=("$d")
    done
    [[ ${#out[@]} -gt 0 ]] || { PLAN_ERR="no DNS servers given"; return 1; }
    DNS_LIST="${out[*]}"
}
valid_key_arg() { [[ "$1" =~ ^(gh|github): || -f "$1" || "$1" =~ ^(ssh-|ecdsa-|sk-) ]]; }

# --- interactive helpers (read from the terminal even with `curl ... | bash`)
ask() {   # ask <var> <prompt> [default]
    local _a
    printf '   %s%s' "$2" "${3:+ [$3]}"; printf ': '
    IFS= read -r -u 3 _a || { echo; die "No input - aborting."; }
    _a="$(ltrim "$_a")"; _a="${_a%"${_a##*[![:space:]]}"}"
    printf -v "$1" '%s' "${_a:-${3:-}}"
}
yesno() { local _r; ask _r "$1 (y/n)" "$2"; [[ "${_r,,}" == y* ]]; }
valid_username() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ && "$1" != root ]]; }
ask_password() {  # ask_password <user> -> NEW_USER_PW ; hidden input, typed twice
    local a b
    while true; do
        printf '   Password for %s (hidden): ' "$1"; IFS= read -rs -u 3 a || { echo; die "No input - aborting."; }; echo
        if [[ -z "$a" ]]; then printf '   %sThe password cannot be empty.%s\n' "$C_Y" "$C_0"; continue; fi
        printf '   Type it again: '; IFS= read -rs -u 3 b || { echo; die "No input - aborting."; }; echo
        if [[ "$a" != "$b" ]]; then printf '   %sThe passwords do not match - try again.%s\n' "$C_Y" "$C_0"; continue; fi
        if (( ${#a} < 8 )) && ! yesno "That is shorter than 8 characters. Use it anyway?" n; then continue; fi
        NEW_USER_PW="$a"; return 0
    done
}

TTY_OK=false
if [[ "$OPT_MENU" != no ]] && [[ -t 1 ]] && { exec 3</dev/tty; } 2>/dev/null; then TTY_OK=true; fi
SHOW_MENU=false
if $TTY_OK && { [[ "$OPT_MENU" == yes ]] || ! $SYS_FLAGS; }; then SHOW_MENU=true; fi

if $SHOW_MENU; then
    # nothing is pre-selected; only items given as flags start ticked
    M=(false "$([[ -n "$NEW_USER" ]] && echo true || echo false)" "$DO_SSH" "$([[ -n "$NEW_HOSTNAME" ]] && echo true || echo false)" \
       "$([[ -n "$NET_IP$NET_MASK$NET_GW" ]] && echo true || echo false)" "$([[ -n "$NET_DNS" ]] && echo true || echo false)")
    ci="$(cur_iface)"
    while true; do
        cur_net="${ci:-no default route}"; [[ -n "$ci" ]] && cur_net+=" $(cur_addr "$ci") ($(cur_mode "$ci")), gateway $(cur_gw "$ci")"
        printf '\n%s  What should this run do?%s\n\n' "$C_B" "$C_0"
        i=0
        for label in "Dotfiles: tools, shell config, xtree" \
                     "Create a user with sudo access" \
                     "Enable SSH access for non-root users" \
                     "Change hostname          now: $(hostname 2>/dev/null)" \
                     "Change IP / subnet / gw  now: $cur_net" \
                     "Change DNS servers       now: $(cur_dns)"; do
            mark=" "; ${M[$i]} && mark="${C_G}x${C_0}"
            printf '   %d) [%s] %s\n' $((i + 1)) "$mark" "$label"; i=$((i + 1))
        done
        printf '\n'
        ask sel "Type numbers to toggle (e.g. \"2 3\"), Enter to start, q to quit"
        case "$sel" in
            q|Q) echo "   Nothing changed."; exit 0 ;;
            "") if [[ " ${M[*]} " == *true* ]]; then break; else printf '   %sSelect at least one item.%s\n' "$C_Y" "$C_0"; fi ;;
            *)  for n in ${sel//,/ }; do
                    if [[ "$n" =~ ^[1-6]$ ]]; then if ${M[$((n - 1))]}; then M[n - 1]=false; else M[n - 1]=true; fi
                    else printf '   %s"%s" is not a menu number%s\n' "$C_Y" "$n" "$C_0"; fi
                done ;;
        esac
    done
    OPT_DOTFILES=${M[0]}; DO_USER=${M[1]}; DO_SSH=${M[2]}; DO_HOST=${M[3]}; DO_NET=${M[4]}; DO_DNS=${M[5]}

    if $DO_USER; then
        printf '\n%s  New user with sudo access%s\n' "$C_B" "$C_0"
        while true; do
            ask NEW_USER "Username" "$NEW_USER"
            valid_username "$NEW_USER" && break
            printf '   %sUse lowercase letters, digits, - and _ (start with a letter), not root.%s\n' "$C_Y" "$C_0"
        done
        id "$NEW_USER" >/dev/null 2>&1 && info "$NEW_USER already exists - it will get sudo access and the new password."
        $OPT_DRY || ask_password "$NEW_USER"
    fi

    if $DO_SSH; then
        printf '\n%s  SSH access for non-root users%s  (root login over SSH will be turned off)\n' "$C_B" "$C_0"
        while true; do
            ask SSH_KEY "Public key for $TARGET_USER - paste it, a file path, or gh:<github-user> (Enter = none)" "$SSH_KEY"
            [[ -z "$SSH_KEY" ]] || valid_key_arg "$SSH_KEY" && break
            printf '   %sThat does not look like a public key (ssh-ed25519 AAAA...), a file or gh:user.%s\n' "$C_Y" "$C_0"
        done
        if [[ -n "$SSH_KEY" ]]; then yesno "Allow password logins too?" y && SSH_PASSWORDS=true || SSH_PASSWORDS=false
        else SSH_PASSWORDS=true; fi
    fi
    if $DO_HOST; then
        printf '\n%s  Hostname%s\n' "$C_B" "$C_0"
        while true; do
            ask NEW_HOSTNAME "New hostname" "$NEW_HOSTNAME"
            valid_hostname "$NEW_HOSTNAME" && break
            printf '   %sUse letters, digits and hyphens (dots between parts), e.g. web-01 or web-01.example.com%s\n' "$C_Y" "$C_0"
        done
    fi
    if $DO_NET; then
        printf '\n%s  IP address%s  (interfaces: %s)\n' "$C_B" "$C_0" "$(list_ifaces)"
        while true; do
            ask NET_IFACE "Interface" "${NET_IFACE:-$ci}"
            c="$(cur_addr "$NET_IFACE")"
            ask m "Static address or DHCP? (s/d)" "s"
            if [[ "${m,,}" == d* ]]; then NET_IP=dhcp
            else
                ask NET_IP "IP address (e.g. 192.168.1.50 or 192.168.1.50/24)" "${c%/*}"
                if [[ "$NET_IP" != */* ]]; then
                    dp="${c#*/}"; [[ "$c" == */* ]] || dp=24
                    ask NET_MASK "Subnet mask or prefix" "$(prefix2mask "$dp") = /$dp"
                    NET_MASK="${NET_MASK%% *}"
                fi
                g="$(cur_gw "$NET_IFACE")"
                ask NET_GW "Gateway" "$g"
            fi
            plan_network && break
            printf '   %s%s - try again%s\n' "$C_Y" "$PLAN_ERR" "$C_0"; NET_GW=""; NET_MASK=""
        done
    fi
    if $DO_DNS || { $DO_NET && [[ "$NET_MODE" == static && -z "$(cur_dns)" ]]; }; then
        DO_DNS=true
        printf '\n%s  DNS servers%s\n' "$C_B" "$C_0"
        while true; do
            ask NET_DNS "DNS servers, separated by spaces (e.g. 1.1.1.1 9.9.9.9)" "${NET_DNS:-$(cur_dns)}"
            plan_dns && break
            printf '   %s%s - try again%s\n' "$C_Y" "$PLAN_ERR" "$C_0"
        done
    fi
else
    if [[ -n "$NEW_USER" ]]; then
        DO_USER=true
        valid_username "$NEW_USER" || die "--add-user: '$NEW_USER' is not a valid username (lowercase letters, digits, - and _; not root)."
        if [[ -n "${DOTFILES_USER_PASSWORD:-}" ]]; then NEW_USER_PW="$DOTFILES_USER_PASSWORD"
        elif ! $OPT_DRY; then
            { $TTY_OK || { exec 3</dev/tty; } 2>/dev/null; } || die "--add-user needs a terminal to ask for the password (or set DOTFILES_USER_PASSWORD)."
            printf '\n%s  New user with sudo access: %s%s\n' "$C_B" "$NEW_USER" "$C_0"
            ask_password "$NEW_USER"
        fi
    fi
    [[ -n "$NEW_HOSTNAME" ]] && DO_HOST=true
    [[ -n "$NET_IP$NET_MASK$NET_GW" ]] && DO_NET=true
    [[ -n "$NET_DNS" ]] && DO_DNS=true
    if $DO_HOST && ! valid_hostname "$NEW_HOSTNAME"; then die "'$NEW_HOSTNAME' is not a valid hostname."; fi
    if [[ -n "$SSH_KEY" ]] && ! valid_key_arg "$SSH_KEY"; then die "--ssh-key: not a public key, a file or gh:<user>: $(short "$SSH_KEY" 40)"; fi
    if $DO_NET; then plan_network || die "--ip/--subnet/--gateway: $PLAN_ERR"; fi
    if $DO_DNS; then plan_dns || die "--dns: $PLAN_ERR"; fi
fi
# a static address keeps the current DNS servers unless new ones were chosen
if $DO_NET && [[ "$NET_MODE" == static ]] && ! $DO_DNS; then
    NET_DNS="$(cur_dns)"
    if [[ -n "$NET_DNS" ]]; then plan_dns || DNS_LIST=""
    else warn "No current DNS servers found - set them with --dns, or name lookups may stop working."; fi
fi
SYS_ANY=false; { $DO_USER || $DO_SSH || $DO_HOST || $DO_NET || $DO_DNS; } && SYS_ANY=true
$OPT_DOTFILES || $SYS_ANY || die "Nothing to do (--no-dotfiles without any system option)."

if $SYS_ANY; then
    step "Planned system changes$($OPT_DRY && echo " (dry run - nothing will be changed)")"
    $DO_USER && info "User:     $NEW_USER - $(id "$NEW_USER" >/dev/null 2>&1 && echo "exists, give sudo access + new password" || echo "create, sudo access, password set")"
    $DO_SSH  && info "SSH:      enable for non-root users, root login off, passwords: $($SSH_PASSWORDS && echo on || echo "off (keys only)")${SSH_KEY:+, add key: $(short "$SSH_KEY" 30)}"
    $DO_HOST && info "Hostname: $(hostname 2>/dev/null) → $NEW_HOSTNAME"
    $DO_NET  && info "Network:  $NET_IFACE → $([[ "$NET_MODE" == dhcp ]] && echo DHCP || echo "$NET_ADDR/$NET_PREFIX ($(prefix2mask "$NET_PREFIX")), gateway $NET_GW")"
    [[ -n "$DNS_LIST" ]] && info "DNS:      $DNS_LIST$($DO_DNS || echo "  (current servers, kept)")"
    $OPT_DOTFILES || info "Dotfiles: skipped"
    if $TTY_OK && ! $OPT_YES && ! $OPT_DRY; then
        yesno "Go ahead?" y || { echo "   Nothing changed."; exit 0; }
    fi
fi

if [[ $EUID -eq 0 ]]; then
    SUDO=()
else
    have sudo || die "sudo is required (or run this script as root)."
    # Pass our PATH through: sudo's secure_path (and sudo-rs defaults) point at
    # /usr/bin:/bin, which on NixOS holds no coreutils - `sudo install` would fail.
    # (sbin dirs appended: they are in secure_path but often not in a user's PATH)
    SUDO=(sudo "$(command -v env)" "PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin")
    step "Requesting sudo (needed for package installs, /usr/local/bin and system settings)"
    sudo -v || die "Could not obtain sudo privileges."
    # keep sudo alive while we work
    ( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
    SUDO_KEEPALIVE=$!
    trap 'kill "${SUDO_KEEPALIVE:-}" 2>/dev/null' EXIT
fi


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
        p="$(candidates "$t" | awk '{print $1}')"
        # shellcheck disable=SC2206  # a+b -> two packages
        [[ -n "$p" ]] && miss+=(${p//+/ })
    done
    [[ ${#miss[@]} -gt 0 ]] || return 0
    info "Installing via $(nix_mode_label): ${miss[*]}"
    info "(first run downloads from the Nix binary cache - this can take a few minutes)"
    pm_install "${miss[@]}" || info "Batch install failed - retrying one package at a time..."
}

# ---------------------------------------------------------------- the package list
# packages/package_list.txt (see its header): one line per package, with the
# package names per package manager where they differ. Parsed into:
declare -A PKG_MAP=()      # "name|pm" -> "a,b+c"
declare -A PKG_CMD=()      # name -> "cmd1,cmd2"  ("-" = none)
declare -A PKG_PATH=()     # name -> "file1,file2"
declare -A PKG_SEC=()      # section -> "name name ..."

load_package_list() {  # load_package_list <file> ; 1 if unreadable
    local f="$1" line sec=tools name tok k v n=0
    local -a toks
    [[ -r "$f" && -s "$f" ]] || return 1
    PKG_MAP=(); PKG_CMD=(); PKG_PATH=(); PKG_SEC=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"; line="${line//$'\r'/}"
        read -ra toks <<<"$line"
        [[ ${#toks[@]} -eq 0 ]] && continue
        if [[ "${toks[0]}" =~ ^\[([A-Za-z0-9_-]+)\]$ ]]; then sec="${BASH_REMATCH[1]}"; continue; fi
        name="${toks[0]}"
        if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
            warn "package_list: '$name' is not a valid package name - line skipped"; continue
        fi
        [[ " ${PKG_SEC[$sec]:-} " == *" $name "* ]] || PKG_SEC[$sec]+="$name "
        n=$((n + 1))
        for tok in "${toks[@]:1}"; do
            k="${tok%%=*}"; v="${tok#*=}"
            if [[ "$tok" != *=* || -z "$v" ]]; then warn "package_list: '$tok' (for $name) is not key=value - ignored"; continue; fi
            case "$k" in
                cmd)  PKG_CMD[$name]="$v" ;;
                path) PKG_PATH[$name]="$v" ;;
                apt|dnf|yum|pacman|zypper|apk|nix) PKG_MAP[$name|$k]="$v" ;;
                *) warn "package_list: unknown key '$k' (for $name) - ignored" ;;
            esac
        done
    done < "$f"
    PKG_COUNT=$n
}

pkg_section() {  # the names in one or more sections, in file order
    local s; for s in "$@"; do printf '%s' "${PKG_SEC[$s]:-}"; done
}

# Package candidates for this package manager, space separated; "a+b" means
# install together. Prints nothing when the list says "-" (skip here).
candidates() {
    local t="$1" v
    v="${PKG_MAP[$t|$PM]:-}"
    [[ -z "$v" && "$PM" == yum ]] && v="${PKG_MAP[$t|dnf]:-}"
    [[ -z "$v" ]] && v="$t"
    [[ "$v" == "-" ]] && return 0
    printf '%s\n' "${v//,/ }"
}

# is the package installed? (asks the package manager)
pm_has() {
    case "$PM" in
        apt)            dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed' ;;
        dnf|yum|zypper) rpm -q --whatprovides "$1" >/dev/null 2>&1 ;;
        pacman)         pacman -Q "$1" >/dev/null 2>&1 ;;
        apk)            apk info -e "$1" >/dev/null 2>&1 ;;
        *)              return 1 ;;
    esac
}

# explicit check given in the list (cmd= or path=)?
has_check() { [[ -n "${PKG_PATH[$1]:-}" || ( -n "${PKG_CMD[$1]:-}" && "${PKG_CMD[$1]}" != "-" ) ]]; }

tool_present() {
    local t="$1" x first
    if has_check "$t"; then
        local pp="${PKG_PATH[$t]:-}" pc="${PKG_CMD[$t]:-}"
        for x in ${pp//,/ }; do [[ -e "$x" ]] && return 0; done
        [[ "${PKG_CMD[$t]:--}" == "-" ]] && return 1
        for x in ${pc//,/ }; do have "$x" && return 0; done
        return 1
    fi
    [[ "${PKG_CMD[$t]:-}" != "-" ]] && have "$t" && return 0
    # no command of that name: is the (first) package installed?
    first="$(candidates "$t" | awk '{print $1}')"
    [[ -n "$first" ]] || return 1
    for x in ${first//+/ }; do pm_has "$x" || return 1; done
}

# install the first candidate that works; no checks (locales, sudo, sshd...)
# 0 = installed, 1 = failed, 2 = the list says not needed on this system
pkg_install_entry() {
    local c cands
    cands="$(candidates "$1")"
    [[ -n "$cands" ]] || return 2
    # shellcheck disable=SC2086  # a+b -> two packages
    for c in $cands; do pm_install ${c//+/ } && return 0; done
    return 1
}

ensure_tool() {  # ensure_tool <name from the list>
    local tool="$1" pkg cands
    if tool_present "$tool"; then ok "$tool (already installed)"; return 0; fi
    cands="$(candidates "$tool")"
    if [[ -z "$cands" ]]; then ok "$tool (not needed with $PM)"; return 0; fi
    pm_refresh
    for pkg in $cands; do
        # shellcheck disable=SC2086
        pm_install ${pkg//+/ } || continue
        if tool_present "$tool"; then ok "$tool (via $PM: ${pkg//+/ + })"; return 0; fi
        if ! has_check "$tool"; then   # installed, but no command named like it
            ok "$tool (via $PM: ${pkg//+/ + }; no '$tool' command - add cmd= in package_list.txt to check it)"
            return 0
        fi
    done
    # tool-specific fallbacks
    if declare -F "fallback_$tool" >/dev/null && "fallback_$tool" && tool_present "$tool"; then
        return 0
    fi
    warn "Could not install '$tool' with $PM (tried: ${cands// /, }) - skipped. Fix its line in package_list.txt if the name differs here."
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
#  0b. Load the package list (needed before anything is installed)
# =============================================================================
SELF="${BASH_SOURCE[0]:-}"
SELF_DIR=""
[[ -n "$SELF" && -f "$SELF" ]] && SELF_DIR="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)"

# Only used when no list can be read or downloaded (no curl/wget yet): just
# enough to get a downloader, then the real list is fetched.
BOOTSTRAP_LIST='[prerequisites]
certs path=/etc/ssl/certs/ca-certificates.crt,/etc/pki/tls/certs/ca-bundle.crt,/etc/ssl/certs apt=ca-certificates dnf=ca-certificates pacman=ca-certificates zypper=ca-certificates apk=ca-certificates nix=cacert
curl'

# get_package_list <dest> : --package-list, else this checkout, else download
get_package_list() {
    local src="$OPT_PKG_LIST"
    if [[ -n "$src" ]]; then
        if [[ "$src" =~ ^https?:// ]]; then fetch "$src" "$1" && { PKG_LIST_SRC="$src"; return 0; }
            die "Could not download the package list $src"
        fi
        [[ "$src" == /* ]] || src="$PWD/$src"
        [[ -r "$src" ]] || die "Package list not found: $OPT_PKG_LIST"
        cp "$src" "$1" && PKG_LIST_SRC="$src" && return 0
    fi
    if [[ -n "$SELF_DIR" && -r "$SELF_DIR/$PKG_LIST_REL" ]]; then
        cp "$SELF_DIR/$PKG_LIST_REL" "$1" && PKG_LIST_SRC="$SELF_DIR/$PKG_LIST_REL" && return 0
    fi
    if { have curl || have wget; } && fetch "$RAW_BASE/$PKG_LIST_REL" "$1"; then
        PKG_LIST_SRC="$RAW_BASE/$PKG_LIST_REL"; return 0
    fi
    return 1
}

PKG_LIST_SRC=""
if ! get_package_list "$WORKDIR/package_list.txt" || ! load_package_list "$WORKDIR/package_list.txt"; then
    if $OPT_PACKAGES && [[ "$PM" != none ]] && ! have curl && ! have wget; then
        info "No curl or wget yet - installing curl first to download the package list"
        printf '%s\n' "$BOOTSTRAP_LIST" > "$WORKDIR/bootstrap.txt"
        load_package_list "$WORKDIR/bootstrap.txt"
        for t in certs curl; do ensure_tool "$t" || true; done
    fi
    if get_package_list "$WORKDIR/package_list.txt" && load_package_list "$WORKDIR/package_list.txt"; then :
    elif $OPT_PACKAGES && $OPT_DOTFILES; then
        warn "Could not read the package list ($PKG_LIST_REL) - only the prerequisites curl/certs are handled; packages from the list are skipped."
        printf '%s\n' "$BOOTSTRAP_LIST" > "$WORKDIR/bootstrap.txt"; load_package_list "$WORKDIR/bootstrap.txt"
    fi
fi
[[ -n "$PKG_LIST_SRC" ]] && info "Package list: $PKG_LIST_SRC (${PKG_COUNT:-0} packages)"

# =============================================================================
#  1. Prerequisites
# =============================================================================
if $OPT_DOTFILES && $OPT_PACKAGES; then
    [[ "$PM" == "none" ]] && warn "No supported package manager found - skipping package installs."
    if [[ "$PM" != "none" ]]; then
        step "Installing prerequisites"
        enable_epel
        read -ra PREREQS <<<"$(pkg_section prerequisites)"
        nix_batch "${PREREQS[@]}"
        for t in "${PREREQS[@]}"; do ensure_tool "$t" || true; done
    fi
fi

# =============================================================================
#  2. Get the repo files (local checkout, or clone/update ~/.dotfiles-nixish)
# =============================================================================
step "Fetching dotfiles-nixish"

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
        mkdir -p "$SRC_DIR/scripts" "$SRC_DIR/config"
        DL=(install.sh scripts/xtree.sh scripts/system-setup.sh config/bashrc_append.sh config/zshrc_append.sh)
        # only fetch the files this OS needs (see "Trimming" below)
        if $IS_NIXOS || $OPT_KEEP_ALL; then DL+=(flake.nix flake.lock default.nix nix/module.nix nix/packages.nix nix/xtree.nix); fi
        DL+=("$PKG_LIST_REL")   # used on every OS
        for f in "${DL[@]}"; do
            mkdir -p "$SRC_DIR/$(dirname "$f")"
            fetch "$RAW_BASE/$f" "$SRC_DIR/$f" || die "Failed to download $f from $RAW_BASE"
        done
        chmod +x "$SRC_DIR/install.sh" "$SRC_DIR/scripts/xtree.sh"
        [[ $EUID -eq 0 && "$TARGET_USER" != "root" ]] && chown -R "$TARGET_USER:$TARGET_GROUP" "$SRC_DIR"
        ok "Downloaded into $SRC_DIR"
        DIRECT_DL=true
    fi
fi
[[ -f "$SRC_DIR/scripts/xtree.sh" ]] || die "scripts/xtree.sh missing in $SRC_DIR"

# =============================================================================
#  2b. Keep only the repo files this OS needs
# =============================================================================
# NixOS-only : flake.nix flake.lock default.nix nix/   (declarative Nix install)
#              -> removed on every other OS
# packages/package_list.txt is used on EVERY OS (NixOS too), so it always stays.
# Git checkouts are trimmed with sparse-checkout: the files leave the working
# tree, `git status` stays clean, `git pull` keeps working and --keep-all
# brings everything back. Plain (non-git) copies just have the files deleted.
NIX_ONLY=(flake.nix flake.lock default.nix nix)
NON_NIX_ONLY=()   # nothing: NixOS uses every file (older versions hid packages/)
if $IS_NIXOS; then UNNEEDED=(${NON_NIX_ONLY[@]+"${NON_NIX_ONLY[@]}"}); OS_KIND="NixOS"; KIND="non-NixOS"
else UNNEEDED=("${NIX_ONLY[@]}"); OS_KIND="$OS_NAME"; KIND="NixOS-only"; fi
SPARSE_TAG="# dotfiles-nixish: sparse-checkout managed by install.sh"
TRIM_NOTE=""       # one-line result, repeated in the Summary

what_is() {  # what each OS-specific path is for
    case "$1" in
        flake.nix)   echo "Nix flake (NixOS module + packages)" ;;
        flake.lock)  echo "version pins for the flake" ;;
        default.nix) echo "Nix entry point without flakes" ;;
        nix)         echo "NixOS module and Nix package definitions" ;;
        packages)    echo "the package list (used on every OS)" ;;
        *)           echo "" ;;
    esac
}
plural() { (( $1 == 1 )) && printf '%d %s' "$1" "$2" || printf '%d %ss' "$1" "$2"; }

# print the list of paths about to be removed; sets TRIM_FILES (file count)
list_unneeded() {  # list_unneeded git|plain <path>...
    local mode="$1" p n name; shift
    TRIM_FILES=0
    sub "Removing ${KIND} files - they are unnecessary on ${OS_KIND}:"
    for p in "$@"; do
        if [[ "$mode" == git ]]; then n=$(as_target git -C "$SRC_DIR" ls-files -- "$p" | wc -l)
        else n=$(find "$SRC_DIR/$p" -type f 2>/dev/null | wc -l); fi
        TRIM_FILES=$(( TRIM_FILES + n ))
        name="$p"; [[ -d "$SRC_DIR/$p" || "$n" -gt 1 ]] && name="$p/ ($(plural "$n" file))"
        printf '       %s-%s %-20s %s%s%s\n' "$C_Y" "$C_0" "$name" "$C_C" "$(what_is "$p")" "$C_0"
    done
}

# final status line for a completed removal
report_trim() {  # report_trim <how>
    TRIM_NOTE="$(plural "$TRIM_FILES" "${KIND} file") removed as unnecessary on ${OS_KIND}"
    ok "${TRIM_NOTE}"
    sub "$1"
}

trim_git() {
    local spf cur top=() p pats dirty
    spf="$(as_target git -C "$SRC_DIR" rev-parse --git-path info/sparse-checkout 2>/dev/null)" || return 1
    [[ "$spf" == /* ]] || spf="$SRC_DIR/$spf"
    cur="$(as_target git -C "$SRC_DIR" config --bool core.sparseCheckout 2>/dev/null || echo false)"
    if [[ "$cur" == "true" ]] && ! grep -qxF "$SPARSE_TAG" "$spf" 2>/dev/null; then
        info "$SRC_DIR already uses your own sparse-checkout setup - not touching it."
        return 0
    fi
    if $OPT_KEEP_ALL; then
        if [[ "$cur" == "true" ]]; then
            sub "--keep-all: restoring every file in $(disp "$SRC_DIR")"
            printf '%s\n/*\n' "$SPARSE_TAG" | as_target tee "$spf" >/dev/null
            as_target git -C "$SRC_DIR" read-tree -mu HEAD \
                && as_target git -C "$SRC_DIR" config core.sparseCheckout false \
                && as_target rm -f "$spf" && ok "All repo files restored"
        else
            ok "--keep-all: keeping every repo file"
        fi
        return 0
    fi
    if [[ ${#UNNEEDED[@]} -eq 0 ]]; then
        if [[ "$cur" == "true" ]]; then   # an older install.sh hid files that are needed now
            sub "Files hidden by an older install.sh are needed now (packages/ is used on ${OS_KIND} too) - restoring them"
            printf '%s\n/*\n' "$SPARSE_TAG" | as_target tee "$spf" >/dev/null
            if as_target git -C "$SRC_DIR" read-tree -mu HEAD \
                && as_target git -C "$SRC_DIR" config core.sparseCheckout false \
                && as_target rm -f "$spf"; then ok "All repo files restored - every file is used on ${OS_KIND}"
            else warn "Could not restore the hidden files in $(disp "$SRC_DIR") - run: git -C $SRC_DIR sparse-checkout disable"; fi
        else
            ok "Nothing to remove - every repo file is used on ${OS_KIND}"
        fi
        return 0
    fi
    # only consider paths the repo actually tracks
    for p in "${UNNEEDED[@]}"; do
        [[ -n "$(as_target git -C "$SRC_DIR" ls-files -- "$p" 2>/dev/null)" ]] && top+=("$p")
    done
    if [[ ${#top[@]} -eq 0 ]]; then ok "No ${KIND} files in this copy - nothing unnecessary to remove"; return 0; fi
    local present=false
    for p in "${top[@]}"; do [[ -e "$SRC_DIR/$p" ]] && present=true; done
    if [[ "$cur" == "true" ]] && ! $present; then
        as_target git -C "$SRC_DIR" read-tree -mu HEAD 2>/dev/null   # re-apply after a pull, just in case
        TRIM_NOTE="${KIND} files (${top[*]}) are not on disk - unnecessary on ${OS_KIND}"
        ok "${KIND} files already removed - unnecessary on ${OS_KIND}"
        local shown=()
        for p in "${top[@]}"; do case "$p" in nix|packages) shown+=("$p/") ;; *) shown+=("$p") ;; esac; done
        sub "Not on disk: ${shown[*]}"
        return 0
    fi
    dirty="$(as_target git -C "$SRC_DIR" status --porcelain -- "${top[@]}" 2>/dev/null)"
    if [[ -n "$dirty" ]]; then
        warn "Not trimming $(disp "$SRC_DIR"): you have local changes in files it would remove:"
        printf '%s\n' "$dirty" | sed 's/^/        /'
        return 0
    fi
    list_unneeded git "${top[@]}"
    pats="$SPARSE_TAG"$'\n'"# hidden on $OS_KIND (re-run install.sh --keep-all to restore)"$'\n/*'
    for p in "${top[@]}"; do
        if [[ -d "$SRC_DIR/$p" ]] || as_target git -C "$SRC_DIR" ls-files -- "$p/" | grep -q .; then pats+=$'\n'"!/$p/"
        else pats+=$'\n'"!/$p"; fi
    done
    as_target mkdir -p "$(dirname "$spf")"
    if ! printf '%s\n' "$pats" | as_target tee "$spf" >/dev/null \
       || ! as_target git -C "$SRC_DIR" config core.sparseCheckoutCone false \
       || ! as_target git -C "$SRC_DIR" config core.sparseCheckout true \
       || ! as_target git -C "$SRC_DIR" read-tree -mu HEAD; then
        warn "git sparse-checkout failed in $(disp "$SRC_DIR") - all files kept."
        as_target git -C "$SRC_DIR" config core.sparseCheckout false 2>/dev/null
        return 0
    fi
    for p in "${top[@]}"; do
        [[ -e "$SRC_DIR/$p" ]] && { warn "$p is still present after sparse-checkout - left as-is."; return 0; }
    done
    report_trim "Hidden with git sparse-checkout: git status stays clean; --keep-all brings them back"
}

trim_plain() {
    local p found=()
    if $OPT_KEEP_ALL; then ok "--keep-all: keeping every repo file"; return 0; fi
    if [[ ${#UNNEEDED[@]} -eq 0 ]]; then ok "Nothing to remove - every repo file is used on ${OS_KIND}"; return 0; fi
    for p in "${UNNEEDED[@]}"; do [[ -e "$SRC_DIR/$p" ]] && found+=("$p"); done
    if [[ ${#found[@]} -eq 0 ]]; then
        if $DIRECT_DL; then
            TRIM_NOTE="${KIND} files were never downloaded - unnecessary on ${OS_KIND}"
            ok "${KIND} files were not downloaded - they are unnecessary on ${OS_KIND}"
        else
            ok "No ${KIND} files in this folder - nothing unnecessary to remove"
        fi
        return 0
    fi
    list_unneeded plain "${found[@]}"
    for p in "${found[@]}"; do rm -rf "${SRC_DIR:?}/$p"; done
    report_trim "Deleted from this folder; they are still on GitHub if you ever need them"
}

step "Keeping only the repo files needed on ${OS_NAME}"
sub "Detected $($IS_NIXOS && echo "NixOS - every repo file is used here" || echo "$OS_NAME (not NixOS) - the NixOS/Nix files are not needed")"
if [[ -e "$SRC_DIR/.git" ]] && ! have git; then
    info "$(disp "$SRC_DIR") is a git checkout but git is not installed - leaving its files alone."
elif have git && [[ -d "$SRC_DIR/.git" || -f "$SRC_DIR/.git" ]] \
   && [[ "$(as_target git -C "$SRC_DIR" rev-parse --show-toplevel 2>/dev/null)" == "$(cd "$SRC_DIR" && pwd -P)" ]]; then
    trim_git
elif have git && as_target git -C "$SRC_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    info "$(disp "$SRC_DIR") is inside another git repository - leaving its files alone."
else
    trim_plain
fi

TOOLS=()
ZSH_DONE=false
XTREE_BIN_OK=false
if $OPT_DOTFILES; then
# =============================================================================
#  3. Packages
# =============================================================================
# A user-edited list in the checkout wins over the one downloaded at the
# start (unless --package-list was given)
if [[ -z "$OPT_PKG_LIST" && -r "$SRC_DIR/$PKG_LIST_REL" ]] \
   && ! cmp -s "$SRC_DIR/$PKG_LIST_REL" "$WORKDIR/package_list.txt"; then
    cp "$SRC_DIR/$PKG_LIST_REL" "$WORKDIR/package_list.txt" \
        && load_package_list "$WORKDIR/package_list.txt" \
        && PKG_LIST_SRC="$SRC_DIR/$PKG_LIST_REL" \
        && { ! $OPT_PACKAGES || info "Using the package list in $(disp "$PKG_LIST_SRC") (${PKG_COUNT:-0} packages)"; }
fi
read -ra TOOLS <<<"$(pkg_section tools)"
if $OPT_ZSH; then read -ra ZT <<<"$(pkg_section zsh)"; TOOLS+=("${ZT[@]}"); fi
[[ ${#TOOLS[@]} -eq 0 ]] && info "The package list has no [tools] entries - no tools to install."

if $OPT_PACKAGES && [[ "$PM" != "none" ]]; then
    step "Installing packages"
    if [[ ${#TOOLS[@]} -gt 0 ]]; then
        nix_batch "${TOOLS[@]}"
        for t in "${TOOLS[@]}"; do ensure_tool "$t" || true; done
    fi

    # The fortune binary can exist without any quote database ("No fortunes found"):
    # apt's --no-install-recommends skips 'fortunes-min'/'fortunes'. Verify and fix.
    if [[ " ${TOOLS[*]} " == *" fortune "* ]] && have fortune && ! fortune >/dev/null 2>&1; then
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
    if [[ " ${TOOLS[*]} " == *" tldr "* ]] && have tldr; then
        if as_target timeout 90 tldr --update >/dev/null 2>&1; then ok "tldr page cache updated"
        else info "(tldr cache update skipped - run 'tldr --update' later if needed)"; fi
    fi
fi

# =============================================================================
#  4. Locale: en_US.UTF-8 (generated if missing, then made the system default)
# =============================================================================
has_en_us() { locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; }
if $OPT_PACKAGES && ! has_en_us && [[ "$PM" != apk ]]; then
    step "Generating the en_US.UTF-8 locale"
    pkg_install_entry locales; LOC_RC=$?   # 2 = the list says nothing to install here
    case "$PM" in
        apt)    "${SUDO[@]}" sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen 2>/dev/null
                grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen 2>/dev/null \
                    || echo 'en_US.UTF-8 UTF-8' | "${SUDO[@]}" tee -a /etc/locale.gen >/dev/null
                "${SUDO[@]}" locale-gen >/dev/null 2>&1 ;;
        pacman) "${SUDO[@]}" sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen && "${SUDO[@]}" locale-gen >/dev/null 2>&1 ;;
        nix)    info "NixOS locales are declarative - add to /etc/nixos/configuration.nix:"
                info '  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];  # then: sudo nixos-rebuild switch' ;;
    esac
    [[ $LOC_RC -eq 1 ]] && info "(could not install the [locale] package(s): $(candidates locales))"
    if has_en_us; then ok "en_US.UTF-8 available"
    else warn "en_US.UTF-8 locale not available - the shell keeps the current locale."; fi
fi

# The system default (LANG) - cloud/VM images ship C.UTF-8. Written where the
# distro reads it at login: /etc/default/locale (Debian/Ubuntu),
# /etc/locale.conf (Fedora/RHEL, Arch, openSUSE), /etc/profile.d (Alpine:
# musl has no locale database, any name works). NixOS: i18n.defaultLocale,
# which is en_US.UTF-8 unless you changed it - left to your configuration.
LOC_FILE=""
case "$PM" in
    apt) LOC_FILE=/etc/default/locale ;;
    apk) LOC_FILE=/etc/profile.d/00-dotfiles-nixish-locale.sh ;;
    nix) ;;
    *)   LOC_FILE=/etc/locale.conf ;;
esac
if [[ -n "$LOC_FILE" ]] && { [[ "$PM" == apk ]] || has_en_us; }; then
    if grep -qsE '^(export[[:space:]]+)?LANG="?en_US\.UTF-8"?[[:space:]]*$' "$LOC_FILE" && ! grep -qsE '^(export[[:space:]]+)?LC_ALL=' "$LOC_FILE"; then
        ok "System locale is already en_US.UTF-8 ($LOC_FILE)"
    elif $OPT_DRY; then
        info "[dry-run] would set the system locale to LANG=en_US.UTF-8 in $LOC_FILE"
    else
        step "Setting the system locale to en_US.UTF-8"
        [[ -f "$LOC_FILE" ]] && "${SUDO[@]}" cp -p "$LOC_FILE" "$LOC_FILE.dotfiles-nixish.bak.$TS"
        if [[ "$PM" == apk ]]; then
            # /etc/profile sets LANG=C.UTF-8 first, then sources profile.d
            printf '# Managed by dotfiles-nixish (install.sh)\nexport LANG=en_US.UTF-8\n' | "${SUDO[@]}" tee "$LOC_FILE" >/dev/null
        elif [[ "$PM" == apt ]] && have update-locale; then
            "${SUDO[@]}" update-locale LANG=en_US.UTF-8 >/dev/null 2>&1 \
                || { printf 'LANG=en_US.UTF-8\n' | "${SUDO[@]}" tee "$LOC_FILE" >/dev/null; }
        else
            # keep other LC_* lines, replace LANG; LC_ALL would override everything
            { grep -vsE '^(export[[:space:]]+)?(LANG|LC_ALL)=' "$LOC_FILE"; echo 'LANG=en_US.UTF-8'; } > "$WORKDIR/locale.conf" 2>/dev/null \
                || echo 'LANG=en_US.UTF-8' > "$WORKDIR/locale.conf"
            "${SUDO[@]}" tee "$LOC_FILE" < "$WORKDIR/locale.conf" >/dev/null
        fi
        # tell systemd-localed too, so localectl shows it (no-op in containers without it)
        [[ "$PM" != apk ]] && have localectl && "${SUDO[@]}" localectl set-locale LANG=en_US.UTF-8 >/dev/null 2>&1
        if grep -qsE '^(export[[:space:]]+)?LANG="?en_US\.UTF-8"?' "$LOC_FILE"; then
            ok "System locale: LANG=en_US.UTF-8 ($LOC_FILE) - applies to new logins"
        else
            warn "Could not set LANG=en_US.UTF-8 in $LOC_FILE"
        fi
    fi
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
# regex that matches any definition of the same setting as rc line $1
setting_re() {
    local l k; l="$(ltrim "$1")"
    case "$l" in
        alias[[:space:]]*)
            k="$(ltrim "${l#alias}")"; k="${k%%=*}"
            printf '^[[:space:]]*alias[[:space:]]+%s=' "$k" ;;
        shopt[[:space:]]*|setopt[[:space:]]*)
            k="$(awk '{print $NF}' <<<"${l%%#*}")"
            printf '^[[:space:]]*(shopt[[:space:]]+-[su]|setopt)[[:space:]]+%s([[:space:]]|$)' "$k" ;;
        *)
            [[ "$l" == export[[:space:]]* ]] && l="$(ltrim "${l#export}")"
            k="${l%%=*}"
            printf '^[[:space:]]*(export[[:space:]]+)?%s=' "$k" ;;
    esac
}

# describe what the managed block sets for the same setting as rc line $1
block_value() {
    local line snippet="$2" re; local -a defs
    line="$(ltrim "$1")"; re="$(setting_re "$line")"
    mapfile -t defs < <(grep -E "$re" "$snippet" | sed -E 's/^[[:space:]]*//; s/[[:space:]]+#[[:space:]].*$//' | awk '!seen[$0]++')
    if (( ${#defs[@]} == 0 )); then printf 'set in the block'
    elif (( ${#defs[@]} == 1 )) && [[ "${defs[0]}" == "$line" ]]; then printf 'identical line is in the block'
    else
        printf 'block: %s' "$(short "${defs[0]}")"
        (( ${#defs[@]} > 1 )) && printf ' (+%d fallback%s)' $(( ${#defs[@]} - 1 )) "$( (( ${#defs[@]} > 2 )) && echo s)"
    fi
    return 0
}

dedupe_rc() {  # dedupe_rc <rcfile> <snippet> <file-to-filter-in-place>
    local rc="$1" snippet="$2" f="$3" vars aliases opts kvars pat ipat kpat shell_chk
    local hits indented kept ln line why n
    DEDUP_COUNT=0
    # PATH is built up incrementally and HISTFILE's default must not clobber a user value
    vars=$(grep -oE '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' "$snippet" \
           | sed -E 's/^[[:space:]]*(export[[:space:]]+)?//; s/=$//' | sort -u)
    # the block always extends PATH (inside case/&& lines the scan above can't see)
    kvars=$(printf 'PATH\n%s\n' "$(grep -xE 'HISTFILE' <<<"$vars")" | grep . | paste -sd'|' -)
    vars=$(grep -vxE 'PATH|HISTFILE' <<<"$vars" | paste -sd'|' -)
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
    ipat="^[[:space:]]+${pat#^}"                                   # same, but indented
    kpat=""; [[ -n "$kvars" ]] && kpat="^[[:space:]]*(export[[:space:]]+)?($kvars)="

    sub "Scanning $(disp "$rc") for older options that the dotfiles-nixish block sets again..."
    # matches OUTSIDE our block, reported with their line numbers in the real file
    outside() { awk -v b="$MARK_BEGIN" -v e="$MARK_END" -v p="$1" \
        '$0==b{s=1;next} $0==e{s=0;next} !s && $0 ~ p && $0 !~ /\\$/ {print NR "\t" $0}' "$rc"; }
    hits=$(outside "$pat"); indented=$(outside "$ipat"); kept=""; [[ -n "$kpat" ]] && kept=$(outside "$kpat")

    if [[ -z "$hits" ]]; then
        sub "No older duplicate options found"
    else
        n=$(grep -c '' <<<"$hits")
        sub "Found $n older duplicate option(s) (each setting should exist only once):"
        while IFS=$'\t' read -r ln line; do
            printf '       %s-%s line %-4s %-34s %s→ %s%s\n' "$C_Y" "$C_0" "$ln:" "$(short "$line" 34)" "$C_C" "$(block_value "$line" "$snippet")" "$C_0"
        done <<<"$hits"
    fi
    if [[ -n "$indented" ]]; then
        while IFS=$'\t' read -r ln line; do
            printf '       %s·%s line %-4s %-34s %s(left alone: inside an if/case block)%s\n' "$C_C" "$C_0" "$ln:" "$(short "$(ltrim "$line")" 34)" "$C_C" "$C_0"
        done <<<"$indented"
    fi
    if [[ -n "$kept" ]]; then
        while IFS=$'\t' read -r ln line; do
            case "$(ltrim "$line")" in
                *HISTFILE=*) why="kept: the block uses your HISTFILE" ;;
                *)           why="kept: the block only adds to PATH" ;;
            esac
            printf '       %s=%s line %-4s %-34s %s(%s)%s\n' "$C_G" "$C_0" "$ln:" "$(short "$(ltrim "$line")" 34)" "$C_C" "$why" "$C_0"
        done <<<"$kept"
    fi
    if [[ -n "$hits" ]]; then
        awk -v p="$pat" '$0 ~ p && $0 !~ /\\$/ {next} {print}' "$f" > "$f.dd"
        case "$rc" in *zshrc*) shell_chk=zsh ;; *) shell_chk=bash ;; esac
        if have "$shell_chk" && ! "$shell_chk" -n "$f.dd" 2>/dev/null; then
            rm -f "$f.dd"
            warn "$(disp "$rc"): removing those lines would break the file's syntax ($shell_chk -n) - kept them all."
        else
            mv "$f.dd" "$f"; DEDUP_COUNT=$n
            if have "$shell_chk"; then sub "Removed $n duplicate line(s); syntax check ($shell_chk -n) passed"
            else sub "Removed $n duplicate line(s)"; fi
        fi
    fi
    return 0
}

install_block() {  # install_block <rcfile> <snippet>
    local rc="$1" snippet="$2" tmp nb ne d bak
    d="$(disp "$rc")"
    printf '\n   %s%s%s\n' "$C_B" "$d" "$C_0"
    [[ -f "$snippet" ]] || { warn "Snippet $snippet missing"; return 1; }
    if [[ ! -e "$rc" ]]; then
        sub "$d does not exist yet - creating it"
        touch "$rc" && fix_owner "$rc"
    else
        sub "Reading $d ($(grep -c '' "$rc") lines)"
    fi
    nb=$(grep -cxF "$MARK_BEGIN" "$rc" || true); ne=$(grep -cxF "$MARK_END" "$rc" || true)
    if [[ "$nb" != "$ne" ]]; then
        warn "$d has unbalanced dotfiles-nixish markers - fix it manually; not modified."
        return 1
    fi
    if [[ "$nb" -gt 0 ]]; then sub "Found the existing dotfiles-nixish block - it will be refreshed in place"
    else sub "No dotfiles-nixish block yet - it will be added at the end"; fi
    tmp="$WORKDIR/rc.$$"
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
        $0==b {skip=1; next}  $0==e {skip=0; next}  !skip {print}' "$rc" > "$tmp.base"
    dedupe_rc "$rc" "$snippet" "$tmp.base"
    # drop trailing blank lines left behind by a previous block
    sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp.base" > "$tmp"
    { [[ -s "$tmp" ]] && echo; cat "$snippet"; } >> "$tmp"
    if cmp -s "$tmp" "$rc"; then
        ok "$d already up to date - no changes written"
    else
        if [[ -s "$rc" ]]; then
            bak="$rc.dotfiles-nixish.bak.$TS"
            cp -p "$rc" "$bak" && fix_owner "$bak" && sub "Backup of the original saved: $(disp "$bak")"
        fi
        sub "Writing dotfiles-nixish block ($(grep -c '' "$snippet") lines) to $d"
        cat "$tmp" > "$rc"   # keep inode/permissions
        ok "$d $([[ "$nb" -gt 0 ]] && echo updated || echo configured)$( (( DEDUP_COUNT > 0 )) && echo " - $DEDUP_COUNT duplicate option(s) removed")"
    fi
}

step "Editing shell dotfiles"
install_block "$TARGET_HOME/.bashrc" "$SRC_DIR/config/bashrc_append.sh"

# Login shells (console, SSH) read only the FIRST of ~/.bash_profile,
# ~/.bash_login, ~/.profile - never ~/.bashrc. Ubuntu's skel ~/.profile sources
# ~/.bashrc, but NixOS (no /etc/skel) and minimal installs start with an empty
# home, so without this the whole block is ignored in login shells.
LOGIN_RC=""
for f in .bash_profile .bash_login .profile; do
    [[ -f "$TARGET_HOME/$f" ]] && { LOGIN_RC="$TARGET_HOME/$f"; break; }
done
printf '\n   %sLogin shell file%s\n' "$C_B" "$C_0"
sub "Checking that console/SSH logins load ~/.bashrc..."
if [[ -z "$LOGIN_RC" ]]; then
    LOGIN_RC="$TARGET_HOME/.bash_profile"
    sub "No ~/.bash_profile, ~/.bash_login or ~/.profile found - creating $(disp "$LOGIN_RC")"
    # shellcheck disable=SC2016
    printf '# Created by dotfiles-nixish: login shells (console/SSH) should load ~/.bashrc\n[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' > "$LOGIN_RC"
    fix_owner "$LOGIN_RC"
    ok "$(disp "$LOGIN_RC") created (login shells now load ~/.bashrc)"
elif ! grep -qE '(\.|source)[[:space:]]+.*\.bashrc' "$LOGIN_RC"; then
    sub "$(disp "$LOGIN_RC") does not load ~/.bashrc - appending 2 lines"
    cp -p "$LOGIN_RC" "$LOGIN_RC.dotfiles-nixish.bak.$TS" && fix_owner "$LOGIN_RC.dotfiles-nixish.bak.$TS" \
        && sub "Backup of the original saved: $(disp "$LOGIN_RC.dotfiles-nixish.bak.$TS")"
    # ~/.profile is also read by sh/dash/ash, so only source bashrc from bash
    # shellcheck disable=SC2016
    printf '\n# dotfiles-nixish: load ~/.bashrc in bash login shells\nif [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi\n' >> "$LOGIN_RC"
    fix_owner "$LOGIN_RC"
    ok "$(disp "$LOGIN_RC") now loads ~/.bashrc"
else
    ok "$(disp "$LOGIN_RC") already loads ~/.bashrc - no changes written"
fi

if have zsh; then
    install_block "$TARGET_HOME/.zshrc" "$SRC_DIR/config/zshrc_append.sh" && ZSH_DONE=true
else
    printf '\n'; info "zsh not installed - skipping ~/.zshrc (re-run with --zsh to install it)."
fi

XTREE_BIN_OK=true
fi   # OPT_DOTFILES

# =============================================================================
#  6b. System settings: SSH, hostname, IP address/subnet/gateway, DNS
# =============================================================================
SYS_NOTES=()
if $SYS_ANY; then
    if [[ -f "$SRC_DIR/scripts/system-setup.sh" ]]; then
        # shellcheck source=scripts/system-setup.sh
        . "$SRC_DIR/scripts/system-setup.sh"
        system_setup
    else
        warn "scripts/system-setup.sh missing in $SRC_DIR - system settings skipped (git -C $SRC_DIR pull)."
    fi
fi

# =============================================================================
#  7. Summary
# =============================================================================
step "Summary"
XT=(); $XTREE_BIN_OK && XT=(xtree)
for t in "${TOOLS[@]}" "${XT[@]}"; do
    if { [[ "$t" == xtree ]] && [[ -x "$XTREE_BIN" ]]; } || { [[ "$t" != xtree ]] && tool_present "$t"; }; then printf '   %s✔%s %s\n' "$C_G" "$C_0" "$t"
    else printf '   %s✖%s %s %s(missing)%s\n' "$C_R" "$C_0" "$t" "$C_Y" "$C_0"; fi
done

if [[ ${#SYS_NOTES[@]} -gt 0 ]]; then
    printf '\n'; for n in "${SYS_NOTES[@]}"; do printf '   %s✔%s %s\n' "$C_G" "$C_0" "$n"; done
fi
[[ -n "$TRIM_NOTE" ]] && printf '\n   %sℹ%s %s\n' "$C_C" "$C_0" "$TRIM_NOTE"

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '\n%sWarnings:%s\n' "$C_Y" "$C_0"
    printf '   - %s\n' "${WARNINGS[@]}"
fi

if $OPT_DOTFILES; then
cat <<EOF

${C_B}${C_G}🎉 dotfiles-nixish is installed!${C_0}

   Activate it now:   ${C_B}source ~/.bashrc${C_0}$($ZSH_DONE && printf '   (zsh: %ssource ~/.zshrc%s)' "$C_B" "$C_0")
   ...or simply open a new terminal.

   Try:  ${C_C}l${C_0}  ${C_C}ll${C_0}  ${C_C}cowsays${C_0}  ${C_C}xtree -f -L 2 .${C_0}  ${C_C}xtree -r -p -u -t ~${C_0}  ${C_C}duf${C_0}  ${C_C}btop${C_0}
   Update later:  bash ${SRC_DIR}/install.sh   (after: git -C ${SRC_DIR} pull)
EOF
elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '\n%s%s⚠ Finished with %d warning(s) - see above%s\n' "$C_B" "$C_Y" "${#WARNINGS[@]}" "$C_0"
else
    printf '\n%s%s🎉 Done%s%s\n' "$C_B" "$C_G" "$($OPT_DRY && echo " (dry run - nothing was changed)")" "$C_0"
fi
exit 0
