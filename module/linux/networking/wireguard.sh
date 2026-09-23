#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

print_banner() {
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║             WIREGUARD SETUP & MANAGEMENT TOOL                     ║${RESET}"
    echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_separator() {
    echo -e "${DIM}─────────────────────────────────────────────────────────────────────${RESET}"
}

log_info()    { echo -e "  ${BLUE}${BOLD}[INFO]${RESET}    $1"; }
log_success() { echo -e "  ${GREEN}${BOLD}[OK]${RESET}      $1"; }
log_warn()    { echo -e "  ${YELLOW}${BOLD}[WARN]${RESET}    $1"; }
log_error()   { echo -e "  ${RED}${BOLD}[ERROR]${RESET}   $1"; }

# Check if input indicates user wants to cancel
is_cancel() {
    local val="$1"
    [[ "$val" =~ ^(c|cancel|C|CANCEL|q|quit|Q|QUIT|exit|EXIT)$ ]]
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root. Use: sudo bash $0"
        exit 1
    fi
}

check_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
        UPDATE_CMD=(apt-get update -y)
        INSTALL_CMD=(apt-get install wireguard wireguard-tools -y)
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        UPDATE_CMD=(dnf check-update)
        INSTALL_CMD=(dnf install wireguard-tools -y)
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        UPDATE_CMD=(yum check-update)
        INSTALL_CMD=(yum install wireguard-tools -y)
    else
        log_error "No supported package manager (apt, dnf, yum) found."
        return 1
    fi
}

install_wireguard() {
    log_info "Checking package manager..."
    if ! check_package_manager; then
        return
    fi

    log_info "Installing WireGuard using $PKG_MANAGER..."
    # BUG FIX: commands were stored as plain strings and invoked unquoted
    # ($UPDATE_CMD), which relies on word-splitting to work at all and
    # breaks the moment a package name needs quoting. Arrays + "${..[@]}"
    # expand safely regardless of contents.
    "${UPDATE_CMD[@]}"
    "${INSTALL_CMD[@]}"

    if command -v wg &> /dev/null; then
        log_success "WireGuard installed successfully!"
        if [ "$PKG_MANAGER" = "dnf" ] || [ "$PKG_MANAGER" = "yum" ]; then
            if ! modprobe wireguard 2>/dev/null && [ ! -e /sys/module/wireguard ]; then
                log_warn "The wireguard kernel module could not be loaded."
                log_warn "On older RHEL/CentOS kernels (< 5.6) this usually means the"
                log_warn "kernel module is missing - install kmod-wireguard (ELRepo) or"
                log_warn "upgrade the kernel, then try bringing the interface up again."
            fi
        fi
    else
        log_error "Failed to install WireGuard."
    fi
}

generate_keys() {
    if ! command -v wg &> /dev/null; then
        log_error "WireGuard is not installed. Please install it first."
        return
    fi

    local key_dir="/etc/wireguard/keys"
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"

    if [ -f "$key_dir/privatekey" ]; then
        log_warn "An existing keypair was found in $key_dir."
        log_warn "Overwriting it will break any peer still configured with the old public key."
        read -rp "  Overwrite the existing keypair? [y/N]: " OVERWRITE_KEYS
        if [[ ! "$OVERWRITE_KEYS" =~ ^[Yy]$ ]]; then
            log_info "Keeping existing keypair. No changes made."
            return
        fi
    fi

    log_info "Generating new keypair (Private & Public Key)..."
    local privkey
    local pubkey

    privkey=$(wg genkey)
    if [ -z "$privkey" ]; then
        log_error "wg genkey failed to produce a private key (is the wireguard kernel module loaded?)."
        return 1
    fi
    pubkey=$(echo "$privkey" | wg pubkey)
    if [ -z "$pubkey" ]; then
        log_error "wg pubkey failed to derive a public key from the generated private key."
        return 1
    fi

    echo "$privkey" > "$key_dir/privatekey"
    echo "$pubkey" > "$key_dir/publickey"
    chmod 600 "$key_dir/privatekey"
    chmod 644 "$key_dir/publickey"

    print_separator
    log_success "Keypair generated successfully and saved in $key_dir:"
    echo -e "  ${BOLD}Private Key :${RESET} $privkey"
    echo -e "  ${BOLD}Public Key  :${RESET} $pubkey"
    print_separator
}

