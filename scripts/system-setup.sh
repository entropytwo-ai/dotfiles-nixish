# shellcheck shell=bash
# shellcheck disable=SC2154   # the variables and helpers come from install.sh
# =============================================================================
#  dotfiles-nixish system setup - sourced by install.sh, not run on its own.
#
#    * SSH access for non-root users (root login over SSH is turned off)
#    * hostname
#    * IP address, subnet and gateway (static or DHCP)
#    * DNS servers
#
#  Network backends, picked automatically (override: DOTFILES_NET_BACKEND):
#    nm        NetworkManager (nmcli)          Fedora, RHEL, desktops, NixOS+NM
#    netplan   /etc/netplan (netplan set)      Ubuntu server
#    networkd  /etc/systemd/network            Arch, minimal systemd installs
#    ifupdown  /etc/network/interfaces         Debian, Alpine
#    wicked    /etc/sysconfig/network          openSUSE without NetworkManager
#    nixos     /etc/nixos/dotfiles-nixish-system.nix + nixos-rebuild switch
#
#  --dry-run prints every file and command instead of applying it.
#  DOTFILES_NO_APPLY=1 writes the config files but does not activate the
#  network change (used by the tests).
# =============================================================================

SYS_TAG="# Managed by dotfiles-nixish (install.sh) - re-run the installer to change it."
SYS_NOTES=()                 # one-liners for the Summary
NIX_PARTS=()                 # NixOS: option lines for the generated module
NIX_SYS_FILE=/etc/nixos/dotfiles-nixish-system.nix
NET_APPLY=()                 # shell lines that activate the network change
NET_APPLY_SCRIPT=/run/dotfiles-nixish-network-apply.sh
NET_LOG=/var/log/dotfiles-nixish-network.log
DROP_RISK=false              # true when the change will cut our own SSH session

if [[ -d /run/systemd/system && "$(cat /proc/1/comm 2>/dev/null || echo systemd)" == systemd ]]; then INIT=systemd
elif have rc-service && [[ -d /run/openrc ]]; then INIT=openrc
else INIT=none; fi

sudo_() { "${SUDO[@]}" "$@"; }
dry()   { $OPT_DRY; }

# sys_write <file> [mode-for-new-files]   (content on stdin)
# Keeps a timestamped backup and the file's inode/permissions.
sys_write() {
    local f="$1" mode="${2:-644}" tmp
    tmp="$(mktemp "$WORKDIR/sys.XXXXXX")"; cat > "$tmp"
    if dry; then
        sub "[dry-run] would write $f:"
        sed 's/^/           /' "$tmp"
        return 0
    fi
    if sudo_ test -e "$f"; then
        if sudo_ cmp -s "$tmp" "$f"; then sub "$f is already up to date"; return 0; fi
        sudo_ cp -p "$f" "$f.dotfiles-nixish.bak.$TS" && sub "Backup: $f.dotfiles-nixish.bak.$TS"
        sudo_ tee "$f" < "$tmp" >/dev/null || { warn "Could not write $f"; return 1; }
        sub "Updated $f"
    else
        sudo_ mkdir -p "$(dirname "$f")" \
            && sudo_ tee "$f" < "$tmp" >/dev/null && sudo_ chmod "$mode" "$f" \
            || { warn "Could not write $f"; return 1; }
        sub "Created $f"
        printf '%s\n' "$f" >> "$WORKDIR/sys-created"   # a file: sys_write often runs in a pipe (subshell)
    fi
}

# sys_run <cmd...>: run as root (or show it in --dry-run)
sys_run() {
    if dry; then sub "[dry-run] would run: $*"; return 0; fi
    sudo_ "$@"
}

# remove a file we created (with backup); used when a check fails
sys_remove() {
    dry && return 0
    sudo_ test -e "$1" || return 0
    sudo_ cp -p "$1" "$1.dotfiles-nixish.bak.$TS" 2>/dev/null
    sudo_ rm -f "$1"
}

# restore_backup <file> : undo this run's change to <file>
#   changed this run -> put the backup back; created this run -> remove it;
#   untouched (e.g. already up to date) -> leave it alone, never delete it
restore_backup() {
    local b="$1.dotfiles-nixish.bak.$TS"
    if sudo_ test -e "$b"; then sudo_ tee "$1" < <(sudo_ cat "$b") >/dev/null; return; fi
    if grep -qxF -- "$1" "$WORKDIR/sys-created" 2>/dev/null; then sudo_ rm -f "$1"; fi
    return 0
}

# nix_parse <file|-> : 0 = parses, 1 = syntax error, 2 = could not check
nix_parse() {
    local out
    have nix-instantiate || return 2
    out="$(nix-instantiate --parse "$1" 2>&1 >/dev/null)" && return 0
    grep -qiE 'syntax error|unexpected|undefined variable|at «stdin»|, at /' <<<"$out" && { NIX_PARSE_ERR="$(grep -m1 'error' <<<"$out")"; return 1; }
    return 2
}

nix_str() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//\$\{/\\\$\{}"; printf '"%s"' "$s"; }

port_open() { timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null; }

# =============================================================================
#  SSH for non-root users
# =============================================================================
sshd_bin() { local b; for b in "$(command -v sshd 2>/dev/null)" /usr/sbin/sshd /usr/bin/sshd /run/current-system/sw/bin/sshd; do
    [[ -n "$b" && -x "$b" ]] && { echo "$b"; return 0; }; done; return 1; }

ssh_unit() {  # Debian/Ubuntu call it ssh, everyone else sshd
    local u; for u in ssh sshd; do systemctl cat "$u.service" >/dev/null 2>&1 && { echo "$u"; return; }; done; echo sshd
}

# print the valid public keys described by $SSH_KEY (key text, file, or gh:<user>)
resolve_ssh_keys() {
    local raw="" line
    case "$SSH_KEY" in
        gh:*|github:*)
            if fetch "https://github.com/${SSH_KEY#*:}.keys" "$WORKDIR/gh.keys"; then raw="$(cat "$WORKDIR/gh.keys")"
            else warn "Could not download the keys of GitHub user '${SSH_KEY#*:}'"; return 0; fi
            [[ -n "$raw" ]] || warn "GitHub user '${SSH_KEY#*:}' has no public SSH keys"
            ;;
        *)  if [[ -f "$SSH_KEY" ]]; then raw="$(cat "$SSH_KEY")"; else raw="$SSH_KEY"; fi ;;
    esac
    while IFS= read -r line; do
        line="$(ltrim "$line")"
        [[ -z "$line" || "$line" == \#* ]] && continue
        if ssh-keygen -l -f /dev/stdin <<<"$line" >/dev/null 2>&1; then printf '%s\n' "$line"
        else warn "Not a valid SSH public key - skipped: $(short "$line" 40)"; fi
    done <<<"$raw"
}

user_has_password() {
    local pw; pw="$(sudo_ awk -F: -v u="$TARGET_USER" '$1==u {print $2}' /etc/shadow 2>/dev/null)"
    case "$pw" in ""|'!'*|'*'*) return 1 ;; *) return 0 ;; esac
}

