#!/bin/bash

# ============================================================================
# DHCP AUTO SETUP SCRIPT
# Automated DHCP server configuration with minimal user input
# ============================================================================

# ----------------------------- UI Colors & Formatting -------------------------
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
    echo -e "${CYAN}${BOLD}║              DHCP AUTO SETUP TOOL                                ║${RESET}"
    echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_separator() {
    echo -e "${DIM}─────────────────────────────────────────────────────────────────────${RESET}"
}

log_info()    { echo -e "  ${CYAN}${BOLD}[INFO]${RESET}    $1"; }
log_success() { echo -e "  ${GREEN}${BOLD}[OK]${RESET}      $1"; }
log_warn()    { echo -e "  ${YELLOW}${BOLD}[WARN]${RESET}    $1"; }
log_error()   { echo -e "  ${RED}${BOLD}[ERROR]${RESET}   $1"; }

# Check if input indicates user wants to cancel
is_cancel() {
    local val="$1"
    [[ "$val" =~ ^(c|cancel|C|CANCEL|q|quit|Q|QUIT|exit|EXIT)$ ]]
}

# ----------------------------- Safety & Path Resolution -----------------------

# Resolve the project root based on this script's location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root. Use: sudo bash $0"
        exit 1
    fi
}

# ----------------------------- Main Logic --------------------------------------

main() {
    check_root
    clear
    print_banner
    print_separator
    
    log_info "DHCP Auto Setup - Automated Configuration"
    log_info "This script will automatically configure a basic DHCP server"
    echo ""
    
    # Detect package manager
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        DHCP_PKG="isc-dhcp-server"
        DHCP_SERVICE="isc-dhcp-server"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        DHCP_PKG="dhcp-server"
        DHCP_SERVICE="dhcpd"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        DHCP_PKG="dhcp"
        DHCP_SERVICE="dhcpd"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
        DHCP_PKG="dhcp"
        DHCP_SERVICE="dhcpd"
    else
        log_error "No supported package manager found."
        exit 1
    fi
    
    log_info "Detected package manager: $PKG_MANAGER"
    log_info "DHCP package: $DHCP_PKG"
    log_info "DHCP service: $DHCP_SERVICE"
    echo ""
    
    # Ask for confirmation
    read -p "  Proceed with automatic DHCP setup? [Y/n/c]: " answer
    if is_cancel "$answer" || [ "$answer" = "n" ] || [ "$answer" = "N" ]; then
        log_warn "Setup cancelled by user."
        exit 0
    fi
    
    echo ""
    log_info "Starting automatic DHCP setup..."
    
    # Install DHCP server
    log_info "Installing DHCP server package..."
    case $PKG_MANAGER in
        apt)
            apt update
            apt install -y $DHCP_PKG
            ;;
        dnf)
            dnf install -y $DHCP_PKG
            ;;
        yum)
            yum install -y $DHCP_PKG
            ;;
        pacman)
            pacman -Sy --noconfirm $DHCP_PKG
            ;;
    esac
    
    # Configure basic DHCP settings
    log_info "Configuring basic DHCP settings..."
    
    # Create a simple dhcpd.conf
    cat > /etc/dhcp/dhcpd.conf << 'EOF'
# DHCP Auto Setup Configuration
# Basic DHCP server configuration

default-lease-time 600;
max-lease-time 7200;
authoritative;

subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
    option broadcast-address 192.168.1.255;
}
EOF
    
    log_success "Basic DHCP configuration created at /etc/dhcp/dhcpd.conf"
    
    # Enable and start service
    log_info "Enabling and starting DHCP service..."
    case $PKG_MANAGER in
        apt|dnf|yum)
            systemctl enable $DHCP_SERVICE
            systemctl start $DHCP_SERVICE
            ;;
        pacman)
            systemctl enable $DHCP_SERVICE
            systemctl start $DHCP_SERVICE
            ;;
    esac
    
    # Verify service status
    sleep 2
    if systemctl is-active --quiet $DHCP_SERVICE; then
        log_success "DHCP service is running"
    else
        log_warn "DHCP service may not be started properly"
        systemctl status $DHCP_SERVICE --no-pager || true
    fi
    
    echo ""
    log_success "DHCP Auto Setup completed!"
    log_info "To customize configuration, edit /etc/dhcp/dhcpd.conf"
    log_info "To restart service: sudo systemctl restart $DHCP_SERVICE"
    
    # Ask if user wants to see current config
    echo ""
    read -p "  Show current DHCP configuration? [y/N]: " show_config
    if [[ "$show_config" =~ ^[Yy]$ ]]; then
        echo ""
        echo "=== Current DHCP Configuration ==="
        cat /etc/dhcp/dhcpd.conf
        echo "=================================="
    fi
    
    exit 0
}

# ----------------------------- Script Entry Point ------------------------------

main "$@"