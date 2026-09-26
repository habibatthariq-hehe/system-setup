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
    echo -e "  ${YELLOW}${BOLD}WHAT TO DO WITH EACH KEY - read this before continuing:${RESET}"
    echo -e "  ${BOLD}Private Key${RESET} -> stays on THIS machine only. Never share it, never"
    echo -e "                  paste it into the other machine's config. Option 3"
    echo -e "                  (Create/Edit Interface Configuration) will use this"
    echo -e "                  automatically when you choose 'use existing key'."
    echo -e "  ${BOLD}Public Key${RESET}  -> hand this to the OTHER machine. If you're setting up"
    echo -e "                  the server, send this to whoever configures the client"
    echo -e "                  (and vice versa) - option 4 (Add Peer) on the OTHER"
    echo -e "                  machine will ask for it as 'Peer's Public Key'."
    echo ""
    echo -e "  ${DIM}Each machine (server and every client) must run this option ONCE for"
    echo -e "  itself, with its own separate keypair. Never copy a privatekey file or"
    echo -e "  reuse the same keypair across two machines - if both sides show the same"
    echo -e "  public key in 'wg show', that's the bug, not a coincidence.${RESET}"
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

    read -rp "  Interface Name [default: wg0, or 'c' to cancel]: " IFACE
    if is_cancel "$IFACE"; then
        log_warn "Cancelled. No changes made."
        return 1
    fi
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
            log_warn "Interface '$IFACE' is currently UP. Address/ListenPort changes need a full"
            log_warn "restart to take effect - 'wg syncconf' does NOT apply these, only [Peer]"
            log_warn "changes. Bring it down and up again after saving (menu option 7)."
        fi
    fi

    # Prompt for IP Address & Subnet (with existing IP as default option if present)
    echo -e "  ${DIM}This is the tunnel IP for THIS machine only - the address wg0 will have on"
    echo -e "  this interface. Every machine in the same VPN (server and every client)"
    echo -e "  needs a DIFFERENT IP in the SAME subnet, e.g. server 10.10.10.1/24,"
    echo -e "  client A 10.10.10.2/24, client B 10.10.10.3/24.${RESET}"
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
    echo -e "  ${DIM}The UDP port THIS machine listens on for WireGuard traffic. On a server,"
    echo -e "  this must be reachable from outside (open in the firewall, forwarded on the"
    echo -e "  router if behind NAT) since clients connect to it via the Endpoint you'll"
    echo -e "  set up on their side. On a client, it rarely matters - it doesn't need to"
    echo -e "  match the server's port, and the default is fine unless you have a reason"
    echo -e "  to change it.${RESET}"
    local DEFAULT_PORT="${EXISTING_PORT:-51820}"
    while true; do
        read -rp "  Listen Port [default: $DEFAULT_PORT, or 'c' to cancel]: " PORT
        if is_cancel "$PORT"; then
            log_warn "Cancelled. No changes made."
            return 1
        fi
        PORT=${PORT:-$DEFAULT_PORT}
        if is_valid_port "$PORT"; then
            break
        fi
        log_error "Invalid port. Enter a number between 1 and 65535."
    done

    # Check for Private Key
    echo -e "  ${DIM}This must be THIS machine's OWN private key - never the other machine's."
    echo -e "  If server and client ever show the same private/public key pair in"
    echo -e "  'wg show', that means a key got copied between machines by mistake.${RESET}"
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
            read -rp "  Enter Private Key manually (blank = auto-generate, 'c' = cancel): " PRIV_KEY
            if is_cancel "$PRIV_KEY"; then
                log_warn "Cancelled. No changes made."
                return 1
            fi
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

    local THIS_PUBKEY
    THIS_PUBKEY=$(echo "$PRIV_KEY" | wg pubkey 2>/dev/null)
    if [ -n "$THIS_PUBKEY" ]; then
        print_separator
        echo -e "  ${BOLD}Next step:${RESET} send this machine's Public Key to whoever is setting up"
        echo -e "  the OTHER side of the tunnel - they'll need it for option 4 (Add Peer):"
        echo -e "  ${BOLD}Public Key:${RESET} $THIS_PUBKEY"
        print_separator
    fi
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

