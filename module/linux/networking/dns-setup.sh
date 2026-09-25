#!/bin/bash

# ==============================================================================
# DNS SERVER & RESOLVER SETUP TOOL
# Features:
#   * Multi-distro package detection & installation (apt, dnf)
#   * Internet Resolve-Only Mode: Configure BIND9 or DNSMASQ as a high-performance
#     caching DNS forwarder that only resolves from public internet upstream DNS
#     (Cloudflare, Google, Quad9, OpenDNS, or custom upstream servers)
#   * Automated config syntax verification (named-checkconf / dnsmasq --test)
#   * Real-time DNS resolution testing (dig / nslookup / host)
#   * Safe backup & rollback support
#   * Cancel options in every setup, prompt, and menu
# ==============================================================================

set -o pipefail

# ----------------------------- UI Colors & Formatting -------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

BACKUP_DIR="/var/backups/dns-setup"
MANIFEST="/var/lib/dns-setup-manifest"

# Global variables
PKG_MANAGER=""
DISTRO_FAMILY=""
BIND_PKG=""
BIND_SERVICE=""
BIND_CONF_DIR=""
BIND_OPTIONS_FILE=""
ZONES_DB_DIR=""
NAMED_LOCAL_FILE=""
DNSMASQ_PKG="dnsmasq"
DNSMASQ_SERVICE="dnsmasq"
DNSMASQ_CONF="/etc/dnsmasq.conf"
DNSMASQ_DIR="/etc/dnsmasq.d"

# ----------------------------- UI & Logging Helpers ---------------------------

print_banner() {
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║                   DNS SERVER & RESOLVER TOOL                      ║${RESET}"
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

is_cancel() {
    local val="$1"
    [[ "$val" =~ ^(c|cancel|C|CANCEL|q|quit|Q|QUIT|exit|EXIT)$ ]]
}

is_valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local o
    for o in "${BASH_REMATCH[@]:1}"; do
        (( o <= 255 )) || return 1
    done
    return 0
}

# Validate a domain-ish name (zone name)
is_valid_zone_name() {
    local z="$1"
    [[ "$z" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

# ----------------------------- Environment & Distro Detection -----------------

check_privileges() {
    if [ "${SKIP_ROOT_CHECK:-false}" = "true" ]; then
        return 0
    fi
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script requires root privileges. Please run with sudo."
        exit 1
    fi
}

detect_environment() {
    check_privileges

    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
        DISTRO_FAMILY="debian"
        BIND_PKG="bind9 bind9-utils dnsutils"
        BIND_SERVICE="bind9"
        BIND_CONF_DIR="/etc/bind"
        BIND_OPTIONS_FILE="/etc/bind/named.conf.options"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        DISTRO_FAMILY="redhat"
        BIND_PKG="bind bind-utils"
        BIND_SERVICE="named"
        BIND_CONF_DIR="/etc"
        BIND_OPTIONS_FILE="/etc/named.conf"
    else
        log_error "Supported package manager not found (apt-get, dnf required)."
        exit 1
    fi

    ZONES_DB_DIR="${BIND_CONF_DIR}/zones"
    NAMED_LOCAL_FILE="${BIND_CONF_DIR}/named.conf.local"

    mkdir -p "$BACKUP_DIR" 2>/dev/null || true
    mkdir -p "$(dirname "$MANIFEST")" 2>/dev/null || true
    touch "$MANIFEST" 2>/dev/null || true
}

backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local timestamp
        timestamp="$(date +%Y%m%d_%H%M%S)"
        local backup_path="${BACKUP_DIR}/$(basename "$file").bak_${timestamp}"
        cp "$file" "$backup_path"
        echo "${file}|${backup_path}" >> "$MANIFEST"
        log_info "Backed up $(basename "$file") to ${backup_path}"
    fi
}

# ----------------------------- Package Installation ---------------------------

install_dnsmasq() {
    echo -e "  ${DIM}Tip: Type 'c' or 'cancel' to return to the menu.${RESET}\n"
    read -p "  Proceed with installing DNSMASQ via ${PKG_MANAGER}? [Y/n/c]: " confirm
    if is_cancel "$confirm" || [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_warn "Installation cancelled by user."
        return 1
    fi

    log_info "Installing DNSMASQ using ${PKG_MANAGER}..."
    local install_rc=0
    case "$PKG_MANAGER" in
        apt-get)
            apt-get update -y && apt-get install -y dnsmasq dnsutils || install_rc=$? ;;
        dnf)
            dnf install -y dnsmasq bind-utils || install_rc=$? ;;
    esac

    if [ $install_rc -eq 0 ]; then
        log_success "DNSMASQ installed successfully."
        return 0
    else
        log_error "Failed to install DNSMASQ."
        return 1
    fi
}

install_bind9() {
    echo -e "  ${DIM}Tip: Type 'c' or 'cancel' to return to the menu.${RESET}\n"
    read -p "  Proceed with installing BIND9 (${BIND_PKG}) via ${PKG_MANAGER}? [Y/n/c]: " confirm
    if is_cancel "$confirm" || [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_warn "Installation cancelled by user."
        return 1
    fi

    log_info "Installing BIND9 using ${PKG_MANAGER}..."
    local install_rc=0
    case "$PKG_MANAGER" in
        apt-get)
            apt-get update -y && apt-get install -y $BIND_PKG || install_rc=$? ;;
        dnf)
            dnf install -y $BIND_PKG || install_rc=$? ;;
    esac

    if [ $install_rc -eq 0 ]; then
        log_success "BIND9 installed successfully."
        return 0
    else
        log_error "Failed to install BIND9."
        return 1
    fi
}

