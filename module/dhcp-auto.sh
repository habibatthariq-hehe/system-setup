#!/bin/bash
set -e

# ==============================================================================
# DHCP SERVER AUTOMATION SCRIPT WITH AUTO DISTRO DETECTION & CUSTOM CONFIG
# ==============================================================================

# UI Colors & Formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

DEBUG=0

print_banner() {
    echo -e "${CYAN}${BOLD}╔═════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║                AUTOMATED DHCP SERVER SETUP TOOL                 ║${RESET}"
    echo -e "${CYAN}${BOLD}╚═════════════════════════════════════════════════════════════════╝${RESET}\n"
}

# ------------------------------------------------------------------------------
# 1. ROOT & DISTRO DETECTION
# ------------------------------------------------------------------------------
print_banner

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[ERROR]${RESET} This script must be run as root. Please run with sudo or as root user."
    exit 1
fi

echo -e "${BLUE}${BOLD}[1/6] Detecting System Distribution & Package Manager...${RESET}"

DISTRO_NAME="Unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_NAME="${PRETTY_NAME:-$NAME}"
fi

PKG_MGR=""
if command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
elif command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
elif command -v zypper >/dev/null 2>&1; then
    PKG_MGR="zypper"
else
    echo -e "${RED}${BOLD}[ERROR]${RESET} No supported package manager found (apt, dnf, yum, pacman, zypper)."
    exit 1
fi

# Determine distro specific settings
case "$PKG_MGR" in
    apt)
        DHCP_PKG="isc-dhcp-server"
        DHCP_SERVICE="isc-dhcp-server"
        IFACE_CONFIG_FILE="/etc/default/isc-dhcp-server"
        IFACE_VAR="INTERFACESv4"
        ;;
    dnf|yum)
        DHCP_PKG="dhcp-server"
        DHCP_SERVICE="dhcpd"
        IFACE_CONFIG_FILE="/etc/sysconfig/dhcpd"
        IFACE_VAR="DHCPDARGS"
        ;;
    pacman)
        DHCP_PKG="dhcp"
        DHCP_SERVICE="dhcpd4"
        IFACE_CONFIG_FILE="/etc/conf.d/dhcpd4"
        IFACE_VAR="DHCPD4_ARGS"
        ;;
    zypper)
        DHCP_PKG="dhcp-server"
        DHCP_SERVICE="dhcpd"
        IFACE_CONFIG_FILE="/etc/sysconfig/dhcpd"
        IFACE_VAR="DHCPD_INTERFACE"
        ;;
esac

echo -e "  - ${BOLD}Detected OS:${RESET} ${GREEN}${DISTRO_NAME}${RESET}"
echo -e "  - ${BOLD}Package Manager:${RESET} ${GREEN}${PKG_MGR}${RESET}"
echo -e "  - ${BOLD}Target Package:${RESET} ${CYAN}${DHCP_PKG}${RESET}"
echo -e "  - ${BOLD}Target Service:${RESET} ${CYAN}${DHCP_SERVICE}${RESET}\n"

# ------------------------------------------------------------------------------
# 2. NETWORK INTERFACE SELECTION
# ------------------------------------------------------------------------------
echo -e "${BLUE}${BOLD}[2/6] Network Interface Configuration...${RESET}"

