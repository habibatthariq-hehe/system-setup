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
        UPDATE_CMD="apt-get update -y"
        INSTALL_CMD="apt-get install wireguard wireguard-tools -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        UPDATE_CMD="dnf check-update"
        INSTALL_CMD="dnf install wireguard-tools -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        UPDATE_CMD="yum check-update"
        INSTALL_CMD="yum install wireguard-tools -y"
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
    $UPDATE_CMD
    $INSTALL_CMD

    if command -v wg &> /dev/null; then
        log_success "WireGuard installed successfully!"
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

    log_info "Generating new keypair (Private & Public Key)..."
    local privkey
    local pubkey

    privkey=$(wg genkey)
    pubkey=$(echo "$privkey" | wg pubkey)

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

configure_wireguard() {
    log_info "WireGuard Interface Configuration"
    print_separator

    read -rp "  Interface Name [default: wg0]: " IFACE
    IFACE=${IFACE:-wg0}

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

        if [ -n "$EXISTING_IP" ]; then
            log_info "Current IP Address: $EXISTING_IP"
        fi

        read -rp "  Do you want to edit or overwrite this configuration? [Y/n]: " MODIFY_CONF
        if [[ "$MODIFY_CONF" =~ ^[Nn]$ ]]; then
            log_info "Configuration update cancelled."
            return
        fi
    fi

    # Prompt for IP Address & Subnet (with existing IP as default option if present)
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

    # Prompt for Port
    local DEFAULT_PORT="${EXISTING_PORT:-51820}"
    read -rp "  Listen Port [default: $DEFAULT_PORT]: " PORT
    PORT=${PORT:-$DEFAULT_PORT}

    # Check for Private Key
    local PRIV_KEY="$EXISTING_KEY"
    if [ -z "$PRIV_KEY" ] && [ -f "/etc/wireguard/keys/privatekey" ]; then
        read -rp "  Use Private Key from /etc/wireguard/keys/privatekey? [Y/n]: " USE_EXISTING
        if [[ "$USE_EXISTING" =~ ^[Yy]$ ]] || [ -z "$USE_EXISTING" ]; then
            PRIV_KEY=$(cat /etc/wireguard/keys/privatekey)
        fi
    fi

    if [ -z "$PRIV_KEY" ]; then
        read -rp "  Enter Private Key manually (leave blank to generate automatically): " PRIV_KEY
        if [ -z "$PRIV_KEY" ]; then
            PRIV_KEY=$(wg genkey)
            log_info "Private Key generated automatically."
        fi
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

    echo "  1) Enable / Up"
    echo "  2) Disable / Down"
    read -rp "  Select Action [1-2]: " ACT

    case $ACT in
        1)
            log_info "Bringing up interface $IFACE..."
            wg-quick up "$IFACE" && log_success "Interface $IFACE brought up successfully!" || log_error "Failed to bring up $IFACE."
            ;;
        2)
            log_info "Bringing down interface $IFACE..."
            wg-quick down "$IFACE" && log_success "Interface $IFACE brought down successfully!" || log_error "Failed to bring down $IFACE."
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
        echo -e "  ${BOLD}4.${RESET} Check Status & Configuration"
        echo -e "  ${BOLD}5.${RESET} Bring Up / Down WireGuard Interface"
        echo -e "  ${BOLD}0.${RESET} Exit"
        print_separator

        read -rp "  Select Option [1-6]: " OPT

        case $OPT in
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
                check_status
                ;;
            5)
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