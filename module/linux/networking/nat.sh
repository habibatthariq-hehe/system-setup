#!/bin/bash

# ==============================================================================
# NAT GATEWAY SETUP TOOL (built from zero)
# Backend: nftables (recommended) or iptables - user-selectable, with
# automatic detection of what is available.
#
# Features:
#   * Backend picker: choose nftables or iptables (only installed ones offered)
#   * Auto-detects network interfaces (WAN / LAN / DMZ candidates) + IP ranges
#   * Interactive wizard with confirmation before ANY change
#   * Applies: IP forwarding, NAT/masquerade rule, optional DHCP-safe
#     forward policy between LAN and WAN
#   * Manifest-based rollback: run with --rollback to undo everything,
#     including restoring sysctl forwarding if we enabled it. The manifest is
#     APPEND-ONLY across runs so rules from earlier sessions are covered too.
#
# Persistence (DEFAULT-ON):
#   * After applying rules the wizard asks "persist across reboot?" with
#     Enter = YES, so NAT survives reboots out of the box.
#   * nftables backend: table dumped to /etc/nftables.d/nat-tool.conf,
#     nftables.service enabled, and the include line wired into
#     /etc/nftables.conf automatically (backed up for rollback).
#   * iptables backend: saved via netfilter-persistent (Debian) or an
#     iptables-restore file + systemd oneshot unit (other distros).
#   * All persistence artifacts are fully removed by --rollback.
#
# Usage:
#   sudo bash nat.sh             interactive setup
#   sudo bash nat.sh --rollback  undo all changes recorded by this script
#   sudo bash nat.sh --status    show current NAT rules for this tool
# ==============================================================================

set -o pipefail

# ----------------------------- UI Colors --------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'
DIM='\033[2m'; RESET='\033[0m'

BACKEND=""            # "nft" or "ipt"
HAS_NFT=0             # backend availability flags (set by detect_available_backends)
HAS_IPT=0
MANIFEST="/var/lib/nat-tool-manifest"
BACKUP_DIR="/var/lib/nat-tool-backup"
WAN_IFACE=""
LAN_IFACE=""
DMZ_IFACES=""

# Persistence locations (per backend)
NFT_PERSIST_FILE="/etc/nftables.d/nat-tool.conf"
IPT_PERSIST_DIR="/etc/nat-tool"
IPT_RESTORE_FILE="$IPT_PERSIST_DIR/rules.v4"
IPT_UNIT_FILE="/etc/systemd/system/nat-tool-restore.service"

print_banner() {
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║                      NAT GATEWAY SETUP TOOL                       ║${RESET}"
    echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}
print_separator() { echo -e "${DIM}─────────────────────────────────────────────────────────────────────${RESET}"; }
log_info()    { echo -e "  ${BLUE}${BOLD}[INFO]${RESET}    $1"; }
log_success() { echo -e "  ${GREEN}${BOLD}[OK]${RESET}      $1"; }
log_warn()    { echo -e "  ${YELLOW}${BOLD}[WARN]${RESET}    $1"; }
log_error()   { echo -e "  ${RED}${BOLD}[ERROR]${RESET}   $1"; }

is_cancel() { [[ "$1" =~ ^(c|cancel|C|CANCEL|q|quit|Q|QUIT)$ ]]; }

# ask VAR PROMPT - guarded read used for every wizard prompt.
# BUG FIX: a bare 'read' returns nonzero on EOF/Ctrl-D, leaving VAR empty.
# In the pickers that meant an infinite "Invalid selection" spin; in the
# multi-picker EOF was indistinguishable from Enter (silent zone skip).
# Every ask() call site sits BEFORE any disk/service mutation, so exiting
# here is always safe.
ask() {
    if ! read -r -p "$2" "$1"; then
        echo ""
        log_warn "Input closed (EOF) - aborting safely."
        exit 1
    fi
}

# ----------------------------- Root check -------------------------------------
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root. Use: sudo bash $0"
        exit 1
    fi
}

