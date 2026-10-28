# dotfiles-nixish BEGIN
# Managed by https://github.com/entropytwo-ai/dotfiles-nixish
# Re-running install.sh replaces everything between BEGIN/END. Put your own
# customizations OUTSIDE this block.

# --- PATH: Debian/Ubuntu ship cowsay/fortune in /usr/games -------------------
[[ -d /usr/games && ":$PATH:" != *:/usr/games:* ]] && PATH="$PATH:/usr/games"
[[ ":$PATH:" != *:/usr/local/bin:* ]] && PATH="/usr/local/bin:$PATH"
# Nix user profiles (NixOS / Nix on other distros) - where eza etc. live there
for _d in "$HOME/.local/bin" "$HOME/.nix-profile/bin" "$HOME/.local/state/nix/profile/bin" "/etc/profiles/per-user/$USER/bin"; do
    [[ ":$PATH:" != *":$_d:"* && -d "$_d" ]] && PATH="$_d:$PATH"
done; unset _d
export PATH

# --- History (zsh equivalents of the bash settings) -----------------------------
HISTFILE="${HISTFILE:-$HOME/.zsh_history}"
HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY          # bash: shopt -s histappend
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_SPACE       # bash: HISTCONTROL=ignorespace
setopt HIST_IGNORE_DUPS        # bash: HISTCONTROL=ignoredups
setopt HIST_IGNORE_ALL_DUPS    # bash: HISTCONTROL=erasedups
setopt EXTENDED_HISTORY        # store timestamps
# bash: HISTTIMEFORMAT='%m/%d/%y %T '
alias history='fc -t "%m/%d/%y %T" -l 1'

# --- Locale: the system default (set by the installer, default en_US.UTF-8) ---
# Re-applied here because SSH clients often send their own LANG/LC_*. Only
# used when it exists (else every program warns "cannot change locale");
# musl/Alpine has no 'locale -a' and accepts any name.
_loc=$(sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}LANG=["'"'"']\{0,1\}\([^"'"'"' ]*\).*/\2/p' \
       /etc/default/locale /etc/locale.conf /etc/profile.d/00-dotfiles-nixish-locale.sh 2>/dev/null | head -n 1)
case "$_loc" in ""|C|C.*|POSIX) _loc=en_US.UTF-8 ;; esac
_have=$(locale -a 2>/dev/null | tr 'A-Z' 'a-z' | sed 's/utf-8/utf8/')
if [ -z "$_have" ] || printf '%s\n' "$_have" | grep -qxF "$(printf '%s' "$_loc" | tr 'A-Z' 'a-z' | sed 's/utf-8/utf8/')"; then
    export LANG="$_loc"
    export LC_TIME="$_loc"
fi
unset _loc _have

# --- Aliases --------------------------------------------------------------------
if command -v eza >/dev/null 2>&1; then
    alias l='eza -la --color=always --group-directories-first'
    alias ll='eza -a --color=always --group-directories-first'
elif command -v exa >/dev/null 2>&1; then
    alias l='exa -la --color=always --group-directories-first'
    alias ll='exa -a --color=always --group-directories-first'
else
    alias l='ls -la --color=always --group-directories-first'
    alias ll='ls -a --color=always --group-directories-first'
fi
alias la='ls -A'

if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    alias bat='batcat'
fi

alias cowsays='{ [ -d /etc/update-motd.d ] && run-parts /etc/update-motd.d/; }; fastfetch --logo <(fortune | cowsay -W 30) --logo-color-1 cyan --logo-color-2 yellow'

[ -x /usr/local/bin/xtree ] && alias xtree='/usr/local/bin/xtree'   # else xtree comes from PATH (~/.local/bin fallback or the NixOS module)

# --- Greeting (interactive shells only) -----------------------------------------
if [[ -o interactive ]] && command -v fastfetch >/dev/null 2>&1; then
    if command -v fortune >/dev/null 2>&1 && command -v cowsay >/dev/null 2>&1; then
        fastfetch --logo <(fortune | cowsay -W 30) --logo-color-1 cyan --logo-color-2 yellow
    else
        fastfetch
    fi
fi
# dotfiles-nixish END