# ----------------------------- Upstream DNS Presets ---------------------------

select_upstream_dns() {
    echo ""
    echo -e "${BOLD}  Select upstream Internet DNS servers to forward to:${RESET}"
    echo "    1) Cloudflare DNS       (1.1.1.1, 1.0.0.1) [Fast & Privacy-focused]"
    echo "    2) Google Public DNS     (8.8.8.8, 8.8.4.4) [High Reliability]"
    echo "    3) Quad9 DNS             (9.9.9.9, 149.112.112.112) [Malware Blocking]"
    echo "    4) OpenDNS / Cisco       (208.67.222.222, 208.67.220.220)"
    echo "    5) Custom Upstream IPs   (Specify your own public DNS servers)"
    echo "    0) Cancel"
    echo ""
    read -p "  Enter choice [1-5, default: 1, or 'c' to cancel]: " dns_choice

    if is_cancel "$dns_choice" || [ "$dns_choice" = "0" ]; then
        log_warn "Upstream DNS selection cancelled."
        return 1
    fi

    case "$dns_choice" in
        2)
            UPSTREAM_SERVERS=("8.8.8.8" "8.8.4.4")
            DNS_PROVIDER_NAME="Google Public DNS"
            ;;
        3)
            UPSTREAM_SERVERS=("9.9.9.9" "149.112.112.112")
            DNS_PROVIDER_NAME="Quad9 DNS"
            ;;
        4)
            UPSTREAM_SERVERS=("208.67.222.222" "208.67.220.220")
            DNS_PROVIDER_NAME="OpenDNS"
            ;;
        5)
            DNS_PROVIDER_NAME="Custom DNS"
            echo ""
            read -p "  Enter primary DNS IP (or 'c' to cancel): " custom_dns1
            if is_cancel "$custom_dns1"; then
                log_warn "Upstream DNS configuration cancelled."
                return 1
            fi
            while ! is_valid_ipv4 "$custom_dns1"; do
                log_error "Invalid IPv4 address."
                read -p "  Enter primary DNS IP (or 'c' to cancel): " custom_dns1
                if is_cancel "$custom_dns1"; then
                    log_warn "Upstream DNS configuration cancelled."
                    return 1
                fi
            done

            read -p "  Enter secondary DNS IP (optional, press Enter to skip, or 'c' to cancel): " custom_dns2
            if is_cancel "$custom_dns2"; then
                log_warn "Upstream DNS configuration cancelled."
                return 1
            fi
            if [ -n "$custom_dns2" ] && ! is_valid_ipv4 "$custom_dns2"; then
                log_warn "Secondary IP invalid, skipping secondary."
                custom_dns2=""
            fi

            UPSTREAM_SERVERS=("$custom_dns1")
            [ -n "$custom_dns2" ] && UPSTREAM_SERVERS+=("$custom_dns2")
            ;;
        1|"")
            UPSTREAM_SERVERS=("1.1.1.1" "1.0.0.1")
            DNS_PROVIDER_NAME="Cloudflare DNS"
            ;;
        *)
            log_error "Invalid choice: ${dns_choice}"
            return 1
            ;;
    esac
    return 0
}

# ----------------------------- Internet Resolve Mode Setup --------------------