# Auto-detect available network interfaces
DETECTED_IFACES=($(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v '^lo$' || true))
if [ ${#DETECTED_IFACES[@]} -eq 0 ]; then
    DETECTED_IFACES=($(ls /sys/class/net 2>/dev/null | grep -v '^lo$' || true))
fi

echo -e "Detected available network interfaces:"
if [ ${#DETECTED_IFACES[@]} -gt 0 ]; then
    for i in "${!DETECTED_IFACES[@]}"; do
        echo -e "  [${CYAN}$((i+1))${RESET}] ${DETECTED_IFACES[$i]}"
    done
else
    echo -e "  ${YELLOW}(No active interfaces auto-detected)${RESET}"
fi

echo -e ""
read -p "Enter network interface(s) to bind DHCP (e.g. ens37 ens38 or number 1): " IFACE_INPUT

SELECTED_IFACES=""
if [[ "$IFACE_INPUT" =~ ^[0-9]+$ ]] && [ "$IFACE_INPUT" -ge 1 ] && [ "$IFACE_INPUT" -le "${#DETECTED_IFACES[@]}" ]; then
    SELECTED_IFACES="${DETECTED_IFACES[$((IFACE_INPUT-1))]}"
elif [ -n "$IFACE_INPUT" ]; then
    SELECTED_IFACES="$IFACE_INPUT"
else
    if [ ${#DETECTED_IFACES[@]} -gt 0 ]; then
        SELECTED_IFACES="${DETECTED_IFACES[0]}"
    else
        SELECTED_IFACES="eth0"
    fi
fi
echo -e "  Selected interface(s): ${GREEN}${SELECTED_IFACES}${RESET}\n"

# ------------------------------------------------------------------------------
# 3. INTERACTIVE IP & SUBNET CONFIGURATION
# ------------------------------------------------------------------------------
echo -e "${BLUE}${BOLD}[3/6] DHCP Global & Subnet Settings...${RESET}"

read -p "Use default template subnets (192.168.30.0/24 & 192.168.40.0/24)? [y/N]: " USE_DEFAULTS

GLOBAL_DOMAIN="lab.local"
GLOBAL_DNS="192.168.1.1"
DEFAULT_LEASE="600"
MAX_LEASE="7200"

SUBNETS=()

if [[ "$USE_DEFAULTS" =~ ^[Yy]$ ]]; then
    # Default preset subnets
    SUBNETS+=(
        "SUBNET=192.168.30.0|NETMASK=255.255.255.0|RANGE_START=192.168.30.100|RANGE_END=192.168.30.200|ROUTER=192.168.30.1|DNS=192.168.30.2|DOMAIN=lab.local"
        "SUBNET=192.168.40.0|NETMASK=255.255.255.0|RANGE_START=192.168.40.100|RANGE_END=192.168.40.200|ROUTER=192.168.40.1|DNS=192.168.30.2|DOMAIN=lab.local"
    )
else
    # Custom input
    read -p "Global Domain Name [$GLOBAL_DOMAIN]: " INPUT_DOMAIN
    [ -n "$INPUT_DOMAIN" ] && GLOBAL_DOMAIN="$INPUT_DOMAIN"

    read -p "Global Primary DNS [$GLOBAL_DNS]: " INPUT_DNS
    [ -n "$INPUT_DNS" ] && GLOBAL_DNS="$INPUT_DNS"

    read -p "Default Lease Time (seconds) [$DEFAULT_LEASE]: " INPUT_DEFAULT_LEASE
    [ -n "$INPUT_DEFAULT_LEASE" ] && DEFAULT_LEASE="$INPUT_DEFAULT_LEASE"

    read -p "Max Lease Time (seconds) [$MAX_LEASE]: " INPUT_MAX_LEASE
    [ -n "$INPUT_MAX_LEASE" ] && MAX_LEASE="$INPUT_MAX_LEASE"

    ADD_MORE="y"
    SUBNET_COUNT=1
    while [[ "$ADD_MORE" =~ ^[Yy]$ ]]; do
        echo -e "\n${CYAN}--- Subnet #$SUBNET_COUNT Configuration ---${RESET}"
        
        DEF_NET="192.168.$((30 + (SUBNET_COUNT-1)*10)).0"
        DEF_MASK="255.255.255.0"
        DEF_START="192.168.$((30 + (SUBNET_COUNT-1)*10)).100"
        DEF_END="192.168.$((30 + (SUBNET_COUNT-1)*10)).200"
        DEF_GW="192.168.$((30 + (SUBNET_COUNT-1)*10)).1"

        read -p "Subnet Network IP [$DEF_NET]: " SUB_NET
        [ -z "$SUB_NET" ] && SUB_NET="$DEF_NET"

        read -p "Subnet Netmask [$DEF_MASK]: " SUB_MASK
        [ -z "$SUB_MASK" ] && SUB_MASK="$DEF_MASK"

        read -p "DHCP Range Start [$DEF_START]: " R_START
        [ -z "$R_START" ] && R_START="$DEF_START"

        read -p "DHCP Range End [$DEF_END]: " R_END
        [ -z "$R_END" ] && R_END="$DEF_END"

        read -p "Router / Gateway IP [$DEF_GW]: " GW
        [ -z "$GW" ] && GW="$DEF_GW"

        read -p "Subnet DNS Server [$GLOBAL_DNS]: " S_DNS
        [ -z "$S_DNS" ] && S_DNS="$GLOBAL_DNS"

        read -p "Subnet Domain Name [$GLOBAL_DOMAIN]: " S_DOM
        [ -z "$S_DOM" ] && S_DOM="$GLOBAL_DOMAIN"

        SUBNETS+=(
            "SUBNET=$SUB_NET|NETMASK=$SUB_MASK|RANGE_START=$R_START|RANGE_END=$R_END|ROUTER=$GW|DNS=$S_DNS|DOMAIN=$S_DOM"
        )

        SUBNET_COUNT=$((SUBNET_COUNT+1))
        read -p "Do you want to add another subnet? [y/N]: " ADD_MORE
    done
fi

# ------------------------------------------------------------------------------
# 4. CONFIGURATION REVIEW & USER APPROVAL
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}${BOLD}=================================================================${RESET}"
echo -e "${YELLOW}${BOLD}               CONFIGURATION REVIEW & SUMMARY                   ${RESET}"
echo -e "${YELLOW}${BOLD}=================================================================${RESET}"
echo -e " ${BOLD}OS Detected:${RESET}         $DISTRO_NAME ($PKG_MGR)"
echo -e " ${BOLD}DHCP Package:${RESET}        $DHCP_PKG"
echo -e " ${BOLD}DHCP Service:${RESET}        $DHCP_SERVICE"
echo -e " ${BOLD}Target Interface(s):${RESET} $SELECTED_IFACES"
echo -e " ${BOLD}Global Domain Name:${RESET}  $GLOBAL_DOMAIN"
echo -e " ${BOLD}Global Primary DNS:${RESET}  $GLOBAL_DNS"
echo -e " ${BOLD}Default Lease Time:${RESET}  $DEFAULT_LEASE sec"
echo -e " ${BOLD}Max Lease Time:${RESET}      $MAX_LEASE sec"
echo -e " ${BOLD}Subnet Count:${RESET}        ${#SUBNETS[@]}"
echo -e " ${BOLD}Subnet Breakdown:${RESET}"

for idx in "${!SUBNETS[@]}"; do
    IFS='|' read -r s_net s_mask r_start r_end router dns domain <<< "${SUBNETS[$idx]}"
    s_net="${s_net#*=}"
    s_mask="${s_mask#*=}"
    r_start="${r_start#*=}"
    r_end="${r_end#*=}"
    router="${router#*=}"
    dns="${dns#*=}"
    domain="${domain#*=}"
    echo -e "   ${CYAN}[Subnet $((idx+1))]${RESET} Network: $s_net/$s_mask | Range: $r_start - $r_end | GW: $router | DNS: $dns | Domain: $domain"
done
echo -e "${YELLOW}${BOLD}=================================================================${RESET}\n"

read -p "Do you approve and want to apply this configuration to the system? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${RED}${BOLD}[CANCELLED]${RESET} Configuration aborted by user. No changes were made."
    exit 0
fi

# ------------------------------------------------------------------------------
# 5. PACKAGE INSTALLATION & CONFIGURATION APPLICATION
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}${BOLD}[4/6] Installing DHCP Package ($DHCP_PKG)...${RESET}"
read -p "Proceed with installing/updating $DHCP_PKG via $PKG_MGR? [Y/n]: " INSTALL_CONFIRM
if [[ "$INSTALL_CONFIRM" =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}[SKIP] Skipping package installation.${RESET}"
else
    case "$PKG_MGR" in
        apt)
            apt update
            apt install -y "$DHCP_PKG"
            ;;
        dnf)
            dnf install -y "$DHCP_PKG"
            ;;
        yum)
            yum install -y "$DHCP_PKG"
            ;;
        pacman)
            pacman -Sy --noconfirm "$DHCP_PKG"
            ;;
        zypper)
            zypper install -y "$DHCP_PKG"
            ;;
    esac