# ----------------------------- Manifest engine --------------------------------
# BUG FIX: the old init TRUNCATED the manifest on every run, but iptables -A
# appends duplicate rules on re-run. Live rules from the previous run then had
# no rollback records left -> '--rollback' orphaned them. The manifest is now
# append-only across runs (rollback tolerates already-deleted entries).
manifest_init()  { mkdir -p "$(dirname "$MANIFEST")"; [ -f "$MANIFEST" ] || : > "$MANIFEST"; }
record()         { printf '%s\n' "$1|$2" >> "$MANIFEST"; }

do_rollback() {
    print_banner
    if [ ! -s "$MANIFEST" ]; then
        log_warn "Nothing recorded in $MANIFEST - nothing to roll back."
        exit 0
    fi
    log_info "Rolling back NAT changes (reverse order)..."

    tac "$MANIFEST" | while IFS= read -r entry; do
        action="${entry%%|*}"; value="${entry#*|}"
        case "$action" in
            nft_table)
                nft delete table ip nat_tool 2>/dev/null \
                    && log_success "Removed nftables table 'nat_tool'" ;;
            ipt_rule)
                # value = full iptables args, delete the exact rule
                iptables $value 2>/dev/null && log_success "Reverted iptables: $value" ;;
            sysctl_forward)
                # value = previous value (0 or 1); restore it
                if [ -n "$value" ]; then
                    sysctl -w net.ipv4.ip_forward="$value" >/dev/null \
                        && log_success "Restored ip_forward=$value"
                else
                    # was not settable file before -> remove our override
                    sed -i '/nat-tool:/d' /etc/sysctl.conf 2>/dev/null
                    sysctl -w net.ipv4.ip_forward=0 >/dev/null
                    log_success "Disabled ip_forward (was off)"
                fi ;;
            sysctl_persist)
                # BUG FIX: previous pattern removed only the comment line and
                # left "net.ipv4.ip_forward = 1" behind. Delete both.
                sed -i -e '/nat-tool: enable IPv4 forwarding/d' \
                       -e '/^net\.ipv4\.ip_forward[[:space:]]*=[[:space:]]*1/d' /etc/sysctl.conf 2>/dev/null
                sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1 || true
                log_success "Removed forwarding entry from /etc/sysctl.conf" ;;
            conf_backup)
                # value = original file path; restore our one-time backup,
                # or remove the file outright if it never existed before us.
                if [ -f "$BACKUP_DIR/$(basename "$value").bak" ]; then
                    cp "$BACKUP_DIR/$(basename "$value").bak" "$value" \
                        && log_success "Restored $(basename "$value") from backup"
                else
                    rm -f "$value" && log_success "Removed generated $(basename "$value")"
                fi ;;
            nft_persist_file|ipt_restore_file|ipt_unit_file|ipt_netfilter_persist)
                # Handled collectively by remove_persistence below
                ;;
        esac
    done

    remove_persistence

    : > "$MANIFEST"
    print_separator
    log_success "Rollback complete."
    exit 0
}

# NOTE: no early dispatch here. do_rollback calls remove_persistence which is
# defined further down; dispatching before all function definitions caused
# "remove_persistence: command not found" and left persistence files behind.

# ----------------------------- Backend selection ------------------------------
# NEW FEATURE: the user can now choose between nftables and iptables.
detect_available_backends() {
    HAS_NFT=0; HAS_IPT=0
    if command -v nft >/dev/null 2>&1 && nft list tables >/dev/null 2>&1; then
        HAS_NFT=1
    fi
    if command -v iptables >/dev/null 2>&1; then
        HAS_IPT=1
    fi
    if [ "$HAS_NFT" -eq 0 ] && [ "$HAS_IPT" -eq 0 ]; then
        log_error "Neither nftables nor iptables found."
        log_info "Install one of: apt install nftables | dnf install nftables"
        return 1
    fi
    return 0
}

