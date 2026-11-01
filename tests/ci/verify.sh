#!/usr/bin/env bash
# shellcheck disable=SC2088  # "~/..." in messages is text, not a path
# Checks what install.sh left behind - by RUNNING things the way the user
# would (login + interactive shell), not just by looking for files:
# a command that exists but has no data (fortune without quotes, a locale that
# was never generated, an alias to a missing binary) counts as a failure.
#
#   verify.sh <scenario> <user> <home> <src-dir> <install-log> <exit-code> [sums-before sums-after]
#   scenario: full | oneliner | tools | shell | xtree | rerun
set -uo pipefail
SCENARIO="$1" U="$2" H="$3" SRC="$4" LOG="$5" RC="$6"

FAILS=0
pass() { printf '  \033[32m✔\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✖ %s\033[0m\n' "$*"; echo "::error title=${SCENARIO}::$*"; FAILS=$((FAILS + 1)); }
note() { printf '  \033[33mℹ %s\033[0m\n' "$*"; echo "::notice title=${SCENARIO}::$*"; }
check() {  # check "<description>" <command...>
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi
}

# Run a command as the user in an interactive bash (reads ~/.bashrc) inside a
# login session (PAM / /etc/profile: PATH, locale) - like opening a terminal.
# Job-control noise from running bash -i without a terminal is dropped.
NOISE='cannot set terminal process group|no job control in this shell|Inappropriate ioctl'
in_login() {  # in_login <command> - a login session of the user, no rc files beyond the login ones
    if [[ "$U" == root ]]; then bash -lc "$1" </dev/null 2>&1
    else su - "$U" -c "$1" </dev/null 2>&1; fi
}
ush()  { in_login "TERM=dumb bash -ic $(printf %q "$1")" | grep -Ev "$NOISE"; return "${PIPESTATUS[0]}"; }
uzsh() { in_login "TERM=dumb zsh -ic $(printf %q "$1")"  | grep -Ev "$NOISE"; return "${PIPESTATUS[0]}"; }
# only what $1 prints - the greeting that every interactive shell shows first is cut off
uout()  { ush  "echo __CI_OUT__; $1" | sed -n '/^__CI_OUT__$/,$p' | sed 1d; }
uzout() { uzsh "echo __CI_OUT__; $1" | sed -n '/^__CI_OUT__$/,$p' | sed 1d; }
expect() {  # expect "<description>" "<command>" "<regex the output must match>"
    local out; out="$(uout "$2")"
    if grep -Eq -- "$3" <<<"$out"; then pass "$1"; else fail "$1 - got: $(head -3 <<<"$out" | cat -v | tr '\n' '|')"; fi
}

is_nix() { [[ -e /etc/NIXOS ]]; }
has_block() { [[ -f "$1" ]] && grep -qxF '# dotfiles-nixish BEGIN' "$1"; }
one_block() {
    [[ "$(grep -cxF '# dotfiles-nixish BEGIN' "$1")" == 1 && "$(grep -cxF '# dotfiles-nixish END' "$1")" == 1 ]]
}

printf '\n== %s (user %s) ==\n' "$SCENARIO" "$U"

# ---------------------------------------------------------------------------
# The run itself
# ---------------------------------------------------------------------------
[[ "$RC" == 0 ]] && pass "install.sh exited 0" || fail "install.sh exited $RC"
if grep -q '✖' "$LOG"; then fail "install log has ✖ lines:"; grep '✖' "$LOG" | sed 's/^/      /'
else pass "no ✖ in the install log"; fi
if grep -q '⚠' "$LOG"; then fail "install.sh printed warnings:"; grep '⚠' "$LOG" | sed 's/^/      /'
else pass "no warnings"; fi
check "the bash greeting/summary reached the end ('🎉')" grep -q '🎉' "$LOG"

# ---------------------------------------------------------------------------
# Second run (idempotency)
# ---------------------------------------------------------------------------
if [[ "$SCENARIO" == rerun ]]; then
    BEFORE="$7" AFTER="$8"
    if diff -u "$BEFORE" "$AFTER" >/tmp/sums.diff; then pass "second run changed no file in $H"
    else fail "second run changed files in $H:"; sed 's/^/      /' /tmp/sums.diff; fi
    check "~/.bashrc reported as already up to date" grep -q 'bashrc already up to date' "$LOG"
    check "no new backup files" bash -c "! grep -q 'Backup of the original saved' '$LOG'"
    [[ $FAILS -eq 0 ]] && { printf '\n\033[32mAll checks passed\033[0m\n'; exit 0; }
    printf '\n\033[31m%d check(s) failed\033[0m\n' "$FAILS"; exit 1
fi