# Converts a dotted IPv4 address to its 32-bit integer form.
ip_to_int() {
    local a b c d
    IFS='.' read -r a b c d <<< "$1"
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

# Converts a 32-bit integer back to dotted IPv4 form.
int_to_ip() {
    local ip="$1"
    echo "$(( (ip >> 24) & 255 )).$(( (ip >> 16) & 255 )).$(( (ip >> 8) & 255 )).$(( ip & 255 ))"
}

# Suggests the first unused host IP within $1 (a CIDR, e.g. "10.10.10.1/24")
# given a list of already-used bare IPv4 addresses (no prefix) as the
# remaining args. Skips the network and broadcast addresses. Prints the
# suggestion (bare IP, no prefix) on success; returns 1 with no output if
# the subnet is full, has no usable host range (/31, /32), or is malformed.
suggest_next_ip() {
    local cidr="$1"; shift
    local used=("$@")
    local base_ip="${cidr%%/*}" prefix="${cidr##*/}"

    is_valid_cidr "$cidr" || return 1
    [ "$prefix" -le 30 ] || return 1   # /31 and /32 have no usable host range

    local base_int host_bits net_size network broadcast
    base_int=$(ip_to_int "$base_ip")
    host_bits=$((32 - prefix))
    net_size=$((1 << host_bits))
    network=$(( base_int & (~(net_size - 1)) ))
    broadcast=$(( network + net_size - 1 ))

    local -A used_set=()
    local u u_int
    for u in "${used[@]}"; do
        [ -n "$u" ] || continue
        is_valid_cidr "${u}/32" || continue   # skip anything not a plain IPv4
        u_int=$(ip_to_int "$u")
        used_set["$u_int"]=1
    done

    local candidate
    for (( candidate=network+1; candidate<broadcast; candidate++ )); do
        if [ -z "${used_set[$candidate]+x}" ]; then
            int_to_ip "$candidate"
            return 0
        fi
    done
    return 1
}

# Generates a complete, ready-to-import [Interface]+[Peer] .conf file for a
# NEW client, meant to be run ON THE SERVER. This does not touch the
# server's own wg0.conf - it only writes a separate client file (and,
# optionally, a QR code) that you hand to the client device. It is purely
# additive: it does not replace add_peer(), which is still how the new
# client's public key gets registered on the server side.
generate_client_config() {
    log_info "Generate Client Config"
    print_separator
    echo -e "  ${DIM}This builds a ready-to-import .conf file FOR a new client (phone,"
    echo -e "  laptop, etc) - run this ON THE SERVER. It does NOT modify this"
    echo -e "  server's own wg0.conf; you still add the client as a peer separately"
    echo -e "  (option 4) so the server accepts its connection.${RESET}"
    print_separator

    read -rp "  Server's Interface Name (the one clients connect to) [default: wg0, or 'c' to cancel]: " SRV_IFACE
    if is_cancel "$SRV_IFACE"; then
        log_warn "Cancelled."
        return 1
    fi
    SRV_IFACE=${SRV_IFACE:-wg0}
    if ! is_valid_iface_name "$SRV_IFACE"; then
        log_error "Invalid interface name. Use letters, numbers, '-' or '_' only (max 15 chars)."
        return 1
    fi

    local SRV_CONF="/etc/wireguard/${SRV_IFACE}.conf"
    if [ ! -f "$SRV_CONF" ]; then
        log_error "No config found at $SRV_CONF - create the server interface first (option 3)."
        return 1
    fi

    # --- Server's own public key, needed for the client's [Peer] section ---
    local SRV_PRIVKEY SRV_PUBKEY SRV_ADDR
    SRV_PRIVKEY=$(grep -i "^\s*PrivateKey" "$SRV_CONF" | head -1 | cut -d'=' -f2- | xargs)
    SRV_ADDR=$(grep -i "^\s*Address" "$SRV_CONF" | head -1 | cut -d'=' -f2- | xargs)
    if [ -z "$SRV_PRIVKEY" ] || ! is_valid_wg_key "$(echo "$SRV_PRIVKEY" | wg pubkey 2>/dev/null)" 2>/dev/null; then
        SRV_PUBKEY=""
    else
        SRV_PUBKEY=$(echo "$SRV_PRIVKEY" | wg pubkey 2>/dev/null)
    fi
    if [ -z "$SRV_PUBKEY" ]; then
        log_error "Could not derive this server's public key from $SRV_CONF (missing or invalid PrivateKey)."
        return 1
    fi
    log_info "Server Public Key (will be embedded in the client file): $SRV_PUBKEY"

    # --- Client identity: a friendly name, purely for the filename ---
    read -rp "  Client name (used for the filename, e.g. 'android-phone') [or 'c' to cancel]: " CLIENT_NAME
    is_cancel "$CLIENT_NAME" && { log_warn "Cancelled."; return 1; }
    if [ -z "$CLIENT_NAME" ]; then
        log_error "Client name cannot be empty."
        return 1
    fi
    if ! [[ "$CLIENT_NAME" =~ ^[A-Za-z0-9_-]{1,32}$ ]]; then
        log_error "Use letters, numbers, '-' or '_' only (max 32 chars)."
        return 1
    fi

    local OUT_DIR="/etc/wireguard/clients"
    mkdir -p "$OUT_DIR"
    chmod 700 "$OUT_DIR"
    local OUT_CONF="${OUT_DIR}/${CLIENT_NAME}.conf"
    if [ -f "$OUT_CONF" ]; then
        log_warn "A client file named '${CLIENT_NAME}.conf' already exists at $OUT_CONF."
        read -rp "  Overwrite it? [y/N]: " OVERWRITE_CLIENT
        if [[ ! "$OVERWRITE_CLIENT" =~ ^[Yy]$ ]]; then
            log_info "Cancelled - no changes made."
            return 0
        fi
    fi

    # --- Client's own keypair: always generated fresh here, never reused ---
    echo -e "  ${DIM}A brand-new keypair is generated for this client - never reuse a keypair"
    echo -e "  across two devices.${RESET}"
    local CLIENT_PRIVKEY CLIENT_PUBKEY
    CLIENT_PRIVKEY=$(wg genkey)
    if [ -z "$CLIENT_PRIVKEY" ]; then
        log_error "wg genkey failed to produce a private key (is the wireguard kernel module loaded?)."
        return 1
    fi
    CLIENT_PUBKEY=$(echo "$CLIENT_PRIVKEY" | wg pubkey 2>/dev/null)
    if [ -z "$CLIENT_PUBKEY" ]; then
        log_error "wg pubkey failed to derive a public key for this client."
        return 1
    fi

    # --- Client's tunnel IP: auto-suggested from the server's subnet, same
    #     logic add_peer() uses, so the two never collide with each other. ---
    local CLIENT_ADDR DEFAULT_CLIENT_IP=""
    if [ -n "$SRV_ADDR" ] && is_valid_cidr "$SRV_ADDR"; then
        local USED_IPS=() SUGGESTED_IP
        USED_IPS+=("${SRV_ADDR%%/*}")
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            USED_IPS+=("${line%%/*}")
        done < <(grep -i "^\s*AllowedIPs" "$SRV_CONF" | cut -d'=' -f2- | tr ',' '\n' | xargs -n1 2>/dev/null | grep -E '/32$')
        if SUGGESTED_IP=$(suggest_next_ip "$SRV_ADDR" "${USED_IPS[@]}"); then
            DEFAULT_CLIENT_IP="${SUGGESTED_IP}/32"
            log_info "Suggested next free IP in ${SRV_ADDR}'s subnet: $DEFAULT_CLIENT_IP"
        fi
    fi
    echo -e "  ${DIM}This client's own tunnel IP (its Address=, not AllowedIPs) - must be"
    echo -e "  unique, unused by the server or any other client on this subnet.${RESET}"
    while true; do
        if [ -n "$DEFAULT_CLIENT_IP" ]; then
            read -rp "  Client tunnel IP [default: $DEFAULT_CLIENT_IP]: " CLIENT_ADDR
            CLIENT_ADDR=${CLIENT_ADDR:-$DEFAULT_CLIENT_IP}
        else
            read -rp "  Client tunnel IP (e.g. 10.10.10.3/32): " CLIENT_ADDR
        fi
        is_cancel "$CLIENT_ADDR" && { log_warn "Cancelled."; return 1; }
        if is_valid_cidr "$CLIENT_ADDR"; then
            break
        fi
        log_error "Invalid format. Expected an IPv4 CIDR, e.g. 10.10.10.3/32."
    done

    # --- Endpoint: how the client reaches this server ---
    echo -e "  ${BOLD}What is 'Endpoint'?${RESET}"
    echo -e "  ${DIM}The server's REAL network address - how the client reaches it BEFORE"
    echo -e "  the tunnel exists (its LAN IP if the client is on the same local network,"
    echo -e "  its public IP or a DDNS hostname if the client connects over the"
    echo -e "  internet). Never the tunnel IP - that only works after the handshake.${RESET}"
    local ENDPOINT
    while true; do
        read -rp "  Server Endpoint (host_or_ip:port, e.g. 192.168.1.50:51820): " ENDPOINT
        is_cancel "$ENDPOINT" && { log_warn "Cancelled."; return 1; }
        if is_valid_endpoint "$ENDPOINT"; then
            break
        fi
        log_error "Invalid format. Expected host_or_ip:port with a valid port (1-65535)."
    done

    # --- AllowedIPs on the CLIENT side (what gets routed into the tunnel) ---
    echo -e "  ${DIM}Full-tunnel (0.0.0.0/0) sends ALL of the client's traffic through this"
    echo -e "  server, internet included. Split-tunnel routes only specific subnets -"
    echo -e "  e.g. just this VPN's own subnet, if you only need to reach machines"
    echo -e "  behind this server rather than replace the client's normal internet.${RESET}"
    local CLIENT_ALLOWED
    while true; do
        read -rp "  AllowedIPs for this client [default: 0.0.0.0/0]: " CLIENT_ALLOWED
        CLIENT_ALLOWED=${CLIENT_ALLOWED:-0.0.0.0/0}
        is_cancel "$CLIENT_ALLOWED" && { log_warn "Cancelled."; return 1; }
        if is_valid_allowed_ips "$CLIENT_ALLOWED"; then
            break
        fi
        log_error "Invalid format. Expected one or more comma-separated IPv4 CIDRs."
    done

    # --- Optional DNS ---
    echo -e "  ${DIM}Optional: which DNS resolver the client should use while the tunnel is"
    echo -e "  up. Leave blank to keep the client's own DNS untouched.${RESET}"
    local CLIENT_DNS
    read -rp "  DNS for this client [blank to skip]: " CLIENT_DNS
    if [ -n "$CLIENT_DNS" ] && ! is_valid_cidr "${CLIENT_DNS}/32"; then
        log_warn "'$CLIENT_DNS' doesn't look like a plain IPv4 address - omitting DNS line."
        CLIENT_DNS=""
    fi

    # --- Keepalive ---
    echo -e "  ${DIM}Recommended if this client will be behind NAT (almost always true for"
    echo -e "  phones and home routers) - keeps the connection from going idle-silent.${RESET}"
    local CLIENT_KEEPALIVE
    read -rp "  PersistentKeepalive in seconds [default: 25, blank to omit]: " CLIENT_KEEPALIVE
    if [ -n "$CLIENT_KEEPALIVE" ] && ! [[ "$CLIENT_KEEPALIVE" =~ ^[0-9]+$ ]]; then
        log_warn "'$CLIENT_KEEPALIVE' is not a number - omitting PersistentKeepalive."
        CLIENT_KEEPALIVE=""
    fi
    [ -z "$CLIENT_KEEPALIVE" ] && CLIENT_KEEPALIVE="25"

    # --- Summary before writing anything ---
    print_separator
    echo -e "  ${BOLD}About to write $OUT_CONF:${RESET}"
    echo "    [Interface]"
    echo "    PrivateKey = <client's new private key, hidden>"
    echo "    Address = $CLIENT_ADDR"
    [ -n "$CLIENT_DNS" ] && echo "    DNS = $CLIENT_DNS"
    echo "    [Peer]"
    echo "    PublicKey = $SRV_PUBKEY"
    echo "    Endpoint = $ENDPOINT"
    echo "    AllowedIPs = $CLIENT_ALLOWED"
    [ -n "$CLIENT_KEEPALIVE" ] && echo "    PersistentKeepalive = $CLIENT_KEEPALIVE"
    print_separator
    read -rp "  Write this file? [Y/n]: " CONFIRM_WRITE
    if [[ "$CONFIRM_WRITE" =~ ^[Nn]$ ]]; then
        log_info "Cancelled - nothing written."
        return 0
    fi

    {
        echo "[Interface]"
        echo "PrivateKey = $CLIENT_PRIVKEY"
        echo "Address = $CLIENT_ADDR"
        [ -n "$CLIENT_DNS" ] && echo "DNS = $CLIENT_DNS"
        echo ""
        echo "[Peer]"
        echo "PublicKey = $SRV_PUBKEY"
        echo "Endpoint = $ENDPOINT"
        echo "AllowedIPs = $CLIENT_ALLOWED"
        [ -n "$CLIENT_KEEPALIVE" ] && echo "PersistentKeepalive = $CLIENT_KEEPALIVE"
    } > "$OUT_CONF"
    chmod 600 "$OUT_CONF"
    log_success "Client config written to: $OUT_CONF"

    print_separator
    echo -e "  ${BOLD}This client's Public Key (needed to register it on the server):${RESET}"
    echo "    $CLIENT_PUBKEY"
    print_separator

    # --- Optional: show a QR code for mobile apps (Android/iOS WireGuard) ---
    if command -v qrencode &> /dev/null; then
        read -rp "  Show this as a QR code to scan on a phone? [Y/n]: " SHOW_QR
        if [[ ! "$SHOW_QR" =~ ^[Nn]$ ]]; then
            qrencode -t ansiutf8 < "$OUT_CONF"
            log_warn "This QR code encodes the client's PRIVATE key - treat it like a password."
        fi
    else
        log_info "Tip: install 'qrencode' (e.g. apt install qrencode) to also get a scannable"
        log_info "QR code here for the WireGuard mobile app instead of transferring this file."
    fi

    # BUG FOUND DURING TESTING: calling add_peer() directly here to "chain"
    # straight into registration seemed convenient, but add_peer() always
    # asks for the Interface Name from scratch (it has no way to inherit
    # SRV_IFACE from this function) - in practice, whatever the operator
    # types next gets consumed as add_peer's OWN first prompt, not as an
    # answer this function already knew. That silently misaligns every
    # subsequent prompt. Rather than reach into add_peer() to special-case
    # this (which the brief asked not to touch), this just hands the
    # operator everything needed to run option 4 themselves right after -
    # copy-pasting the printed public key is one extra step, but never
    # produces a misaligned prompt sequence like the chained call did.
    print_separator
    echo -e "  ${BOLD}Next step - register this client on the server (option 4):${RESET}"
    echo "    Interface:    $SRV_IFACE"
    echo "    Role:         1 (THIS machine is the SERVER)"
    echo "    Public Key:   $CLIENT_PUBKEY"
    echo "    AllowedIPs:   $CLIENT_ADDR"
    print_separator
    log_info "The client won't be able to connect until that's done."
}

# Adds a [Peer] block to an existing interface config. Works for both
# directions: a server adding a client peer, or a client adding the server
# as its peer - the only difference is which fields are prompted for.
add_peer() {
    log_info "Add WireGuard Peer"
    print_separator

    read -rp "  Interface Name to add the peer to [default: wg0, or 'c' to cancel]: " IFACE
    if is_cancel "$IFACE"; then
        log_warn "Cancelled."
        return 1
    fi
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
    echo -e "  ${BOLD}What are you connecting THIS machine to?${RESET}"
    echo "    1) THIS machine is the SERVER, and you're registering a CLIENT that"
    echo "       will connect to it"
    echo "    2) THIS machine is the CLIENT, and you're registering the SERVER"
    echo "       it should connect to"
    read -rp "  Select [1-2, or 'c' to cancel]: " ROLE
    is_cancel "$ROLE" && { log_warn "Cancelled."; return 1; }
    case "$ROLE" in
        1) ;;
        2) ;;
        *) log_error "Invalid option."; return 1 ;;
    esac

    # --- Public key of the peer (always required) ---
    local PEER_PUBKEY
    if [ "$ROLE" = "1" ]; then
        echo -e "  ${DIM}Enter the CLIENT's Public Key - the one THAT machine showed you after"
        echo -e "  running option 2 (Generate Keys) on itself. NOT this server's own key.${RESET}"
    else
        echo -e "  ${DIM}Enter the SERVER's Public Key - the one the server showed after running"
        echo -e "  option 2 (Generate Keys) on itself. NOT this client's own key.${RESET}"
    fi
    while true; do
        read -rp "  Peer's Public Key: " PEER_PUBKEY
        is_cancel "$PEER_PUBKEY" && { log_warn "Cancelled."; return 1; }
        if is_valid_wg_key "$PEER_PUBKEY"; then
            break
        fi
        log_error "That doesn't look like a valid WireGuard key (expected 44-char base64, e.g. ending in '=')."
    done

    # Catch the exact mistake from the earlier session: pasting THIS
    # machine's own public key as the peer's key (usually from copying the
    # same generated keypair, or the same config file, to both machines).
    local OWN_PRIVKEY OWN_PUBKEY
    OWN_PRIVKEY=$(grep -i "^\s*PrivateKey" "$CONF_FILE" | head -1 | cut -d'=' -f2- | xargs)
    if [ -n "$OWN_PRIVKEY" ]; then
        OWN_PUBKEY=$(echo "$OWN_PRIVKEY" | wg pubkey 2>/dev/null)
        if [ -n "$OWN_PUBKEY" ] && [ "$OWN_PUBKEY" = "$PEER_PUBKEY" ]; then
            log_error "This is THIS machine's OWN public key, not the other machine's."
            log_error "Server and client each need their own separate keypair (option 2,"
            log_error "run on each machine individually) - re-check which key you copied."
            return 1
        fi
    fi

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
    echo -e "  ${BOLD}What is 'AllowedIPs'?${RESET}"
    echo -e "  ${DIM}Despite the name, this isn't just a permission list - it does TWO things"
    echo -e "  at once: (1) which source IPs THIS machine will accept from this peer, and"
    echo -e "  (2) which destination IPs get ROUTED into the tunnel to reach this peer."
    echo -e "  Set it too narrow and legitimate traffic gets silently dropped; set it too"
    echo -e "  wide (e.g. 0.0.0.0/0 on both sides) and you can create a routing loop.${RESET}"
    if [ "$ROLE" = "1" ]; then
        echo "  (Server side: this is usually the client's tunnel IP, e.g. 10.10.10.2/32)"

        # Suggest the next free host IP in the server's own subnet, so the
        # operator can just press Enter instead of tracking used IPs by hand.
        local SERVER_ADDR SERVER_CIDR USED_IPS=() SUGGESTED_IP
        SERVER_ADDR=$(grep -i "^\s*Address" "$CONF_FILE" | head -1 | cut -d'=' -f2- | xargs)
        if [ -n "$SERVER_ADDR" ] && is_valid_cidr "$SERVER_ADDR"; then
            # BUG FIX: the used-IP list only came from existing peers'
            # AllowedIPs - it never included the server's own host IP (the
            # Address= line), so suggest_next_ip happily offered the SAME
            # IP the server itself already uses as "free" for the first
            # client. Seed the used set with the server's own address first.
            USED_IPS+=("${SERVER_ADDR%%/*}")

            # Collect the bare IPv4 of every existing "AllowedIPs = x.x.x.x/32"
            # peer line (only /32 entries represent a single occupied host).
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                USED_IPS+=("${line%%/*}")
            done < <(grep -i "^\s*AllowedIPs" "$CONF_FILE" | cut -d'=' -f2- | tr ',' '\n' | xargs -n1 2>/dev/null | grep -E '/32$')

            if SUGGESTED_IP=$(suggest_next_ip "$SERVER_ADDR" "${USED_IPS[@]}"); then
                DEFAULT_ALLOWED="${SUGGESTED_IP}/32"
                log_info "Suggested next free IP in ${SERVER_ADDR}'s subnet: $DEFAULT_ALLOWED"
            else
                log_warn "Could not find a free host IP in ${SERVER_ADDR}'s subnet automatically (subnet full, or none used yet outside /32 entries) - enter one manually."
            fi
        else
            log_warn "Could not read a valid Address from $CONF_FILE - enter the client's tunnel IP manually."
        fi
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
        echo -e "  ${BOLD}What is 'Endpoint'?${RESET}"
        echo -e "  ${DIM}The server's REAL network address - how THIS client reaches it BEFORE"
        echo -e "  the tunnel exists. Think of it like a street address: it's how you find"
        echo -e "  the building before you can use a room number inside it. The tunnel IP"
        echo -e "  (10.x.x.x) is that room number - it only works AFTER the handshake"
        echo -e "  succeeds, so it can never be used here.${RESET}"
        echo ""
        echo -e "  ${DIM}Which address to use depends on where the server actually is:${RESET}"
        echo -e "  ${DIM}  - Same LAN as this client  -> server's LAN IP,   e.g. 192.168.1.50:51820${RESET}"
        echo -e "  ${DIM}  - Reached over the internet -> server's public IP, e.g. 203.0.113.5:51820${RESET}"
        echo -e "  ${DIM}  - Server's public IP changes -> a DDNS hostname, e.g. myhome.ddns.net:51820${RESET}"
        echo -e "  ${DIM}(Only the client side sets this - the server just listens and never"
        echo -e "  needs the client's address, since the client connects to it first.)${RESET}"
        while true; do
            read -rp "  Server Endpoint (host_or_ip:port, e.g. 203.0.113.5:51820): " ENDPOINT
            is_cancel "$ENDPOINT" && { log_warn "Cancelled."; return 1; }
            if is_valid_endpoint "$ENDPOINT"; then
                break
            fi
            log_error "Invalid format. Expected host_or_ip:port with a valid port (1-65535)."
        done
        echo -e "  ${DIM}What is 'PersistentKeepalive'? WireGuard normally stays silent when idle -"
        echo -e "  fine for a server with a stable public address, but most home routers/"
        echo -e "  mobile networks (NAT) forget an idle connection after a short time and"
        echo -e "  the server can no longer reach the client until it messages first. This"
        echo -e "  sends a tiny heartbeat every N seconds to keep that NAT mapping open.${RESET}"
        read -rp "  PersistentKeepalive in seconds [default: 25, blank to omit, 'c' to cancel]: " KEEPALIVE
        if is_cancel "$KEEPALIVE"; then
            log_warn "Cancelled - nothing written."
            return 1
        fi
        if [ -n "$KEEPALIVE" ] && ! [[ "$KEEPALIVE" =~ ^[0-9]+$ ]]; then
            log_warn "'$KEEPALIVE' is not a number - omitting PersistentKeepalive."
            KEEPALIVE=""
        fi
        [ -z "$KEEPALIVE" ] && KEEPALIVE="25"
    else
        echo -e "  ${DIM}Usually left blank here - PersistentKeepalive only needs to be set on"
        echo -e "  ONE side of a pair to keep both directions alive, and it's normally set on"
        echo -e "  the client's peer entry (the one you'd add with role 2), not the server's.${RESET}"
        read -rp "  PersistentKeepalive in seconds [blank to omit, 'c' to cancel]: " KEEPALIVE
        if is_cancel "$KEEPALIVE"; then
            log_warn "Cancelled - nothing written."
            return 1
        fi
        if [ -n "$KEEPALIVE" ] && ! [[ "$KEEPALIVE" =~ ^[0-9]+$ ]]; then
            log_warn "'$KEEPALIVE' is not a number - omitting PersistentKeepalive."
            KEEPALIVE=""
        fi
    fi

    # --- Show a summary and let the operator back out before writing ---
    print_separator
    echo -e "  ${BOLD}About to add this [Peer] block to $CONF_FILE:${RESET}"
    echo "    PublicKey = $PEER_PUBKEY"
    echo "    AllowedIPs = $ALLOWED_IPS"
    [ -n "$ENDPOINT" ] && echo "    Endpoint = $ENDPOINT"
    [ -n "$KEEPALIVE" ] && echo "    PersistentKeepalive = $KEEPALIVE"
    print_separator
    read -rp "  Write this to $CONF_FILE? [Y/n]: " CONFIRM_WRITE
    if [[ "$CONFIRM_WRITE" =~ ^[Nn]$ ]]; then
        log_info "Cancelled - nothing written."
        return 0
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
                log_error "'wg syncconf' failed. Bring the interface down/up manually (menu option 7) to apply it."
            fi
        else
            log_info "Remember to bring '$IFACE' down and up again (menu option 7) to apply the new peer."
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
        echo -e "  ${BOLD}5.${RESET} Generate Client Config (ready-to-import .conf + QR)"
        echo -e "  ${BOLD}6.${RESET} Check Status & Configuration"
        echo -e "  ${BOLD}7.${RESET} Bring Up / Down WireGuard Interface"
        echo -e "  ${BOLD}0.${RESET} Exit"
        print_separator
        echo -e "  ${DIM}First time setting up a tunnel? Run these on EACH machine (server AND"
        echo -e "  every client), in order: 1 -> 2 -> 3 -> 4 -> 7. Each machine generates its"
        echo -e "  own keypair in step 2 - never copy a private key between machines."
        echo -e "  Adding a phone or laptop as a client? Run option 5 ON THE SERVER instead"
        echo -e "  of steps 2-4 on that device - it builds the client's .conf (and QR code)"
        echo -e "  for you in one go."
        echo -e "  To enable internet access trough wireguard vpn, you need to enable "
        echo -e "  nat and ip forwarding in the vpn server side and you can do that by using nat.sh script"
        echo -e "   ${YELLOW}(you need to run it on the vpn server side)${RESET}"
        print_separator

        read -rp "  Select Option [0-7]: " OPT

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
                generate_client_config
                ;;
            6)
                check_status
                ;;
            7)
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