setup_internet_resolve_bind9() {
    log_info "Configuring BIND9 in Internet Resolve-Only mode (Forwarder)..."
    echo -e "  ${DIM}Tip: Type 'c' or 'cancel' at any prompt to abort.${RESET}\n"

    # Ensure bind is installed
    if ! command -v named &> /dev/null; then
        log_warn "BIND9 is not installed. Installing now..."
        install_bind9 || return 1
    fi

    select_upstream_dns || return 1

    # Ask for allowed subnets
    echo ""
    echo -e "${BOLD}  Network Access Control (ACL) for DNS queries:${RESET}"
    echo "    1) Localhost and Local Subnets (127.0.0.1, 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12) [Recommended]"
    echo "    2) Any client (0.0.0.0/0 - Open recursive resolver)"
    echo "    3) Localhost only (127.0.0.1)"
    echo "    0) Cancel"
    echo ""
    read -p "  Enter choice [1-3, default: 1, or 'c' to cancel]: " acl_choice

    if is_cancel "$acl_choice" || [ "$acl_choice" = "0" ]; then
        log_warn "Configuration cancelled by user. No changes made."
        return 1
    fi

    local acl_block=""
    case "$acl_choice" in
        2)
            acl_block="any;"
            ;;
        3)
            acl_block="127.0.0.1; ::1;"
            ;;
        1|"")
            acl_block="127.0.0.1; ::1; 192.168.0.0/16; 10.0.0.0/8; 172.16.0.0/12;"
            ;;
        *)
            log_error "Invalid choice: ${acl_choice}"
            return 1
            ;;
    esac

    # Format forwarders block for named.conf
    local forwarders_text=""
    for s in "${UPSTREAM_SERVERS[@]}"; do
        forwarders_text+="        ${s};\n"
    done

    mkdir -p "$BIND_CONF_DIR"

    if [ "$DISTRO_FAMILY" = "debian" ]; then
        backup_file "$BIND_OPTIONS_FILE"

        cat <<EOF > "$BIND_OPTIONS_FILE"
// Generated by dns-setup.sh - Internet Resolve-Only Mode
options {
    directory "/var/cache/bind";

    // Enable recursion and forward ONLY to public Internet DNS
    recursion yes;
    forward only;

    forwarders {
$(echo -e "$forwarders_text")    };

    allow-query {
        ${acl_block}
    };

    allow-recursion {
        ${acl_block}
    };

    listen-on { any; };
    listen-on-v6 { any; };

    dnssec-validation auto;
    auth-nxdomain no;
};
EOF
    else
        # RHEL / Fedora / Arch / SUSE
        backup_file "$BIND_OPTIONS_FILE"

        cat <<EOF > "$BIND_OPTIONS_FILE"
// Generated by dns-setup.sh - Internet Resolve-Only Mode
options {
    directory "/var/named";
    dump-file "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";

    // Enable recursion and forward ONLY to public Internet DNS
    recursion yes;
    forward only;

    forwarders {
$(echo -e "$forwarders_text")    };

    allow-query {
        ${acl_block}
    };

    allow-recursion {
        ${acl_block}
    };

    listen-on port 53 { any; };
    listen-on-v6 port 53 { any; };

    dnssec-validation auto;
};

include "/etc/named.rfc1912.zones";
EOF
    fi

    # Check configuration syntax
    log_info "Validating BIND9 configuration with named-checkconf..."
    if command -v named-checkconf &> /dev/null; then
        if ! named-checkconf "$BIND_OPTIONS_FILE"; then
            log_error "BIND9 configuration validation failed!"
            return 1
        fi
        log_success "Configuration syntax verified successfully."
    fi

    # Enable and restart service
    log_info "Restarting and enabling ${BIND_SERVICE}..."
    systemctl enable "$BIND_SERVICE" &> /dev/null
    systemctl restart "$BIND_SERVICE"

    if systemctl is-active --quiet "$BIND_SERVICE"; then
        log_success "BIND9 is running in Internet Resolve-Only mode using ${DNS_PROVIDER_NAME} (${UPSTREAM_SERVERS[*]})."
    else
        log_error "BIND9 failed to start. Run 'journalctl -u ${BIND_SERVICE} -n 30' for details."
        return 1
    fi
}