add_authorized_keys() {
    local ak="$TARGET_HOME/.ssh/authorized_keys" keys k added=0
    [[ -n "$SSH_KEY" ]] || return 0
    if [[ "$TARGET_USER" == root ]]; then
        warn "You are running as root - not adding the key to root (root may not log in over SSH). Re-run as your normal user."
        return 0
    fi
    keys="$(resolve_ssh_keys)"
    [[ -n "$keys" ]] || return 0
    if dry; then sub "[dry-run] would add $(grep -c '' <<<"$keys") key(s) to $(disp "$ak")"; return 0; fi
    as_target mkdir -p "$TARGET_HOME/.ssh" && as_target chmod 700 "$TARGET_HOME/.ssh"
    as_target touch "$ak" && as_target chmod 600 "$ak"
    while IFS= read -r k; do
        if grep -qxF "$k" "$ak" 2>/dev/null; then sub "Key already authorized: $(short "$k" 50)"
        else printf '%s\n' "$k" | as_target tee -a "$ak" >/dev/null && added=$((added + 1)) && sub "Key added: $(short "$k" 50)"; fi
    done <<<"$keys"
    have restorecon && sudo_ restorecon -R "$TARGET_HOME/.ssh" >/dev/null 2>&1
    ok "$(disp "$ak"): $added new key(s), $(grep -cE '^(ssh-|ecdsa-|sk-)' "$ak") total"
}

authorized_key_count() { grep -cE '^[[:space:]]*(ssh-|ecdsa-|sk-)' "$TARGET_HOME/.ssh/authorized_keys" 2>/dev/null || echo 0; }

# =============================================================================
#  New user with sudo access
# =============================================================================
admin_group() {  # Debian/Ubuntu use "sudo", everyone else "wheel"
    if ! $IS_NIXOS && getent group sudo >/dev/null 2>&1; then echo sudo; else echo wheel; fi
}

sudoers_allows_group() {
    sudo_ sh -c "cat /etc/sudoers /etc/sudoers.d/* 2>/dev/null" | grep -qE "^[[:space:]]*%$1[[:space:]]+ALL"
}