WANT_TOOLS=false WANT_SHELL=false WANT_XTREE=false
case "$SCENARIO" in
    full|oneliner) WANT_TOOLS=true WANT_SHELL=true WANT_XTREE=true ;;
    tools) WANT_TOOLS=true ;;
    shell) WANT_SHELL=true ;;
    xtree) WANT_XTREE=true ;;
esac

# ---------------------------------------------------------------------------
# 1a. Tools: each one must RUN, with its data
# ---------------------------------------------------------------------------
echo "-- tools (1a)"
TOOL_CMDS=(eza duf cowsay fortune fastfetch tldr nmap ncdu btop fzf glances bat)
if $WANT_TOOLS; then
    for t in "${TOOL_CMDS[@]}"; do
        case "$t" in
            cowsay)    expect "cowsay draws a cow" "cowsay moo" 'moo' ;;
            fortune)   out="$(uout 'fortune')"
                       if [[ -n "$out" && "$out" != *"No fortunes"* && "$out" != *"not found"* ]]; then pass "fortune prints a quote (quote database present)"
                       else fail "fortune prints no quote: $out"; fi ;;
            tldr)      expect "tldr shows the tar page (page cache present)" "tldr tar" 'tar (-|--)?[a-z]' ;;
            fastfetch) expect "fastfetch runs" "fastfetch --pipe -s os" '[A-Za-z]' ;;
            *)         expect "$t runs ($t --version)" "command -v $t >/dev/null && $t --version >/dev/null 2>&1 && echo OK" '^OK$' ;;
        esac
    done
else
    # a part that was not chosen must not have been done
    for t in duf btop glances; do
        expect "$t NOT installed (tools not chosen)" "command -v $t || echo ABSENT" '^ABSENT$'
    done
fi

# ---------------------------------------------------------------------------
# 1c. xtree
# ---------------------------------------------------------------------------
echo "-- xtree (1c)"
if $WANT_XTREE; then
    if is_nix || [[ -x /usr/local/bin/xtree ]] || [[ -x "$H/.local/bin/xtree" ]]; then pass "xtree binary installed"; else fail "no xtree in /usr/local/bin or ~/.local/bin"; fi
    check "~/xtree points to a working file" test -x "$H/xtree"
    out="$(uout 'xtree -L 1 /etc')"
    [[ "$out" == *Name* && "$out" != *"not found"* ]] && pass "xtree draws a tree" || fail "xtree output wrong: $(head -3 <<<"$out")"
    out="$(uout 'xtree -p -u -t -L 1 /etc')"
    [[ "$out" == *Name* ]] && pass "xtree -p -u -t (permissions, owner, dates) works" || fail "xtree -p -u -t failed: $(head -3 <<<"$out")"
else
    check "xtree NOT installed (xtree not chosen)" bash -c "[[ ! -e /usr/local/bin/xtree && ! -e '$H/xtree' ]]"
fi