fi

echo -e "\n${BLUE}${BOLD}[5/6] Writing Configuration Files...${RESET}"

# Update Interface Defaults file
if [ -n "$IFACE_CONFIG_FILE" ]; then
    mkdir -p "$(dirname "$IFACE_CONFIG_FILE")"
    if [ -f "$IFACE_CONFIG_FILE" ]; then
        cp "$IFACE_CONFIG_FILE" "${IFACE_CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    fi

    if grep -q "^${IFACE_VAR}=" "$IFACE_CONFIG_FILE" 2>/dev/null; then
        sed -i "s|^${IFACE_VAR}=.*|${IFACE_VAR}=\"${SELECTED_IFACES}\"|" "$IFACE_CONFIG_FILE"
    else
        echo "${IFACE_VAR}=\"${SELECTED_IFACES}\"" >> "$IFACE_CONFIG_FILE"
    fi
    echo -e "  - Updated interface in ${GREEN}${IFACE_CONFIG_FILE}${RESET}"
fi

# Backup & Write /etc/dhcp/dhcpd.conf
mkdir -p /etc/dhcp
if [ -f /etc/dhcp/dhcpd.conf ]; then
    cp /etc/dhcp/dhcpd.conf "/etc/dhcp/dhcpd.conf.bak.$(date +%Y%m%d%H%M%S)"
