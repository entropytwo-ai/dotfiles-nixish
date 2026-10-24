# dotfiles-nixish BEGIN
# Managed by https://github.com/entropytwo-ai/dotfiles-nixish
# Re-running install.sh replaces everything between BEGIN/END. Put your own
# customizations OUTSIDE this block.

# --- PATH: Debian/Ubuntu ship cowsay/fortune in /usr/games -------------------
[[ -d /usr/games && ":$PATH:" != *:/usr/games:* ]] && PATH="$PATH:/usr/games"
[[ ":$PATH:" != *:/usr/local/bin:* ]] && PATH="/usr/local/bin:$PATH"
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
export LC_TIME=en_US.UTF-8
# bash: HISTTIMEFORMAT='%m/%d/%y %T '
alias history='fc -t "%m/%d/%y %T" -l 1'

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

[ -x /usr/local/bin/xtree ] && alias xtree='/usr/local/bin/xtree'   # else xtree comes from PATH (e.g. the NixOS module)

# --- Greeting (interactive shells only) -----------------------------------------
if [[ -o interactive ]] && command -v fastfetch >/dev/null 2>&1; then
    if command -v fortune >/dev/null 2>&1 && command -v cowsay >/dev/null 2>&1; then
        fastfetch --logo <(fortune | cowsay -W 30) --logo-color-1 cyan --logo-color-2 yellow
    else
        fastfetch
    fi
fi
# dotfiles-nixish END