# ---------------------------------------------------------------------------
# 1b. Shell config
# ---------------------------------------------------------------------------
echo "-- shell config (1b)"
if $WANT_SHELL; then
    if [[ -f "$H/.bashrc" ]] && one_block "$H/.bashrc"; then pass "~/.bashrc has exactly one dotfiles-nixish block"; else fail "~/.bashrc block missing or duplicated"; fi
    check "~/.bashrc passes bash -n" bash -n "$H/.bashrc"
    # the greeting runs in every interactive shell: it must not print errors
    greet="$(ush 'true')"
    if grep -Eqi 'command not found|No fortunes|syntax error|No such file' <<<"$greet"; then
        fail "the login greeting prints errors:"; grep -Ei 'command not found|No fortunes|syntax error|No such file' <<<"$greet" | sed 's/^/      /'
    else pass "interactive shell starts without errors"; fi
    # "l ." not "l": with no path and a stdin that is not a terminal (as here,
    # or ssh host l / cron), eza >= 0.21 reads the file names from stdin
    if $WANT_TOOLS; then
        [[ -n "$greet" ]] && pass "greeting shows (fastfetch + fortune | cowsay)" || fail "no greeting in an interactive shell"
        expect "alias l uses eza" "type l" 'eza'
        expect "'l' lists files" "d=\$(mktemp -d) && touch \$d/hello.txt && cd \$d && l ." 'hello\.txt'
        expect "'bat' runs" "bat --version" '^bat '
    else
        expect "'l' falls back to plain ls and works" "d=\$(mktemp -d) && touch \$d/hello.txt && cd \$d && l ." 'hello\.txt'
    fi
    expect "'cowsays' alias is defined" "type cowsays" 'alias'
    # login shells (console / SSH) must load ~/.bashrc too
    # (an interactive login shell reads only ~/.bash_profile|~/.bash_login|~/.profile)
    out="$(in_login "TERM=dumb bash -lic 'echo __CI_OUT__; type cowsays'" | sed -n '/^__CI_OUT__$/,$p')"
    [[ "$out" == *alias* ]] && pass "a login shell (console/SSH) loads ~/.bashrc" || fail "a login shell does not load ~/.bashrc: $(tail -1 <<<"$out")"
    # locale: the shell config switches a language-less system to en_US.UTF-8
    if is_nix; then
        note "NixOS container: locale is set by the NixOS module (i18n.defaultLocale), not checked here"
    else
        lang="$(uout 'echo LANG=$LANG' | grep -o 'LANG=.*' | tail -1)"
        [[ "$lang" == "LANG=en_US.UTF-8" ]] && pass "new login has LANG=en_US.UTF-8" || fail "new login has $lang (want en_US.UTF-8)"
        loc_err="$(uout 'locale' | grep -i 'cannot' || true)"
        [[ -z "$loc_err" ]] && pass "the locale really exists (no 'locale: Cannot set' errors)" || fail "locale errors: $loc_err"
    fi
    # eza theme (only installed together with eza)
    if uout 'command -v eza' | grep -q eza; then
        if cmp -s "$SRC/config/eza-theme.yml" "$H/.config/eza/theme.yml"; then pass "~/.config/eza/theme.yml installed"
        else fail "~/.config/eza/theme.yml missing or different from config/eza-theme.yml"; fi
        ver="$(uout 'eza --version' | grep -oE 'v[0-9]+\.[0-9]+' | head -1 | tr -d v)"
        if [[ -n "$ver" ]] && (( ${ver%%.*} > 0 || ${ver#*.} >= 20 )); then
            out="$(uout "cd /etc && env -u LS_COLORS -u EZA_COLORS eza -l --color=always passwd")"
            [[ "$out" == *"38;5;75m"* ]] && pass "eza shows timestamps in the lighter blue (theme is read)" || fail "eza $ver ignores the theme (no colour 75 in: $(cat -v <<<"$out" | tail -1))"
        else
            note "eza ${ver:-?} is older than 0.20 and does not read theme.yml - timestamps keep the default blue"
        fi
    else
        check "no eza theme without eza" test ! -e "$H/.config/eza/theme.yml"
    fi
    # zsh (only installed with --zsh, i.e. full / oneliner)
    if [[ "$SCENARIO" == full || "$SCENARIO" == oneliner ]]; then
        if command -v zsh >/dev/null 2>&1 || is_nix; then
            if [[ -f "$H/.zshrc" ]] && one_block "$H/.zshrc"; then pass "~/.zshrc has exactly one dotfiles-nixish block"; else fail "~/.zshrc block missing or duplicated"; fi
            out="$(uzout 'alias l')"
            [[ "$out" == *eza* ]] && pass "zsh: alias l uses eza" || fail "zsh: alias l wrong: $out"
            zgreet="$(uzsh 'true')"
            if grep -Eqi 'command not found|No fortunes|parse error|no such file' <<<"$zgreet"; then fail "zsh greeting prints errors: $(grep -Ei 'command not found|No fortunes|parse error|no such file' <<<"$zgreet" | head -3)"
            else pass "zsh starts without errors"; fi
        else fail "--zsh given but zsh is not installed"; fi
    fi
else
    if has_block "$H/.bashrc"; then fail "~/.bashrc was changed although the shell config was not chosen"
    else pass "~/.bashrc untouched (shell config not chosen)"; fi
    check "no eza theme (shell config not chosen)" test ! -e "$H/.config/eza/theme.yml"
fi

# ---------------------------------------------------------------------------
# Every run
# ---------------------------------------------------------------------------
echo "-- general"
if [[ "$U" != root ]]; then
    wrong="$(find "$H" ! -user "$U" 2>/dev/null | head -5)"
    [[ -z "$wrong" ]] && pass "everything in $H belongs to $U" || fail "files in $H owned by someone else: $wrong"
fi
if [[ -d "$SRC/.git" ]] && command -v git >/dev/null; then
    st="$(in_login "git -C '$SRC' status --porcelain")"
    [[ -z "$st" ]] && pass "repo checkout is clean (git status)" || fail "git status not clean in $SRC: $(head -5 <<<"$st")"
fi
if $WANT_TOOLS; then
    lp="$(in_login "bash '$SRC/install.sh' --list-packages")"
    missing="$(sed -n '/Always/,/Only when needed/p' <<<"$lp" | grep '·' || true)"
    [[ -z "$missing" ]] && pass "--list-packages shows every package as installed (✔)" || fail "--list-packages still lists packages as not installed: $missing"
fi

if [[ $FAILS -eq 0 ]]; then printf '\n\033[32mAll checks passed\033[0m\n'; exit 0; fi
printf '\n\033[31m%d check(s) failed\033[0m\n' "$FAILS"; exit 1