fi

cat > /etc/dhcp/dhcpd.conf <<EOF
# Global DHCP Config - Generated on $(date)
option domain-name "${GLOBAL_DOMAIN}";
option domain-name-servers ${GLOBAL_DNS};

default-lease-time ${DEFAULT_LEASE};
max-lease-time ${MAX_LEASE};

authoritative;
ddns-update-style none;

EOF

for idx in "${!SUBNETS[@]}"; do
    IFS='|' read -r s_net s_mask r_start r_end router dns domain <<< "${SUBNETS[$idx]}"
    s_net="${s_net#*=}"
    s_mask="${s_mask#*=}"
    r_start="${r_start#*=}"
    r_end="${r_end#*=}"
    router="${router#*=}"
    dns="${dns#*=}"
    domain="${domain#*=}"

    NET_PREFIX=$(echo "$s_net" | cut -d'.' -f1-3)
    BCAST="${NET_PREFIX}.255"

    cat >> /etc/dhcp/dhcpd.conf <<EOF
# Subnet $s_net/$s_mask
subnet $s_net netmask $s_mask {
    range $r_start $r_end;
    option routers $router;
    option subnet-mask $s_mask;
    option broadcast-address $BCAST;
    option domain-name-servers $dns;
    option domain-name "$domain";
}

EOF
done

echo -e "  - Configured ${GREEN}/etc/dhcp/dhcpd.conf${RESET}"

# Syntax Check
echo -e "\n${BLUE}${BOLD}[6/6] Checking Syntax & Starting Service...${RESET}"
if command -v dhcpd >/dev/null 2>&1; then
    echo -e "  - Running DHCP syntax test..."
    dhcpd -t -cf /etc/dhcp/dhcpd.conf
fi

if [ "$DEBUG" -eq 1 ]; then
    echo -e "${YELLOW}DEBUG MODE ENABLED. Running dhcpd in foreground...${RESET}"
    dhcpd -4 -d -cf /etc/dhcp/dhcpd.conf
    exit 0
fi

# Enable and start service
systemctl enable "$DHCP_SERVICE"
systemctl restart "$DHCP_SERVICE"

echo -e "\n${GREEN}${BOLD}=== DHCP SERVER SETUP COMPLETE ===${RESET}"
systemctl status "$DHCP_SERVICE" --no-pager || true