setup_user() {
    local u="$NEW_USER" grp existed=false shell
    grp="$(admin_group)"
    id "$u" >/dev/null 2>&1 && existed=true
    step "$($existed && echo "Giving the existing user $u sudo access" || echo "Creating the user $u with sudo access")"

    # 1. sudo itself (minimal images may not have it)
    if ! $IS_NIXOS && ! have sudo; then
        if dry; then sub "[dry-run] would install: sudo"
        elif pm_install sudo >/dev/null 2>&1; then ok "Installed sudo"
        else warn "Could not install sudo - $u will not be able to use it"; fi
    fi
    getent group "$grp" >/dev/null 2>&1 || sys_run groupadd "$grp" 2>/dev/null || sys_run addgroup "$grp"

    # 2. the account
    shell="$(command -v bash 2>/dev/null || echo /bin/sh)"
    if $existed; then
        sub "$u exists (uid $(id -u "$u")) - keeping its home and files"
    elif have useradd; then
        sys_run useradd -m -s "$shell" "$u" && { dry || ok "User $u created (home $(getent passwd "$u" | cut -d: -f6), shell $shell)"; }
    else  # Alpine / busybox
        sys_run adduser -D -s "$shell" "$u" && { dry || ok "User $u created (busybox adduser)"; }
    fi
    if have usermod; then sys_run usermod -aG "$grp" "$u"; else sys_run addgroup "$u" "$grp"; fi
    dry || sub "Added $u to the '$grp' group"

    # 3. make sure the group may use sudo (Arch, openSUSE, Alpine ship it commented out)
    if $IS_NIXOS; then
        NIX_PARTS+=("# sudo user" "users.users.$(nix_str "$u") = { isNormalUser = true; extraGroups = [ \"wheel\" ]; };"
                    "security.sudo.enable = lib.mkDefault true;")
        sub "Added to the NixOS module: users.users.\"$u\" (isNormalUser, extraGroups = [ \"wheel\" ])"
        if grep -qs 'mutableUsers *= *false' /etc/nixos/*.nix; then
            warn "users.mutableUsers = false: the password set here is reset by NixOS - add hashedPassword for $u to your config"
        fi
    elif sudoers_allows_group "$grp"; then
        sub "sudoers already allows %$grp"
    else
        local sf=/etc/sudoers.d/10-dotfiles-nixish-$grp tmp
        tmp="$(mktemp "$WORKDIR/sudoers.XXXXXX")"
        printf '%s\n%%%s ALL=(ALL:ALL) ALL\n' "$SYS_TAG" "$grp" > "$tmp"
        if dry; then sub "[dry-run] would write $sf:"; sed 's/^/           /' "$tmp"
        elif ! have visudo || sudo_ visudo -cqf "$tmp"; then
            sudo_ mkdir -p /etc/sudoers.d && sudo_ install -m 440 -o root -g root "$tmp" "$sf" && ok "Created $sf (%$grp ALL=(ALL:ALL) ALL)"
        else
            warn "visudo rejected the sudoers rule - not installed"
        fi
    fi

    # 4. password (stdin only - never on a command line)
    if dry; then sub "[dry-run] would set the password for $u (chpasswd)"
    elif [[ -n "$NEW_USER_PW" ]]; then
        if printf '%s:%s\n' "$u" "$NEW_USER_PW" | sudo_ chpasswd; then ok "Password set for $u"
        else warn "Setting the password failed - run: sudo passwd $u"; fi
    else
        warn "No password given for $u - set one: sudo passwd $u"
    fi
    NEW_USER_PW=""

    # 5. SSH key: the key given for SSH also lets the new user in
    if $DO_SSH && [[ -n "$SSH_KEY" ]] && ! dry; then
        local th; th="$(getent passwd "$u" | cut -d: -f6)"
        TARGET_USER="$u" TARGET_HOME="$th" add_authorized_keys >/dev/null 2>&1 && sub "SSH key also added for $u"
    fi

    # 6. verify
    dry && { SYS_NOTES+=("User: $u (sudo via $grp)"); return 0; }
    if id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp"; then
        if $IS_NIXOS || sudo_ sudo -l -U "$u" 2>/dev/null | grep -q '(ALL'; then ok "Verified: $u is in '$grp' and may run any command with sudo"
        else warn "$u is in '$grp' but sudo -l shows no rights - check /etc/sudoers"; fi
    else
        warn "$u is not in the '$grp' group - check: id $u"
    fi
    SYS_NOTES+=("User: $u (sudo via $grp) - log in with: su - $u$($DO_SSH && echo "  or  ssh $u@<this-host>")")
}

setup_ssh() {
    step "Enabling SSH access for non-root users"
    local pw_auth=yes
    $SSH_PASSWORDS || pw_auth=no

    if $IS_NIXOS; then
        add_authorized_keys
        if [[ "$pw_auth" == no && "$(authorized_key_count)" -eq 0 ]] && ! dry; then
            warn "No SSH key for $TARGET_USER - keeping password logins on so you can't lock yourself out."
            pw_auth=yes
        fi
        NIX_PARTS+=(
            "# SSH for non-root users (root may not log in over SSH)"
            "services.openssh.enable = true;"
            "services.openssh.openFirewall = true;"
            "services.openssh.settings.PermitRootLogin = lib.mkForce \"no\";"
            "services.openssh.settings.PasswordAuthentication = lib.mkForce $([[ "$pw_auth" == yes ]] && echo true || echo false);"
        )
        sub "Added to the NixOS module: services.openssh (root login off, passwords: $pw_auth)"
        SSH_NOTE_PW="$pw_auth"
        return 0
    fi

    local sshd pkg main dropin=/etc/ssh/sshd_config.d/10-dotfiles-nixish.conf main_changed=false port eff
    # 1. package
    if ! sshd="$(sshd_bin)"; then
        sub "OpenSSH server not installed - installing it"
        pm_refresh
        case "$PM" in
            apt) pkg="openssh-server" ;; pacman) pkg="openssh" ;; apk) pkg="openssh-server openssh" ;;
            *)   pkg="openssh-server openssh" ;;
        esac
        if dry; then sub "[dry-run] would install: ${pkg%% *}"
        else for p in $pkg; do pm_install "$p" && break; done; fi
        if ! dry && ! sshd="$(sshd_bin)"; then warn "Could not install the OpenSSH server - SSH not set up."; return 1; fi
        sshd="${sshd:-/usr/sbin/sshd}"
        ok "OpenSSH server installed ($sshd)"
    else
        ok "OpenSSH server already installed ($sshd)"
    fi
    dry || sudo_ ssh-keygen -A >/dev/null 2>&1   # create any missing host keys

    # 2. make sure drop-in files are read (first value wins in sshd, so Include goes on top)
    main=/etc/ssh/sshd_config
    [[ -e "$main" ]] || { [[ -e /usr/etc/ssh/sshd_config ]] && main=/usr/etc/ssh/sshd_config; }
    if sudo_ grep -qiE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$main" 2>/dev/null; then
        sub "$main already reads /etc/ssh/sshd_config.d/*.conf"
    elif [[ "$main" == /etc/* ]]; then
        sub "$main does not read /etc/ssh/sshd_config.d/ - adding an Include line at the top"
        { printf '# dotfiles-nixish: read drop-in files first (sshd keeps the first value it sees)\nInclude /etc/ssh/sshd_config.d/*.conf\n\n'
          sudo_ cat "$main" 2>/dev/null; } | sys_write "$main" 600 && main_changed=true
    else
        warn "$main does not include /etc/ssh/sshd_config.d - add 'Include /etc/ssh/sshd_config.d/*.conf' to /etc/ssh/sshd_config."
    fi

    # 3. key + our settings
    add_authorized_keys
    if [[ "$pw_auth" == no && "$(authorized_key_count)" -eq 0 ]] && ! dry; then
        warn "No SSH key for $TARGET_USER - keeping password logins on so you can't lock yourself out."
        pw_auth=yes
    fi
    sys_write "$dropin" 644 <<EOF
$SYS_TAG
# SSH access for non-root users: root may not log in over SSH.
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication $pw_auth
EOF

    if dry; then
        SSH_NOTE_PW="$pw_auth"
        $IS_NIXOS || SYS_NOTES+=("SSH: ssh $TARGET_USER@<this-host>  (root login off, passwords: $pw_auth)")
        return 0
    fi

    # 4. validate before touching the running service
    #    (sshd -t needs its privilege-separation dir; missing before first start)
    [ -d /run/sshd ] || { sudo_ mkdir -p /run/sshd && sudo_ chmod 755 /run/sshd; }
    if ! eff="$(sudo_ "$sshd" -t 2>&1)"; then
        warn "sshd rejected the new config - changes undone: $(head -1 <<<"$eff")"
        restore_backup "$dropin"; $main_changed && restore_backup "$main"
        return 1
    fi
    sub "Config test (sshd -t) passed"
    eff="$(sudo_ "$sshd" -T -C "user=$TARGET_USER,host=localhost,addr=127.0.0.1" 2>/dev/null)"
    port="$(awk '$1=="port" {print $2; exit}' <<<"$eff")"; port="${port:-22}"
    if ! grep -qx 'permitrootlogin no' <<<"$eff" || ! grep -qx "passwordauthentication $pw_auth" <<<"$eff"; then
        warn "Another sshd setting overrides ours - check: $(sudo_ grep -rliE '^[[:space:]]*(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null | grep -v dotfiles-nixish | tr '\n' ' ')"
    else
        sub "Effective settings: PermitRootLogin no, PasswordAuthentication $pw_auth, port $port"
    fi

    # 5. enable + (re)start
    case "$INIT" in
        systemd)
            local u; u="$(ssh_unit)"
            if sudo_ systemctl enable --now "$u.service" >/dev/null 2>&1 \
               || sudo_ systemctl enable --now "$u.socket" >/dev/null 2>&1; then
                sudo_ systemctl try-restart "$u.service" >/dev/null 2>&1
                ok "SSH service enabled at boot and running ($u)"
            else
                warn "Could not enable/start $u.service"
            fi ;;
        openrc)
            sudo_ rc-update add sshd default >/dev/null 2>&1
            if sudo_ rc-service sshd restart >/dev/null 2>&1; then ok "SSH service enabled at boot and running (OpenRC: sshd)"
            else warn "Could not start sshd (rc-service sshd restart)"; fi ;;
        none)   # containers / no init system
            if pgrep -x sshd >/dev/null 2>&1; then
                sudo_ pkill -HUP -o -x sshd && ok "Running sshd reloaded (no init system found)"
            else
                sudo_ mkdir -p /run/sshd && sudo_ chmod 755 /run/sshd
                if sudo_ "$sshd"; then ok "sshd started (no init system found - it will not start at boot)"
                else warn "Could not start sshd"; fi
            fi ;;
    esac

    # 6. firewall
    if have ufw && sudo_ ufw status 2>/dev/null | grep -q '^Status: active'; then
        sudo_ ufw allow "$port/tcp" >/dev/null && ok "Firewall (ufw): port $port/tcp allowed"
    elif have firewall-cmd && sudo_ firewall-cmd --state >/dev/null 2>&1; then
        if [[ "$port" == 22 ]]; then sudo_ firewall-cmd -q --permanent --add-service=ssh
        else sudo_ firewall-cmd -q --permanent --add-port="$port/tcp"; fi
        sudo_ firewall-cmd -q --reload && ok "Firewall (firewalld): SSH allowed"
    fi

    # 7. verify it really answers and that the user can get in
    local _; for _ in 1 2 3 4 5 6; do port_open "$port" && break; sleep 1; done  # sshd re-execs on reload
    if port_open "$port"; then ok "sshd is accepting connections on port $port"
    else warn "Nothing is listening on port $port yet - check: sudo journalctl -u $(ssh_unit 2>/dev/null || echo sshd)"; fi
    if ! user_has_password && [[ "$(authorized_key_count)" -eq 0 ]]; then
        warn "$TARGET_USER has no password and no SSH key, so SSH logins will fail - set one: sudo passwd $TARGET_USER"
    elif [[ "$pw_auth" == yes ]] && ! user_has_password; then
        info "Note: $TARGET_USER has no password - only key logins will work (set one: sudo passwd $TARGET_USER)"
    fi
    SSH_NOTE_PW="$pw_auth"
    SYS_NOTES+=("SSH: ssh $TARGET_USER@<this-host>$([[ "$port" != 22 ]] && echo " -p $port")  (root login off, passwords: $pw_auth)")
}

# =============================================================================
#  Hostname
# =============================================================================
update_etc_hosts() {  # point the 127.0.1.1 line at the new name, drop the old one
    local old="$1" new="$2" names short="${2%%.*}"
    names="$new"; [[ "$short" != "$new" ]] && names="$new $short"
    awk -v old="$old" -v olds="${old%%.*}" -v names="$names" '
        function strip(   i, out, hit) {
            out = $1; hit = 0
            for (i = 2; i <= NF; i++) {
                if ($i ~ /^#/) { for (; i <= NF; i++) out = out " " $i; break }
                if ((($i == old) || ($i == olds)) && $i !~ /^localhost/) { hit = 1; continue }
                out = out "\t" $i
            }
            return hit ? out : $0
        }
        $1 == "127.0.1.1" { if (!done) { print "127.0.1.1\t" names; done = 1 }; next }
        $1 ~ /^127\./ || $1 == "::1" {
            l = strip(); if (l == $1) next; print l
            if (!done && $1 == "127.0.0.1") { print "127.0.1.1\t" names; done = 1 }
            next }
        { print }
        END { if (!done) print "127.0.1.1\t" names }' /etc/hosts
}

setup_hostname() {
    local old short="${NEW_HOSTNAME%%.*}"
    old="$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)"
    step "Changing the hostname: ${old:-?} → $NEW_HOSTNAME"

    if $IS_NIXOS; then
        NIX_PARTS+=("# hostname" "networking.hostName = lib.mkForce $(nix_str "$short");")
        [[ "$short" != "$NEW_HOSTNAME" ]] && NIX_PARTS+=("networking.domain = lib.mkForce $(nix_str "${NEW_HOSTNAME#*.}");")
        sub "Added to the NixOS module: networking.hostName = \"$short\""
        if [[ -f /etc/nixos/flake.nix ]] && grep -q "nixosConfigurations\.\"\?$old\"\?" /etc/nixos/flake.nix 2>/dev/null; then
            warn "Your flake names this machine nixosConfigurations.$old. After the rename, plain 'nixos-rebuild switch' looks for '$short' - use 'nixos-rebuild switch --flake /etc/nixos#$old' or rename it in flake.nix."
        fi
        return 0
    fi

    if [[ "$INIT" == systemd ]] && have hostnamectl && sys_run hostnamectl set-hostname "$NEW_HOSTNAME" 2>/dev/null; then
        dry || sub "hostnamectl set-hostname $NEW_HOSTNAME (also writes /etc/hostname)"
    else
        printf '%s\n' "$NEW_HOSTNAME" | sys_write /etc/hostname 644
        sys_run hostname "$NEW_HOSTNAME" 2>/dev/null || info "Could not rename the running system - the new name applies after a reboot."
    fi
    update_etc_hosts "$old" "$NEW_HOSTNAME" | sys_write /etc/hosts 644
    # cloud-init would reset the name at the next boot
    if [[ -d /etc/cloud/cloud.cfg.d ]]; then
        printf '%s\npreserve_hostname: true\n' "$SYS_TAG" | sys_write /etc/cloud/cloud.cfg.d/99-dotfiles-nixish-hostname.cfg 644
    fi
    dry && { SYS_NOTES+=("Hostname: $NEW_HOSTNAME"); return 0; }
    if [[ "$(hostname 2>/dev/null)" == "$NEW_HOSTNAME" || "$(hostname 2>/dev/null)" == "$short" ]]; then
        ok "Hostname is now $(hostname)"
    elif [[ "$(cat /etc/hostname 2>/dev/null)" == "$NEW_HOSTNAME" ]]; then
        ok "Hostname saved in /etc/hostname - active after a reboot (running name: $(hostname))"
    else
        warn "Hostname change could not be verified (hostname: $(hostname))"
    fi
    SYS_NOTES+=("Hostname: $NEW_HOSTNAME")
}

# =============================================================================
#  Network: IP address / subnet / gateway and DNS
# =============================================================================
net_backend() {
    if [[ -n "${DOTFILES_NET_BACKEND:-}" ]]; then echo "$DOTFILES_NET_BACKEND"; return; fi
    if have nmcli && nmcli -t -f RUNNING general 2>/dev/null | grep -q '^running'; then echo nm
    elif $IS_NIXOS; then echo nixos
    elif have netplan && compgen -G '/etc/netplan/*.yaml' >/dev/null; then echo netplan
    elif [[ "$INIT" == systemd ]] && systemctl is-active -q systemd-networkd 2>/dev/null; then echo networkd
    elif have wicked && [[ -d /etc/sysconfig/network ]]; then echo wicked
    elif [[ -f /etc/network/interfaces ]]; then echo ifupdown
    else echo none; fi
}

dns4() { local d o=(); for d in $DNS_LIST; do [[ "$d" == *:* ]] || o+=("$d"); done; echo "${o[*]}"; }
dns6() { local d o=(); for d in $DNS_LIST; do [[ "$d" == *:* ]] && o+=("$d"); done; echo "${o[*]}"; }
csv()  { local IFS=,; echo "$*"; }

# --- NetworkManager
net_nm() {
    local con args=()
    con="$(nmcli -g GENERAL.CONNECTION device show "$NET_IFACE" 2>/dev/null | head -1)"
    if [[ -z "$con" ]]; then
        con="dotfiles-nixish-$NET_IFACE"
        sub "No NetworkManager profile on $NET_IFACE - creating '$con'"
        sys_run nmcli -t connection add type ethernet ifname "$NET_IFACE" con-name "$con" >/dev/null || { warn "nmcli could not create a profile"; return 1; }
    else
        sub "NetworkManager profile on $NET_IFACE: '$con'"
    fi
    if $DO_NET; then
        if [[ "$NET_MODE" == dhcp ]]; then args+=(ipv4.method auto ipv4.addresses "" ipv4.gateway "")
        else args+=(ipv4.method manual ipv4.addresses "$NET_ADDR/$NET_PREFIX" ipv4.gateway "$NET_GW"); fi
    fi
    if [[ -n "$DNS_LIST" ]]; then
        args+=(ipv4.dns "$(dns4 | tr " " ,)" ipv4.ignore-auto-dns yes)
        [[ -n "$(dns6)" ]] && args+=(ipv6.dns "$(dns6 | tr " " ,)" ipv6.ignore-auto-dns yes)
    elif $DO_NET && [[ "$NET_MODE" == dhcp ]]; then
        args+=(ipv4.dns "" ipv4.ignore-auto-dns no)
    fi
    sys_run nmcli connection modify "$con" "${args[@]}" || { warn "nmcli connection modify failed"; return 1; }
    sub "Saved in the NetworkManager profile: ${args[*]}"
    NET_APPLY+=("nmcli connection up $(printf '%q' "$con")")
}

# --- netplan (sequences in later files are APPENDED, so clear the old values first)
netplan_section() {
    local s id
    for s in ethernets wifis bonds bridges vlans; do
        for id in $(sudo_ netplan get "$s" 2>/dev/null | awk -F: '/^[^ #-][^:]*:/ {print $1}'); do
            if [[ "$id" == "$NET_IFACE" || "$(sudo_ netplan get "$s.$id.set-name" 2>/dev/null)" == "$NET_IFACE" ]]; then
                echo "$s.$id"; return; fi
        done
    done
    echo "ethernets.$NET_IFACE"
}

net_netplan() {
    local key f k val dns=""
    if ! netplan set --help >/dev/null 2>&1; then warn "This netplan is too old for 'netplan set' - edit /etc/netplan by hand."; return 1; fi
    key="$(netplan_section)"
    sub "netplan definition: $key"
    if ! dry; then
        for f in /etc/netplan/*.yaml; do sudo_ cp -p "$f" "$f.dotfiles-nixish.bak.$TS"; done
        sub "Backups: /etc/netplan/*.yaml.dotfiles-nixish.bak.$TS"
    fi
    [[ -n "$DNS_LIST" ]] && dns="nameservers: {addresses: [$(csv $DNS_LIST)]}"
    if $DO_NET; then
        for k in addresses routes gateway4 nameservers dhcp4 dhcp4-overrides; do sys_run netplan set "$key.$k=null"; done
        if [[ "$NET_MODE" == dhcp ]]; then
            val="{dhcp4: true${dns:+, dhcp4-overrides: {use-dns: false}, $dns}}"
        else
            val="{dhcp4: false, addresses: [$NET_ADDR/$NET_PREFIX], routes: [{to: default, via: $NET_GW}]${dns:+, $dns}}"
        fi
    else
        sys_run netplan set "$key.nameservers=null"
        val="{$dns}"
        [[ "$(sudo_ netplan get "$key.dhcp4" 2>/dev/null)" == true ]] && val="{dhcp4-overrides: {use-dns: false}, $dns}"
    fi
    sys_run netplan set --origin-hint 90-dotfiles-nixish "$key=$val" || { warn "netplan set failed"; return 1; }
    if ! dry; then
        sudo_ chmod 600 /etc/netplan/*.yaml 2>/dev/null
        if ! sudo_ netplan generate 2>"$WORKDIR/np.err"; then
            warn "netplan rejected the config - restoring the backups: $(head -1 "$WORKDIR/np.err")"
            sudo_ rm -f /etc/netplan/90-dotfiles-nixish.yaml
            for f in /etc/netplan/*.yaml.dotfiles-nixish.bak."$TS"; do sudo_ cp -p "$f" "${f%.dotfiles-nixish.bak.*}"; done
            return 1
        fi
        sub "netplan generate: config is valid"
    fi
    # cloud-init rewrites 50-cloud-init.yaml at boot unless told not to
    if [[ -d /etc/cloud/cloud.cfg.d ]]; then
        printf '%s\nnetwork: {config: disabled}\n' "$SYS_TAG" | sys_write /etc/cloud/cloud.cfg.d/99-dotfiles-nixish-network.cfg 644
    fi
    NET_APPLY+=("netplan apply")
}

# --- systemd-networkd: our 00- file sorts first, so it wins for this interface
net_networkd() {
    local f="/etc/systemd/network/00-dotfiles-nixish-$NET_IFACE.network" cur d body
    cur="$(networkctl status "$NET_IFACE" 2>/dev/null | awk -F': ' '/Network File/ {print $2; exit}')"
    [[ -n "$cur" ]] && sub "Current networkd file for $NET_IFACE: $cur"
    if ! $DO_NET && [[ "$cur" == "$f" ]]; then
        # DNS only, and the interface already uses our file: keep its address settings
        body="$(sudo_ grep -vE '^(DNS=|UseDNS=|\[DHCPv4\])' "$f")"$'\n\n[Network]\n'
        for d in $DNS_LIST; do body+="DNS=$d"$'\n'; done
        grep -q '^DHCP=yes' "$f" && body+=$'\n[DHCPv4]\nUseDNS=no\n'
        printf '%s' "$body" | sys_write "$f" 644
    elif $DO_NET || [[ -z "$cur" ]]; then
        body="$SYS_TAG"$'\n[Match]\nName='"$NET_IFACE"$'\n\n[Network]\n'
        if [[ "$NET_MODE" == dhcp ]] || ! $DO_NET; then
            body+=$'DHCP=yes\n'
        else
            body+="Address=$NET_ADDR/$NET_PREFIX"$'\n'"Gateway=$NET_GW"$'\n'
        fi
        for d in $DNS_LIST; do body+="DNS=$d"$'\n'; done
        if [[ -n "$DNS_LIST" ]] && { [[ "$NET_MODE" == dhcp ]] || ! $DO_NET; }; then body+=$'\n[DHCPv4]\nUseDNS=no\n'; fi
        printf '%s' "$body" | sys_write "$f" 644
    else
        # DNS only: drop-in for the file that already manages the interface
        f="/etc/systemd/network/$(basename "$cur").d/90-dotfiles-nixish-dns.conf"
        body="$SYS_TAG"$'\n[Network]\n'
        for d in $DNS_LIST; do body+="DNS=$d"$'\n'; done
        body+=$'\n[DHCPv4]\nUseDNS=no\n'
        printf '%s' "$body" | sys_write "$f" 644
    fi
    NET_APPLY+=("networkctl reload && networkctl reconfigure $(printf '%q' "$NET_IFACE") || systemctl restart systemd-networkd")
}

# --- ifupdown (/etc/network/interfaces, Debian and Alpine)
net_ifupdown() {
    local f=/etc/network/interfaces cand body autoline="auto $NET_IFACE"
    for cand in /etc/network/interfaces.d/*; do
        [[ -f "$cand" ]] && grep -qE "^[[:space:]]*iface[[:space:]]+${NET_IFACE}[[:space:]]+inet[[:space:]]" "$cand" && { f="$cand"; break; }
    done
    if $DO_NET; then
        sub "Rewriting the '$NET_IFACE' stanza in $f"
        grep -qE "^[[:space:]]*allow-hotplug[[:space:]]+$NET_IFACE\$" "$f" && autoline="allow-hotplug $NET_IFACE"
        if [[ "$NET_MODE" == dhcp ]]; then
            body="$autoline"$'\n'"iface $NET_IFACE inet dhcp"
        else
            body="$autoline"$'\n'"iface $NET_IFACE inet static"$'\n'"    address $NET_ADDR"$'\n'"    netmask $(prefix2mask "$NET_PREFIX")"$'\n'"    gateway $NET_GW"
        fi
        # drop the old auto/allow-hotplug line and the inet (IPv4) stanza; keep inet6 and everything else
        awk -v ifc="$NET_IFACE" -v body="$body" '
            BEGIN { kw = "^(iface|auto|allow-[a-z]+|mapping|source|source-directory|rename)([[:space:]]|$)" }
            $0 ~ kw { skip = 0 }
            ($1 == "auto" || $1 ~ /^allow-/) && NF == 2 && $2 == ifc { next }
            $1 == "iface" && $2 == ifc && $3 == "inet" { skip = 1; if (!done) { print "# dotfiles-nixish"; print body; done = 1 }; next }
            skip { next }
            { print }
            END { if (!done) { print ""; print "# dotfiles-nixish"; print body } }' "$f" | sys_write "$f" 644
        NET_APPLY+=("ifdown $(printf '%q' "$NET_IFACE") 2>/dev/null; ip -4 addr flush dev $(printf '%q' "$NET_IFACE"); ifup $(printf '%q' "$NET_IFACE")")
    fi
    [[ -n "$DNS_LIST" ]] && dns_resolv_conf
}

# --- wicked (openSUSE)
net_wicked() {
    local cfg="/etc/sysconfig/network/ifcfg-$NET_IFACE" rt="/etc/sysconfig/network/ifroute-$NET_IFACE"
    if $DO_NET; then
        { sudo_ cat "$cfg" 2>/dev/null | grep -vE '^(BOOTPROTO|IPADDR|NETMASK|PREFIXLEN|STARTMODE)='
          echo "STARTMODE='auto'"
          if [[ "$NET_MODE" == dhcp ]]; then echo "BOOTPROTO='dhcp'"
          else echo "BOOTPROTO='static'"; echo "IPADDR='$NET_ADDR/$NET_PREFIX'"; fi
        } | sys_write "$cfg" 644
        if [[ "$NET_MODE" == static ]]; then printf 'default %s - %s\n' "$NET_GW" "$NET_IFACE" | sys_write "$rt" 644
        else sys_remove "$rt"; fi
        NET_APPLY+=("wicked ifreload $(printf '%q' "$NET_IFACE")")
    fi
    if [[ -n "$DNS_LIST" ]]; then
        sudo_ sed -E "s|^NETCONFIG_DNS_STATIC_SERVERS=.*|NETCONFIG_DNS_STATIC_SERVERS=\"$DNS_LIST\"|; s|^NETCONFIG_DNS_POLICY=.*|NETCONFIG_DNS_POLICY=\"STATIC_FALLBACK\"|" \
            /etc/sysconfig/network/config | sys_write /etc/sysconfig/network/config 644
        NET_APPLY+=("netconfig update -f")
    fi
}

# --- DNS without a network manager: resolved drop-in, or /etc/resolv.conf
dns_resolv_conf() {
    local d
    if [[ "$INIT" == systemd ]] && systemctl is-active -q systemd-resolved 2>/dev/null; then
        printf '%s\n[Resolve]\nDNS=%s\nDomains=~.\n' "$SYS_TAG" "$DNS_LIST" | sys_write /etc/systemd/resolved.conf.d/90-dotfiles-nixish.conf 644
        NET_APPLY+=("systemctl restart systemd-resolved")
        return 0
    fi
    if [[ -L /etc/resolv.conf ]]; then
        warn "/etc/resolv.conf is a symlink to $(readlink /etc/resolv.conf), managed by another tool - DNS not changed."
        return 1
    fi
    { echo "$SYS_TAG"
      grep -E '^(search|domain|options)[[:space:]]' /etc/resolv.conf 2>/dev/null
      for d in $DNS_LIST; do echo "nameserver $d"; done; } | sys_write /etc/resolv.conf 644
    # stop DHCP clients from overwriting it again
    if [[ -f /etc/dhcp/dhclient.conf ]] && [[ -n "$(dns4)" ]]; then
        { sudo_ grep -v 'dotfiles-nixish' /etc/dhcp/dhclient.conf
          echo "supersede domain-name-servers $(dns4 | sed 's/ /, /g'); # dotfiles-nixish"; } | sys_write /etc/dhcp/dhclient.conf 644
    fi
    if [[ "$PM" == apk ]]; then
        { sudo_ grep -v '^RESOLV_CONF=' /etc/udhcpc/udhcpc.conf 2>/dev/null; echo 'RESOLV_CONF="no"   # dotfiles-nixish'; } \
            | sys_write /etc/udhcpc/udhcpc.conf 644
    fi
}

# --- NixOS without NetworkManager
# Does this NixOS configure its network with systemd-networkd? (the Incus/LXD
# container images do: systemd.network.networks."50-eth0" with DHCP)
nixos_networkd() {
    grep -qsE 'systemd\.network([.[:space:]=]|$)|useNetworkd[[:space:]]*=[[:space:]]*true' /etc/nixos/*.nix \
        || systemctl is-active -q systemd-networkd 2>/dev/null
}

net_nixos() {
    local d list=""
    for d in $DNS_LIST; do list+=" $(nix_str "$d")"; done
    if $DO_NET && nixos_networkd; then
        # networkd uses the first matching .network file in name order, so
        # "10-..." wins over the image's "50-eth0" without editing it
        local n; n="$(nix_str "10-dotfiles-nixish-$NET_IFACE")"
        NIX_PARTS+=("# IPv4 on $NET_IFACE (systemd-networkd; overrides later units such as 50-$NET_IFACE)"
                    "systemd.network.enable = true;"
                    "systemd.network.networks.$n.matchConfig.Name = $(nix_str "$NET_IFACE");"
                    "systemd.network.networks.$n.linkConfig.RequiredForOnline = \"routable\";")
        if [[ "$NET_MODE" == dhcp ]]; then
            NIX_PARTS+=("systemd.network.networks.$n.networkConfig.DHCP = \"ipv4\";")
            [[ -n "$list" ]] && NIX_PARTS+=("systemd.network.networks.$n.dhcpV4Config.UseDNS = false;")
        else
            NIX_PARTS+=("systemd.network.networks.$n.networkConfig.DHCP = \"no\";"
                        "systemd.network.networks.$n.address = [ $(nix_str "$NET_ADDR/$NET_PREFIX") ];"
                        "systemd.network.networks.$n.gateway = [ $(nix_str "$NET_GW") ];")
        fi
        [[ -n "$list" ]] && NIX_PARTS+=("systemd.network.networks.$n.dns = [$list ];" "# DNS" "networking.nameservers = lib.mkForce [$list ];")
        sub "Added the network settings to the NixOS module (systemd-networkd unit 10-dotfiles-nixish-$NET_IFACE)"
        return 0
    fi
    if $DO_NET; then
        NIX_PARTS+=("# IPv4 on $NET_IFACE")
        if [[ "$NET_MODE" == dhcp ]]; then
            NIX_PARTS+=("networking.interfaces.$(nix_str "$NET_IFACE").useDHCP = lib.mkForce true;")
        else
            NIX_PARTS+=(
                "networking.interfaces.$(nix_str "$NET_IFACE").useDHCP = lib.mkForce false;"
                "networking.interfaces.$(nix_str "$NET_IFACE").ipv4.addresses = lib.mkForce [ { address = $(nix_str "$NET_ADDR"); prefixLength = $NET_PREFIX; } ];"
                "networking.defaultGateway = lib.mkForce { address = $(nix_str "$NET_GW"); interface = $(nix_str "$NET_IFACE"); };"
            )
        fi
    fi
    if [[ -n "$DNS_LIST" ]]; then
        NIX_PARTS+=("# DNS" "networking.nameservers = lib.mkForce [$list ];")
        if [[ "$NET_MODE" == dhcp || "$DO_NET" == false ]] && ! nixos_networkd; then
            NIX_PARTS+=("networking.dhcpcd.extraConfig = \"nohook resolv.conf\";")
        fi
    fi
    sub "Added the network settings to the NixOS module"
}

ssh_on_iface() {  # is our own SSH session coming in over this interface?
    local srv; srv="$(awk '{print $3}' <<<"${SSH_CONNECTION:-}")"
    [[ -n "$srv" ]] && ip -o addr show dev "$NET_IFACE" 2>/dev/null | grep -qF " $srv/" && echo "$srv"
}

setup_network() {
    local backend what=() srv
    backend="$(net_backend)"
    $DO_NET && what+=("IP address")
    $DO_DNS && what+=("DNS")
    step "Changing the network settings ($(IFS=/; echo "${what[*]}")) on $NET_IFACE - backend: $backend"
    $DO_NET && sub "New IPv4: $([[ "$NET_MODE" == dhcp ]] && echo "DHCP" || echo "$NET_ADDR/$NET_PREFIX ($(prefix2mask "$NET_PREFIX")), gateway $NET_GW")"
    [[ -n "$DNS_LIST" ]] && sub "DNS servers: $DNS_LIST$($DO_DNS || echo " (kept from the current setup)")"

    if srv="$(ssh_on_iface)" && $DO_NET && { [[ "$NET_MODE" == dhcp ]] || [[ "$srv" != "$NET_ADDR" ]]; }; then
        DROP_RISK=true
        warn "You are connected over SSH to $srv on $NET_IFACE - this session will drop when the change is applied. Reconnect to $([[ "$NET_MODE" == dhcp ]] && echo "the new DHCP address" || echo "$NET_ADDR")."
    fi

    case "$backend" in
        nm)       net_nm ;;
        netplan)  net_netplan ;;
        networkd) net_networkd ;;
        ifupdown) net_ifupdown ;;
        wicked)   net_wicked ;;
        nixos)    net_nixos ;;
        *)        if $DO_NET; then warn "No supported network configuration system found (NetworkManager, netplan, systemd-networkd, ifupdown, wicked) - IP not changed."; fi
                  if [[ -n "$DNS_LIST" ]] && $DO_DNS; then dns_resolv_conf; fi ;;
    esac
}

# activate the network change - detached if it will cut our SSH session
apply_network() {
    [[ ${#NET_APPLY[@]} -gt 0 ]] || return 0
    local s
    if dry; then for s in "${NET_APPLY[@]}"; do sub "[dry-run] would run: $s"; done; return 0; fi
    if [[ -n "${DOTFILES_NO_APPLY:-}" ]]; then
        for s in "${NET_APPLY[@]}"; do sub "(DOTFILES_NO_APPLY) not running: $s"; done; return 0
    fi
    printf '#!/bin/sh\n# dotfiles-nixish: activate the new network settings\n%s\n' "$(printf '%s\n' "${NET_APPLY[@]}")" \
        | sudo_ tee "$NET_APPLY_SCRIPT" >/dev/null && sudo_ chmod 700 "$NET_APPLY_SCRIPT"
    if $DROP_RISK; then
        sudo_ sh -c "setsid nohup sh -c 'sleep 5; sh $NET_APPLY_SCRIPT' >$NET_LOG 2>&1 </dev/null &"
        ok "The new network settings will be applied in 5 seconds (in the background, log: $NET_LOG)"
        return 0
    fi
    sub "Applying: ${NET_APPLY[*]}"
    if sudo_ sh "$NET_APPLY_SCRIPT" >"$WORKDIR/net.log" 2>&1; then ok "Network settings applied"
    else warn "Applying the network settings reported errors: $(tail -2 "$WORKDIR/net.log" | tr '\n' ' ')"; fi
    sleep 3
    verify_network
}

verify_network() {
    local d now
    if $DO_NET && [[ "$NET_MODE" == static ]]; then
        if ip -o -4 addr show dev "$NET_IFACE" 2>/dev/null | grep -qF " $NET_ADDR/$NET_PREFIX"; then ok "$NET_IFACE has $NET_ADDR/$NET_PREFIX"
        else warn "$NET_IFACE does not show $NET_ADDR/$NET_PREFIX yet (now: $(cur_addr "$NET_IFACE"))"; fi
        if [[ "$(cur_gw "$NET_IFACE")" == "$NET_GW" ]]; then ok "Default gateway is $NET_GW"
        else warn "Default gateway is not $NET_GW yet (now: $(cur_gw "$NET_IFACE"))"; fi
    elif $DO_NET; then
        now="$(cur_addr "$NET_IFACE")"
        [[ -n "$now" ]] && ok "$NET_IFACE got $now via DHCP" || warn "$NET_IFACE has no IPv4 address yet (DHCP may still be running)"
    fi
    if $DO_DNS; then
        now=" $(cur_dns) "
        for d in $DNS_LIST; do [[ "$now" == *" $d "* ]] || { warn "DNS server $d is not active yet (now:$now)"; return 0; }; done
        ok "DNS servers active: $DNS_LIST"
    fi
}

# =============================================================================
#  NixOS: write the module, import it, rebuild
# =============================================================================
nixos_import() {  # add ./dotfiles-nixish-system.nix to configuration.nix imports
    local cfg=/etc/nixos/configuration.nix
    grep -q 'dotfiles-nixish-system\.nix' "$cfg" 2>/dev/null && { sub "configuration.nix already imports it"; return 0; }
    [[ -f "$cfg" ]] || { warn "$cfg not found - add ./dotfiles-nixish-system.nix to your configuration by hand."; return 1; }
    awk '
        !done && /^[[:space:]]*imports[[:space:]]*=/ { want = 1 }
        want && !done && /\[/ {
            if ($0 ~ /\]/) { sub(/\[/, "[ ./dotfiles-nixish-system.nix"); print; done = 1; next }
            print; print "      ./dotfiles-nixish-system.nix  # added by dotfiles-nixish"; done = 1; next }
        { print }
        END { if (!done) exit 3 }' "$cfg" > "$WORKDIR/cfg.nix"
    if [[ $? -eq 3 ]]; then   # no imports list: add one right after the opening brace of the module
        awk '!done && /^[[:space:]]*\{[[:space:]]*$/ && seen { print; print "  imports = [ ./dotfiles-nixish-system.nix ];  # added by dotfiles-nixish"; done = 1; next }
             /\}[[:space:]]*:/ { seen = 1 } { print }' "$cfg" > "$WORKDIR/cfg.nix"
    fi
    local rc=0; nix_parse "$WORKDIR/cfg.nix" || rc=$?
    if ! grep -q 'dotfiles-nixish-system\.nix' "$WORKDIR/cfg.nix" || [[ $rc -eq 1 ]]; then
        warn "Could not add the import automatically - add ./dotfiles-nixish-system.nix to 'imports' in $cfg."
        return 1
    fi
    sys_write "$cfg" 644 < "$WORKDIR/cfg.nix"
}

# Relative files imported by configuration.nix that do not exist break every
# nixos-rebuild. The Incus/LXD NixOS images import ./incus.nix (or ./lxd.nix),
# which only Incus/LXD generate when the container is created - Proxmox never
# does, so nixos-rebuild fails there out of the box. Recreate that one file
# (same content Incus would write); stop for anything else.
NIX_STUBS=()
nixos_check_imports() {
    local cfg=/etc/nixos/configuration.nix rel f bad=() host
    [[ -f "$cfg" ]] || return 0
    while IFS= read -r rel; do
        [[ "$rel" == ./dotfiles-nixish-system.nix ]] && continue
        f="/etc/nixos/${rel#./}"
        [[ -e "$f" ]] && continue
        case "${rel##*/}" in
            incus.nix|lxd.nix)
                host="$(hostname 2>/dev/null || echo nixos)"
                sub "configuration.nix imports $rel, which is missing. Incus/LXD create it when the"
                sub "container is made, Proxmox does not - so nixos-rebuild could not work here yet."
                printf '%s\n# Normally generated by Incus/LXD from its container template.\n{ lib, ... }:\n{\n  networking.hostName = lib.mkDefault %s;\n}\n' \
                    "$SYS_TAG" "$(nix_str "$host")" | sys_write "$f" 644 || return 1
                dry || ok "Recreated $f (keeps the hostname \"$host\")"
                NIX_STUBS+=("$f") ;;
            *) bad+=("$rel") ;;
        esac
    done < <(sed 's/#.*//' "$cfg" | grep -oE '\./[A-Za-z0-9._/+-]+' | sort -u)
    if [[ ${#bad[@]} -gt 0 ]]; then
        warn "Your configuration.nix imports ${bad[*]}, which does not exist - nixos-rebuild fails even without dotfiles-nixish. Fix that, then re-run. Nothing was changed."
        return 1
    fi
}

nixos_not_applied() {  # list the settings that needed nixos-rebuild
    local l=()
    $DO_USER && l+=("user $NEW_USER (NixOS entry only - the account itself was created)")
    $DO_SSH && l+=("SSH"); $DO_HOST && l+=("hostname")
    [[ "$(net_backend)" == nixos ]] && { $DO_NET && l+=("IP address"); $DO_DNS && l+=("DNS"); }
    local IFS=','; echo "${l[*]}" | sed 's/,/, /g'
}

nixos_undo() {  # put /etc/nixos back exactly as it was before this run
    dry && return 0
    local f
    for f in /etc/nixos/configuration.nix "$NIX_SYS_FILE" "${NIX_STUBS[@]}"; do restore_backup "$f"; done
}

NIX_STATE=""   # ok | failed | background | manual | dry ("" = nothing for NixOS)
nixos_apply() {
    [[ ${#NIX_PARTS[@]} -gt 0 ]] || return 0
    step "Applying the system settings on NixOS (declaratively)"
    local body l
    NIX_STATE=failed
    body="$SYS_TAG"$'\n# Imported from configuration.nix. Delete the import line to undo.\n{ lib, ... }:\n{\n'
    for l in "${NIX_PARTS[@]}"; do body+="  $l"$'\n'; done
    body+=$'}\n'
    printf '%s' "$body" > "$WORKDIR/module.nix"
    local prc=0; nix_parse "$WORKDIR/module.nix" || prc=$?
    case $prc in
        0) sub "Generated module parses (nix-instantiate --parse)" ;;
        1) warn "Generated Nix module does not parse - nothing changed (please report this bug): $NIX_PARSE_ERR"; return 1 ;;
        *) sub "Could not run nix-instantiate --parse - nixos-rebuild will check the module" ;;
    esac
    nixos_check_imports || { nixos_undo; return 1; }
    printf '%s' "$body" | sys_write "$NIX_SYS_FILE" 644 || { nixos_undo; return 1; }
    if [[ -f /etc/nixos/flake.nix ]] && ! grep -q 'configuration\.nix' /etc/nixos/flake.nix; then
        warn "Your flake.nix does not use configuration.nix - add ./dotfiles-nixish-system.nix to its modules list, then run: sudo nixos-rebuild switch"
        NIX_STATE=manual; return 0
    fi
    nixos_import || { nixos_undo; NIX_STATE=manual; return 0; }
    # flakes only see files git knows about
    if [[ -f /etc/nixos/flake.nix && -d /etc/nixos/.git ]]; then
        sys_run git -C /etc/nixos add dotfiles-nixish-system.nix && sub "git add dotfiles-nixish-system.nix (flakes only see tracked files)"
    fi
    if dry; then sub "[dry-run] would run: nixos-rebuild switch"; NIX_STATE=dry; return 0; fi
    if $DROP_RISK; then
        sudo_ sh -c "setsid nohup nixos-rebuild switch >$NET_LOG 2>&1 </dev/null &"
        ok "nixos-rebuild switch is running in the background (log: $NET_LOG) - your SSH session will drop"
        NIX_STATE=background; return 0
    fi
    sub "Running nixos-rebuild switch (this can take a few minutes)..."
    local log=/var/log/dotfiles-nixish-rebuild.log
    if sudo_ nixos-rebuild switch >"$WORKDIR/rebuild.log" 2>&1; then
        ok "nixos-rebuild switch finished"
        NIX_STATE=ok
    else
        sudo_ cp "$WORKDIR/rebuild.log" "$log" 2>/dev/null || log="$WORKDIR/rebuild.log"
        warn "nixos-rebuild failed - the running system was not changed. Not applied: $(nixos_not_applied). Full log: $log"
        sub "Errors:"
        { grep -E '^[[:space:]]*error:' "$WORKDIR/rebuild.log" || tail -3 "$WORKDIR/rebuild.log"; } \
            | sed 's/^[[:space:]]*//' | awk '!seen[$0]++' | head -5 | sed 's/^/        /'
        sub "Undoing the config edits"
        nixos_undo
        # tell the user whose problem it is: does their own config build without us?
        sub "Checking whether the configuration as it was before this run builds..."
        if sudo_ nixos-rebuild dry-build >"$WORKDIR/dry.log" 2>&1; then
            info "It does - so the new settings caused the failure. Please report it with $log"
        else
            warn "Your NixOS configuration did not build before this run either - 'sudo nixos-rebuild switch' fails the same way. Fix it first, then re-run."
        fi
        return 1
    fi
    # verify what we asked for
    if $DO_SSH; then
        if systemctl is-active -q sshd 2>/dev/null && port_open 22; then ok "sshd is running and accepting connections on port 22"
        else warn "sshd is not answering on port 22 - check: systemctl status sshd"; fi
        SYS_NOTES+=("SSH: ssh $TARGET_USER@<this-host>  (root login off, passwords: ${SSH_NOTE_PW:-yes})")
    fi
    if $DO_HOST; then
        [[ "$(hostname)" == "${NEW_HOSTNAME%%.*}" || "$(hostname)" == "$NEW_HOSTNAME" ]] && ok "Hostname is now $(hostname)" \
            || warn "Hostname is still $(hostname) - it may need a reboot"
        SYS_NOTES+=("Hostname: $NEW_HOSTNAME")
    fi
    if [[ "$(net_backend)" == nixos ]] && { $DO_NET || $DO_DNS; }; then sleep 3; verify_network; fi
}

# =============================================================================
#  Entry point
# =============================================================================
system_setup() {
    $DO_USER && setup_user
    $DO_SSH  && setup_ssh
    $DO_HOST && setup_hostname
    if $DO_NET || $DO_DNS; then setup_network; fi
    nixos_apply
    apply_network
    # on NixOS the network only changes if nixos-rebuild did its job
    local tail=""
    if [[ "$(net_backend)" == nixos ]]; then
        case "$NIX_STATE" in
            ok|dry) ;;
            background) tail="  (being applied in the background)" ;;
            *) return 0 ;;
        esac
    fi
    if $DO_NET; then
        if [[ "$NET_MODE" == dhcp ]]; then SYS_NOTES+=("Network: $NET_IFACE uses DHCP$tail")
        else SYS_NOTES+=("Network: $NET_IFACE $NET_ADDR/$NET_PREFIX via $NET_GW$tail"); fi
    fi
    $DO_DNS && SYS_NOTES+=("DNS: $DNS_LIST$tail")
    return 0
}