setup_internet_resolve_dnsmasq() {
    log_info "Configuring DNSMASQ in Internet Resolve-Only mode (Forwarder)..."
    echo -e "  ${DIM}Tip: Type 'c' or 'cancel' at any prompt to abort.${RESET}\n"

    # Ensure dnsmasq is installed
    if ! command -v dnsmasq &> /dev/null; then
        log_warn "DNSMASQ is not installed. Installing now..."
        install_dnsmasq || return 1
    fi

    select_upstream_dns || return 1

    mkdir -p "$DNSMASQ_DIR"
    backup_file "$DNSMASQ_CONF"

    local server_lines=""
    for s in "${UPSTREAM_SERVERS[@]}"; do
        server_lines+="server=${s}\n"
    done

    # Create optimized dnsmasq configuration
    cat <<EOF > "$DNSMASQ_CONF"
# Generated by dns-setup.sh - Internet Resolve-Only Mode

# Do not read /etc/resolv.conf, strictly resolve via upstream servers below
no-resolv
no-poll

# Upstream Internet DNS Servers (${DNS_PROVIDER_NAME})
$(echo -e "$server_lines")
# Caching & performance settings
cache-size=1500
neg-ttl=60
domain-needed
bogus-priv

# Listen on all local interfaces
listen-address=127.0.0.1
bind-interfaces

# Include additional custom configs
conf-dir=/etc/dnsmasq.d/,*.conf
EOF

    # Validate dnsmasq configuration syntax
    log_info "Validating DNSMASQ configuration..."
    if dnsmasq --test &> /dev/null; then
        log_success "DNSMASQ configuration is valid."
    else
        log_error "DNSMASQ configuration test failed!"
        return 1
    fi

    # Handle systemd-resolved conflict on port 53 if active
    if systemctl is-active --quiet systemd-resolved; then
        log_warn "systemd-resolved is active and may occupy port 53."
        read -p "  Disable systemd-resolved DNS stub listener to avoid port 53 conflicts? [Y/n/c]: " disable_stub
        if is_cancel "$disable_stub"; then
            log_warn "Configuration cancelled by user."
            return 1
        elif [[ ! "$disable_stub" =~ ^(n|N|no|No)$ ]]; then
            mkdir -p /etc/systemd/resolved.conf.d
            cat <<EOF > /etc/systemd/resolved.conf.d/disable-stub.conf
[Resolve]
DNSStubListener=no
EOF
            systemctl restart systemd-resolved
            log_success "Disabled systemd-resolved stub listener."
        fi
    fi

    log_info "Restarting and enabling ${DNSMASQ_SERVICE}..."
    systemctl enable "$DNSMASQ_SERVICE" &> /dev/null
    systemctl restart "$DNSMASQ_SERVICE"

    if systemctl is-active --quiet "$DNSMASQ_SERVICE"; then
        log_success "DNSMASQ is running in Internet Resolve-Only mode using ${DNS_PROVIDER_NAME} (${UPSTREAM_SERVERS[*]})."
    else
        log_error "DNSMASQ failed to start. Run 'journalctl -u ${DNSMASQ_SERVICE} -n 30' for details."
        return 1
    fi
}

configure_internet_resolve_mode() {
    print_separator
    echo -e "${BOLD}  INTERNET RESOLVE-ONLY MODE SETUP${RESET}"
    echo -e "  Configures a caching forwarder DNS resolver to query public internet DNS."
    print_separator
    echo "    1) Configure BIND9 as Internet Resolve-Only forwarder"
    echo "    2) Configure DNSMASQ as Internet Resolve-Only forwarder"
    echo "    0) Return to Main Menu / Cancel"
    echo ""
    read -p "  Choose backend [1-2, default: 1, or 'c' to cancel]: " backend_choice

    local res=0
    case "$backend_choice" in
        2)
            setup_internet_resolve_dnsmasq || res=$?
            ;;
        0|c|C|cancel|CANCEL|q|Q|quit|QUIT|exit|EXIT)
            log_warn "Cancelled."
            return 0
            ;;
        1|"")
            setup_internet_resolve_bind9 || res=$?
            ;;
        *)
            log_error "Invalid choice: ${backend_choice}"
            return 1
            ;;
    esac

    if [ $res -eq 0 ]; then
        test_dns_resolution
    fi
}

# ----------------------------- Verification & Testing -------------------------

