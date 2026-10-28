# dotfiles-nixish BEGIN
# Managed by https://github.com/entropytwo-ai/dotfiles-nixish
# Re-running install.sh replaces everything between BEGIN/END. Put your own
# customizations OUTSIDE this block.

# --- PATH: Debian/Ubuntu ship cowsay/fortune in /usr/games -------------------
case ":$PATH:" in *:/usr/games:*) ;; *) [ -d /usr/games ] && PATH="$PATH:/usr/games" ;; esac
case ":$PATH:" in *:/usr/local/bin:*) ;; *) PATH="/usr/local/bin:$PATH" ;; esac
# Nix user profiles (NixOS / Nix on other distros) - where eza etc. live there
for _d in "$HOME/.local/bin" "$HOME/.nix-profile/bin" "$HOME/.local/state/nix/profile/bin" "/etc/profiles/per-user/$USER/bin"; do
    case ":$PATH:" in *":$_d:"*) ;; *) [ -d "$_d" ] && PATH="$_d:$PATH" ;; esac
done; unset _d
export PATH

# --- History ------------------------------------------------------------------
# (ignoreboth + erasedups combined: a second plain HISTCONTROL= line would
#  silently overwrite the first one)
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
HISTSIZE=10000
HISTFILESIZE=10000
export HISTTIMEFORMAT='%m/%d/%y %T '

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
# eza replacement for ls (falls back to exa, then plain ls)
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

# bat is called "batcat" on Debian/Ubuntu
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    alias bat='batcat'
fi

# Cowsay alias (MOTD only on systems that have /etc/update-motd.d, e.g. Ubuntu)
alias cowsays='{ [ -d /etc/update-motd.d ] && run-parts /etc/update-motd.d/; }; fastfetch --logo <(fortune | cowsay -W 30) --logo-color-1 cyan --logo-color-2 yellow'

# xtree
[ -x /usr/local/bin/xtree ] && alias xtree='/usr/local/bin/xtree'   # else xtree comes from PATH (~/.local/bin fallback or the NixOS module)

# --- Greeting (interactive shells only) -----------------------------------------
if [[ $- == *i* ]] && command -v fastfetch >/dev/null 2>&1; then
    if command -v fortune >/dev/null 2>&1 && command -v cowsay >/dev/null 2>&1; then
        fastfetch --logo <(fortune | cowsay -W 30) --logo-color-1 cyan --logo-color-2 yellow
    else
        fastfetch
    fi
fi
# dotfiles-nixish END
