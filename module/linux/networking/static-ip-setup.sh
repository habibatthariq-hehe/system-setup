#!/bin/bash

# ==============================================================================
# STATIC IP SETUP SCRIPT
# Features: Safety checks, Backup/Rollback, Cancel, Menu Loop, Dry Run Mode
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
fi

log_info()    { echo -e "  ${BLUE}${BOLD}[INFO]${RESET}    $1"; }
log_success() { echo -e "  ${GREEN}${BOLD}[OK]${RESET}      $1"; }
log_warn()    { echo -e "  ${YELLOW}${BOLD}[WARN]${RESET}    $1"; }
log_error()   { echo -e "  ${RED}${BOLD}[ERROR]${RESET}   $1"; }
dry_run_print() { echo -e "  ${YELLOW}${BOLD}[DRY RUN]${RESET} $1"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        if [ "$DRY_RUN" = true ]; then
            log_warn "Not running as root. This is allowed in DRY RUN mode."
        else
            log_error "This script must be run as root. Use: sudo bash $0"
            exit 1
        fi
    fi
}

is_cancel() {
    local val="$1"
    [[ "$val" =~ ^(c|cancel|C|CANCEL|q|quit|Q|QUIT|exit|EXIT)$ ]]
}

# Basic IPv4 validation (0-255 per octet)
is_valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local o
    for o in "${BASH_REMATCH[@]:1}"; do
        (( o <= 255 )) || return 1
    done
    return 0
}

# Convert CIDR prefix length (0-32) to dotted-decimal netmask
cidr_to_netmask() {
    local cidr="$1"
    local mask=0 i
    for (( i=0; i<cidr; i++ )); do
        mask=$(( (mask >> 1) | 0x80000000 ))
    done
    printf '%d.%d.%d.%d' \
        $(( (mask >> 24) & 255 )) \
        $(( (mask >> 16) & 255 )) \
        $(( (mask >>  8) & 255 )) \
        $(( mask & 255 ))
}

pause_and_clear() {
    echo ""
    read -p "  Press [Enter] to return to the main menu..." _
    clear
}

