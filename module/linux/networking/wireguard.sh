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

#------------------------------------------------------------------------------#
# ----------------------------- INSTALL WIREGUARD ------------------------------#
# ------------------------------------------------------------------------------#

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

#-------------------------------#
#--------Generate Keys--------#
#-------------------------------#

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

    # Create the private key file already restricted (umask 077 in a subshell)
    # rather than world-readable-then-chmod, which left a short window where
    # the key could be read.
    ( umask 077; echo "$privkey" > "$key_dir/privatekey" )
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
    # BUG FIX: this loop variable was not declared local, so it silently
    # overwrote any same-named `o` in whichever function called is_valid_cidr
    # (allowed_ips_warnings loops over candidate IPs in a variable also
    # called `o` - every validity check here clobbered it mid-loop).
    local o
    for o in "$o1" "$o2" "$o3" "$o4"; do
        # Leading zeros ("08") are ambiguous - bash reads them as octal and
        # crashes in arithmetic - so reject them outright.
        [[ "$o" =~ ^0[0-9]+$ ]] && return 1
        [ "$o" -le 255 ] || return 1
    done
    [[ "$prefix" =~ ^0[0-9]+$ ]] && return 1
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

#-----------------------------------#
#--------Configure Wireguard--------#
#-----------------------------------#

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
    local EXTRA_IFACE_LINES=""

    # Check if configuration file already exists
    if [ -f "$CONF_FILE" ]; then
        log_warn "Configuration file '$CONF_FILE' already exists."
        EXISTING_IP=$(grep -i "^\s*Address" "$CONF_FILE" | cut -d'=' -f2- | xargs)
        EXISTING_PORT=$(grep -i "^\s*ListenPort" "$CONF_FILE" | cut -d'=' -f2- | xargs)
        EXISTING_KEY=$(grep -i "^\s*PrivateKey" "$CONF_FILE" | cut -d'=' -f2- | xargs)
        # Case-insensitive, whitespace-tolerant match - wg-quick itself accepts
        # "[peer]" and "[Peer] ", and the strict version used to drop every peer.
        PEERS=$(sed -n '/^[[:space:]]*\[[Pp][Ee][Ee][Rr]\]/,$p' "$CONF_FILE")
        # Keep any [Interface] lines this wizard does not manage (PostUp/
        # PostDown, DNS, MTU, Table, SaveConfig...). Rewriting the section
        # from just PrivateKey/Address/ListenPort used to delete them silently.
        EXTRA_IFACE_LINES=$(awk '
            BEGIN { sec = "" }
            {
                low = tolower($0)
                if (low ~ /^[ \t]*\[/) { sec = (low ~ /^[ \t]*\[interface\]/) ? "i" : "o"; next }
                if (sec != "i") next
                t = $0
                sub(/#.*/, "", t)
                gsub(/^[ \t]+/, "", t); gsub(/[ \t\r]+$/, "", t)
                if (t == "") next
                key = t; sub(/[ \t]*=.*/, "", key); key = tolower(key)
                if (key == "privatekey" || key == "address" || key == "listenport") next
                print $0
            }
        ' "$CONF_FILE")

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
    if [ -n "$PRIV_KEY" ]; then
        log_info "Keeping the PrivateKey already in $CONF_FILE (this machine's key stays the same)."
    fi
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

    # Write [Interface] section. umask 077 so the private key is never
    # world-readable, not even for an instant before the chmod below.
    if ! (
        umask 077
        {
            echo "[Interface]"
            echo "PrivateKey = $PRIV_KEY"
            echo "Address = $ADDRESS"
            echo "ListenPort = $PORT"
            [ -n "$EXTRA_IFACE_LINES" ] && echo "$EXTRA_IFACE_LINES"
            echo ""
        } > "$CONF_FILE"
    ); then
        log_error "Could not write $CONF_FILE (disk full or no permission?)."
        return 1
    fi
    if [ -n "$EXTRA_IFACE_LINES" ]; then
        log_info "Preserved $(printf '%s\n' "$EXTRA_IFACE_LINES" | grep -c '') additional [Interface] line(s) (e.g. PostUp/DNS/MTU)."
    fi

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
    # Hostname/FQDN: dot-separated labels of letters/digits/hyphen. A single
    # label ("homelab") is allowed - common on a LAN with local name
    # resolution - but the name must contain a letter, so a mistyped IP such
    # as "192.168.1" is rejected instead of being accepted as a hostname.
    [[ "$host" =~ [A-Za-z] ]] || return 1
    [[ "$host" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]
}

# Converts a dotted IPv4 address to its 32-bit integer form.
ip_to_int() {
    local a b c d
    IFS='.' read -r a b c d <<< "$1"
    echo $(( (10#$a << 24) + (10#$b << 16) + (10#$c << 8) + 10#$d ))
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

# ---------------------------------------------------------------------------
# IPv4 range helpers - used to spot overlapping or mistaken AllowedIPs
# ---------------------------------------------------------------------------

# Prints "first last" (inclusive integers) for the network a CIDR describes,
# ignoring any host bits (so 10.10.10.2/24 describes the whole 10.10.10.0/24).
cidr_bounds() {
    local cidr="$1" ip prefix ipint size start
    ip="${cidr%%/*}"
    prefix=$((10#${cidr##*/}))
    ipint=$(ip_to_int "$ip")
    size=$(( 1 << (32 - prefix) ))
    start=$(( ipint & ~(size - 1) & 0xFFFFFFFF ))
    echo "$start $(( start + size - 1 ))"
}

# True (exit 0) if the two CIDRs share at least one address.
cidrs_overlap() {
    local a_first a_last b_first b_last
    read -r a_first a_last <<< "$(cidr_bounds "$1")"
    read -r b_first b_last <<< "$(cidr_bounds "$2")"
    [ "$a_first" -le "$b_last" ] && [ "$b_first" -le "$a_last" ]
}

# True (exit 0) if CIDR $2 lies entirely inside CIDR $1.
cidr_contains() {
    local o_first o_last i_first i_last
    read -r o_first o_last <<< "$(cidr_bounds "$1")"
    read -r i_first i_last <<< "$(cidr_bounds "$2")"
    [ "$o_first" -le "$i_first" ] && [ "$i_last" -le "$o_last" ]
}

# Tidies an AllowedIPs value: trims spaces around each comma-separated entry
# and joins them as "a, b, c".
normalize_allowed_ips() {
    local value="$1" entry out=""
    local -a entries
    IFS=',' read -ra entries <<< "$value"
    for entry in "${entries[@]}"; do
        entry=$(echo "$entry" | xargs)
        [ -n "$entry" ] || continue
        out="${out:+$out, }$entry"
    done
    echo "$out"
}

# Validates a comma-separated list of plain IPv4 addresses (for DNS =) and
# prints it tidied as "a, b". Exits 1 with no output if any entry is invalid.
normalize_dns_list() {
    local value="$1" entry out=""
    local -a entries
    [ -n "$value" ] || return 1
    IFS=',' read -ra entries <<< "$value"
    for entry in "${entries[@]}"; do
        entry=$(echo "$entry" | xargs)
        is_valid_cidr "${entry}/32" || return 1
        out="${out:+$out, }$entry"
    done
    echo "$out"
}

# Prints this machine's primary outbound IPv4 address (nothing if unknown).
detect_primary_ip() {
    command -v ip &> /dev/null || return 0
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }'
}

# Prompts for a PersistentKeepalive value and re-asks until it is valid.
#   $1 = value used when the operator just presses Enter ("" = leave it out)
# Sets KEEPALIVE_RESULT ("" means: do not write the line). 0 also means
# "leave it out" (that is what 0 means to WireGuard). Returns 1 on cancel.
read_keepalive() {
    local default="$1" input hint
    if [ -n "$default" ]; then
        hint="Enter = $default, 0 = leave out"
    else
        hint="Enter or 0 = leave out"
    fi
    while true; do
        read -rp "  PersistentKeepalive in seconds [$hint, 'c' to cancel]: " input
        if is_cancel "$input"; then
            return 1
        fi
        input=${input:-$default}
        if [ -z "$input" ]; then
            KEEPALIVE_RESULT=""
            return 0
        fi
        if [[ "$input" =~ ^[0-9]{1,5}$ ]] && [ "$((10#$input))" -le 65535 ]; then
            input=$((10#$input))
            if [ "$input" -eq 0 ]; then
                KEEPALIVE_RESULT=""
            else
                KEEPALIVE_RESULT="$input"
            fi
            return 0
        fi
        log_error "Enter a whole number of seconds between 0 and 65535."
    done
}

# ---------------------------------------------------------------------------
# [Peer] parsing and safe rewriting
# ---------------------------------------------------------------------------

# Prints one line per [Peer] block in config $1, as:
#   index|PublicKey|AllowedIPs|Endpoint|PersistentKeepalive
# Tolerant of hand-edited files: case-insensitive section/key names, optional
# spaces around '=', inline '#' comments, and repeated AllowedIPs lines
# (joined with ", "). Uses only POSIX awk, so it works with mawk and gawk.
list_peers() {
    awk '
        function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
        BEGIN { n = 0; inpeer = 0 }
        {
            line = $0
            low = tolower(line)
            if (low ~ /^[ \t]*\[/) {
                if (low ~ /^[ \t]*\[peer\][ \t\r]*(#.*)?$/) { n++; inpeer = 1 } else { inpeer = 0 }
                next
            }
            if (!inpeer) next
            sub(/#.*/, "", line)
            eq = index(line, "=")
            if (eq == 0) next
            key = tolower(trim(substr(line, 1, eq - 1)))
            val = trim(substr(line, eq + 1))
            if (key == "publickey") pk[n] = val
            else if (key == "allowedips") ai[n] = (ai[n] == "" ? val : ai[n] ", " val)
            else if (key == "endpoint") ep[n] = val
            else if (key == "persistentkeepalive") ka[n] = val
        }
        END { for (i = 1; i <= n; i++) printf "%d|%s|%s|%s|%s\n", i, pk[i], ai[i], ep[i], ka[i] }
    ' "$1"
}

# Prints a compact, narrow-terminal-friendly summary of list_peers output ($1).
print_peer_summary() {
    local idx pk ai ep ka
    while IFS='|' read -r idx pk ai ep ka; do
        [ -n "$idx" ] || continue
        if [ -n "$pk" ]; then
            echo -e "  ${BOLD}[$idx]${RESET} key ${pk:0:12}...   AllowedIPs: ${ai:--}"
        else
            echo -e "  ${BOLD}[$idx]${RESET} (no PublicKey line!)   AllowedIPs: ${ai:--}"
        fi
        echo "        Endpoint: ${ep:--}   PersistentKeepalive: ${ka:--}"
    done <<< "$1"
}

# Prints a modified copy of config $1 to stdout; $1 itself is never touched.
#   $2 = peer number (1-based, in file order)
#   $3 = mode:  set    replace the field (or add it if missing; extra
#                      duplicate lines of that field are dropped)
#               unset  delete the field
#               remove delete the whole [Peer] block
#   $4 = field name as it should be written (PublicKey, AllowedIPs, ...)
#   $5 = new value (set mode only)
# Everything else in the file - other peers, [Interface], comments, blank
# lines, unknown keys such as PresharedKey - passes through unchanged. Comment
# lines sitting between two peers are never deleted. Exits 3 if the peer
# number does not exist.
rewrite_peer_block() {
    awk -v IDX="$2" -v MODE="$3" -v FIELD="$4" -v VALUE="$5" '
        function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
        function keyof(l,   eq) {
            sub(/#.*/, "", l)
            eq = index(l, "=")
            if (eq == 0) return ""
            return tolower(trim(substr(l, 1, eq - 1)))
        }
        function emit(s) { O[++nout] = s }
        { L[NR] = $0 }
        END {
            n = NR; pc = 0; start = 0; prevstop = 0
            for (i = 1; i <= n; i++)
                if (tolower(L[i]) ~ /^[ \t]*\[peer\][ \t\r]*(#.*)?$/) { pc++; if (pc == IDX + 0) start = i }
            if (start == 0) exit 3
            stop = n
            for (i = start + 1; i <= n; i++)
                if (L[i] ~ /^[ \t]*\[/) { stop = i - 1; break }
            lastf = start
            for (i = start + 1; i <= stop; i++)
                if (keyof(L[i]) != "") lastf = i
            # Where the PREVIOUS section (be it [Interface] or an earlier
            # [Peer]) actually ends, so the comment-removal walk-back below
            # can never eat into it, even if that section is itself empty.
            for (i = start - 1; i >= 1; i--)
                if (L[i] !~ /^[ \t\r]*$/ && L[i] !~ /^[ \t]*#/) { prevstop = i; break }
            # A block of comment-only lines directly above this [Peer] almost
            # always documents THIS peer (e.g. "# Android phone - Budi") -
            # remove those too, so deleting a peer does not leave an orphaned,
            # now-inaccurate label sitting between its neighbors.
            cmt_start = start
            for (i = start - 1; i > prevstop; i--) {
                if (L[i] ~ /^[ \t]*#/) cmt_start = i
                else break
            }
            want = tolower(FIELD)
            done = 0; skipblank = 0; nout = 0
            for (i = 1; i <= n; i++) {
                if (MODE == "remove") {
                    if (i >= cmt_start && i <= lastf) { skipblank = 1; continue }
                    if (skipblank) {
                        if (L[i] ~ /^[ \t\r]*$/ && (nout == 0 || O[nout] ~ /^[ \t\r]*$/)) continue
                        skipblank = 0
                    }
                } else if (i > start && i <= lastf) {
                    k = keyof(L[i])
                    if (k != "" && k == want) {
                        if (MODE == "set" && !done) { emit(FIELD " = " VALUE); done = 1 }
                        continue
                    }
                }
                emit(L[i])
                if (MODE == "set" && i == lastf && !done) { emit(FIELD " = " VALUE); done = 1 }
            }
            if (MODE == "remove")
                while (nout > 0 && O[nout] ~ /^[ \t\r]*$/) nout--
            for (i = 1; i <= nout; i++) print O[i]
        }
    ' "$1"
}

# Runs wg-quick's own parser over a candidate config so a bad edit is caught
# BEFORE it replaces the working file. Treated as OK when wg-quick is not
# installed. On failure prints wg-quick's error message and returns 1.
#   $1 = candidate file   $2 = interface name (wg-quick derives it from the filename)
validate_wg_conf() {
    local candidate="$1" iface="$2" tmpdir out
    command -v wg-quick &> /dev/null || return 0
    tmpdir=$(mktemp -d) || return 0
    cp "$candidate" "$tmpdir/${iface}.conf"
    chmod 600 "$tmpdir/${iface}.conf"
    if out=$(wg-quick strip "$tmpdir/${iface}.conf" 2>&1 >/dev/null); then
        rm -rf "$tmpdir"
        return 0
    fi
    rm -rf "$tmpdir"
    echo "$out"
    return 1
}

# Applies ONE edit to peer number $3 of config $2, safely. The modified config
# is built in a private temp file, sanity-checked, vetted by wg-quick's own
# parser, and only then swapped in - with the previous file kept as ".bak".
# The live config is never touched unless every check passes.
#   $1 iface   $2 config file   $3 peer number
#   $4 mode (set|unset|remove)  $5 field name   $6 value (set mode)
apply_peer_edit() {
    local iface="$1" conf="$2" idx="$3" mode="$4" field="$5" value="$6"
    local cand old_count new_count expect_count pk_old pk_new col got want verr

    cand=$(mktemp "${conf}.XXXXXX") || {
        log_error "Could not create a temporary file next to $conf - nothing was changed."
        return 1
    }

    if ! rewrite_peer_block "$conf" "$idx" "$mode" "$field" "$value" > "$cand"; then
        rm -f "$cand"
        log_error "Could not find peer #$idx in $conf - nothing was changed."
        return 1
    fi

    # Sanity check 1: the number of peers is what it should be.
    old_count=$(list_peers "$conf" | grep -c '')
    new_count=$(list_peers "$cand" | grep -c '')
    expect_count=$old_count
    [ "$mode" = "remove" ] && expect_count=$((old_count - 1))
    if [ "$new_count" -ne "$expect_count" ]; then
        rm -f "$cand"
        log_error "Safety check failed (peer count would go from $old_count to $new_count, expected $expect_count). Nothing was changed."
        return 1
    fi

    # Sanity check 2: [Interface] and the PrivateKey survived untouched.
    pk_old=$(grep -ci '^[[:space:]]*PrivateKey' "$conf")
    pk_new=$(grep -ci '^[[:space:]]*PrivateKey' "$cand")
    if [ "$pk_old" -ne "$pk_new" ] || \
       { grep -qi '^[[:space:]]*\[interface\]' "$conf" && ! grep -qi '^[[:space:]]*\[interface\]' "$cand"; }; then
        rm -f "$cand"
        log_error "Safety check failed ([Interface] section would be damaged). Nothing was changed."
        return 1
    fi

    # Sanity check 3: the edited field really holds the value we meant to write.
    if [ "$mode" != "remove" ]; then
        case "$field" in
            PublicKey)           col=2 ;;
            AllowedIPs)          col=3 ;;
            Endpoint)            col=4 ;;
            PersistentKeepalive) col=5 ;;
            *) rm -f "$cand"; log_error "Unknown field '$field'. Nothing was changed."; return 1 ;;
        esac
        got=$(list_peers "$cand" | awk -F'|' -v i="$idx" -v c="$col" '$1 == i { print $c }')
        want="$value"
        [ "$mode" = "unset" ] && want=""
        if [ "$got" != "$want" ]; then
            rm -f "$cand"
            log_error "Safety check failed (peer #$idx $field would read '$got', expected '$want'). Nothing was changed."
            return 1
        fi
    fi

    # wg-quick's own parser gets the final say.
    if ! verr=$(validate_wg_conf "$cand" "$iface"); then
        rm -f "$cand"
        log_error "wg-quick rejected the edited config, so it was NOT saved:"
        echo "$verr" | sed 's/^/      /'
        log_info "Your original $conf is untouched. If the message above points at a"
        log_info "different peer or line, fix that by hand first, then retry."
        return 1
    fi

    # Commit: keep the previous version, then swap the new file in.
    if ! cp -p "$conf" "${conf}.bak"; then
        rm -f "$cand"
        log_error "Could not create the backup ${conf}.bak - nothing was changed."
        return 1
    fi
    chmod 600 "${conf}.bak"
    if ! mv -f "$cand" "$conf"; then
        rm -f "$cand"
        log_error "Could not replace $conf - nothing was changed."
        return 1
    fi
    chmod 600 "$conf"
    log_info "Previous version kept at ${conf}.bak (undo with: cp ${conf}.bak ${conf})"
    return 0
}

# Prints one warning per line (nothing if the value looks fine) for an
# AllowedIPs value that is about to be saved.
#   $1 = config file being edited
#   $2 = the AllowedIPs value (comma separated)
#   $3 = "server" when the entry describes a CLIENT registered on this
#        machine (normally a single /32 tunnel IP), or "client" when it
#        describes the SERVER this machine connects to (ranges and
#        0.0.0.0/0 are normal there)
#   $4 = number of the peer being edited - its own current entries are
#        skipped in the overlap check (0 when adding a brand-new peer)
allowed_ips_warnings() {
    local conf="$1" value="$2" mode="$3" skip="$4"
    # BUG FIX: this used a single-letter `o` for the loop variable, which
    # collided with is_valid_cidr's own (previously unscoped) loop variable
    # of the same name and silently corrupted it mid-comparison. Renamed to
    # something collision-resistant as defense in depth, on top of the
    # is_valid_cidr fix itself.
    local entry ip prefix first last ip_int own_addr own_ip other_ip
    local pidx ppk pai pep pka
    local -a entries other_entries

    own_addr=$(grep -i "^\s*Address" "$conf" | head -1 | cut -d'=' -f2- | xargs)
    own_ip="${own_addr%%/*}"

    IFS=',' read -ra entries <<< "$value"
    for entry in "${entries[@]}"; do
        entry=$(echo "$entry" | xargs)
        [ -n "$entry" ] || continue
        is_valid_cidr "$entry" || continue
        ip="${entry%%/*}"
        prefix=$((10#${entry##*/}))
        read -r first last <<< "$(cidr_bounds "$entry")"
        ip_int=$(ip_to_int "$ip")

        if [ "$prefix" -lt 32 ] && [ "$ip_int" -ne "$first" ]; then
            echo "$entry has host bits set - WireGuard reads it as $(int_to_ip "$first")/$prefix, i.e. the whole range, not just $ip."
        fi
        if [ "$mode" = "server" ]; then
            if [ "$prefix" -eq 0 ]; then
                echo "$entry claims ALL traffic for this one peer. That belongs on the CLIENT side only - here it hijacks routing for every other client."
            elif [ "$prefix" -lt 32 ]; then
                echo "$entry covers $(( last - first + 1 )) addresses. A client registered on the server normally gets one tunnel IP (/32); a wide range also claims addresses meant for other clients. (Fine only if this peer is a router for a LAN behind it.)"
            fi
        fi
        if [ -n "$own_ip" ] && [ "$prefix" -eq 32 ] && [ "$ip" = "$own_ip" ]; then
            echo "$entry is THIS machine's own tunnel IP ($own_addr) - a peer cannot use it."
        fi

        while IFS='|' read -r pidx ppk pai pep pka; do
            [ -n "$pidx" ] || continue
            [ "$pidx" = "$skip" ] && continue
            IFS=',' read -ra other_entries <<< "$pai"
            for other_ip in "${other_entries[@]}"; do
                other_ip=$(echo "$other_ip" | xargs)
                is_valid_cidr "$other_ip" || continue
                if cidrs_overlap "$entry" "$other_ip"; then
                    echo "$entry overlaps peer #$pidx ($other_ip). WireGuard gives an address to only ONE peer, so one of the two stops working."
                fi
            done
        done < <(list_peers "$conf")
    done
}

# True (exit 0) if every entry of AllowedIPs value $2 lies inside the tunnel
# subnet of interface config $1 (its Address=). Such entries are already
# routed by the interface's own subnet route; anything outside needs a route
# that only `wg-quick up` installs.
allowed_ips_within_iface_subnet() {
    local conf="$1" value="$2" own_addr entry
    local -a entries
    own_addr=$(grep -i "^\s*Address" "$conf" | head -1 | cut -d'=' -f2- | xargs)
    is_valid_cidr "$own_addr" || return 1
    IFS=',' read -ra entries <<< "$value"
    for entry in "${entries[@]}"; do
        entry=$(echo "$entry" | xargs)
        [ -n "$entry" ] || continue
        cidr_contains "$own_addr" "$entry" || return 1
    done
    return 0
}

# After a config change: if the interface is UP, offer to push the change into
# the running tunnel with `wg syncconf` (no downtime) - unless the change adds
# AllowedIPs outside the tunnel's own subnet. Those need kernel routes that
# only `wg-quick up` installs (syncconf cannot add them), so a restart is the
# honest advice there. Errors are shown, not swallowed.
#   $1 iface   $2 config file   $3 AllowedIPs touched by this change ("" if none)
offer_live_apply() {
    local iface="$1" conf="$2" routed="$3" sync_now tmp err
    is_interface_active "$iface" || return 0

    if [ -n "$routed" ] && ! allowed_ips_within_iface_subnet "$conf" "$routed"; then
        log_warn "Interface '$iface' is UP, but these AllowedIPs reach outside the tunnel's own subnet."
        log_warn "They need kernel routes that only 'wg-quick up' installs ('wg syncconf' cannot add"
        log_warn "them), so restart the interface (menu option 7: down, then up) to apply this change."
        return 0
    fi

    log_warn "Interface '$iface' is currently UP - this change is not live yet."
    read -rp "  Apply it now without restarting the tunnel? [Y/n]: " sync_now
    if [[ "$sync_now" =~ ^[Nn]$ ]]; then
        log_info "Remember to bring '$iface' down and up again (menu option 7) to apply it."
        return 0
    fi

    tmp=$(mktemp) || { log_error "Could not create a temporary file."; return 1; }
    if ! err=$(wg-quick strip "$iface" 2>&1 >"$tmp"); then
        rm -f "$tmp"
        log_error "wg-quick strip failed: $err"
        return 1
    fi
    if err=$(wg syncconf "$iface" "$tmp" 2>&1); then
        log_success "Applied live via 'wg syncconf' - no downtime."
    else
        log_error "'wg syncconf' failed: $err"
        log_error "Bring the interface down/up manually (menu option 7) to apply it."
    fi
    rm -f "$tmp"
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
    local SRV_PRIVKEY SRV_PUBKEY SRV_ADDR SRV_PORT
    SRV_PRIVKEY=$(grep -i "^\s*PrivateKey" "$SRV_CONF" | head -1 | cut -d'=' -f2- | xargs)
    SRV_ADDR=$(grep -i "^\s*Address" "$SRV_CONF" | head -1 | cut -d'=' -f2- | xargs)
    SRV_PORT=$(grep -i "^\s*ListenPort" "$SRV_CONF" | head -1 | cut -d'=' -f2- | xargs)
    SRV_PUBKEY=""
    if [ -n "$SRV_PRIVKEY" ]; then
        SRV_PUBKEY=$(echo "$SRV_PRIVKEY" | wg pubkey 2>/dev/null)
        is_valid_wg_key "$SRV_PUBKEY" || SRV_PUBKEY=""
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
    local CLIENT_ADDR DEFAULT_CLIENT_IP="" CLIENT_WARN FORCE_IP w
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
        if ! is_valid_cidr "$CLIENT_ADDR"; then
            log_error "Invalid format. Expected an IPv4 CIDR, e.g. 10.10.10.3/32."
            continue
        fi
        # The auto-suggested IP is always free, but a typed-in one was never
        # checked against the server's own address or the other clients.
        CLIENT_WARN=$(allowed_ips_warnings "$SRV_CONF" "${CLIENT_ADDR%%/*}/32" server 0)
        if [ -z "$CLIENT_WARN" ]; then
            break
        fi
        while IFS= read -r w; do
            log_warn "$w"
        done <<< "$CLIENT_WARN"
        read -rp "  Use this IP anyway? [y/N]: " FORCE_IP
        [[ "$FORCE_IP" =~ ^[Yy]$ ]] && break
    done

    # --- Endpoint: how the client reaches this server ---
    echo -e "  ${BOLD}What is 'Endpoint'?${RESET}"
    echo -e "  ${DIM}The server's REAL network address - how the client reaches it BEFORE"
    echo -e "  the tunnel exists (its LAN IP if the client is on the same local network,"
    echo -e "  its public IP or a DDNS hostname if the client connects over the"
    echo -e "  internet). Never the tunnel IP - that only works after the handshake.${RESET}"
    local ENDPOINT LAN_IP
    if [ -n "$SRV_PORT" ] && is_valid_port "$SRV_PORT"; then
        log_info "This server listens on UDP port $SRV_PORT - use that port in the Endpoint."
    fi
    LAN_IP=$(detect_primary_ip)
    if [ -n "$LAN_IP" ]; then
        log_info "This server's primary IP is $LAN_IP - a valid Endpoint host only if the client is"
        log_info "on the same LAN; from the internet you need the public IP or a DDNS name instead."
    fi
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
    local CLIENT_DNS CLIENT_DNS_NORM
    while true; do
        read -rp "  DNS for this client (IPv4; comma-separated for several) [blank to skip, 'c' to cancel]: " CLIENT_DNS
        is_cancel "$CLIENT_DNS" && { log_warn "Cancelled."; return 1; }
        [ -z "$CLIENT_DNS" ] && break
        # A typo used to be silently dropped, leaving the client on its own
        # resolver (a DNS leak on a full tunnel). Re-ask instead.
        if CLIENT_DNS_NORM=$(normalize_dns_list "$CLIENT_DNS"); then
            CLIENT_DNS="$CLIENT_DNS_NORM"
            break
        fi
        log_error "Expected plain IPv4 addresses, e.g. 1.1.1.1 or 1.1.1.1, 8.8.8.8."
    done

    # --- Keepalive ---
    echo -e "  ${DIM}Recommended if this client will be behind NAT (almost always true for"
    echo -e "  phones and home routers) - keeps the connection from going idle-silent.${RESET}"
    local CLIENT_KEEPALIVE
    # The old prompt promised "blank to omit" but blank (and even garbage
    # input, after claiming to omit it) silently became 25.
    if ! read_keepalive 25; then
        log_warn "Cancelled."
        return 1
    fi
    CLIENT_KEEPALIVE="$KEEPALIVE_RESULT"

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
    # Always a single /32 here, whatever prefix the client's own Address uses:
    # registering "10.10.10.7/24" on the server would claim the whole subnet.
    echo "    AllowedIPs:   ${CLIENT_ADDR%%/*}/32"
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
    local ALLOWED_IPS DEFAULT_ALLOWED="" ROLE_MODE="server" ALLOWED_WARN FORCE_ALLOWED w
    [ "$ROLE" = "2" ] && ROLE_MODE="client"
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
        if ! is_valid_allowed_ips "$ALLOWED_IPS"; then
            log_error "Invalid format. Expected one or more comma-separated IPv4 CIDRs."
            continue
        fi
        ALLOWED_IPS=$(normalize_allowed_ips "$ALLOWED_IPS")
        # Catch the classic mistakes (a /24 on a server-side peer, 0.0.0.0/0 on
        # both ends, an IP another peer already owns) before they are saved.
        ALLOWED_WARN=$(allowed_ips_warnings "$CONF_FILE" "$ALLOWED_IPS" "$ROLE_MODE" 0)
        if [ -z "$ALLOWED_WARN" ]; then
            break
        fi
        while IFS= read -r w; do
            log_warn "$w"
        done <<< "$ALLOWED_WARN"
        read -rp "  Use it anyway? [y/N]: " FORCE_ALLOWED
        [[ "$FORCE_ALLOWED" =~ ^[Yy]$ ]] && break
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
        if ! read_keepalive 25; then
            log_warn "Cancelled - nothing written."
            return 1
        fi
        KEEPALIVE="$KEEPALIVE_RESULT"
    else
        echo -e "  ${DIM}Usually left blank here - PersistentKeepalive only needs to be set on"
        echo -e "  ONE side of a pair to keep both directions alive, and it's normally set on"
        echo -e "  the client's peer entry (the one you'd add with role 2), not the server's.${RESET}"
        if ! read_keepalive ""; then
            log_warn "Cancelled - nothing written."
            return 1
        fi
        KEEPALIVE="$KEEPALIVE_RESULT"
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

    # Shared with edit_peer: shows real error text on failure (the old inline
    # version threw it away) and knows that AllowedIPs outside the tunnel
    # subnet need a restart, since `wg syncconf` cannot install routes.
    offer_live_apply "$IFACE" "$CONF_FILE" "$ALLOWED_IPS"
}

# Edits or removes a peer that is ALREADY in an interface's config file:
# fix a wrong AllowedIPs, point a client at a new Endpoint, change the
# keepalive, replace a public key, or delete the peer. One change per run.
# Every change is checked, then written via apply_peer_edit() (which keeps a
# .bak of the previous config), and can be pushed into a running tunnel.
edit_peer() {
    local IFACE CONF_FILE PEER_LINES PEER_TOTAL SEL ACTION
    local PK AI EP KA MODE_HINT ROLE_TEXT
    local E_FIELD="" E_MODE="" E_VALUE="" E_ROUTED="" E_BEFORE="" E_AFTER=""
    local CONFIRM FORCE NEW_AI NEW_EP NEW_PK CUR_KA WARN_TEXT OWN_PRIV OWN_PUB w

    log_info "Edit / Remove Peer"
    print_separator
    echo -e "  ${DIM}Change or remove a peer that is ALREADY in an interface's config file -"
    echo -e "  e.g. fix a wrong AllowedIPs, point a client at a new Endpoint, replace a"
    echo -e "  public key after a device re-generated its keys, or delete a peer. Every"
    echo -e "  change is checked before it is saved, and the previous config is kept as"
    echo -e "  <interface>.conf.bak so it can be undone.${RESET}"
    print_separator

    read -rp "  Interface Name [default: wg0, or 'c' to cancel]: " IFACE
    if is_cancel "$IFACE"; then
        log_warn "Cancelled."
        return 1
    fi
    IFACE=${IFACE:-wg0}
    if ! is_valid_iface_name "$IFACE"; then
        log_error "Invalid interface name. Use letters, numbers, '-' or '_' only (max 15 chars)."
        return 1
    fi

    CONF_FILE="/etc/wireguard/${IFACE}.conf"
    if [ ! -f "$CONF_FILE" ]; then
        log_error "No config found at $CONF_FILE - create the interface first (option 3)."
        return 1
    fi

    PEER_LINES=$(list_peers "$CONF_FILE")
    if [ -z "$PEER_LINES" ]; then
        log_warn "$CONF_FILE has no [Peer] entries yet - nothing to edit. Use option 4 or 5 to add one."
        return 0
    fi
    PEER_TOTAL=$(printf '%s\n' "$PEER_LINES" | grep -c '')

    echo ""
    echo -e "  ${BOLD}Peers in $CONF_FILE:${RESET}"
    print_peer_summary "$PEER_LINES"
    echo ""
    while true; do
        read -rp "  Which peer number? [1-$PEER_TOTAL, or 'c' to cancel]: " SEL
        if is_cancel "$SEL"; then
            log_warn "Cancelled."
            return 1
        fi
        if [[ "$SEL" =~ ^[0-9]{1,4}$ ]] && [ "$((10#$SEL))" -ge 1 ] && [ "$((10#$SEL))" -le "$PEER_TOTAL" ]; then
            SEL=$((10#$SEL))
            break
        fi
        log_error "Enter a number between 1 and $PEER_TOTAL."
    done

    IFS='|' read -r _ PK AI EP KA <<< "$(printf '%s\n' "$PEER_LINES" | awk -F'|' -v i="$SEL" '$1 == i')"
    if [ -n "$EP" ]; then
        MODE_HINT="client"
        ROLE_TEXT="has an Endpoint - looks like the SERVER this machine connects to"
    else
        MODE_HINT="server"
        ROLE_TEXT="no Endpoint - looks like a CLIENT registered on this machine"
    fi

    print_separator
    echo -e "  ${BOLD}Peer #$SEL${RESET} ($ROLE_TEXT)"
    echo "    PublicKey           : $PK"
    echo "    AllowedIPs          : ${AI:-<not set>}"
    echo "    Endpoint            : ${EP:-<not set>}"
    echo "    PersistentKeepalive : ${KA:-<not set>}"
    print_separator
    echo -e "  ${BOLD}What do you want to do with peer #$SEL?${RESET}"
    echo "    1) Change AllowedIPs"
    echo "    2) Change Endpoint"
    echo "    3) Change PersistentKeepalive"
    echo "    4) Replace PublicKey (the device re-generated its keys)"
    echo "    5) Remove this peer"
    read -rp "  Select [1-5, or 'c' to cancel]: " ACTION
    if is_cancel "$ACTION"; then
        log_warn "Cancelled."
        return 1
    fi

    case "$ACTION" in
        1)
            E_FIELD="AllowedIPs"
            if [ "$MODE_HINT" = "server" ]; then
                echo -e "  ${DIM}For a client registered here, use its single tunnel IP, e.g. 10.10.10.2/32.${RESET}"
            else
                echo -e "  ${DIM}For the server you connect to: 0.0.0.0/0 = full tunnel, or list only the"
                echo -e "  subnets that should go through it (split tunnel), comma-separated.${RESET}"
            fi
            while true; do
                read -rp "  New AllowedIPs [current: ${AI:-none}; Enter = keep, 'c' to cancel]: " NEW_AI
                if is_cancel "$NEW_AI"; then
                    log_warn "Cancelled."
                    return 1
                fi
                if [ -z "$NEW_AI" ]; then
                    log_info "No change."
                    return 0
                fi
                if ! is_valid_allowed_ips "$NEW_AI"; then
                    log_error "Invalid format. Expected one or more comma-separated IPv4 CIDRs, e.g. 10.10.10.2/32."
                    continue
                fi
                NEW_AI=$(normalize_allowed_ips "$NEW_AI")
                if [ "$NEW_AI" = "$AI" ]; then
                    log_info "That is already the current value - no change."
                    return 0
                fi
                WARN_TEXT=$(allowed_ips_warnings "$CONF_FILE" "$NEW_AI" "$MODE_HINT" "$SEL")
                if [ -z "$WARN_TEXT" ]; then
                    break
                fi
                while IFS= read -r w; do
                    log_warn "$w"
                done <<< "$WARN_TEXT"
                read -rp "  Use it anyway? [y/N]: " FORCE
                [[ "$FORCE" =~ ^[Yy]$ ]] && break
            done
            E_MODE="set"; E_VALUE="$NEW_AI"; E_ROUTED="$NEW_AI"
            E_BEFORE="$AI"; E_AFTER="$NEW_AI"
            ;;
        2)
            E_FIELD="Endpoint"
            if [ "$MODE_HINT" = "server" ]; then
                log_info "A client registered on a server normally has NO Endpoint - the server learns it"
                log_info "when the client connects. Set one only if you really need it."
            else
                echo -e "  ${DIM}The server's REAL address the client dials (LAN IP, public IP or DDNS name"
                echo -e "  plus port) - never its tunnel IP.${RESET}"
            fi
            while true; do
                read -rp "  New Endpoint [current: ${EP:-none}; Enter = keep, 'none' = remove it, 'c' to cancel]: " NEW_EP
                if is_cancel "$NEW_EP"; then
                    log_warn "Cancelled."
                    return 1
                fi
                if [ -z "$NEW_EP" ]; then
                    log_info "No change."
                    return 0
                fi
                if [ "$NEW_EP" = "none" ] || [ "$NEW_EP" = "NONE" ]; then
                    NEW_EP=""
                    break
                fi
                if is_valid_endpoint "$NEW_EP"; then
                    break
                fi
                log_error "Invalid format. Expected host_or_ip:port with a valid port (1-65535)."
            done
            if [ "$NEW_EP" = "$EP" ]; then
                log_info "That is already the current value - no change."
                return 0
            fi
            if [ -z "$NEW_EP" ]; then
                E_MODE="unset"; E_VALUE=""
            else
                E_MODE="set"; E_VALUE="$NEW_EP"
            fi
            E_ROUTED=""
            E_BEFORE="$EP"; E_AFTER="$NEW_EP"
            ;;
        3)
            E_FIELD="PersistentKeepalive"
            echo -e "  ${DIM}Seconds between heartbeat packets that keep a NAT mapping open. Typical: 25"
            echo -e "  on a client behind NAT, left out on a server. 0 removes the line.${RESET}"
            CUR_KA="$KA"
            [ "$CUR_KA" = "0" ] && CUR_KA=""
            if ! read_keepalive "$CUR_KA"; then
                log_warn "Cancelled."
                return 1
            fi
            if [ "$KEEPALIVE_RESULT" = "$CUR_KA" ]; then
                log_info "That is already the current value - no change."
                return 0
            fi
            if [ -z "$KEEPALIVE_RESULT" ]; then
                E_MODE="unset"; E_VALUE=""
            else
                E_MODE="set"; E_VALUE="$KEEPALIVE_RESULT"
            fi
            E_ROUTED=""
            E_BEFORE="$KA"; E_AFTER="$KEEPALIVE_RESULT"
            ;;
        4)
            E_FIELD="PublicKey"
            echo -e "  ${DIM}Enter the peer's NEW public key - the one that device shows after"
            echo -e "  re-generating its keys. The old key stops being accepted the moment this"
            echo -e "  is applied, so the device must already be using the matching new private key.${RESET}"
            while true; do
                read -rp "  New Public Key [or 'c' to cancel]: " NEW_PK
                if is_cancel "$NEW_PK"; then
                    log_warn "Cancelled."
                    return 1
                fi
                if ! is_valid_wg_key "$NEW_PK"; then
                    log_error "That doesn't look like a valid WireGuard key (expected 44-char base64, e.g. ending in '=')."
                    continue
                fi
                if [ "$NEW_PK" = "$PK" ]; then
                    log_info "That is already this peer's key - no change."
                    return 0
                fi
                OWN_PRIV=$(grep -i "^\s*PrivateKey" "$CONF_FILE" | head -1 | cut -d'=' -f2- | xargs)
                OWN_PUB=""
                [ -n "$OWN_PRIV" ] && OWN_PUB=$(echo "$OWN_PRIV" | wg pubkey 2>/dev/null)
                if [ -n "$OWN_PUB" ] && [ "$NEW_PK" = "$OWN_PUB" ]; then
                    log_error "That is THIS machine's OWN public key, not the peer's. Each machine needs"
                    log_error "its own separate keypair - re-check which key you copied."
                    continue
                fi
                if printf '%s\n' "$PEER_LINES" | awk -F'|' -v k="$NEW_PK" -v me="$SEL" '$2 == k && $1 != me { found = 1 } END { exit !found }'; then
                    log_error "Another peer in this file already uses that public key."
                    continue
                fi
                break
            done
            E_MODE="set"; E_VALUE="$NEW_PK"; E_ROUTED=""
            E_BEFORE="$PK"; E_AFTER="$NEW_PK"
            ;;
        5)
            E_FIELD="peer"
            print_separator
            echo -e "  ${BOLD}This will remove peer #$SEL from $CONF_FILE:${RESET}"
            echo "    PublicKey  : $PK"
            echo "    AllowedIPs : ${AI:-<not set>}"
            [ -n "$EP" ] && echo "    Endpoint   : $EP"
            print_separator
            log_info "The previous config is kept as ${CONF_FILE}.bak, so this can be undone."
            read -rp "  Remove this peer? [y/N]: " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                log_info "Cancelled - nothing changed."
                return 0
            fi
            E_MODE="remove"; E_VALUE=""; E_ROUTED=""
            ;;
        *)
            log_error "Invalid option."
            return 1
            ;;
    esac

    # Show exactly what will change and confirm (removal already asked above).
    if [ "$E_MODE" != "remove" ]; then
        print_separator
        echo -e "  ${BOLD}Peer #$SEL - $E_FIELD${RESET}"
        echo "    before: ${E_BEFORE:-<not set>}"
        echo "    after:  ${E_AFTER:-<removed>}"
        print_separator
        read -rp "  Save this change? [Y/n]: " CONFIRM
        if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
            log_info "Cancelled - nothing written."
            return 0
        fi
    fi

    if ! apply_peer_edit "$IFACE" "$CONF_FILE" "$SEL" "$E_MODE" "$E_FIELD" "$E_VALUE"; then
        return 1
    fi
    if [ "$E_MODE" = "remove" ]; then
        log_success "Peer #$SEL removed from $CONF_FILE."
    else
        log_success "Peer #$SEL updated in $CONF_FILE."
    fi

    echo ""
    PEER_LINES=$(list_peers "$CONF_FILE")
    if [ -n "$PEER_LINES" ]; then
        echo -e "  ${BOLD}Peers now in $CONF_FILE:${RESET}"
        print_peer_summary "$PEER_LINES"
    else
        log_warn "$CONF_FILE now has no peers."
    fi
    echo ""
    offer_live_apply "$IFACE" "$CONF_FILE" "$E_ROUTED"
}

check_status() {
    if ! command -v wg &> /dev/null; then
        log_error "WireGuard is not installed."
        return
    fi

    log_info "WireGuard Interface Status (wg show):"
    print_separator
    local WG_OUT
    WG_OUT=$(wg show 2>&1)
    if [ -n "$WG_OUT" ]; then
        echo "$WG_OUT"
    else
        echo "  (no WireGuard interface is currently up)"
    fi
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
    read -rp "  Enter Interface Name [default: wg0, or 'c' to cancel]: " IFACE
    if is_cancel "$IFACE"; then
        log_warn "Cancelled."
        return
    fi
    IFACE=${IFACE:-wg0}
    if ! is_valid_iface_name "$IFACE"; then
        log_error "Invalid interface name. Use letters, numbers, '-' or '_' only (max 15 chars)."
        return
    fi

    if [ ! -f "/etc/wireguard/${IFACE}.conf" ]; then
        log_error "No config found at /etc/wireguard/${IFACE}.conf - create it first (option 3)."
        return
    fi

    local STATE="DOWN"
    is_interface_active "$IFACE" && STATE="UP"
    log_info "Interface '$IFACE' is currently $STATE."

    echo "  1) Enable / Up"
    echo "  2) Disable / Down"
    read -rp "  Select Action [1-2, or 'c' to cancel]: " ACT

    # BUG FIX: unquoted `case $ACT in` is subject to word-splitting/globbing
    # on the case subject. Low-risk with a `read` result in practice, but
    # inconsistent with the quoting discipline used everywhere else in this
    # script - quoted here for correctness.
    case "$ACT" in
        1)
            if [ "$STATE" = "UP" ]; then
                log_info "Interface $IFACE is already up - nothing to do."
            else
                log_info "Bringing up interface $IFACE..."
                wg-quick up "$IFACE" && log_success "Interface $IFACE brought up successfully!" || log_error "Failed to bring up $IFACE."
            fi
            ;;
        2)
            if [ "$STATE" = "DOWN" ]; then
                log_info "Interface $IFACE is already down - nothing to do."
            else
                log_info "Bringing down interface $IFACE..."
                wg-quick down "$IFACE" && log_success "Interface $IFACE brought down successfully!" || log_error "Failed to bring down $IFACE."
            fi
            ;;
        c|C|cancel|CANCEL|q|Q)
            log_warn "Cancelled."
            ;;
        *)
            log_warn "Invalid option."
            ;;
    esac
}
#----------------------------------------------#
#-------------------Main Menu------------------#
#----------------------------------------------#
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
        echo -e "  ${BOLD}8.${RESET} Edit / Remove Peer"
        echo -e "  ${BOLD}0.${RESET} Exit"
        print_separator
        echo -e "  ${CYAN}${BOLD}QUICK GUIDE & WORKFLOW:${RESET}"
        echo -e "  ${BOLD}• First-Time Setup:${RESET}"
        echo -e "    Run on ${BOLD}each machine${RESET} in order: ${GREEN}${BOLD}1${RESET} → ${GREEN}${BOLD}2${RESET} → ${GREEN}${BOLD}3${RESET} → ${GREEN}${BOLD}4${RESET} → ${GREEN}${BOLD}7${RESET}"
        echo -e "    ${DIM}(Generate unique keys on each host; never share private keys)${RESET}"
        echo -e "  ${BOLD}• Phone / Laptop Client:${RESET}"
        echo -e "    Run option ${GREEN}${BOLD}5${RESET} on the ${BOLD}Server${RESET} to create ready-to-use .conf & QR code"
        echo -e "  ${BOLD}• Manage Peers:${RESET}"
        echo -e "    Run option ${GREEN}${BOLD}8${RESET} to edit AllowedIPs, Endpoints, or remove peers"
        echo -e "  ${BOLD}• Internet Forwarding (VPN Gateway):${RESET}"
        echo -e "    Run ${YELLOW}${BOLD}nat.sh${RESET} on the server to enable NAT & IPv4 forwarding"
        print_separator

        read -rp "  Select Option [0-8]: " OPT

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
            8)
                edit_peer
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