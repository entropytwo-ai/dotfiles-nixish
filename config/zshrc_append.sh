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

# --- Locale: en_US.UTF-8 ------------------------------------------------------
# Only when the locale exists (else every program warns "cannot change locale").
# musl/Alpine has no 'locale -a' and accepts any name.
_loc=$(locale -a 2>/dev/null)
if [ -z "$_loc" ] || printf '%s\n' "$_loc" | grep -qiE '^en_US\.utf-?8$'; then
    export LANG=en_US.UTF-8
    export LC_TIME=en_US.UTF-8
fi
unset _loc

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