print_banner() {
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║                   STATIC IP SETUP TOOL                            ║${RESET}"
    echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_separator() {
    echo -e "${DIM}─────────────────────────────────────────────────────────────────────${RESET}"
}

# ----------------------------- Feature Functions ------------------------------

BACKUP_DIR="/var/backups/static-ip-setup"
INTERFACES_FILE="/etc/network/interfaces"
NETPLAN_DIR="/etc/netplan"

RESOLVCONF_TAIL="/etc/resolvconf/resolv.conf.d/tail"

# Install resolvconf (if not already present) and register the DNS
# server(s) the user entered so they survive interface restarts.
install_configure_resolvconf() {
    local dns_servers="$1"

    if [ -z "$dns_servers" ]; then
        log_warn "No DNS servers provided; skipping resolvconf setup."
        return
    fi

    log_info "Checking for resolvconf..."
    if command -v resolvconf >/dev/null 2>&1; then
        log_info "resolvconf is already installed."
    else
        if [ "$DRY_RUN" = true ]; then
            dry_run_print "Would install resolvconf (apt-get install -y resolvconf)"
        else
            if ! command -v apt-get >/dev/null 2>&1; then
                log_error "apt-get not found. Please install resolvconf manually."
                return 1
            fi
            log_info "Installing resolvconf..."
            apt-get update -qq
            if ! DEBIAN_FRONTEND=noninteractive apt-get install -y resolvconf; then
                log_error "Failed to install resolvconf."
                return 1
            fi
            log_success "resolvconf installed."
        fi
    fi

    # Build "nameserver x.x.x.x" lines from the comma-separated input
    local ns_lines=""
    local ns_array=()
    IFS=',' read -ra ns_array <<< "$dns_servers"
    local ns
    for ns in "${ns_array[@]}"; do
        ns="$(echo "$ns" | xargs)"  # trim whitespace
        [ -z "$ns" ] && continue
        if ! is_valid_ipv4 "$ns"; then
            log_warn "Skipping invalid DNS entry: $ns"
            continue
        fi
        ns_lines+="nameserver $ns"$'\n'
    done

    if [ -z "$ns_lines" ]; then
        log_warn "No valid DNS servers to configure; skipping resolvconf setup."
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would write the following to $RESOLVCONF_TAIL:"
        echo "$ns_lines" | sed 's/^/    /'
        dry_run_print "Would execute: resolvconf -u"
        return
    fi

    mkdir -p "$(dirname "$RESOLVCONF_TAIL")"
    # Avoid duplicating entries on repeated runs
    touch "$RESOLVCONF_TAIL"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        grep -qxF "$line" "$RESOLVCONF_TAIL" || echo "$line" >> "$RESOLVCONF_TAIL"
    done <<< "$ns_lines"
    log_success "Added nameserver(s) to $RESOLVCONF_TAIL"

    if command -v resolvconf >/dev/null 2>&1; then
        resolvconf -u
        log_success "resolvconf updated (/etc/resolv.conf regenerated)."
    else
        log_warn "resolvconf command not found; entries saved but not applied."
    fi
}

set_static_ip() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Option 1] Set Static IP Address${RESET}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}${BOLD}[DRY RUN MODE ENABLED - NO CHANGES WILL BE APPLIED]${RESET}"
    fi
    print_separator
    
    echo -e "  ${BOLD}Available Interfaces:${RESET}"
    ip -o link show | awk -F': ' '{print $2}' | sed 's/^/    /'
    echo ""
    
    echo -e "  ${DIM}Tip: Type 'c' or 'cancel' at ANY prompt to abort and return to the menu.${RESET}\n"

    read -p "  Enter interface (e.g. eth0, ens33): " interface
    if is_cancel "$interface"; then return; fi
    if [ -z "$interface" ]; then log_error "Interface cannot be empty."; return; fi

    # BUG FIX: validate IP address, gateway format before accepting input
    local ip_address
    while true; do
        read -p "  Enter IP Address (e.g. 192.168.1.100/24): " ip_address
        if is_cancel "$ip_address"; then return; fi
        local ip_part="${ip_address%/*}"
        if is_valid_ipv4 "$ip_part"; then break; fi
        log_error "Invalid IP address format. Use format: 192.168.1.100 or 192.168.1.100/24"
    done
    # BUG FIX: default to /24 here so BOTH the netplan and ifupdown branches
    # get a valid CIDR-qualified address (netplan requires a prefix length
    # in its 'addresses' list; without this it silently wrote an invalid
    # entry like "addresses: [192.168.1.100]").
    if [[ "$ip_address" != */* ]]; then
        ip_address="${ip_address}/24"
        log_warn "No CIDR provided, defaulting to /24 ($ip_address)"
    fi

    local gateway
    while true; do
        read -p "  Enter Gateway (e.g. 192.168.1.1): " gateway
        if is_cancel "$gateway"; then return; fi
        if is_valid_ipv4 "$gateway"; then break; fi
        log_error "Invalid gateway IP address."
    done

    # BUG FIX: DNS input previously had no validation at all, unlike
    # IP/gateway; garbage input flowed straight into the config files.
    local dns
    while true; do
        read -p "  Enter DNS Servers (comma separated, e.g. 8.8.8.8,1.1.1.1): " dns
        if is_cancel "$dns"; then return; fi
        if [ -z "$dns" ]; then log_error "DNS servers cannot be empty."; continue; fi
        local dns_ok=true
        local dns_check=()
        IFS=',' read -ra dns_check <<< "$dns"
        local d
        for d in "${dns_check[@]}"; do
            d="$(echo "$d" | xargs)"
            if ! is_valid_ipv4 "$d"; then
                log_error "Invalid DNS server IP: '$d'"
                dns_ok=false
                break
            fi
        done
        if [ "$dns_ok" = true ]; then break; fi
    done

    echo -e "\n  ${YELLOW}${BOLD}--- Configuration Review ---${RESET}"
    echo -e "  Interface: $interface"
    echo -e "  IP Address: $ip_address"
    echo -e "  Gateway: $gateway"
    echo -e "  DNS: $dns"
    
    read -p "  Apply this configuration? [y/N/c]: " confirm
    if is_cancel "$confirm" || [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "Configuration cancelled. No changes were made."
        return
    fi

    read -p "  Install/configure resolvconf with these DNS server(s)? [Y/n/c]: " resolvconf_confirm
    if [[ ! "$resolvconf_confirm" =~ ^[Nn]$ ]] && ! is_cancel "$resolvconf_confirm"; then
        install_configure_resolvconf "$dns"
    fi

    # BUG FIX: declare local first, then assign, so the exit code of
    # the command substitution is not masked by 'local' returning 0.
    local timestamp
    timestamp=$(date +%Y%m%d%H%M%S)
    
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would create backup directory: $BACKUP_DIR"
    else
        mkdir -p "$BACKUP_DIR"
    fi

    # Determine system network manager
    if [ -d "$NETPLAN_DIR" ] && ls "$NETPLAN_DIR"/*.yaml >/dev/null 2>&1; then
        log_info "Detected Netplan."
        for f in "$NETPLAN_DIR"/*.yaml; do
            [ -f "$f" ] || continue
            if [ "$DRY_RUN" = true ]; then
                dry_run_print "Would backup $f to $BACKUP_DIR/$(basename "$f").bak.$timestamp"
            else
                cp "$f" "$BACKUP_DIR/$(basename "$f").bak.$timestamp"
            fi
        done
        if [ "$DRY_RUN" = false ]; then log_success "Netplan config backed up to $BACKUP_DIR/"; fi
        
        local netplan_target="$NETPLAN_DIR/01-static-ip-$interface.yaml"
        local netplan_content
        read -r -d '' netplan_content <<EOF
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
        addresses: [${dns}]
EOF
        
        if [ "$DRY_RUN" = true ]; then
            dry_run_print "Would create netplan configuration at $netplan_target with contents:"
            echo "$netplan_content" | sed 's/^/    /'
        else
            echo "$netplan_content" > "$netplan_target"
            log_success "Created netplan configuration at $netplan_target"
        fi
        
        read -p "  Apply netplan changes now? [Y/n/c]: " apply_confirm
        if [[ ! "$apply_confirm" =~ ^[Nn]$ ]] && ! is_cancel "$apply_confirm"; then
            if [ "$DRY_RUN" = true ]; then
                dry_run_print "Would execute: netplan apply"
            else
                netplan apply
                log_success "Netplan applied."
            fi
        fi

    elif [ -f "$INTERFACES_FILE" ]; then
        log_info "Detected /etc/network/interfaces."
        if [ "$DRY_RUN" = true ]; then
            dry_run_print "Would backup $INTERFACES_FILE to $BACKUP_DIR/interfaces.bak.$timestamp"
        else
            cp "$INTERFACES_FILE" "$BACKUP_DIR/interfaces.bak.$timestamp"
            log_success "Interfaces config backed up to $BACKUP_DIR/"
        fi

        local ip_only="${ip_address%/*}"
        local cidr="${ip_address#*/}"
        if [ "$ip_only" == "$cidr" ]; then
            cidr="24"
            log_warn "No CIDR provided, defaulting to /24"
        fi
        # BUG FIX: convert CIDR to dotted netmask; ifupdown needs a
        # separate 'netmask' line and a plain IP on 'address'.
        local netmask
        netmask=$(cidr_to_netmask "$cidr")

        local interfaces_content
        read -r -d '' interfaces_content <<EOF || true

# Added by static-ip-setup.sh
auto $interface
iface $interface inet static
    address $ip_only
    netmask $netmask
    gateway $gateway
    dns-nameservers ${dns//,/ }
EOF

        if [ "$DRY_RUN" = true ]; then
            dry_run_print "Would remove existing blocks for $interface and append the following to $INTERFACES_FILE:"
            echo "$interfaces_content" | sed 's/^/    /'
        else
            # BUG FIX: the old sed range delete ("/auto IFACE/,/dns-nameservers/d")
            # had no bound if the existing stanza for this interface lacked a
            # dns-nameservers line (e.g. a DHCP block, or one edited by hand) -
            # sed would then delete everything to the end of the file. This
            # awk version only removes the block starting at "auto IFACE" and
            # stops at the first blank line or the next "auto " block, so it
            # can never consume more than that one interface's stanza.
            local iface_escaped="${interface//./\\.}"
            awk -v pat="^auto[[:space:]]+${iface_escaped}([[:space:]]|\$)" '
                $0 ~ pat { skip=1; next }
                skip && /^[[:space:]]*$/ { skip=0; next }
                skip && /^auto[[:space:]]+/ { skip=0 }
                skip { next }
                { print }
            ' "$INTERFACES_FILE" > "${INTERFACES_FILE}.tmp" && mv "${INTERFACES_FILE}.tmp" "$INTERFACES_FILE"
            echo "$interfaces_content" >> "$INTERFACES_FILE"
            log_success "Appended configuration to $INTERFACES_FILE"
        fi
        
        read -p "  Restart networking service now? [Y/n/c]: " restart_confirm
        if [[ ! "$restart_confirm" =~ ^[Nn]$ ]] && ! is_cancel "$restart_confirm"; then
            if [ "$DRY_RUN" = true ]; then
                dry_run_print "Would execute: systemctl restart networking"
            else
                systemctl restart networking
                log_success "Networking service restarted."
            fi
        fi
    else
        log_error "Could not determine network management system (Netplan or ifupdown not found)."
        return 1
    fi
}

rollback_config() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Option 5] Rollback Configuration${RESET}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}${BOLD}[DRY RUN MODE ENABLED - NO CHANGES WILL BE APPLIED]${RESET}"
    fi
    print_separator
    echo -e "  ${DIM}Tip: Type 'c' or 'cancel' to abort.${RESET}\n"

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        log_warn "No backups found in $BACKUP_DIR."
        return
    fi

    echo -e "  Available Backups:"
    ls -1 "$BACKUP_DIR" | grep "\.bak\." | nl
    
    local backups=()
    mapfile -t backups < <(ls "$BACKUP_DIR" 2>/dev/null | grep "\.bak\.")
    if [ ${#backups[@]} -eq 0 ]; then
        log_warn "No valid backups found."
        return
    fi

    echo ""
    read -p "  Enter the number of the backup to restore (or 'c' to cancel): " rb_choice
    if is_cancel "$rb_choice"; then return; fi

    if [[ ! "$rb_choice" =~ ^[0-9]+$ ]] || [ "$rb_choice" -lt 1 ] || [ "$rb_choice" -gt "${#backups[@]}" ]; then
        log_error "Invalid selection."
        return
    fi

    local selected_file="${backups[$((rb_choice-1))]}"
    log_info "Selected backup: $selected_file"
    
    if [[ "$selected_file" == interfaces.bak.* ]]; then
        if [ "$DRY_RUN" = true ]; then
            dry_run_print "Would restore $BACKUP_DIR/$selected_file to $INTERFACES_FILE"
            dry_run_print "Would execute: systemctl restart networking"
        else
            cp "$BACKUP_DIR/$selected_file" "$INTERFACES_FILE"
            log_success "Restored $INTERFACES_FILE"
            systemctl restart networking 2>/dev/null
        fi
    elif [[ "$selected_file" == *.yaml.bak.* ]]; then
        local orig_name="${selected_file%.bak.*}"
        if [ "$DRY_RUN" = true ]; then
            dry_run_print "Would restore $BACKUP_DIR/$selected_file to $NETPLAN_DIR/$orig_name"
            dry_run_print "Would execute: netplan apply"
        else
            cp "$BACKUP_DIR/$selected_file" "$NETPLAN_DIR/$orig_name"
            log_success "Restored $NETPLAN_DIR/$orig_name"
            netplan apply 2>/dev/null
        fi
    else
        log_error "Unknown backup format."
        return
    fi
}

# ----------------------------- Main Loop --------------------------------------

main() {
    check_root
    
    while true; do
        clear
        print_banner
        echo -e "  ${BOLD}Static IP Configuration Menu${RESET}"
        print_separator
        
        local dry_run_status
        if [ "$DRY_RUN" = true ]; then
            dry_run_status="${YELLOW}[ON]${RESET}"
        else
            dry_run_status="${DIM}[OFF]${RESET}"
        fi

        echo -e "  ${CYAN}1${RESET}) Set Static IP Address"
        echo -e "  ${CYAN}2${RESET}) Detect Interfaces"
        echo -e "  ${CYAN}3${RESET}) Show IP Addresses"
        echo -e "  ${CYAN}4${RESET}) Show Network Configuration Files"
        echo -e "  ${CYAN}5${RESET}) Rollback Configuration"
        echo -e "  ${CYAN}6${RESET}) Toggle Dry Run Mode $dry_run_status"
        echo -e "  ${RED}0${RESET}) Exit ${DIM}(or type 'c' / 'q')${RESET}"
        print_separator
        
        read -p "  Enter your choice [0-6]: " choice
        
        case $choice in
            1)
                set_static_ip
                pause_and_clear
                ;;
            2)
                echo -e "\n  ${GREEN}${BOLD}[OK]${RESET}      Detected Interfaces:"
                ip addr show | grep -E '^[0-9]' | awk '{print $2}' | sed 's/://' | sed 's/^/    /'
                pause_and_clear
                ;;
            3)
                echo -e "\n  ${GREEN}${BOLD}[OK]${RESET}      IP Addresses:"
                ip -4 addr show | sed 's/^/    /'
                pause_and_clear
                ;;
            4)
                echo -e "\n  ${BLUE}${BOLD}[INFO]${RESET}    Network Configuration Files:"
                if [ -f "$INTERFACES_FILE" ]; then
                    echo -e "\n  ${DIM}--- /etc/network/interfaces ---${RESET}"
                    cat "$INTERFACES_FILE" | sed 's/^/    /'
                fi
                if [ -d "$NETPLAN_DIR" ]; then
                    for f in "$NETPLAN_DIR"/*.yaml; do
                        [ -f "$f" ] || continue
                        echo -e "\n  ${DIM}--- $f ---${RESET}"
                        cat "$f" | sed 's/^/    /'
                    done
                fi
                pause_and_clear
                ;;
            5)
                rollback_config
                pause_and_clear
                ;;
            6)
                if [ "$DRY_RUN" = true ]; then
                    DRY_RUN=false
                    # BUG FIX: root was only ever checked once at startup. If the
                    # script was launched as --dry-run by a non-root user and then
                    # switched to live mode from here, every write later on would
                    # fail silently/confusingly instead of a clear upfront error.
                    check_root
                    log_success "Dry Run mode DISABLED. Changes will be APPLIED."
                else
                    DRY_RUN=true
                    log_success "Dry Run mode ENABLED. Changes will only be PRINTED."
                fi
                sleep 1.5
                ;;
            0|q|Q|c|C|exit|quit)
                echo ""
                log_info "Exiting Static IP Setup Tool. Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid choice. Please enter a number between 0-6."
                sleep 1.2
                clear
                ;;
        esac
    done
}

main