# Validates an IPv4 CIDR like 10.0.0.1/24 (octets 0-255, prefix 0-32).
is_valid_cidr() {
    local val="$1"
    [[ "$val" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]] || return 1
    local o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}" o3="${BASH_REMATCH[3]}" o4="${BASH_REMATCH[4]}" prefix="${BASH_REMATCH[5]}"
    for o in "$o1" "$o2" "$o3" "$o4"; do
        [ "$o" -le 255 ] || return 1
    done
    [ "$prefix" -le 32 ] || return 1
    return 0
}

# Validates a TCP/UDP port number (1-65535).
is_valid_port() {
    local val="$1"
    [[ "$val" =~ ^[0-9]+$ ]] || return 1
    [ "$val" -ge 1 ] && [ "$val" -le 65535 ]
}

# Validates a WireGuard key: base64, 44 chars, padded with a single '='.
is_valid_wg_key() {
    local val="$1"
    [[ "$val" =~ ^[A-Za-z0-9+/]{43}=$ ]]
}

# Validates an interface name: safe to use as a bare filename component.
is_valid_iface_name() {
    local val="$1"
    [[ "$val" =~ ^[A-Za-z0-9_-]{1,15}$ ]]
}

# Checks whether a WireGuard interface is currently up (present in `wg show`).
is_interface_active() {
    local iface="$1"
    command -v wg &> /dev/null || return 1
    wg show "$iface" &> /dev/null
}