test_dns_resolution() {
    print_separator
    echo -e "${BOLD}  Testing Local DNS Resolution (127.0.0.1)...${RESET}"
    print_separator

    local test_domains=("google.com" "cloudflare.com" "github.com")
    local success_count=0

    for domain in "${test_domains[@]}"; do
        if command -v dig &> /dev/null; then
            local res
            res=$(dig @127.0.0.1 "$domain" +short +time=2 +tries=2 2>/dev/null | head -n 1)
            if [ -n "$res" ]; then
                log_success "Resolved ${domain} -> ${res} (via 127.0.0.1)"
                ((success_count++))
            else
                log_error "Failed to resolve ${domain} via 127.0.0.1"
            fi
        elif command -v nslookup &> /dev/null; then
            if nslookup "$domain" 127.0.0.1 &> /dev/null; then
                log_success "Resolved ${domain} successfully via 127.0.0.1"
                ((success_count++))
            else
                log_error "Failed to resolve ${domain} via 127.0.0.1"
            fi
        elif command -v host &> /dev/null; then
            if host "$domain" 127.0.0.1 &> /dev/null; then
                log_success "Resolved ${domain} successfully via 127.0.0.1"
                ((success_count++))
            else
                log_error "Failed to resolve ${domain} via 127.0.0.1"
            fi
        else
            log_warn "Neither 'dig', 'nslookup', nor 'host' found. Install dnsutils/bind-utils to test."
            return 0
        fi
    done

    if [ "$success_count" -gt 0 ]; then
        log_success "DNS resolution is working properly!"
    else
        log_warn "DNS queries to 127.0.0.1 did not return answers. Check service logs and firewall."
    fi
}

show_service_status() {
    print_separator
    echo -e "${BOLD}  DNS Services Status:${RESET}"
    print_separator

    echo -n "  BIND9 (${BIND_SERVICE}): "
    if systemctl is-active --quiet "$BIND_SERVICE" 2>/dev/null; then
        echo -e "${GREEN}${BOLD}ACTIVE (RUNNING)${RESET}"
    else
        echo -e "${RED}INACTIVE${RESET}"
    fi

    echo -n "  DNSMASQ (${DNSMASQ_SERVICE}): "
    if systemctl is-active --quiet "$DNSMASQ_SERVICE" 2>/dev/null; then
        echo -e "${GREEN}${BOLD}ACTIVE (RUNNING)${RESET}"
    else
        echo -e "${RED}INACTIVE${RESET}"
    fi

    echo ""
    echo -e "${BOLD}  Active Port 53 Listeners:${RESET}"
    if command -v ss &> /dev/null; then
        ss -tulnp | grep ':53 ' || echo "  (No process listening on port 53)"
    elif command -v netstat &> /dev/null; then
        netstat -tulnp | grep ':53 ' || echo "  (No process listening on port 53)"
    fi
}

bind9_status() {
    print_separator
    echo -n "  BIND9 (${BIND_SERVICE}): "
    systemctl status "${BIND_SERVICE}.service" 2>/dev/null || systemctl status named.service
}

dnsmasq_status() {
    print_separator
    echo -n "  DNSMASQ (${DNSMASQ_SERVICE}): "
    systemctl status "${DNSMASQ_SERVICE}.service"
}

rollback_config() {
    print_separator
    echo -e "${BOLD}  DNS Configuration Rollback${RESET}"
    print_separator

    if [ ! -s "$MANIFEST" ]; then
        log_warn "No backups found in manifest (${MANIFEST})."
        return 0
    fi

    echo "  Available backups:"
    local count=0
    while IFS='|' read -r orig_file backup_path; do
        if [ -f "$backup_path" ]; then
            ((count++))
            echo "    ${count}) $(basename "$backup_path") -> ${orig_file}"
        fi
    done < "$MANIFEST"

    if [ "$count" -eq 0 ]; then
        log_warn "No valid backup files found."
        return 0
    fi

    echo "    0) Cancel"
    echo ""
    read -p "  Enter backup number to restore (or 'c' to cancel): " restore_idx
    if is_cancel "$restore_idx" || [ "$restore_idx" = "0" ]; then
        log_warn "Rollback cancelled."
        return 0
    fi

    local current=0
    local restored=0
    while IFS='|' read -r orig_file backup_path; do
        if [ -f "$backup_path" ]; then
            ((current++))
            if [ "$current" -eq "$restore_idx" ]; then
                cp "$backup_path" "$orig_file"
                log_success "Restored ${orig_file} from ${backup_path}"
                restored=1
                break
            fi
        fi
    done < "$MANIFEST"

    if [ "$restored" -eq 1 ]; then
        read -p "  Restart DNS service now? [Y/n/c]: " restart_svc
        if is_cancel "$restart_svc"; then
            log_warn "Service restart cancelled."
            return 0
        elif [[ ! "$restart_svc" =~ ^(n|N|no|No)$ ]]; then
            # BUG FIX: only restart services that are actually installed/active
            # to avoid spurious errors when only one backend was configured.
            if systemctl list-unit-files "${BIND_SERVICE}.service" &>/dev/null && \
               systemctl is-enabled "$BIND_SERVICE" &>/dev/null; then
                systemctl restart "$BIND_SERVICE" 2>/dev/null && log_success "Restarted ${BIND_SERVICE}"
            fi
            if systemctl list-unit-files "${DNSMASQ_SERVICE}.service" &>/dev/null && \
               systemctl is-enabled "$DNSMASQ_SERVICE" &>/dev/null; then
                systemctl restart "$DNSMASQ_SERVICE" 2>/dev/null && log_success "Restarted ${DNSMASQ_SERVICE}"
            fi
        fi
    else
        log_error "Invalid selection."
    fi
}

