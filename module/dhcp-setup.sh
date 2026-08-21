#!/bin/bash

# ==============================================================================
# DHCP SERVER INTERACTIVE SETUP SCRIPT
# Features: Auto-detection, Interactive Config, Rollback, Debug/Validation,
#           Cancel at any prompt, Automatic Screen Clearing, Append/Replace
# ==============================================================================

# ----------------------------- UI Colors & Formatting -------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

DHCPD_CONF="/etc/dhcp/dhcpd.conf"

# ----------------------------- Helper Functions -------------------------------

print_banner() {
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║              DHCP SERVER INTERACTIVE SETUP TOOL                  ║${RESET}"
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

# Pause and clear screen before returning to main menu
pause_and_clear() {
    echo ""
    read -p "  Press [Enter] to return to the main menu..." _
    clear
}

# ----------------------------- Root Check -------------------------------------

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root. Please run with sudo."
        exit 1
    fi
}

# ----------------------------- Package Manager Detection ----------------------

PKG_MGR=""
DISTRO_NAME="Unknown"
DHCP_PKG=""
DHCP_SERVICE=""
IFACE_CONFIG_FILE=""
IFACE_VAR=""

detect_package_manager() {
    echo -e "${BLUE}${BOLD}  Detecting System Distribution & Package Manager...${RESET}"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_NAME="${PRETTY_NAME:-$NAME}"
    fi

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
        log_error "No supported package manager found (apt, dnf, yum, pacman, zypper)."
        exit 1
    fi

    # Map distro-specific DHCP settings
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

    log_success "OS Detected:      ${GREEN}${DISTRO_NAME}${RESET}"
    log_success "Package Manager:  ${GREEN}${PKG_MGR}${RESET}"
    log_success "DHCP Package:     ${CYAN}${DHCP_PKG}${RESET}"
    log_success "DHCP Service:     ${CYAN}${DHCP_SERVICE}${RESET}"
}

# ==============================================================================
# MENU OPTION 1: Install DHCP Server
# ==============================================================================

install_dhcp() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Option 1] Install DHCP Server ($DHCP_PKG)${RESET}"
    print_separator
    echo -e "  ${DIM}Tip: Type 'c' or 'cancel' to return to the main menu.${RESET}\n"

    read -p "  Proceed with installing $DHCP_PKG via $PKG_MGR? [Y/n/c]: " confirm
    if is_cancel "$confirm" || [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_warn "Installation cancelled by user."
        return
    fi

    case "$PKG_MGR" in
        apt)
            apt update && apt install -y "$DHCP_PKG"
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

    if [ $? -eq 0 ]; then
        log_success "DHCP Server ($DHCP_PKG) installed successfully!"
    else
        log_error "Installation failed. Check the output above for details."
    fi
}

# ==============================================================================
# MENU OPTION 2: Detect Network Interfaces
# ==============================================================================