configure_wireguard() {
    log_info "WireGuard Interface Configuration"
    print_separator

    read -rp "  Interface Name [default: wg0]: " IFACE
    IFACE=${IFACE:-wg0}
    if ! is_valid_iface_name "$IFACE"; then
        log_error "Invalid interface name. Use letters, numbers, '-' or '_' only (max 15 chars)."
        return 1
    fi

    local CONF_FILE="/etc/wireguard/${IFACE}.conf"
    local EXISTING_IP=""
    local EXISTING_PORT=""
    local EXISTING_KEY=""
    local PEERS=""

    # Check if configuration file already exists
    if [ -f "$CONF_FILE" ]; then
        log_warn "Configuration file '$CONF_FILE' already exists."
        EXISTING_IP=$(grep -i "^\s*Address" "$CONF_FILE" | cut -d'=' -f2- | xargs)
        EXISTING_PORT=$(grep -i "^\s*ListenPort" "$CONF_FILE" | cut -d'=' -f2- | xargs)
        EXISTING_KEY=$(grep -i "^\s*PrivateKey" "$CONF_FILE" | cut -d'=' -f2- | xargs)
        PEERS=$(sed -n '/^\[Peer\]/,$p' "$CONF_FILE")

        # BUG FIX: values read from an existing file were trusted as-is and
        # fed straight back in as defaults with no re-validation. A hand-edited
        # or corrupted file (bad port, malformed key) would silently propagate.
        if [ -n "$EXISTING_PORT" ] && ! is_valid_port "$EXISTING_PORT"; then
            log_warn "Existing ListenPort ('$EXISTING_PORT') in $CONF_FILE is invalid - ignoring it."
            EXISTING_PORT=""
        fi
        if [ -n "$EXISTING_KEY" ] && ! is_valid_wg_key "$EXISTING_KEY"; then
            log_warn "Existing PrivateKey in $CONF_FILE does not look valid - ignoring it."
            EXISTING_KEY=""
        fi
        if [ -n "$EXISTING_IP" ] && ! is_valid_cidr "$EXISTING_IP"; then
            log_warn "Existing Address ('$EXISTING_IP') in $CONF_FILE is invalid - ignoring it."
            EXISTING_IP=""
        fi

        if [ -n "$EXISTING_IP" ]; then
            log_info "Current IP Address: $EXISTING_IP"
        fi

        # BUG FIX: this prompt was the only one in the script with no cancel
        # path - is_cancel() existed but wasn't checked here, so typing 'c'
        # just fell through to "overwrite" instead of aborting like every
        # other prompt in the wizard.
        read -rp "  Do you want to edit or overwrite this configuration? [Y/n/c]: " MODIFY_CONF
        if is_cancel "$MODIFY_CONF"; then
            log_warn "Cancelled. No changes made."
            return
        fi
        if [[ "$MODIFY_CONF" =~ ^([Nn]|[Nn][Oo]|[Tt]idak)$ ]]; then
            log_info "Configuration update cancelled."
            return
        fi

        # BUG FIX: editing the [Interface] section of a config belonging to
        # an interface that is currently UP silently desynced the running
        # kernel state from the file - wg-quick had already loaded the old
        # values, and nothing here re-applied the new ones. The user had no
        # indication their change wasn't live yet.
        if is_interface_active "$IFACE"; then
            log_warn "Interface '$IFACE' is currently UP. The running tunnel will keep using"
            log_warn "the OLD settings until you bring it down and up again (menu option 6),"
            log_warn "or run: wg syncconf $IFACE <(wg-quick strip $IFACE)"
        fi
    fi

    # Prompt for IP Address & Subnet (with existing IP as default option if present)
    while true; do
        if [ -n "$EXISTING_IP" ]; then
            read -rp "  IP Address & Subnet [current: $EXISTING_IP]: " ADDRESS
            ADDRESS=${ADDRESS:-$EXISTING_IP}
        else
            read -rp "  IP Address & Subnet (e.g., 10.0.0.1/24): " ADDRESS
        fi

        if is_cancel "$ADDRESS" || [ -z "$ADDRESS" ]; then
            log_warn "Configuration setup cancelled."
            return
        fi

        if is_valid_cidr "$ADDRESS"; then
            break
        fi
        log_error "Invalid format. Expected an IPv4 address with a subnet prefix, e.g. 10.0.0.1/24."
    done

    # Prompt for Port
    local DEFAULT_PORT="${EXISTING_PORT:-51820}"
    while true; do
        read -rp "  Listen Port [default: $DEFAULT_PORT]: " PORT
        PORT=${PORT:-$DEFAULT_PORT}
        if is_valid_port "$PORT"; then
            break
        fi
        log_error "Invalid port. Enter a number between 1 and 65535."
    done

    # Check for Private Key
    local PRIV_KEY="$EXISTING_KEY"
    if [ -z "$PRIV_KEY" ] && [ -f "/etc/wireguard/keys/privatekey" ]; then
        read -rp "  Use Private Key from /etc/wireguard/keys/privatekey? [Y/n]: " USE_EXISTING
        if [[ "$USE_EXISTING" =~ ^[Yy]$ ]] || [ -z "$USE_EXISTING" ]; then
            PRIV_KEY=$(cat /etc/wireguard/keys/privatekey)
            if [ -z "$PRIV_KEY" ]; then
                log_warn "/etc/wireguard/keys/privatekey exists but is empty; ignoring it."
            fi
        fi
    fi

    if [ -z "$PRIV_KEY" ]; then
        while true; do
            read -rp "  Enter Private Key manually (leave blank to generate automatically): " PRIV_KEY
            if [ -z "$PRIV_KEY" ]; then
                PRIV_KEY=$(wg genkey)
                if [ -z "$PRIV_KEY" ]; then
                    log_error "wg genkey failed to produce a private key (is the wireguard kernel module loaded?)."
                    return 1
                fi
                log_info "Private Key generated automatically."
                break
            fi
            if is_valid_wg_key "$PRIV_KEY"; then
                break
            fi
            log_error "That doesn't look like a valid WireGuard key (expected 44-char base64, e.g. ending in '=')."
        done
    fi

    # Write [Interface] section
    cat <<EOF > "$CONF_FILE"
[Interface]
PrivateKey = $PRIV_KEY
Address = $ADDRESS
ListenPort = $PORT

EOF

    # Re-append any existing [Peer] configurations if available
    if [ -n "$PEERS" ]; then
        echo "$PEERS" >> "$CONF_FILE"
        log_info "Preserved existing [Peer] configuration(s)."
    else
        echo "# Add [Peer] section below as needed" >> "$CONF_FILE"
    fi

    chmod 600 "$CONF_FILE"
    log_success "Configuration file saved successfully at: $CONF_FILE"
    log_info "Configured IP Address: $ADDRESS"
}

