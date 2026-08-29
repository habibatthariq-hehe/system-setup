#!/bin/bash

DRY_RUN=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
    esac
done

#Check Root 
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "\033[0;31m[ERROR]\033[0m This script must be run as root. Use: sudo bash $0"
        exit 1
    fi
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

#Print Banner 
print_banner() {
    clear
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║                   STATIC IP SETUP TOOL                            ║${RESET}"
    echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_separator() {
    echo -e "${DIM}─────────────────────────────────────────────────────────────────────${RESET}"
}

log_error() {
    echo -e "${RED}${BOLD}[ERROR]${RESET}   $1"
}

set_static_ip() {
    echo -e "${CYAN}Setting static IP Address${RESET}"
    read -p "Enter interface (e.g., eth0): " interface
    if [ -z "$interface" ]; then
        log_error "Interface cannot be empty"
        return
    fi
    read -p "Enter IP Address with CIDR (e.g., 192.168.1.100/24): " ip_address
    read -p "Enter Gateway (e.g., 192.168.1.1): " gateway
    read -p "Enter DNS (comma separated, e.g., 8.8.8.8,1.1.1.1): " dns

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}${BOLD}[DRY RUN]${RESET} The following configuration would be applied:"
        echo "Interface: $interface"
        echo "IP Address: $ip_address"
        echo "Gateway: $gateway"
        echo "DNS: $dns"
        echo -e "${YELLOW}${BOLD}[DRY RUN]${RESET} No changes were made."
        return
    fi

    # Detect network manager
    if command -v nmcli &> /dev/null; then
        echo -e "${GREEN}${BOLD}[OK]${RESET}      Using NetworkManager (nmcli) to set static IP"
        nmcli con mod "$interface" ipv4.addresses "$ip_address"
        nmcli con mod "$interface" ipv4.gateway "$gateway"
        nmcli con mod "$interface" ipv4.dns "$dns"
        nmcli con mod "$interface" ipv4.method manual
        nmcli con up "$interface"
        echo -e "${GREEN}${BOLD}[OK]${RESET}      Configuration applied successfully via nmcli."
    elif [ -d "/etc/netplan" ]; then
        echo -e "${GREEN}${BOLD}[OK]${RESET}      Using Netplan to set static IP"
        local netplan_file="/etc/netplan/99-custom-static-$interface.yaml"
        cat <<EOF > "$netplan_file"
network:
  version: 2
  renderer: networkd
  ethernets:
    $interface:
      dhcp4: no
      addresses:
        - $ip_address
      routes:
        - to: default
          via: $gateway
      nameservers:
        addresses: [${dns//,/, }]
EOF
        netplan apply
        echo -e "${GREEN}${BOLD}[OK]${RESET}      Configuration applied successfully via Netplan."
    elif [ -d "/etc/network" ]; then
        echo -e "${GREEN}${BOLD}[OK]${RESET}      Using /etc/network/interfaces to set static IP"
        local ip_no_cidr=$(echo "$ip_address" | cut -d/ -f1)
        cat <<EOF >> /etc/network/interfaces

# Added by static IP setup tool
auto $interface
iface $interface inet static
    address $ip_no_cidr
    gateway $gateway
    dns-nameservers ${dns//,/ }
EOF
        systemctl restart networking
        echo -e "${GREEN}${BOLD}[OK]${RESET}      Configuration applied successfully via ifupdown."
    else
        log_error "Could not detect supported network manager (nmcli, netplan, or ifupdown)"
    fi
}

check_root

while true; do
    print_banner
    print_separator
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}${BOLD}*** DRY RUN MODE ENABLED ***${RESET}"
        print_separator
    fi

    echo "1. Set static IP Address"
    echo "2. Detect Interfaces"
    echo "3. Show IP Address"
    echo "4. Show Network Configuration File"
    echo "5. Toggle Dry Run Mode"
    echo "0. Exit"
    read -p "Enter your choice: " choice
    echo
    case $choice in
        1)
            set_static_ip
            ;;  
        2)
            echo -e "${GREEN}${BOLD}[OK]${RESET}      Detected Interfaces:"
            ip -br link show | awk '{print $1}'
            ;;  
        3)
            echo -e "${GREEN}${BOLD}[OK]${RESET}      IP Addresses:"
            ip -br addr show
            ;;  
        4)
            echo "Network Configuration File:"
            if [ -f /etc/network/interfaces ]; then
                echo -e "\n${CYAN}--- /etc/network/interfaces ---${RESET}"
                cat /etc/network/interfaces 2>/dev/null
            fi
            if ls /etc/netplan/*.yaml 1> /dev/null 2>&1; then
                echo -e "\n${CYAN}--- /etc/netplan/*.yaml ---${RESET}"
                cat /etc/netplan/*.yaml 2>/dev/null
            fi
            if command -v nmcli &> /dev/null; then
                echo -e "\n${CYAN}--- NetworkManager Connections ---${RESET}"
                nmcli con show 2>/dev/null
            fi
            ;;  
        5)
            if [ "$DRY_RUN" = true ]; then
                DRY_RUN=false
                echo -e "${GREEN}${BOLD}[OK]${RESET}      Dry Run Mode DISABLED"
            else
                DRY_RUN=true
                echo -e "${GREEN}${BOLD}[OK]${RESET}      Dry Run Mode ENABLED"
            fi
            ;;
        0)
            echo -e "${GREEN}${BOLD}[OK]${RESET}      Exiting"
            exit 0
            ;;  
        *)
            log_error "Invalid choice"
            ;;
    esac
    echo
    read -p "Press Enter to continue..."
done