# ----------------------------- Local LAN Zone Setup (BIND9) -------------------

setup_local_zone_bind9() {
    log_info "Configuring Local LAN DNS Zone (BIND9)..."
    echo -e "  ${DIM}Tip: Type 'c' or 'cancel' at any prompt to abort.${RESET}\n"

    if ! command -v named &> /dev/null; then
        log_warn "BIND9 is not installed. Installing now..."
        install_bind9 || return 1
    fi

    if [ ! -f "$NAMED_LOCAL_FILE" ]; then
        log_error "named.conf.local not found at ${NAMED_LOCAL_FILE}. Is BIND9 installed correctly?"
        return 1
    fi

    # --- Ask zone name ---
    echo ""
    read -p "  Enter the zone/domain name (e.g. lks.local, internal.lan, or 'c' to cancel): " zone_name
    if is_cancel "$zone_name"; then
        log_warn "Zone setup cancelled."
        return 1
    fi
    while ! is_valid_zone_name "$zone_name"; do
        log_error "Invalid zone name format."
        read -p "  Enter the zone/domain name (or 'c' to cancel): " zone_name
        if is_cancel "$zone_name"; then
            log_warn "Zone setup cancelled."
            return 1
        fi
    done

    # --- Check if zone already registered ---
    if grep -q "zone \"${zone_name}\"" "$NAMED_LOCAL_FILE" 2>/dev/null; then
        log_warn "Zone '${zone_name}' already exists in ${NAMED_LOCAL_FILE}."
        read -p "  Overwrite its zone file entries? [y/N/c]: " overwrite
        if is_cancel "$overwrite"; then
            log_warn "Zone setup cancelled."
            return 1
        elif [[ ! "$overwrite" =~ ^(y|Y|yes|Yes)$ ]]; then
            log_info "Aborted. No changes made."
            return 0
        fi
    fi

    # --- Ask primary server hostname & IP ---
    read -p "  Enter this server's hostname [default: ns1, or 'c' to cancel]: " host_name
    if is_cancel "$host_name"; then
        log_warn "Zone setup cancelled."
        return 1
    fi
    [ -z "$host_name" ] && host_name="ns1"

    read -p "  Enter this server's LAN IP (e.g. 192.168.10.1, or 'c' to cancel): " server_ip
    if is_cancel "$server_ip"; then
        log_warn "Zone setup cancelled."
        return 1
    fi
    while ! is_valid_ipv4 "$server_ip"; do
        log_error "Invalid IPv4 address."
        read -p "  Enter this server's LAN IP (or 'c' to cancel): " server_ip
        if is_cancel "$server_ip"; then
            log_warn "Zone setup cancelled."
            return 1
        fi
    done

    read -p "  Enter admin email for SOA [default: admin@${zone_name}, or 'c' to cancel]: " admin_email
    if is_cancel "$admin_email"; then
        log_warn "Zone setup cancelled."
        return 1
    fi
    [ -z "$admin_email" ] && admin_email="admin.${zone_name}"
    # SOA format wants first dot instead of @
    admin_email_soa="${admin_email/@/.}"

    local zone_file="${ZONES_DB_DIR}/db.${zone_name}"
    local serial
    serial="$(date +%Y%m%d)01"

    mkdir -p "$ZONES_DB_DIR"

    # --- Register zone in named.conf.local ---
    backup_file "$NAMED_LOCAL_FILE"

    # Remove any pre-existing block for this zone before re-adding
    if command -v python3 &> /dev/null; then
        python3 - "$NAMED_LOCAL_FILE" "$zone_name" <<'PYEOF'
import re, sys
path, zone = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()
pattern = re.compile(r'zone\s+"' + re.escape(zone) + r'"\s*\{.*?\};\s*', re.DOTALL)
content = pattern.sub('', content)
with open(path, 'w') as f:
    f.write(content)
PYEOF
    fi

    cat <<EOF >> "$NAMED_LOCAL_FILE"

// LAN zone: ${zone_name} - added by dns-setup.sh
zone "${zone_name}" {
    type master;
    file "${zone_file}";
    allow-update { none; };
};
EOF

    log_success "Registered zone '${zone_name}' in ${NAMED_LOCAL_FILE}."

    # --- Optionally set up reverse zone ---
    read -p "  Also set up a reverse (PTR) zone for this subnet? [y/N/c]: " want_reverse
    if is_cancel "$want_reverse"; then
        log_warn "Reverse zone skipped/cancelled."
        want_reverse="n"
    fi
    local reverse_zone="" reverse_file="" octets subnet_prefix
    if [[ "$want_reverse" =~ ^(y|Y|yes|Yes)$ ]]; then
        IFS='.' read -r o1 o2 o3 o4 <<< "$server_ip"
        reverse_zone="${o3}.${o2}.${o1}.in-addr.arpa"
        reverse_file="${ZONES_DB_DIR}/db.${o1}.${o2}.${o3}"

        cat <<EOF >> "$NAMED_LOCAL_FILE"

// Reverse zone for ${o1}.${o2}.${o3}.0/24 - added by dns-setup.sh
zone "${reverse_zone}" {
    type master;
    file "${reverse_file}";
    allow-update { none; };
};
EOF
        log_success "Registered reverse zone '${reverse_zone}'."
    fi

    # --- Build forward zone db file ---
    cat <<EOF > "$zone_file"
\$TTL    604800
@       IN      SOA     ${host_name}.${zone_name}. ${admin_email_soa}. (
                         ${serial}     ; Serial
                         3600          ; Refresh
                         900           ; Retry
                         604800        ; Expire
                         86400 )       ; Negative Cache TTL
;
@       IN      NS      ${host_name}.${zone_name}.
${host_name}    IN      A       ${server_ip}
EOF

    log_success "Created zone file ${zone_file}."

    # --- Loop: add A records for other local hosts ---
    echo ""
    echo -e "${BOLD}  Add additional host A records for this zone (e.g. web-01, mail-srv)${RESET}"
    echo "  Press Enter with empty hostname or 'c' to finish."
    while true; do
        read -p "  Hostname (e.g. web-01) [Enter to finish, or 'c' to stop]: " rec_host
        if [ -z "$rec_host" ] || is_cancel "$rec_host"; then break; fi
        read -p "  IP address for ${rec_host}.${zone_name} (or 'c' to cancel this record): " rec_ip
        if is_cancel "$rec_ip"; then
            log_warn "Record cancelled."
            continue
        fi
        while ! is_valid_ipv4 "$rec_ip"; do
            log_error "Invalid IPv4 address."
            read -p "  IP address for ${rec_host}.${zone_name} (or 'c' to cancel this record): " rec_ip
            if is_cancel "$rec_ip"; then break; fi
        done
        if is_cancel "$rec_ip"; then
            log_warn "Record cancelled."
            continue
        fi
        echo "${rec_host}    IN      A       ${rec_ip}" >> "$zone_file"
        log_success "Added A record: ${rec_host}.${zone_name} -> ${rec_ip}"

        if [ -n "$reverse_file" ]; then
            IFS='.' read -r _ _ _ last_octet <<< "$rec_ip"
            echo "${last_octet}    IN      PTR     ${rec_host}.${zone_name}." >> "${reverse_file}.tmp_ptr"
        fi
    done

    # --- Build reverse zone db file (if requested) ---
    if [ -n "$reverse_file" ]; then
        local rev_serial="$serial"
        {
            echo "\$TTL    604800"
            echo "@       IN      SOA     ${host_name}.${zone_name}. ${admin_email_soa}. ("
            echo "                         ${rev_serial}     ; Serial"
            echo "                         3600          ; Refresh"
            echo "                         900           ; Retry"
            echo "                         604800        ; Expire"
            echo "                         86400 )       ; Negative Cache TTL"
            echo ";"
            echo "@       IN      NS      ${host_name}.${zone_name}."
            IFS='.' read -r _ _ _ last_octet <<< "$server_ip"
            echo "${last_octet}    IN      PTR     ${host_name}.${zone_name}."
            [ -f "${reverse_file}.tmp_ptr" ] && cat "${reverse_file}.tmp_ptr" && rm -f "${reverse_file}.tmp_ptr"
        } > "$reverse_file"
        log_success "Created reverse zone file ${reverse_file}."
    fi

    # --- Validate & reload ---
    log_info "Validating BIND9 configuration with named-checkconf..."
    if command -v named-checkconf &> /dev/null; then
        if ! named-checkconf; then
            log_error "BIND9 configuration validation failed! Check ${NAMED_LOCAL_FILE} and ${zone_file} manually."
            return 1
        fi
        log_success "Configuration syntax verified successfully."
    fi

    if command -v named-checkzone &> /dev/null; then
        named-checkzone "$zone_name" "$zone_file" &> /dev/null && \
            log_success "Zone file syntax OK." || \
            log_warn "named-checkzone reported issues with ${zone_file}."
    fi

    log_info "Reloading ${BIND_SERVICE}..."
    systemctl reload "$BIND_SERVICE" 2>/dev/null || systemctl restart "$BIND_SERVICE"

    if systemctl is-active --quiet "$BIND_SERVICE"; then
        log_success "Local zone '${zone_name}' is now active on ${DNS_PROVIDER_NAME:-BIND9}."
    else
        log_error "BIND9 failed to reload/restart. Run 'journalctl -u ${BIND_SERVICE} -n 30' for details."
        return 1
    fi
}