detect_interfaces() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Option 2] Detected Network Interfaces${RESET}"
    print_separator

    # Collect non-loopback interfaces
    local ifaces=()
    if command -v ip >/dev/null 2>&1; then
        mapfile -t ifaces < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v '^lo$')
    fi
    # Fallback to /sys/class/net
    if [ ${#ifaces[@]} -eq 0 ]; then
        mapfile -t ifaces < <(ls /sys/class/net 2>/dev/null | grep -v '^lo$')
    fi

    if [ ${#ifaces[@]} -eq 0 ]; then
        log_warn "No network interfaces detected (besides loopback)."
        return
    fi

    echo ""
    printf "  ${BOLD}%-5s %-16s %-8s %-20s${RESET}\n" "#" "INTERFACE" "STATE" "IP ADDRESS"
    print_separator

    for i in "${!ifaces[@]}"; do
        local iface="${ifaces[$i]}"
        local state="DOWN"
        local ip_addr="N/A"

        # Detect link state
        if ip link show "$iface" 2>/dev/null | grep -q "state UP"; then
            state="${GREEN}UP${RESET}"
        elif ip link show "$iface" 2>/dev/null | grep -q "state UNKNOWN"; then
            state="${YELLOW}UNKNOWN${RESET}"
        else
            state="${RED}DOWN${RESET}"
        fi

        # Detect IP address
        local detected_ip
        detected_ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
        if [ -n "$detected_ip" ]; then
            ip_addr="${GREEN}${detected_ip}${RESET}"
        fi

        printf "  ${CYAN}%-5s${RESET} %-16s %-18s %-20s\n" "[$((i+1))]" "$iface" "$state" "$ip_addr"
    done

    echo ""
    log_info "Total interfaces found: ${BOLD}${#ifaces[@]}${RESET}"
    log_info "Use option ${CYAN}3 (Configure DHCP Server)${RESET} to bind an interface."
}

# ==============================================================================
# MENU OPTION 3: Configure DHCP Server (Full Interactive)
# ==============================================================================

configure_dhcp() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Option 3] DHCP Server Configuration Wizard${RESET}"
    print_separator
    echo -e "  ${DIM}Tip: Type 'c' or 'cancel' at ANY prompt to abort and return to the menu.${RESET}\n"

    # ------ Step 1: Interface Selection ------
    echo -e "${CYAN}${BOLD}  [Step 1/4] Select Network Interface${RESET}"

    local ifaces=()
    if command -v ip >/dev/null 2>&1; then
        mapfile -t ifaces < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v '^lo$')
    fi
    if [ ${#ifaces[@]} -eq 0 ]; then
        mapfile -t ifaces < <(ls /sys/class/net 2>/dev/null | grep -v '^lo$')
    fi

    if [ ${#ifaces[@]} -gt 0 ]; then
        echo -e "  Detected interfaces:"
        for i in "${!ifaces[@]}"; do
            local iface="${ifaces[$i]}"
            local state_info=""
            if ip link show "$iface" 2>/dev/null | grep -q "state UP"; then
                state_info="${GREEN}(UP)${RESET}"
            else
                state_info="${RED}(DOWN)${RESET}"
            fi
            echo -e "    ${CYAN}[$((i+1))]${RESET} $iface $state_info"
        done
    else
        log_warn "No interfaces auto-detected."
    fi

    echo ""
    read -p "  Enter interface(s) to bind [${ifaces[0]:-eth0}] (or 'c' to cancel): " iface_input
    if is_cancel "$iface_input"; then
        log_warn "Configuration cancelled by user. No changes were made."
        return
    fi

    local selected_ifaces=""
    if [ -z "$iface_input" ]; then
        selected_ifaces="${ifaces[0]:-eth0}"
    elif [[ "$iface_input" =~ ^[0-9]+$ ]] && [ "$iface_input" -ge 1 ] 2>/dev/null && [ "$iface_input" -le "${#ifaces[@]}" ] 2>/dev/null; then
        selected_ifaces="${ifaces[$((iface_input-1))]}"
    else
        selected_ifaces="$iface_input"
    fi

    log_success "Selected interface(s): ${GREEN}${selected_ifaces}${RESET}"

    # ------ Subnet & Configuration Mode Detection ------
    local config_mode="replace"
    if [ -f "$DHCPD_CONF" ] && grep -qE "^[[:space:]]*subnet " "$DHCPD_CONF"; then
        echo -e "\n${YELLOW}${BOLD}  [Attention] Existing Configuration Detected${RESET}"
        log_info "The file $DHCPD_CONF already contains subnet declarations."
        read -p "  Do you want to (A)dd a new subnet or (R)eplace the entire config? [A/r/c]: " mode_choice
        
        if is_cancel "$mode_choice"; then
            log_warn "Configuration cancelled by user."
            return
        elif [[ "$mode_choice" =~ ^[Rr]$ ]]; then
            echo -e "\n${RED}${BOLD}  --- SAFETY WARNING ---${RESET}"
            read -p "  Are you sure you want to OVERWRITE the existing configuration? [y/N]: " overwrite_confirm
            if [[ ! "$overwrite_confirm" =~ ^[Yy]$ ]]; then
                log_warn "Configuration cancelled."
                return
            fi
            config_mode="replace"
        else
            config_mode="append"
        fi
    fi

    # ------ Step 2: Global Settings ------
    local global_domain="lab.local"
    local global_dns="192.168.1.1"
    local default_lease="600"
    local max_lease="7200"

    if [ "$config_mode" == "replace" ]; then
        echo -e "\n${CYAN}${BOLD}  [Step 2/4] Global DHCP Settings${RESET}"

        read -p "  Domain Name [$global_domain] (or 'c' to cancel): " input
        if is_cancel "$input"; then return; fi
        [ -n "$input" ] && global_domain="$input"

        read -p "  Primary DNS Server [$global_dns] (or 'c' to cancel): " input
        if is_cancel "$input"; then return; fi
        [ -n "$input" ] && global_dns="$input"

        read -p "  Default Lease Time in seconds [$default_lease] (or 'c' to cancel): " input
        if is_cancel "$input"; then return; fi
        [ -n "$input" ] && default_lease="$input"

        read -p "  Max Lease Time in seconds [$max_lease] (or 'c' to cancel): " input
        if is_cancel "$input"; then return; fi
        [ -n "$input" ] && max_lease="$input"

        log_success "Global settings captured."
    else
        echo -e "\n${CYAN}${BOLD}  [Step 2/4] Global DHCP Settings (Skipped)${RESET}"
        log_info "Appending new subnets. Existing global settings in dhcpd.conf will be preserved."
    fi

    # ------ Step 3: Subnet Configuration ------
    echo -e "\n${CYAN}${BOLD}  [Step 3/4] Subnet Configuration${RESET}"

    local subnets=()
    local add_more="y"
    local subnet_count=1

    while [[ "$add_more" =~ ^[Yy]$ ]]; do
        echo -e "\n  ${YELLOW}${BOLD}--- Subnet #$subnet_count ---${RESET} ${DIM}(type 'c' to cancel configuration)${RESET}"

        local def_net="192.168.$((30 + (subnet_count-1)*10)).0"
        local def_mask="255.255.255.0"
        local def_start="192.168.$((30 + (subnet_count-1)*10)).100"
        local def_end="192.168.$((30 + (subnet_count-1)*10)).200"
        local def_gw="192.168.$((30 + (subnet_count-1)*10)).1"

        local sub_net sub_mask r_start r_end gw s_dns s_dom

        read -p "  Subnet Network IP [$def_net]: " sub_net
        if is_cancel "$sub_net"; then return; fi
        [ -z "$sub_net" ] && sub_net="$def_net"

        read -p "  Subnet Netmask [$def_mask]: " sub_mask
        if is_cancel "$sub_mask"; then return; fi
        [ -z "$sub_mask" ] && sub_mask="$def_mask"

        read -p "  DHCP Range Start [$def_start]: " r_start
        if is_cancel "$r_start"; then return; fi
        [ -z "$r_start" ] && r_start="$def_start"

        read -p "  DHCP Range End [$def_end]: " r_end
        if is_cancel "$r_end"; then return; fi
        [ -z "$r_end" ] && r_end="$def_end"

        read -p "  Router / Gateway IP [$def_gw]: " gw
        if is_cancel "$gw"; then return; fi
        [ -z "$gw" ] && gw="$def_gw"

        read -p "  Subnet DNS Server [$global_dns]: " s_dns
        if is_cancel "$s_dns"; then return; fi
        [ -z "$s_dns" ] && s_dns="$global_dns"

        read -p "  Subnet Domain Name [$global_domain]: " s_dom
        if is_cancel "$s_dom"; then return; fi
        [ -z "$s_dom" ] && s_dom="$global_domain"

        subnets+=("SUBNET=$sub_net|NETMASK=$sub_mask|RANGE_START=$r_start|RANGE_END=$r_end|ROUTER=$gw|DNS=$s_dns|DOMAIN=$s_dom")

        log_success "Subnet #$subnet_count captured."
        subnet_count=$((subnet_count + 1))

        read -p "  Add another subnet? [y/N/c]: " add_more
        if is_cancel "$add_more"; then return; fi
    done

    # ------ Step 4: Review & Confirm ------
    echo -e "\n${CYAN}${BOLD}  [Step 4/4] Configuration Review${RESET}"
    echo -e "${YELLOW}${BOLD}  ════════════════════════════════════════════════════════════════${RESET}"
    
    if [ "$config_mode" == "replace" ]; then
        echo -e "  ${BOLD}Config Mode:${RESET}    ${RED}REPLACE existing configuration${RESET}"
    else
        echo -e "  ${BOLD}Config Mode:${RESET}    ${GREEN}APPEND to existing configuration${RESET}"
    fi
    
    echo -e "  ${BOLD}Interface(s):${RESET}   $selected_ifaces"
    
    if [ "$config_mode" == "replace" ]; then
        echo -e "  ${BOLD}Domain Name:${RESET}    $global_domain"
        echo -e "  ${BOLD}Primary DNS:${RESET}    $global_dns"
        echo -e "  ${BOLD}Default Lease:${RESET}  $default_lease sec"
        echo -e "  ${BOLD}Max Lease:${RESET}      $max_lease sec"
    fi
    
    echo -e "  ${BOLD}New Subnets:${RESET}    ${#subnets[@]}"
    echo ""

    for idx in "${!subnets[@]}"; do
        IFS='|' read -r s_net s_mask r_start r_end router dns domain <<< "${subnets[$idx]}"
        s_net="${s_net#*=}"; s_mask="${s_mask#*=}"; r_start="${r_start#*=}"
        r_end="${r_end#*=}"; router="${router#*=}"; dns="${dns#*=}"; domain="${domain#*=}"
        echo -e "  ${CYAN}[Subnet $((idx+1))]${RESET}"
        echo -e "    Network:    $s_net / $s_mask"
        echo -e "    Range:      $r_start - $r_end"
        echo -e "    Gateway:    $router"
        echo -e "    DNS:        $dns"
        echo -e "    Domain:     $domain"
    done

    echo -e "${YELLOW}${BOLD}  ════════════════════════════════════════════════════════════════${RESET}"
    echo ""

    read -p "  Apply this configuration? [y/N/c]: " confirm
    if is_cancel "$confirm" || [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "Configuration cancelled. No changes were made."
        return
    fi

    # ------ Apply: Backup & Write ------
    log_info "Creating backups before applying changes..."

    local timestamp
    timestamp=$(date +%Y%m%d%H%M%S)

    # Backup interface config file
    if [ -n "$IFACE_CONFIG_FILE" ] && [ -f "$IFACE_CONFIG_FILE" ]; then
        cp "$IFACE_CONFIG_FILE" "${IFACE_CONFIG_FILE}.bak.${timestamp}"
        log_success "Backed up ${IFACE_CONFIG_FILE} → ${IFACE_CONFIG_FILE}.bak.${timestamp}"
    fi

    # Backup dhcpd.conf
    if [ -f "$DHCPD_CONF" ]; then
        cp "$DHCPD_CONF" "${DHCPD_CONF}.bak.${timestamp}"
        log_success "Backed up ${DHCPD_CONF} → ${DHCPD_CONF}.bak.${timestamp}"
    fi

    # Write interface config
    if [ -n "$IFACE_CONFIG_FILE" ]; then
        mkdir -p "$(dirname "$IFACE_CONFIG_FILE")"
        if [ -f "$IFACE_CONFIG_FILE" ] && grep -q "^${IFACE_VAR}=" "$IFACE_CONFIG_FILE" 2>/dev/null; then
            sed -i "s|^${IFACE_VAR}=.*|${IFACE_VAR}=\"${selected_ifaces}\"|" "$IFACE_CONFIG_FILE"
        else
            echo "${IFACE_VAR}=\"${selected_ifaces}\"" >> "$IFACE_CONFIG_FILE"
        fi
        log_success "Updated interface binding in ${IFACE_CONFIG_FILE}"
    fi

    # Write dhcpd.conf
    mkdir -p /etc/dhcp

    if [ "$config_mode" == "replace" ]; then
        cat > "$DHCPD_CONF" <<EOF
# ==============================================================================
# DHCP Server Configuration
# Generated by dhcp-setup.sh on $(date)
# ==============================================================================

# Global Settings
option domain-name "${global_domain}";
option domain-name-servers ${global_dns};

default-lease-time ${default_lease};
max-lease-time ${max_lease};

authoritative;
ddns-update-style none;

EOF
    else
        cat >> "$DHCPD_CONF" <<EOF

# ==============================================================================
# Appended by dhcp-setup.sh on $(date)
# ==============================================================================

EOF
    fi

    for idx in "${!subnets[@]}"; do
        IFS='|' read -r s_net s_mask r_start r_end router dns domain <<< "${subnets[$idx]}"
        s_net="${s_net#*=}"; s_mask="${s_mask#*=}"; r_start="${r_start#*=}"
        r_end="${r_end#*=}"; router="${router#*=}"; dns="${dns#*=}"; domain="${domain#*=}"

        local net_prefix
        net_prefix=$(echo "$s_net" | cut -d'.' -f1-3)
        local bcast="${net_prefix}.255"

        cat >> "$DHCPD_CONF" <<EOF
# Subnet #$((idx+1)): $s_net/$s_mask
subnet $s_net netmask $s_mask {
    range $r_start $r_end;
    option routers $router;
    option subnet-mask $s_mask;
    option broadcast-address $bcast;
    option domain-name-servers $dns;
    option domain-name "$domain";
}

EOF
    done

    if [ "$config_mode" == "replace" ]; then
        log_success "Configuration written to ${GREEN}${DHCPD_CONF}${RESET}"
    else
        log_success "New subnets appended to ${GREEN}${DHCPD_CONF}${RESET}"
    fi

    # ------ Syntax Check ------
    log_info "Running syntax check..."
    if command -v dhcpd >/dev/null 2>&1; then
        if dhcpd -t -cf "$DHCPD_CONF" 2>&1; then
            log_success "Syntax check ${GREEN}PASSED${RESET}."
        else
            log_error "Syntax check ${RED}FAILED${RESET}. You can use option 5 to rollback."
            return
        fi
    else
        log_warn "dhcpd binary not found — skipping syntax check. Install the DHCP server first."
    fi

    # ------ Restart Service ------
    read -p "  Restart DHCP service now? [Y/n/c]: " restart_confirm
    if is_cancel "$restart_confirm" || [[ "$restart_confirm" =~ ^[Nn]$ ]]; then
        log_info "Service restart skipped. Remember to restart manually."
    else
        systemctl enable "$DHCP_SERVICE" 2>/dev/null
        if systemctl restart "$DHCP_SERVICE" 2>&1; then
            log_success "DHCP service (${DHCP_SERVICE}) restarted successfully!"
        else
            log_error "Failed to restart ${DHCP_SERVICE}. Check logs with option 4 (Debug)."
        fi
    fi
}

# ==============================================================================
# MENU OPTION 4: Debug DHCP Configuration
# ==============================================================================

debug_dhcp() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Option 4] DHCP Configuration Debug & Validation${RESET}"
    print_separator

    local pass_count=0
    local fail_count=0

    # --- Check 1: dhcpd.conf exists ---
    echo -e "\n  ${BOLD}[Check 1] Configuration File Existence${RESET}"
    if [ -f "$DHCPD_CONF" ]; then
        log_success "${DHCPD_CONF} exists."
        pass_count=$((pass_count + 1))
    else
        log_error "${DHCPD_CONF} does not exist. Run option 3 to configure."
        fail_count=$((fail_count + 1))
        echo ""
        echo -e "  ${BOLD}Result: ${RED}$fail_count FAILED${RESET}, ${GREEN}$pass_count PASSED${RESET}"
        return
    fi

    # --- Check 2: Syntax validation ---
    echo -e "\n  ${BOLD}[Check 2] Syntax Validation (dhcpd -t)${RESET}"
    if command -v dhcpd >/dev/null 2>&1; then
        local syntax_output
        syntax_output=$(dhcpd -t -cf "$DHCPD_CONF" 2>&1)
        local syntax_rc=$?
        if [ $syntax_rc -eq 0 ]; then
            log_success "Syntax check PASSED."
            pass_count=$((pass_count + 1))
        else
            log_error "Syntax check FAILED:"
            echo -e "${RED}$syntax_output${RESET}" | sed 's/^/    /'
            fail_count=$((fail_count + 1))
        fi
    else
        log_warn "dhcpd binary not found — cannot run syntax check."
        log_warn "Install DHCP server first (option 1)."
    fi

    # --- Check 3: Required directives ---
    echo -e "\n  ${BOLD}[Check 3] Required Directives${RESET}"
    local missing_directives=0
    for directive in "default-lease-time" "max-lease-time" "authoritative" "subnet"; do
        if grep -q "$directive" "$DHCPD_CONF" 2>/dev/null; then
            log_success "Found directive: ${CYAN}$directive${RESET}"
        else
            log_error "Missing directive: ${RED}$directive${RESET}"
            missing_directives=$((missing_directives + 1))
        fi
    done
    if [ $missing_directives -eq 0 ]; then
        pass_count=$((pass_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi

    # --- Check 4: Interface binding ---
    echo -e "\n  ${BOLD}[Check 4] Interface Binding${RESET}"
    if [ -n "$IFACE_CONFIG_FILE" ] && [ -f "$IFACE_CONFIG_FILE" ]; then
        local bound_iface
        bound_iface=$(grep "^${IFACE_VAR}=" "$IFACE_CONFIG_FILE" 2>/dev/null | head -1)
        if [ -n "$bound_iface" ]; then
            log_success "Interface binding: ${GREEN}$bound_iface${RESET}"
            pass_count=$((pass_count + 1))
        else
            log_warn "No interface binding found in $IFACE_CONFIG_FILE"
            fail_count=$((fail_count + 1))
        fi
    else
        log_warn "Interface config file not found at $IFACE_CONFIG_FILE"
    fi

    # --- Check 5: Service status ---
    echo -e "\n  ${BOLD}[Check 5] Service Status${RESET}"
    if systemctl is-active "$DHCP_SERVICE" >/dev/null 2>&1; then
        log_success "Service ${GREEN}${DHCP_SERVICE}${RESET} is ${GREEN}running${RESET}."
        pass_count=$((pass_count + 1))
    else
        log_error "Service ${RED}${DHCP_SERVICE}${RESET} is ${RED}not running${RESET}."
        fail_count=$((fail_count + 1))
    fi

    # --- Show configuration contents ---
    echo -e "\n  ${BOLD}[Info] Current Configuration File Contents:${RESET}"
    print_separator
    if [ -f "$DHCPD_CONF" ]; then
        cat -n "$DHCPD_CONF" | sed 's/^/  /'
    fi
    print_separator

    # --- Show recent journal logs ---
    echo -e "\n  ${BOLD}[Info] Recent DHCP Journal Logs (last 20 lines):${RESET}"
    print_separator
    if command -v journalctl >/dev/null 2>&1; then
        journalctl -u "$DHCP_SERVICE" --no-pager -n 20 2>/dev/null | sed 's/^/  /' || log_warn "No journal logs available."
    else
        log_warn "journalctl not available on this system."
    fi
    print_separator

    # --- Final Verdict ---
    echo ""
    echo -e "  ${BOLD}═══════════════════════════════════════════${RESET}"
    if [ $fail_count -eq 0 ]; then
        echo -e "  ${GREEN}${BOLD}  VERDICT: ALL CHECKS PASSED ✓ ($pass_count/$pass_count)${RESET}"
    else
        echo -e "  ${RED}${BOLD}  VERDICT: $fail_count CHECK(S) FAILED${RESET}, ${GREEN}$pass_count PASSED${RESET}"
        echo -e "  ${YELLOW}  Tip: Use option 5 (Rollback) if you need to restore a previous config.${RESET}"
    fi
    echo -e "  ${BOLD}═══════════════════════════════════════════${RESET}"
}

# ==============================================================================
# MENU OPTION 5: Rollback Configuration
# ==============================================================================

rollback_config() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Option 5] Rollback DHCP Configuration${RESET}"
    print_separator
    echo -e "  ${DIM}Tip: Type 'c' or 'cancel' to return to the main menu.${RESET}\n"

    # Find all backup files
    local backups=()

    # Scan dhcpd.conf backups
    if ls ${DHCPD_CONF}.bak.* 1>/dev/null 2>&1; then
        for f in ${DHCPD_CONF}.bak.*; do
            backups+=("$f")
        done
    fi

    # Scan interface config backups
    if [ -n "$IFACE_CONFIG_FILE" ] && ls ${IFACE_CONFIG_FILE}.bak.* 1>/dev/null 2>&1; then
        for f in ${IFACE_CONFIG_FILE}.bak.*; do
            backups+=("$f")
        done
    fi

    if [ ${#backups[@]} -eq 0 ]; then
        log_warn "No backup files found. Nothing to rollback."
        return
    fi

    # Sort backups by timestamp (newest first)
    IFS=$'\n' backups_sorted=($(printf '%s\n' "${backups[@]}" | sort -r)); unset IFS

    echo -e "  Available backups (newest first):"
    echo ""
    for i in "${!backups_sorted[@]}"; do
        local bak="${backups_sorted[$i]}"
        local ts
        ts=$(echo "$bak" | grep -oP '\d{14}$' || echo "unknown")
        local formatted_ts="$ts"
        if [ ${#ts} -eq 14 ]; then
            formatted_ts="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}:${ts:12:2}"
        fi
        local size
        size=$(du -h "$bak" 2>/dev/null | awk '{print $1}')
        echo -e "    ${CYAN}[$((i+1))]${RESET} $bak"
        echo -e "        ${DIM}Created: $formatted_ts | Size: $size${RESET}"
    done

    echo ""
    read -p "  Select backup to restore (number), or 'c'/'q' to cancel: " selection

    if is_cancel "$selection" || [ -z "$selection" ]; then
        log_info "Rollback cancelled."
        return
    fi

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#backups_sorted[@]}" ]; then
        log_error "Invalid selection."
        return
    fi

    local selected_backup="${backups_sorted[$((selection-1))]}"

    # Determine the restore target
    local restore_target=""
    if [[ "$selected_backup" == ${DHCPD_CONF}.bak.* ]]; then
        restore_target="$DHCPD_CONF"
    elif [[ "$selected_backup" == ${IFACE_CONFIG_FILE}.bak.* ]]; then
        restore_target="$IFACE_CONFIG_FILE"
    else
        log_error "Cannot determine restore target for: $selected_backup"
        return
    fi

    echo ""
    log_info "Will restore:"
    echo -e "    ${BOLD}Source:${RESET}  $selected_backup"
    echo -e "    ${BOLD}Target:${RESET}  $restore_target"
    echo ""

    read -p "  Confirm rollback? [y/N/c]: " confirm
    if is_cancel "$confirm" || [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Rollback cancelled."
        return
    fi

    # Create a safety backup of the current file before rollback
    if [ -f "$restore_target" ]; then
        local safety_ts
        safety_ts=$(date +%Y%m%d%H%M%S)
        cp "$restore_target" "${restore_target}.pre-rollback.${safety_ts}"
        log_info "Safety backup of current config: ${restore_target}.pre-rollback.${safety_ts}"
    fi

    cp "$selected_backup" "$restore_target"
    log_success "Restored ${GREEN}${restore_target}${RESET} from backup."

    # Restart service after rollback
    read -p "  Restart DHCP service now? [Y/n/c]: " restart_confirm
    if is_cancel "$restart_confirm" || [[ "$restart_confirm" =~ ^[Nn]$ ]]; then
        log_info "Service restart skipped."
    else
        if systemctl restart "$DHCP_SERVICE" 2>&1; then
            log_success "DHCP service restarted successfully after rollback."
        else
            log_error "Failed to restart service. Use option 4 (Debug) to investigate."
        fi
    fi
}

# ==============================================================================
# MENU OPTION 6: Show Current Configuration
# ==============================================================================

show_current_config() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Option 6] Current DHCP Configuration${RESET}"
    print_separator

    if [ -f "$DHCPD_CONF" ]; then
        echo ""
        echo -e "  ${BOLD}File: ${CYAN}${DHCPD_CONF}${RESET}"
        echo -e "  ${BOLD}Size: ${CYAN}$(du -h "$DHCPD_CONF" 2>/dev/null | awk '{print $1}')${RESET}"
        echo -e "  ${BOLD}Modified: ${CYAN}$(stat -c '%y' "$DHCPD_CONF" 2>/dev/null | cut -d'.' -f1 || stat -f '%Sm' "$DHCPD_CONF" 2>/dev/null)${RESET}"
        print_separator
        cat -n "$DHCPD_CONF" | sed 's/^/  /'
        print_separator
    else
        log_warn "${DHCPD_CONF} does not exist."
        log_info "Use option 3 to create a configuration."
    fi

    if [ -n "$IFACE_CONFIG_FILE" ] && [ -f "$IFACE_CONFIG_FILE" ]; then
        echo ""
        echo -e "  ${BOLD}Interface Config: ${CYAN}${IFACE_CONFIG_FILE}${RESET}"
        print_separator
        cat -n "$IFACE_CONFIG_FILE" | sed 's/^/  /'
        print_separator
    fi
}

# ==============================================================================
# MENU OPTION 7: Restart DHCP Service
# ==============================================================================

restart_dhcp_service() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Option 7] Restart DHCP Service${RESET}"
    print_separator
    echo -e "  ${DIM}Tip: Type 'c' or 'cancel' to return to the main menu.${RESET}\n"

    read -p "  Restart $DHCP_SERVICE now? [Y/n/c]: " confirm
    if is_cancel "$confirm" || [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_info "Restart cancelled."
        return
    fi

    log_info "Enabling and restarting ${DHCP_SERVICE}..."

    systemctl enable "$DHCP_SERVICE" 2>/dev/null

    if systemctl restart "$DHCP_SERVICE" 2>&1; then
        log_success "Service ${GREEN}${DHCP_SERVICE}${RESET} restarted successfully!"
        echo ""
        systemctl status "$DHCP_SERVICE" --no-pager 2>/dev/null | sed 's/^/  /'
    else
        log_error "Failed to restart ${DHCP_SERVICE}."
        log_info "Running quick diagnostics..."
        echo ""
        systemctl status "$DHCP_SERVICE" --no-pager 2>/dev/null | sed 's/^/  /'
        echo ""
        log_info "Use option 4 (Debug) for full diagnostics."
    fi
}

# ==============================================================================
# MAIN MENU LOOP
# ==============================================================================

main() {
    check_root
    clear
    print_banner
    detect_package_manager
    echo ""
    read -p "  Press [Enter] to continue to the main menu..." _
    clear

    while true; do
        print_banner
        echo -e "  ${BOLD}System:${RESET} ${GREEN}${DISTRO_NAME}${RESET} (${PKG_MGR}) | ${BOLD}DHCP Package:${RESET} ${CYAN}${DHCP_PKG}${RESET} | ${BOLD}Service:${RESET} ${CYAN}${DHCP_SERVICE}${RESET}"
        print_separator
        echo -e "  ${BOLD}DHCP Server Management Menu${RESET}"
        print_separator
        echo -e "  ${CYAN}1${RESET}) Install DHCP Server"
        echo -e "  ${CYAN}2${RESET}) Detect Network Interfaces"
        echo -e "  ${CYAN}3${RESET}) Configure DHCP Server"
        echo -e "  ${CYAN}4${RESET}) Debug DHCP Configuration"
        echo -e "  ${CYAN}5${RESET}) Rollback Configuration"
        echo -e "  ${CYAN}6${RESET}) Show Current Configuration"
        echo -e "  ${CYAN}7${RESET}) Restart DHCP Service"
        echo -e "  ${RED}8${RESET}) Exit ${DIM}(or type 'c' / 'q')${RESET}"
        print_separator
        read -p "  Enter your choice [1-8]: " choice

        case $choice in
            1)
                install_dhcp
                pause_and_clear
                ;;
            2)
                detect_interfaces
                pause_and_clear
                ;;
            3)
                configure_dhcp
                pause_and_clear
                ;;
            4)
                debug_dhcp
                pause_and_clear
                ;;
            5)
                rollback_config
                pause_and_clear
                ;;
            6)
                show_current_config
                pause_and_clear
                ;;
            7)
                restart_dhcp_service
                pause_and_clear
                ;;
            8|q|Q|c|C|exit|quit)
                echo ""
                log_info "Exiting DHCP Setup Tool. Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid choice. Please enter a number between 1-8."
                sleep 1.2
                clear
                ;;
        esac
    done
}

main