choose_backend() {
    # Sets BACKEND to the user's choice (default: nftables when available).
    local ans
    if [ "$HAS_NFT" -eq 1 ] && [ "$HAS_IPT" -eq 1 ]; then
        echo ""
        echo -e "  ${BOLD}Firewall backend:${RESET}"
        echo -e "    ${CYAN}[1]${RESET} nftables ${DIM}(recommended)${RESET}"
        echo -e "    ${CYAN}[2]${RESET} iptables"
        while true; do
            ask ans "  Select backend [1-2] (Enter = nftables): "
            case "$ans" in
                ""|1) BACKEND="nft"; break ;;
                2)    BACKEND="ipt"; break ;;
                *) log_error "Invalid choice." ;;
            esac
        done
    elif [ "$HAS_NFT" -eq 1 ]; then
        BACKEND="nft"
        log_info "Only nftables available - using it."
    else
        BACKEND="ipt"
        log_info "Only iptables available - using it."
    fi
    if [ "$BACKEND" = "ipt" ] && iptables --version 2>/dev/null | grep -q nf_tables; then
        log_info "(iptables-nft shim detected - rules work through nft core)"
    fi
}

# Auto-detect only (no prompting) - used by --status.
detect_backend() {
    if command -v nft >/dev/null 2>&1 && nft list tables >/dev/null 2>&1; then
        BACKEND="nft"
        log_success "Firewall backend: ${GREEN}nftables${RESET}"
    elif command -v iptables >/dev/null 2>&1; then
        BACKEND="ipt"
        log_success "Firewall backend: ${GREEN}iptables${RESET}"
        # Warn if iptables is actually nft-backed
        if iptables --version 2>/dev/null | grep -q nf_tables; then
            log_info "(iptables-nft shim detected - rules work through nft core)"
        fi
    else
        log_error "Neither nftables nor iptables found."
        log_info "Install one of: apt install nftables | dnf install nftables"
        exit 1
    fi
}

# ----------------------------- Interface detection ----------------------------
# Lists candidate interfaces (name, state, IPv4) excluding loopback.
list_interfaces() {
    local -a out=()
    local name state ip4
    if command -v ip >/dev/null 2>&1; then
        while read -r name; do
            [ "$name" = "lo" ] && continue
            state="DOWN"
            ip link show "$name" 2>/dev/null | grep -qE "state (UP|UNKNOWN)" && state="UP"
            ip4=$(ip -4 addr show "$name" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
            out+=("$name|$state|${ip4:--}")
        done < <(ls /sys/class/net 2>/dev/null)
    fi
    # BUG FIX: guard against empty array (printf would print one blank line)
    if [ ${#out[@]} -gt 0 ]; then
        printf '%s\n' "${out[@]}"
    fi
}

# First IPv4 address of an interface in CIDR form (e.g. 192.168.1.5/24).
# Empty output if the interface has no IPv4 address.
subnet_of() {
    ip -4 addr show "$1" 2>/dev/null | awk '/inet /{print $2; exit}'
}

pick_wan() {
    local -a ifaces
    mapfile -t ifaces < <(list_interfaces)
    # BUG FIX: all display output MUST go to stderr (>&2). This function runs
    # inside $(...) command substitution; without >&2 the whole table was
    # captured into the return variable instead of shown to the user.
    {
        echo ""
        echo -e "  ${BOLD}Detected interfaces:${RESET}"
        print_separator
        if [ ${#ifaces[@]} -eq 0 ]; then
            log_error "No network interfaces found."
        fi
        local i n s a
        for i in "${!ifaces[@]}"; do
            IFS='|' read -r n s a <<< "${ifaces[$i]}"
            printf "   [${CYAN}%d${RESET}] ${BOLD}%-15s${RESET}  State: %-6s IP: %s\n" "$((i+1))" "$n" "$s" "$a"
        done
        print_separator
    } >&2
}

choose_interface() {
    local role="$1"  # WAN or LAN
    local -a ifaces
    mapfile -t ifaces < <(list_interfaces)
    pick_wan
    # BUG FIX (stdout pollution): this function runs inside $(...) command
    # substitution - ALL display output must go to stderr, only the chosen
    # name may touch stdout.
    if [ ${#ifaces[@]} -eq 0 ]; then
        { log_error "Cannot select ${role}: no network interfaces detected."; } >&2
        return 1
    fi
    while true; do
        ask sel "  Select ${role} interface [1-${#ifaces[@]}] (or 'c' to cancel): "
        is_cancel "$sel" && return 1
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#ifaces[@]}" ]; then
            IFS='|' read -r _n _s _a <<< "${ifaces[$((sel-1))]}"
            printf '%s' "$_n"
            return 0
        fi
        { log_error "Invalid selection."; } >&2
    done
}

# ----------------------------- Multi-select picker ----------------------------
# Lets the user pick ONE OR MORE interfaces for a role (LAN / DMZ).
# Accepts numbers ("1", "1 3", "1,2") and/or names ("eth1 eth2"), de-duplicated.
# Output: space-separated names on stdout; returns 1 on cancel/empty.
choose_interfaces_multi() {
    local role="$1"
    local -a ifaces
    mapfile -t ifaces < <(list_interfaces)
    pick_wan   # displays the table (stderr)
    if [ ${#ifaces[@]} -eq 0 ]; then
        { log_error "Cannot select ${role}: no network interfaces detected."; } >&2
        return 1
    fi

    local input tok resolved picked=""
    while true; do
        ask input "  Select ${role} interface(s), one or more [1-${#ifaces[@]}, names ok] (or 'c' to cancel): "
        is_cancel "$input" && return 1

        if [ -z "$input" ]; then
            # BUG FIX (debug run): this log went to stdout and got captured
            # into the caller's variable, producing garbage firewall rules.
            # All display output must go to stderr; only names on stdout.
            { log_info "No interfaces selected for ${role} - skipping."; } >&2
            printf '%s' ""
            return 0
        fi

        picked=""
        for tok in ${input//,/ }; do
            resolved=""
            if [[ "$tok" =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] 2>/dev/null \
               && [ "$tok" -le "${#ifaces[@]}" ] 2>/dev/null; then
                IFS='|' read -r resolved _s _a <<< "${ifaces[$((tok-1))]}"
            else
                # BUG FIX: unknown names were accepted verbatim, so a typo
                # produced bogus firewall rules. Validate against the
                # detected interface list instead.
                local known=0 kn
                for kn in "${ifaces[@]}"; do
                    [ "${kn%%|*}" = "$tok" ] && { known=1; break; }
                done
                if [ "$known" -eq 0 ]; then
                    { log_error "'$tok' is not a detected interface."; } >&2
                    picked=""
                    break
                fi
                resolved="$tok"
            fi
            case " $picked " in
                *" $resolved "*) ;;                       # de-duplicate
                *) picked+="${picked:+ }$resolved" ;;
            esac
        done

        if [ -z "$picked" ]; then
            { log_error "Nothing usable parsed from '$input'. Try again."; } >&2
            continue
        fi
        printf '%s' "$picked"
        return 0
    done
}

# Validates that no interface appears in two roles.
check_no_overlap() {
    local label_a="$1" list_a="$2" label_b="$3" list_b="$4"
    local a b
    for a in $list_a; do
        for b in $list_b; do
            if [ "$a" = "$b" ]; then
                log_error "Interface '$a' cannot be both ${label_a} and ${label_b}."
                return 1
            fi
        done
    done
    return 0
}

# ----------------------------- IP forwarding ----------------------------------
enable_forwarding() {
    local cur
    cur=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
    if [ "$cur" = "1" ]; then
        log_success "IP forwarding already enabled."
        return 0
    fi
    # Record previous state so rollback can restore it
    record sysctl_forward "$cur"
    sysctl -w net.ipv4.ip_forward=1 >/dev/null \
        && log_success "IP forwarding enabled." \
        || { log_error "Failed to enable ip_forward."; return 1; }
    # Persist forwarding across reboots
    if ! grep -q 'nat-tool:' /etc/sysctl.conf 2>/dev/null; then
        echo "# nat-tool: enable IPv4 forwarding" >> /etc/sysctl.conf
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
        record sysctl_persist "added"
    fi
    return 0
}

# ----------------------------- Persistence ------------------------------------
# Makes rules survive reboot. ON by default (prompt defaults to YES);
# fully undone by --rollback.

# NEW: wires 'include "/etc/nftables.d/*.conf"' into /etc/nftables.conf so the
# dumped table is actually loaded at boot. Previously this was only a warning,
# meaning persistence silently did nothing on default installs. The original
# config is backed up once and restored by --rollback (conf_backup action).
ensure_nft_include() {
    local conf="/etc/nftables.conf"
    if [ ! -f "$conf" ]; then
        log_warn "/etc/nftables.conf missing - cannot wire drop-in include automatically."
        log_info  "Create it or add manually: include \"/etc/nftables.d/*.conf\""
        return 1
    fi
    if grep -qE 'include.*nftables\.d' "$conf" 2>/dev/null; then
        return 0   # already wired (by us or the distro)
    fi
    mkdir -p "$BACKUP_DIR"
    if [ ! -f "$BACKUP_DIR/$(basename "$conf").bak" ]; then
        cp "$conf" "$BACKUP_DIR/$(basename "$conf").bak"
    fi
    grep -q "^conf_backup|$conf$" "$MANIFEST" || record conf_backup "$conf"
    printf '\n# nat-tool: load saved NAT rules\ninclude "/etc/nftables.d/*.conf"\n' >> "$conf"
    log_success "Wired include line into /etc/nftables.conf."
    return 0
}

persist_nft() {
    # Dump ONLY our table into a dedicated conf file, then make sure
    # nftables.service loads it at boot.
    mkdir -p "$(dirname "$NFT_PERSIST_FILE")"
    if ! nft list table ip nat_tool > "$NFT_PERSIST_FILE" 2>/dev/null; then
        log_error "Could not dump nftables table for persistence."
        return 1
    fi
    chmod 600 "$NFT_PERSIST_FILE"
    record nft_persist_file "$NFT_PERSIST_FILE"

    ensure_nft_include || true

    if command -v systemctl >/dev/null 2>&1 && systemctl enable nftables >/dev/null 2>&1; then
        log_success "nftables.service enabled (loads $NFT_PERSIST_FILE at boot)."
    else
        log_warn "Could not enable nftables.service automatically."
        log_info  "Enable manually: sudo systemctl enable nftables"
        log_warn  "Rules will NOT survive reboot until that service is enabled."
        return 1
    fi
    return 0
}

persist_ipt() {
    mkdir -p "$IPT_PERSIST_DIR"

    # Preferred: netfilter-persistent plugin if present (Debian family)
    if command -v netfilter-persistent >/dev/null 2>&1; then
        if netfilter-persistent save >/dev/null 2>&1; then
            record ipt_netfilter_persist "saved"
            log_success "Rules saved via netfilter-persistent."
            return 0
        fi
        log_warn "netfilter-persistent save failed - falling back to own unit."
    fi

    # Fallback: our own restore file + systemd oneshot unit
    iptables-save > "$IPT_RESTORE_FILE" || { log_error "iptables-save failed."; return 1; }
    chmod 600 "$IPT_RESTORE_FILE"
    record ipt_restore_file "$IPT_RESTORE_FILE"

    # Resolve the real iptables-restore path - hardcoding /sbin breaks on
    # distros where it lives in /usr/sbin (or usrmerge layouts).
    local restore_bin
    restore_bin=$(command -v iptables-restore 2>/dev/null || echo /sbin/iptables-restore)

    cat > "$IPT_UNIT_FILE" <<EOF
[Unit]
Description=NAT Tool - restore iptables rules at boot
After=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=$restore_bin $IPT_RESTORE_FILE

[Install]
WantedBy=multi-user.target
EOF
    record ipt_unit_file "$IPT_UNIT_FILE"

    if command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload >/dev/null 2>&1 \
       && systemctl enable nat-tool-restore >/dev/null 2>&1; then
        log_success "nat-tool-restore.service enabled (restores rules at boot)."
    else
        log_warn "Could not enable restore unit automatically."
        log_info  "Enable manually: sudo systemctl enable nat-tool-restore"
    fi
    return 0
}

remove_persistence() {
    local removed=0
    if [ -f "$NFT_PERSIST_FILE" ]; then
        rm -f "$NFT_PERSIST_FILE" && log_success "Removed $NFT_PERSIST_FILE" && removed=1
    fi
    if [ -f "$IPT_RESTORE_FILE" ]; then
        rm -f "$IPT_RESTORE_FILE" && log_success "Removed $IPT_RESTORE_FILE" && removed=1
    fi
    if [ -f "$IPT_UNIT_FILE" ]; then
        systemctl disable nat-tool-restore >/dev/null 2>&1
        rm -f "$IPT_UNIT_FILE" && log_success "Removed $IPT_UNIT_FILE" && removed=1
        systemctl daemon-reload >/dev/null 2>&1
    fi
    return 0
}

# ----------------------------- Apply rules ------------------------------------
apply_nft() {
    local wan="$1" lan="$2" dmz="$3"
    nft delete table ip nat_tool 2>/dev/null   # idempotent re-apply
    nft add table ip nat_tool || return 1
    nft add chain ip nat_tool postrouting '{ type nat hook postrouting priority srcnat ; }' || return 1

    # WAN masquerade for every internal interface (LAN + DMZ)
    local ifc
    for ifc in $lan $dmz; do
        nft add rule ip nat_tool postrouting oifname "$wan" iifname "$ifc" masquerade || return 1
    done
    if [ -z "$lan$dmz" ]; then
        # No internal zones: plain WAN-only masquerade
        nft add rule ip nat_tool postrouting oifname "$wan" masquerade || return 1
    fi

    if [ -n "$lan" ]; then
        nft add chain ip nat_tool forward '{ type filter hook forward priority filter ; policy accept ; }' || true
        local l
        for l in $lan; do
            nft add rule ip nat_tool forward iifname "$l" oifname "$wan" accept || true
        done
    fi

    # ---- DMZ policy: isolated zone ----
    # DMZ hosts may go out to WAN, but LAN must NOT reach DMZ directly, and
    # DMZ-initiated connections into LAN are dropped.
    if [ -n "$dmz" ]; then
        nft add chain ip nat_tool forward '{ type filter hook forward priority filter ; policy accept ; }' || true
        local d l
        for d in $dmz; do
            nft add rule ip nat_tool forward iifname "$d" oifname "$wan" accept || true   # DMZ -> WAN ok
            # BUG FIX: loop over every LAN interface; using $lan directly only
            # matches the first word when multiple LAN interfaces are selected.
            for l in $lan; do
                nft add rule ip nat_tool forward iifname "$l" oifname "$d" drop 2>/dev/null || true  # LAN -> DMZ blocked
                nft add rule ip nat_tool forward iifname "$d" oifname "$l" drop 2>/dev/null || true  # DMZ -> LAN blocked
            done
        done
    fi

    record nft_table "ip/nat_tool"
    return 0
}

apply_ipt() {
    local wan="$1" lan="$2" dmz="$3"
    local ifc subnet l d

    # BUG FIX (critical): the old code used '-i' inside POSTROUTING, which
    # iptables rejects ("Can't use -i with POSTROUTING") - every MASQUERADE
    # add failed on a real iptables backend. Match by source subnet instead
    # (preserves per-zone semantics; nft keeps using iifname).
    for ifc in $lan $dmz; do
        subnet=$(subnet_of "$ifc")
        if [ -z "$subnet" ]; then
            log_error "Interface $ifc has no IPv4 address - cannot build MASQUERADE rule."
            return 1
        fi
        # Idempotent re-apply: delete an identical rule before adding so
        # re-running never stacks duplicates.
        iptables -t nat -D POSTROUTING -o "$wan" -s "$subnet" -j MASQUERADE 2>/dev/null || true
        iptables -t nat -A POSTROUTING -o "$wan" -s "$subnet" -j MASQUERADE || return 1
        record ipt_rule "-t nat -D POSTROUTING -o $wan -s $subnet -j MASQUERADE"
    done
    if [ -z "$lan$dmz" ]; then
        iptables -t nat -D POSTROUTING -o "$wan" -j MASQUERADE 2>/dev/null || true
        iptables -t nat -A POSTROUTING -o "$wan" -j MASQUERADE || return 1
        record ipt_rule "-t nat -D POSTROUTING -o $wan -j MASQUERADE"
    fi

    if [ -n "$lan" ]; then
        for l in $lan; do
            iptables -D FORWARD -i "$l" -o "$wan" -j ACCEPT 2>/dev/null || true
            iptables -A FORWARD -i "$l" -o "$wan" -j ACCEPT || true
            record ipt_rule "-D FORWARD -i $l -o $wan -j ACCEPT"

            iptables -D FORWARD -i "$wan" -o "$l" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
            iptables -A FORWARD -i "$wan" -o "$l" -m state --state RELATED,ESTABLISHED -j ACCEPT || true
            record ipt_rule "-D FORWARD -i $wan -o $l -m state --state RELATED,ESTABLISHED -j ACCEPT"
        done
    fi

    # ---- DMZ policy: out to WAN allowed; isolated from LAN both ways ----
    # BUG FIX: loop over every LAN interface; using $lan directly in a single
    # iptables -i rule only matched the first word when multiple were selected.
    if [ -n "$dmz" ] && [ -n "$lan" ]; then
        for d in $dmz; do
            iptables -D FORWARD -i "$d" -o "$wan" -j ACCEPT 2>/dev/null || true
            iptables -A FORWARD -i "$d" -o "$wan" -j ACCEPT || true
            record ipt_rule "-D FORWARD -i $d -o $wan -j ACCEPT"

            for l in $lan; do
                iptables -D FORWARD -i "$l" -o "$d" -j DROP 2>/dev/null || true
                iptables -A FORWARD -i "$l" -o "$d" -j DROP || true
                record ipt_rule "-D FORWARD -i $l -o $d -j DROP"

                iptables -D FORWARD -i "$d" -o "$l" -j DROP 2>/dev/null || true
                iptables -A FORWARD -i "$d" -o "$l" -j DROP || true
                record ipt_rule "-D FORWARD -i $d -o $l -j DROP"
            done
        done
    elif [ -n "$dmz" ]; then
        for d in $dmz; do
            iptables -D FORWARD -i "$d" -o "$wan" -j ACCEPT 2>/dev/null || true
            iptables -A FORWARD -i "$d" -o "$wan" -j ACCEPT || true
            record ipt_rule "-D FORWARD -i $d -o $wan -j ACCEPT"
        done
    fi
    return 0
}

show_status() {
    clear; print_banner
    echo -e "${BLUE}${BOLD}  Current NAT Rules (as applied by this tool)${RESET}"
    print_separator
    detect_backend
    echo ""
    if [ "$BACKEND" = "nft" ]; then
        nft list table ip nat_tool 2>/dev/null || log_warn "No nat_tool table present."
    else
        iptables -t nat -L POSTROUTING -nv 2>/dev/null | grep -E "MASQUERADE|target" || log_warn "No MASQUERADE rules found."
    fi
    print_separator
    echo -e "  ${BOLD}ip_forward:${RESET} $(sysctl -n net.ipv4.ip_forward 2>/dev/null)"
    echo -e "  ${BOLD}Persistence:${RESET}"
    [ -f "$NFT_PERSIST_FILE" ]  && echo -e "      nft conf   : $NFT_PERSIST_FILE (present)"
    [ -f "$IPT_RESTORE_FILE" ]  && echo -e "      ipt file   : $IPT_RESTORE_FILE (present)"
    [ -f "$IPT_UNIT_FILE" ]     && echo -e "      ipt unit   : enabled"
    if [ ! -f "$NFT_PERSIST_FILE" ] && [ ! -f "$IPT_RESTORE_FILE" ]; then
        echo -e "      ${DIM}not saved - rules will not survive reboot${RESET}"
    fi
}

# ----------------------------- Main wizard ------------------------------------
main_wizard() {
    clear; print_banner
    echo -e "${BLUE}${BOLD}  NAT Gateway Configuration Wizard${RESET}"
    print_separator

    detect_available_backends || exit 1
    manifest_init

    # NEW FEATURE: pick nftables or iptables (Enter = nftables when both exist)
    choose_backend
    log_success "Firewall backend: ${GREEN}${BACKEND}${RESET}"

    WAN_IFACE=$(choose_interface "WAN (internet-facing)") || { log_warn "Cancelled."; return 1; }
    log_success "WAN interface: ${GREEN}$WAN_IFACE${RESET}"

    ask want_zones "  Configure internal zones (LAN / DMZ)? [y/N/c]: "
    is_cancel "$want_zones" && { log_warn "Cancelled."; return 1; }
    LAN_IFACE=""
    DMZ_IFACES=""
    if [[ "$want_zones" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "  ${BOLD}Zone assignment:${RESET}"
        echo "    LAN = trusted internal network (full outbound access)"
        echo "    DMZ = isolated zone (outbound to WAN only, cut off from LAN)"
        echo ""
        # --- Multi-select LAN ---
        while true; do
            LAN_IFACE=$(choose_interfaces_multi "LAN") || { log_warn "Cancelled."; return 1; }
            [ -z "$LAN_IFACE" ] && break
            check_no_overlap "WAN" "$WAN_IFACE" "LAN" "$LAN_IFACE" && break
        done
        if [ -n "$LAN_IFACE" ]; then
            log_success "LAN interface(s): ${GREEN}$LAN_IFACE${RESET}"
        fi
        # --- Multi-select DMZ ---
        while true; do
            DMZ_IFACES=$(choose_interfaces_multi "DMZ") || { log_warn "Cancelled."; return 1; }
            [ -z "$DMZ_IFACES" ] && break
            check_no_overlap "WAN" "$WAN_IFACE" "DMZ" "$DMZ_IFACES" \
                && check_no_overlap "LAN" "$LAN_IFACE" "DMZ" "$DMZ_IFACES" && break
        done
        if [ -n "$DMZ_IFACES" ]; then
            log_success "DMZ interface(s): ${GREEN}$DMZ_IFACES${RESET}"
        fi
    fi

    # ---- Review & Confirm ----
    echo ""
    echo -e "${CYAN}${BOLD}  Review configuration:${RESET}"
    echo -e "      Backend : $BACKEND"
    echo -e "      WAN     : $WAN_IFACE (masquerade)"
    [ -n "$LAN_IFACE" ] && echo -e "      LAN     : $LAN_IFACE -> $WAN_IFACE forwarding"
    [ -n "$DMZ_IFACES" ] && {
        echo -e "      DMZ     : $DMZ_IFACES (isolated: no LAN<->DMZ traffic)"
        [ -z "$LAN_IFACE" ] && echo -e "      ${DIM}note: DMZ without LAN - only outbound to WAN${RESET}"
    }
    print_separator
    ask confirm "  Apply this NAT setup? [y/N/c]: "
    # BUG FIX: was a mixed ||/&& chain (left-associative in bash) that only
    # worked by accident - now an explicit if, matching dns-setup.sh style.
    if is_cancel "$confirm" || [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "Cancelled. Nothing changed."
        return 1
    fi

    enable_forwarding || return 1

    echo ""
    log_info "Applying firewall rules..."
    # BUG FIX: capture the return code directly instead of relying on $?
    # after an if/else block (which reflects the last command run inside it).
    local apply_rc=0
    if [ "$BACKEND" = "nft" ]; then
        apply_nft "$WAN_IFACE" "$LAN_IFACE" "$DMZ_IFACES" || apply_rc=$?
    else
        apply_ipt "$WAN_IFACE" "$LAN_IFACE" "$DMZ_IFACES" || apply_rc=$?
    fi

    if [ $apply_rc -eq 0 ]; then
        log_success "NAT gateway is ACTIVE. Manifest: $MANIFEST"
        # ---- Persistence prompt (DEFAULT = YES so NAT survives reboots) ----
        echo ""
        ask persist_answer "  Make rules persist across reboot? [Y/n/c]: "
        if is_cancel "$persist_answer"; then
            log_warn "Cancelled (rules stay active until reboot only)."
        elif [[ "$persist_answer" =~ ^[Nn]$ ]]; then
            log_info "Skipping persistence - rules are active for this session only."
        else
            local persist_ok=0
            if [ "$BACKEND" = "nft" ]; then
                persist_nft && persist_ok=1
            else
                persist_ipt && persist_ok=1
            fi
            if [ $persist_ok -eq 1 ]; then
                log_success "NAT rules will be restored automatically at next boot."
            else
                log_warn "Persistence save failed - rules are active for this boot only."
            fi
        fi

        log_info "Undo anytime with: sudo bash $0 --rollback"
    else
        log_error "Rule application failed - run '$0 --rollback' to clean up."
        return 1
    fi
}

case "${1:-}" in
    --rollback) check_root; do_rollback ;;
    --status)   check_root; show_status ;;
    *)          check_root; main_wizard ;;
esac