# ----------------------------- Main Entry Point -------------------------------

main() {
    detect_environment

    # Parse command line flags if provided
    if [ "$1" = "--internet-resolve" ]; then
        print_banner
        configure_internet_resolve_mode
        exit 0
    elif [ "$1" = "--status" ]; then
        print_banner
        show_service_status
        exit 0
    elif [ "$1" = "--test" ]; then
        print_banner
        test_dns_resolution
        exit 0
    elif [ "$1" = "--rollback" ]; then
        print_banner
        rollback_config
        exit 0
    elif [ "$1" = "--local-zone" ]; then
        print_banner
        setup_local_zone_bind9
        exit 0
    elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        print_banner
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  --internet-resolve   Configure Internet Resolve-Only forwarder"
        echo "  --local-zone         Configure Local LAN DNS Zone (BIND9)"
        echo "  --status             View DNS services status & port 53 listeners"
        echo "  --test               Test local DNS resolution"
        echo "  --rollback           Restore previous DNS configuration"
        echo "  -h, --help           Display this help message"
        exit 0
    fi

    # Interactive Menu Loop
    while true; do
        clear 2>/dev/null || true
        print_banner
        print_separator
        echo -e "${BOLD}  Available Actions:${RESET}"
        echo "    1) Install DNSMASQ"
        echo "    2) Install BIND9"
        echo "    3) Configure Internet Resolve-Only Mode (Forwarder)"
        echo "    4) Test Local DNS Resolution (127.0.0.1)"
        echo "    5) View DNS Services Status & Port 53 Listeners"
        echo "    6) Restore / Rollback Configuration"
        echo "    7) Show BIND9 Status"
        echo "    8) Show DNSMASQ Status"
        echo "    9) Setup Local LAN Zone (BIND9)"
        echo "    0) Exit / Cancel"
        print_separator

        read -p "  Choose an option [0-9, or 'c' to exit]: " option

        case "$option" in
            1)
                print_separator
                install_dnsmasq
                ;;
            2)
                print_separator
                install_bind9
                ;;
            3)
                configure_internet_resolve_mode
                ;;
            4)
                test_dns_resolution
                ;;
            5)
                show_service_status
                ;;
            6)
                rollback_config
                ;;
            7)
                bind9_status
                ;;
            8)
                dnsmasq_status
                ;;
            9)
                setup_local_zone_bind9
                ;;
            0|c|C|cancel|CANCEL|q|Q|quit|QUIT|exit|EXIT)
                echo ""
                log_info "Exiting DNS Setup Tool. Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid option: ${option}"
                ;;
        esac

        echo ""
        read -p "  Press [Enter] to continue (or 'c' to exit)..." cont_choice
        if is_cancel "$cont_choice"; then
            echo ""
            log_info "Exiting DNS Setup Tool. Goodbye!"
            exit 0
        fi
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi