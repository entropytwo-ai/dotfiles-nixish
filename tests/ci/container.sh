#!/bin/sh
# Runs inside a fresh distro container, as root (POSIX sh: Alpine has no bash yet).
#   sh /repo/tests/ci/container.sh <scenario>
# Scenarios:
#   full      install everything (+ --zsh), check it, run again (must change nothing)
#   tools     only --tools        (1a)
#   shell     only --shell-config (1b)
#   xtree     only --xtree        (1c)
#   oneliner  the README one-liner: script piped into bash, repo cloned from
#             $DOTFILES_REPO / $DOTFILES_BRANCH
# Env: TEST_USER (default tester; "root" = run as root, used by the Nix container)
#      NIX_CONTAINER=1  the nixos/nix image, set up to look like NixOS
set -eu
SCENARIO="${1:?scenario}"
TEST_USER="${TEST_USER:-tester}"

say() { printf '\n\033[1;36m### %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. The bare minimum a person has before running the one-liner: bash, sudo,
#    and a normal user with sudo rights. Everything else is the installer's job.
# ---------------------------------------------------------------------------
say "Preparing the container (bash, sudo, user '$TEST_USER')"
if [ -n "${NIX_CONTAINER:-}" ]; then
    # nixos/nix image made to look like NixOS: the marker install.sh checks, a
    # nixpkgs channel, and the base tools every NixOS system has (gawk, sed ...)
    touch /etc/NIXOS
    nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs
    nix-channel --update
    nix-env -iA nixpkgs.gawk nixpkgs.gnused nixpkgs.diffutils nixpkgs.procps \
        nixpkgs.util-linux nixpkgs.ncurses nixpkgs.glibcLocales >/dev/null
elif command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq sudo >/dev/null
elif command -v dnf >/dev/null; then
    dnf install -y -q sudo shadow-utils util-linux >/dev/null
elif command -v pacman >/dev/null; then
    pacman -Sy --noconfirm --needed sudo >/dev/null
elif command -v zypper >/dev/null; then
    zypper -n -q install sudo shadow util-linux >/dev/null
elif command -v apk >/dev/null; then
    apk add -q bash sudo shadow
fi

if [ "$TEST_USER" = root ]; then
    HOME_DIR=/root
else
    useradd -m -s /bin/bash "$TEST_USER"
    mkdir -p /etc/sudoers.d
    echo "$TEST_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-ci-test
    chmod 440 /etc/sudoers.d/90-ci-test
    HOME_DIR="/home/$TEST_USER"
fi

# a private copy of the checkout (with .git), owned by the user - like a real clone
CHECKOUT="$HOME_DIR/dotfiles-nixish"
cp -a /repo "$CHECKOUT"
[ "$TEST_USER" = root ] || chown -R "$TEST_USER:" "$CHECKOUT"

as_user() {  # as_user <command string>  - run like the user would, in a login shell
    if [ "$TEST_USER" = root ]; then bash -lc "$1"
    else su - "$TEST_USER" -c "$1"; fi
}

OPTS="--no-menu -y"
case "$SCENARIO" in
    full|oneliner) OPTS="$OPTS --zsh" ;;
    tools)  OPTS="$OPTS --tools" ;;
    shell)  OPTS="$OPTS --shell-config" ;;
    xtree)  OPTS="$OPTS --xtree" ;;
    *) echo "unknown scenario $SCENARIO" >&2; exit 2 ;;
esac

# checksums of every file in the home directory (caches and git internals excluded)
sums() {
    ( cd "$HOME_DIR" && find . \( -path ./.cache -o -path ./.nix-profile -o -path ./.local/state \
        -o -path ./.local/share -o -path ./.nix-defexpr -o -path ./.nix-channels -o -name .git \
        -o -name .bash_history -o -name .zsh_history \) -prune -o -type f -exec md5sum {} + ) | sort -k2 > "$1"
}

LOG=/tmp/install.log
run_install() {  # run_install <log>
    if [ "$SCENARIO" = oneliner ]; then
        # what the README one-liner does: the script arrives on a pipe, so it is
        # not a file in a checkout and has to fetch the repo ($DOTFILES_BRANCH)
        as_user "cd /tmp && cat '$CHECKOUT/install.sh' | DOTFILES_REPO='${DOTFILES_REPO:-}' DOTFILES_BRANCH='${DOTFILES_BRANCH:-main}' bash -s -- $OPTS" >"$1" 2>&1
    else
        as_user "cd '$CHECKOUT' && bash install.sh $OPTS" >"$1" 2>&1
    fi
}

say "Running install.sh $OPTS ($SCENARIO)"
set +e; run_install "$LOG"; RC=$?; set -e
cat "$LOG"

say "Checking the result"
SRC="$CHECKOUT"; [ "$SCENARIO" = oneliner ] && SRC="$HOME_DIR/.dotfiles-nixish"
bash /repo/tests/ci/verify.sh "$SCENARIO" "$TEST_USER" "$HOME_DIR" "$SRC" "$LOG" "$RC"

if [ "$SCENARIO" = full ] || [ "$SCENARIO" = oneliner ]; then
    say "Second run: must succeed and change nothing"
    sums /tmp/sums.before
    set +e; run_install /tmp/install2.log; RC2=$?; set -e
    cat /tmp/install2.log
    sums /tmp/sums.after
    bash /repo/tests/ci/verify.sh rerun "$TEST_USER" "$HOME_DIR" "$SRC" /tmp/install2.log "$RC2" /tmp/sums.before /tmp/sums.after
fi