# Validates an AllowedIPs value: one or more comma-separated IPv4 CIDRs,
# e.g. "10.10.10.2/32" or "10.10.10.0/24, 192.168.100.0/24".
is_valid_allowed_ips() {
    local val="$1" entry
    [ -n "$val" ] || return 1
    IFS=',' read -ra _entries <<< "$val"
    for entry in "${_entries[@]}"; do
        entry="$(echo "$entry" | xargs)"
        is_valid_cidr "$entry" || return 1
    done
    return 0
}

# Validates an Endpoint value: host:port, where host is an IPv4 address or
# a hostname/FQDN (DDNS is common for home servers behind dynamic IPs).
is_valid_endpoint() {
    local val="$1" host port
    [[ "$val" == *:* ]] || return 1
    port="${val##*:}"
    host="${val%:*}"
    [ -n "$host" ] || return 1
    is_valid_port "$port" || return 1
    if [[ "$host" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        is_valid_cidr "${host}/32" && return 0
        return 1
    fi
    # Hostname/FQDN: labels of letters/digits/hyphen, dot-separated.
    [[ "$host" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

# Adds a [Peer] block to an existing interface config. Works for both
# directions: a server adding a client peer, or a client adding the server
# as its peer - the only difference is which fields are prompted for.
add_peer() {
    log_info "Add WireGuard Peer"
    print_separator

    read -rp "  Interface Name to add the peer to [default: wg0]: " IFACE
    IFACE=${IFACE:-wg0}
    if ! is_valid_iface_name "$IFACE"; then
        log_error "Invalid interface name. Use letters, numbers, '-' or '_' only (max 15 chars)."
        return 1
    fi

    local CONF_FILE="/etc/wireguard/${IFACE}.conf"
    if [ ! -f "$CONF_FILE" ]; then
        log_error "No config found at $CONF_FILE - create the interface first (option 3)."
        return 1
    fi

    echo ""
    echo "  Which role is this machine playing for this peer?"
    echo "    1) Server side - adding a CLIENT as a peer"
    echo "    2) Client side - adding the SERVER as this machine's peer"
    read -rp "  Select [1-2, or 'c' to cancel]: " ROLE
    is_cancel "$ROLE" && { log_warn "Cancelled."; return 1; }
    case "$ROLE" in
        1) ;;
        2) ;;
        *) log_error "Invalid option."; return 1 ;;
    esac

    # --- Public key of the peer (always required) ---
    local PEER_PUBKEY
    while true; do
        read -rp "  Peer's Public Key: " PEER_PUBKEY
        is_cancel "$PEER_PUBKEY" && { log_warn "Cancelled."; return 1; }
        if is_valid_wg_key "$PEER_PUBKEY"; then
            break
        fi
        log_error "That doesn't look like a valid WireGuard key (expected 44-char base64, e.g. ending in '=')."
    done

    # Guard against adding the same peer twice - PublicKey is the identity
    # WireGuard itself keys off, so a duplicate silently confuses `wg show`.
    if grep -qF "$PEER_PUBKEY" "$CONF_FILE" 2>/dev/null; then
        log_warn "A peer with this public key already exists in $CONF_FILE."
        read -rp "  Add it again anyway? [y/N]: " DUP_OK
        if [[ ! "$DUP_OK" =~ ^[Yy]$ ]]; then
            log_info "Cancelled - no duplicate added."
            return 0
        fi
    fi

    # --- AllowedIPs (always required, meaning differs by role) ---
    local ALLOWED_IPS DEFAULT_ALLOWED=""
    if [ "$ROLE" = "1" ]; then
        echo "  (Server side: this is usually the client's tunnel IP, e.g. 10.10.10.2/32)"
    else
        echo "  (Client side: use 0.0.0.0/0 for full-tunnel, or specific subnets for split-tunnel,"
        echo "   e.g. 10.10.10.0/24, 192.168.100.0/24)"
        DEFAULT_ALLOWED="0.0.0.0/0"
    fi
    while true; do
        if [ -n "$DEFAULT_ALLOWED" ]; then
            read -rp "  AllowedIPs [default: $DEFAULT_ALLOWED]: " ALLOWED_IPS
            ALLOWED_IPS=${ALLOWED_IPS:-$DEFAULT_ALLOWED}
        else
            read -rp "  AllowedIPs (e.g. 10.10.10.2/32): " ALLOWED_IPS
        fi
        is_cancel "$ALLOWED_IPS" && { log_warn "Cancelled."; return 1; }
        if is_valid_allowed_ips "$ALLOWED_IPS"; then
            break
        fi
        log_error "Invalid format. Expected one or more comma-separated IPv4 CIDRs."
    done

    # --- Endpoint (only meaningful when THIS machine is the client) ---
    local ENDPOINT="" KEEPALIVE=""
    if [ "$ROLE" = "2" ]; then
        while true; do
            read -rp "  Server Endpoint (host_or_ip:port, e.g. 203.0.113.5:51820): " ENDPOINT
            is_cancel "$ENDPOINT" && { log_warn "Cancelled."; return 1; }
            if is_valid_endpoint "$ENDPOINT"; then
                break
            fi
            log_error "Invalid format. Expected host_or_ip:port with a valid port (1-65535)."
        done
        read -rp "  PersistentKeepalive in seconds [default: 25, blank to omit]: " KEEPALIVE
        if [ -n "$KEEPALIVE" ] && ! [[ "$KEEPALIVE" =~ ^[0-9]+$ ]]; then
            log_warn "'$KEEPALIVE' is not a number - omitting PersistentKeepalive."
            KEEPALIVE=""
        fi
        [ -z "$KEEPALIVE" ] && KEEPALIVE="25"
    else
        read -rp "  PersistentKeepalive in seconds [blank to omit, common if this client is behind NAT]: " KEEPALIVE
        if [ -n "$KEEPALIVE" ] && ! [[ "$KEEPALIVE" =~ ^[0-9]+$ ]]; then
            log_warn "'$KEEPALIVE' is not a number - omitting PersistentKeepalive."
            KEEPALIVE=""
        fi
    fi

    # --- Build and append the [Peer] block ---
    {
        echo ""
        echo "[Peer]"
        echo "PublicKey = $PEER_PUBKEY"
        echo "AllowedIPs = $ALLOWED_IPS"
        [ -n "$ENDPOINT" ] && echo "Endpoint = $ENDPOINT"
        [ -n "$KEEPALIVE" ] && echo "PersistentKeepalive = $KEEPALIVE"
    } >> "$CONF_FILE"

    chmod 600 "$CONF_FILE"
    log_success "Peer added to $CONF_FILE."

    if is_interface_active "$IFACE"; then
        log_warn "Interface '$IFACE' is currently UP - the new peer is not live yet."
        read -rp "  Apply it now without restarting the tunnel? [Y/n]: " SYNC_NOW
        if [[ ! "$SYNC_NOW" =~ ^[Nn]$ ]]; then
            if wg syncconf "$IFACE" <(wg-quick strip "$IFACE") 2>/dev/null; then
                log_success "Peer applied live via 'wg syncconf' - no downtime."
            else
                log_error "'wg syncconf' failed. Bring the interface down/up manually (menu option 6) to apply it."
            fi
        else
            log_info "Remember to bring '$IFACE' down and up again (menu option 6) to apply the new peer."
        fi
    fi
}

check_status() {
    if ! command -v wg &> /dev/null; then
        log_error "WireGuard is not installed."
        return
    fi

    log_info "WireGuard Interface Status (wg show):"
    print_separator
    wg show
    print_separator

    log_info "Available Configuration Files in /etc/wireguard/:"
    ls -l /etc/wireguard/*.conf 2>/dev/null || echo "  (No .conf files found)"
}

toggle_interface() {
    if ! command -v wg-quick &> /dev/null; then
        log_error "wg-quick command not found. Ensure WireGuard is installed."
        return
    fi

    log_info "Manage WireGuard Interface"
    print_separator
    read -rp "  Enter Interface Name [default: wg0]: " IFACE
    IFACE=${IFACE:-wg0}
    if ! is_valid_iface_name "$IFACE"; then
        log_error "Invalid interface name. Use letters, numbers, '-' or '_' only (max 15 chars)."
        return
    fi

    if [ ! -f "/etc/wireguard/${IFACE}.conf" ]; then
        log_error "No config found at /etc/wireguard/${IFACE}.conf - create it first (option 3)."
        return
    fi

    echo "  1) Enable / Up"
    echo "  2) Disable / Down"
    read -rp "  Select Action [1-2, or 'c' to cancel]: " ACT

    # BUG FIX: unquoted `case $ACT in` is subject to word-splitting/globbing
    # on the case subject. Low-risk with a `read` result in practice, but
    # inconsistent with the quoting discipline used everywhere else in this
    # script - quoted here for correctness.
    case "$ACT" in
        1)
            log_info "Bringing up interface $IFACE..."
            wg-quick up "$IFACE" && log_success "Interface $IFACE brought up successfully!" || log_error "Failed to bring up $IFACE."
            ;;
        2)
            log_info "Bringing down interface $IFACE..."
            wg-quick down "$IFACE" && log_success "Interface $IFACE brought down successfully!" || log_error "Failed to bring down $IFACE."
            ;;
        c|C|cancel|CANCEL|q|Q)
            log_warn "Cancelled."
            ;;
        *)
            log_warn "Invalid option."
            ;;
    esac
}

main_menu() {
    check_root

    while true; do
        clear
        print_banner
        echo -e "  ${BOLD}1.${RESET} Install WireGuard"
        echo -e "  ${BOLD}2.${RESET} Generate Keys (Private & Public Key)"
        echo -e "  ${BOLD}3.${RESET} Create / Edit Interface Configuration"
        echo -e "  ${BOLD}4.${RESET} Add Peer (client or server)"
        echo -e "  ${BOLD}5.${RESET} Check Status & Configuration"
        echo -e "  ${BOLD}6.${RESET} Bring Up / Down WireGuard Interface"
        echo -e "  ${BOLD}0.${RESET} Exit"
        print_separator

        read -rp "  Select Option [0-6]: " OPT

        # BUG FIX: unquoted `case $OPT in` - quoted for consistency, same
        # class of issue as the one fixed in toggle_interface.
        case "$OPT" in
            1)
                install_wireguard
                ;;
            2)
                generate_keys
                ;;
            3)
                configure_wireguard
                ;;
            4)
                add_peer
                ;;
            5)
                check_status
                ;;
            6)
                toggle_interface
                ;;
            0)
                log_info "Exiting script. Goodbye!"
                exit 0
                ;;
            *)
                log_warn "Invalid option!"
                ;;
        esac

        echo ""
        read -rp "  Press Enter to return to menu..." temp
    done
}

main_menu
