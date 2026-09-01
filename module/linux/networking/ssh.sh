#!/bin/bash

# ==============================================================================
# SSH INTERACTIVE SETUP SCRIPT
# Features: Package-manager detection, SSH key generation, Target configuration,
#           Key deployment (ssh-copy-id w/ manual fallback), Manifest-based
#           Rollback, Colored UI, Cancel at any prompt.
#
# Bugs fixed vs. previous version:
#   * EOF/Ctrl-D at the package-manager `select` prompt left PKG empty and
#     silently continued -> now defaults to first manager with a warning.
#   * `select` loop could spin forever on garbage input in some shells ->
#     bounded with an explicit retry counter and cancel keyword ('c').
#   * ssh-keygen ran non-interactively (-N "") but its failure was
#     swallowed; now checked explicitly.
#   * Manual key-copy fallback used `cat file | ssh ...` (useless use of cat
#     and no exit-code check) -> now uses `< file` redirection and verifies.
#   * deploy_ssh_key never reported success/failure of ssh-copy-id.
#   * TARGET_PORT accepted arbitrary garbage -> now validated as numeric 1-65535.
#   * TARGET_IP not validated -> basic IPv4 sanity check (warn only, since
#     hostnames are also legal here).
#   * Menu option "3. Manual SSH Key Export" ran deploy_ssh_key which is the
#     same as option 2's final step but without wizard context; kept, but it
#     now clearly states what it does and re-confirms the target.
#
# Rollback feature:
#   * Every generated key is recorded in ~/.ssh-setup-manifest along with its
#     .pub path. Run this script with --rollback to remove keys created by
#     this script (never touches pre-existing keys).
#   * Remote authorized_keys entries added via the manual fallback are NOT
#     auto-removed (would require remote root); the manifest notes them so you
#     can clean up manually.
#
# Usage:
#   bash ssh.sh              normal interactive run
#   bash ssh.sh --dry-run    run in simulated mode, safely printing actions
#   bash ssh.sh --rollback   remove keys/records created by this script
# ==============================================================================

set -o pipefail

DRY_RUN=false
DO_ROLLBACK=false

for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
    elif [[ "$arg" == "--rollback" ]]; then
        DO_ROLLBACK=true
    fi
done

# ----------------------------- UI Colors & Formatting -------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

MANIFEST="$HOME/.ssh-setup-manifest"

# Global variables to store the target configuration
TARGET_HOST=""
TARGET_IP=""
TARGET_USER=""
TARGET_PORT=""

print_banner() {
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║                 SSH INTERACTIVE SETUP SCRIPT                      ║${RESET}"
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
dry_run_print() { echo -e "  ${YELLOW}${BOLD}[DRY RUN]${RESET} $1"; }

pause_menu() {
    echo ""
    read -p "  Press [Enter] to return to the main menu..." _
}

# Check if input indicates user wants to cancel
is_cancel() {
    [[ "$1" =~ ^(c|cancel|C|CANCEL|q|quit|Q|QUIT|exit|EXIT)$ ]]
}

# ----------------------------- Manifest / Rollback engine ---------------------

manifest_init() {
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would initialize manifest at $MANIFEST"
    else
        : > "$MANIFEST"
    fi
}

record() {
    local action="$1"; shift
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would record action '$action' in manifest: $*"
    else
        printf '%s\n' "$action|$*" >> "$MANIFEST"
    fi
}

do_rollback() {
    clear
    print_banner
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}${BOLD}[DRY RUN MODE ENABLED - NO CHANGES WILL BE APPLIED]${RESET}"
        print_separator
    fi

    if [[ ! -s "$MANIFEST" ]]; then
        log_warn "No manifest found at $MANIFEST - nothing to roll back."
        log_info "(A missing or empty manifest means this script has not created anything.)"
        return 0
    fi

    log_info "Rolling back changes recorded in $MANIFEST ..."
    print_separator

    tac "$MANIFEST" | while IFS= read -r entry; do
        local action="${entry%%|*}"
        local args="${entry#*|}"
        case "$action" in
            generated_key)
                # args = "<private_key_path>"
                local priv="$args" pub="${args}.pub"
                if [ "$DRY_RUN" = true ]; then
                    [ -f "$pub" ] && dry_run_print "Would remove public key: $(basename "$pub")"
                    [ -f "$priv" ] && dry_run_print "Would remove private key: $(basename "$priv")"
                else
                    [ -f "$pub"  ] && rm -f "$pub"  && log_success "Removed public key: $(basename "$pub")"
                    [ -f "$priv" ] && rm -f "$priv" && log_success "Removed private key: $(basename "$priv")"
                fi
                ;;
            appended_remote_authorized_keys)
                log_warn "Manual remote deployment was recorded for: $args"
                log_info "Remove that entry manually on the target host:"
                log_info "  ssh <target> 'sed -i \"\\|$(basename "${args%%@*}")|d\" ~/.ssh/authorized_keys'"
                ;;
            installed_pkg)
                log_info "Package '$args' was installed. Remove manually if desired"
                log_info "  (e.g. sudo apt remove openssh-client / sudo dnf remove openssh-clients)."
                ;;
        esac
    done

    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would clear manifest at $MANIFEST"
    else
        : > "$MANIFEST"
    fi
    print_separator
    log_success "Rollback complete."
    return 0
}

[[ "$DO_ROLLBACK" = true ]] && { do_rollback; exit 0; }

# ----------------------------- Validation helpers -----------------------------

valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

# Basic IPv4 shape check (warn-only; hostnames are also valid targets).
looks_like_ipv4() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

# ==========================================
# CORE FUNCTION: Package Manager & SSH Keygen
# ==========================================

detect_package_manager() {
    PKG_MANAGERS=()
    command -v apt     >/dev/null 2>&1 && PKG_MANAGERS+=("apt")
    command -v dnf     >/dev/null 2>&1 && PKG_MANAGERS+=("dnf")
    command -v yum     >/dev/null 2>&1 && PKG_MANAGERS+=("yum")
    command -v pacman  >/dev/null 2>&1 && PKG_MANAGERS+=("pacman")
    command -v zypper  >/dev/null 2>&1 && PKG_MANAGERS+=("zypper")

    if [ ${#PKG_MANAGERS[@]} -eq 0 ]; then
        log_error "No supported package manager found."
        return 1
    fi

    if [ ${#PKG_MANAGERS[@]} -eq 1 ]; then
        PKG="${PKG_MANAGERS[0]}"
        log_success "Detected package manager: ${GREEN}$PKG${RESET}"
    else
        log_info "Multiple package managers detected:"
        local tries=0
        PS3="  Select one [1-${#PKG_MANAGERS[@]}, or 'c' to cancel]: "
        select PKG in "${PKG_MANAGERS[@]}"; do
            if [ -n "$PKG" ]; then
                break
            elif is_cancel "$REPLY"; then
                log_warn "Cancelled by user."
                return 1
            elif [ -z "$REPLY" ] || (( ++tries >= 5 )); then
                PKG="${PKG_MANAGERS[0]}"      # BUG FIX: empty input / EOF no longer falls through
                log_warn "No valid selection - defaulting to: $PKG"
                break
            else
                echo "Invalid selection."
            fi
        done
    fi
    return 0
}

generate_ssh_key() {
    if ls "$HOME"/.ssh/id_*.pub >/dev/null 2>&1; then
        log_success "Existing SSH key(s) detected in ~/.ssh/"
        while true; do
            read -p "  Generate a [new] key or [keep] the existing one? (new/keep/c): " key_choice
            is_cancel "$key_choice" && { log_warn "Cancelled."; return 1; }
            if [[ "$key_choice" == "new" ]]; then
                break
            elif [[ "$key_choice" == "keep" ]]; then
                log_success "Keeping existing SSH key. Skipping generation."
                return 0
            else
                echo "Invalid choice. Please type 'new', 'keep', or 'c' to cancel."
            fi
        done
    else
        log_info "No existing SSH key found."
    fi

    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would create and chmod ~/.ssh directory"
    else
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
    fi

    echo ""
    log_info "Starting ssh-keygen (accept defaults or customize as prompted)..."
    
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would run: ssh-keygen -t ed25519 -f $HOME/.ssh/id_ed25519 -N ''"
        record generated_key "$HOME/.ssh/id_ed25519"
        record installed_pkg "openssh-client (via $PKG)" 2>/dev/null || true
        log_success "[Simulated] New ED25519 key generated and recorded for rollback."
        return 0
    fi

    if ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" ""; then
        record generated_key "$HOME/.ssh/id_ed25519"
        record installed_pkg "openssh-client (via $PKG)" 2>/dev/null || true
        log_success "New ED25519 key generated and recorded for rollback."
    else
        # Fallback to RSA if ed25519 unsupported (very old ssh-keygen)
        log_warn "ED25519 generation failed - falling back to RSA 4096."
        if ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N "" ""; then
            record generated_key "$HOME/.ssh/id_rsa"
            log_success "New RSA-4096 key generated and recorded for rollback."
        else
            log_error "ssh-keygen failed."
            return 1
        fi
    fi
    return 0
}

run_core_function() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Option 1] Core Setup - Package Manager & SSH Keygen${RESET}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}${BOLD}[DRY RUN MODE ENABLED - NO CHANGES WILL BE APPLIED]${RESET}"
    fi
    print_separator
    echo -e "  ${DIM}Tip: Type 'c' or 'cancel' at any prompt to abort.${RESET}"
    echo ""

    log_info "Detecting package manager..."
    detect_package_manager || { pause_menu; return 1; }

    # Ensure an ssh client exists (ssh-keygen lives in openssh-client(s)).
    if ! command -v ssh-keygen >/dev/null 2>&1 || [ "$DRY_RUN" = true ]; then
        log_info "Installing OpenSSH client via $PKG..."
        if [ "$DRY_RUN" = true ]; then
            dry_run_print "Would install openssh-client using $PKG"
            log_success "OpenSSH client installation simulated."
        else
            case $PKG in
                apt)    sudo apt update && sudo apt install -y openssh-client ;;
                dnf)    sudo dnf install -y openssh-clients ;;
                yum)    sudo yum install -y openssh-clients ;;
                pacman) sudo pacman -Sy --noconfirm openssh ;;
                zypper) sudo zypper install -y openssh ;;
            esac
            command -v ssh-keygen >/dev/null 2>&1 \
                && log_success "OpenSSH client installed." \
                || { log_error "openssh install failed."; pause_menu; return 1; }
        fi
    else
        log_success "ssh-keygen already available."
    fi

    generate_ssh_key || true
    pause_menu
}

# ==========================================
# DEPLOY SSH KEY TO TARGET
# ==========================================

deploy_ssh_key() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Deploy] Copy SSH Key to Target${RESET}"
    print_separator

    if [ -z "$TARGET_IP" ] && [ -z "$TARGET_HOST" ]; then
        log_error "No target configured!"
        log_info "Please configure the target first (Main Menu option 2)."
        pause_menu
        return 1
    fi

    if ! ls "$HOME"/.ssh/id_*.pub >/dev/null 2>&1; then
        log_error "No SSH key found on this system!"
        log_info "Run Core Setup (Main Menu option 1) to generate one first."
        pause_menu
        return 1
    fi

    local target_address="${TARGET_IP:-$TARGET_HOST}"
    local ssh_user="${TARGET_USER:-$USER}"
    local ssh_port="${TARGET_PORT:-22}"

    echo ""
    echo -e "  ${BOLD}Target Address :${RESET} $target_address"
    echo -e "  ${BOLD}Target Username:${RESET} $ssh_user"
    echo -e "  ${BOLD}Target Port    :${RESET} $ssh_port"
    echo ""

    read -p "  Proceed with key deployment? [Y/n/c]: " confirm
    if is_cancel "$confirm" || [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_warn "Deployment cancelled by user."
        pause_menu
        return 1
    fi

    echo ""
    log_info "You may be prompted for the remote user's password."
    print_separator

    local rc=1
    if [ "$DRY_RUN" = true ]; then
        if command -v ssh-copy-id >/dev/null 2>&1; then
            dry_run_print "Would run: ssh-copy-id -p \"$ssh_port\" \"$ssh_user@$target_address\""
        else
            dry_run_print "Would run manual SSH key copy to $ssh_user@$target_address:$ssh_port"
            record appended_remote_authorized_keys "$ssh_user@$target_address:$ssh_port"
        fi
        rc=0
    else
        if command -v ssh-copy-id >/dev/null 2>&1; then
            ssh-copy-id -p "$ssh_port" "$ssh_user@$target_address"
            rc=$?
        else
            log_warn "ssh-copy-id not found. Attempting manual copy..."
            # BUG FIX: '< file' redirection instead of useless-use-of-cat, plus
            # pipefail-aware exit-code capture.
            ssh -p "$ssh_port" "$ssh_user@$target_address" \
                "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" \
                < "$HOME"/.ssh/id_*.pub
            rc=$?
            if [ $rc -eq 0 ]; then
                record appended_remote_authorized_keys "$ssh_user@$target_address:$ssh_port"
            fi
        fi
    fi

    print_separator
    if [ $rc -eq 0 ]; then
        log_success "Key successfully deployed to ${GREEN}$ssh_user@$target_address${RESET}!"
        log_info "Test it with: ssh -p $ssh_port $ssh_user@$target_address"
    else
        log_error "Deployment failed (exit code $rc). Check address/credentials and try again."
    fi
    pause_menu
    return $rc
}

# ==========================================
# TARGET CONFIGURATION WIZARD
# ==========================================

configure_target() {
    local step=1

    while true; do
        clear
        print_banner
        echo -e "${BLUE}${BOLD}  [Option 2] Target Configuration Wizard${RESET}"
        print_separator
        echo -e "  ${DIM}Tip: Type 'c' at ANY value prompt to abort the wizard.${RESET}"
        echo ""

        if [ $step -eq 1 ]; then
            echo -e "${CYAN}${BOLD}  --- Step 1: Target Hostname ---${RESET}"
            echo -e "  Current: ${TARGET_HOST:-[Not Set]}"
            echo ""
            echo "  1) Input/Change Target Hostname"
            echo "  2) Next Step (Target IP)"
            echo "  3) Cancel & Return to Main Menu"
            read -p "  Select an option [1-3]: " choice
            case $choice in
                1)
                    read -p "  Enter Target Hostname (or 'c' to cancel): " val
                    is_cancel "$val" && { log_warn "Wizard cancelled."; sleep 1; return; }
                    [ -n "$val" ] && TARGET_HOST="$val"
                    ;;
                2) step=2 ;;
                3) return ;;
                *) log_error "Invalid selection."; sleep 1 ;;
            esac

        elif [ $step -eq 2 ]; then
            echo -e "${CYAN}${BOLD}  --- Step 2: Target IP ---${RESET}"
            echo -e "  Current: ${TARGET_IP:-[Not Set]}"
            echo ""
            echo "  1) Input/Change Target IP"
            echo "  2) Previous Step (Back to Hostname)"
            echo "  3) Next Step (Target Username)"
            echo "  4) Cancel & Return to Main Menu"
            read -p "  Select an option [1-4]: " choice
            case $choice in
                1)
                    read -p "  Enter Target IP (or 'c' to cancel): " val
                    is_cancel "$val" && { log_warn "Wizard cancelled."; sleep 1; return; }
                    if [ -n "$val" ]; then
                        if looks_like_ipv4 "$val"; then
                            TARGET_IP="$val"
                        else
                            # BUG FIX: warn on malformed IP instead of silently accepting garbage.
                            log_warn "'$val' doesn't look like a valid IPv4 address."
                            read -p "  Use it anyway as hostname? [y/N]: " yn
                            [[ "$yn" =~ ^[Yy]$ ]] && TARGET_IP="$val"
                        fi
                    fi
                    ;;
                2) step=1 ;;
                3) step=3 ;;
                4) return ;;
                *) log_error "Invalid selection."; sleep 1 ;;
            esac

        elif [ $step -eq 3 ]; then
            echo -e "${CYAN}${BOLD}  --- Step 3: Target Username ---${RESET}"
            echo -e "  Current: ${TARGET_USER:-[Not Set]}"
            echo ""
            echo "  1) Input/Change Target Username"
            echo "  2) Previous Step (Back to IP)"
            echo "  3) Next Step (Target Port)"
            echo "  4) Cancel & Return to Main Menu"
            read -p "  Select an option [1-4]: " choice
            case $choice in
                1)
                    read -p "  Enter Target Username (or 'c' to cancel): " val
                    is_cancel "$val" && { log_warn "Wizard cancelled."; sleep 1; return; }
                    [ -n "$val" ] && TARGET_USER="$val"
                    ;;
                2) step=2 ;;
                3) step=4 ;;
                4) return ;;
                *) log_error "Invalid selection."; sleep 1 ;;
            esac

        elif [ $step -eq 4 ]; then
            echo -e "${CYAN}${BOLD}  --- Step 4: Target Port ---${RESET}"
            echo -e "  Current: ${TARGET_PORT:-22 (Default)}"
            echo ""
            echo "  1) Use Default Port (22)"
            echo "  2) Input Custom Port"
            echo "  3) Previous Step (Back to Username)"
            echo "  4) Finish & Automatically Deploy SSH Key"
            echo "  5) Cancel & Return to Main Menu"
            read -p "  Select an option [1-5]: " choice
            case $choice in
                1) TARGET_PORT=22 ;;
                2)
                    read -p "  Enter Custom Port (or 'c' to cancel): " val
                    is_cancel "$val" && { log_warn "Wizard cancelled."; sleep 1; return; }
                    # BUG FIX: validate port range instead of accepting arbitrary text.
                    if valid_port "$val"; then
                        TARGET_PORT="$val"
                    else
                        log_error "Invalid port (must be 1-65535)."
                        sleep 1
                    fi
                    ;;
                3) step=3 ;;
                4)
                    if [ -z "$TARGET_HOST" ] && [ -z "$TARGET_IP" ]; then
                        log_error "Cannot finish: no target host/IP configured yet."
                        sleep 2
                        continue
                    fi
                    echo ""
                    log_success "Configuration saved!"
                    echo -e "  ${BOLD}Host:${RESET} ${TARGET_HOST:-None} | ${BOLD}IP:${RESET} ${TARGET_IP:-None} | ${BOLD}User:${RESET} ${TARGET_USER:-\$(current)} | ${BOLD}Port:${RESET} ${TARGET_PORT:-22}"
                    sleep 2
                    deploy_ssh_key
                    return
                    ;;
                5) return ;;
                *) log_error "Invalid selection."; sleep 1 ;;
            esac
        fi
    done
}

# ==========================================
# MAIN MENU LOOP
# ==========================================

while true; do
    clear
    print_banner
    echo -e "${BOLD}  Main Menu:${RESET}"

    dry_run_status=""
    if [ "$DRY_RUN" = true ]; then
        dry_run_status="${YELLOW}[ON]${RESET}"
    else
        dry_run_status="${DIM}[OFF]${RESET}"
    fi

    echo "    1) Run Core Setup (Package Manager & SSH-Keygen)"
    echo "    2) Configure Target and Auto-Deploy SSH Key"
    echo "    3) Manual SSH Key Deployment (uses saved target)"
    echo "    4) Rollback Generated SSH Keys & Changes"
    echo -e "    5) Toggle Dry Run Mode $dry_run_status"
    echo "    6) Exit"
    print_separator

    if [ -n "$TARGET_HOST" ] || [ -n "$TARGET_IP" ] || [ -n "$TARGET_USER" ] || [ -n "$TARGET_PORT" ]; then
        echo -e "  ${BOLD}Current Target:${RESET} Host: ${TARGET_HOST:-None} | IP: ${TARGET_IP:-None} | User: ${TARGET_USER:-\$(current)} | Port: ${TARGET_PORT:-22}"
        print_separator
    fi

    read -p "  Please choose an option [1-6]: " main_choice

    case $main_choice in
        1) run_core_function ;;
        2) configure_target ;;
        3) deploy_ssh_key ;;
        4)
            do_rollback
            pause_menu
            ;;
        5)
            if [ "$DRY_RUN" = true ]; then
                DRY_RUN=false
                log_success "Dry Run mode DISABLED. Changes will be APPLIED."
            else
                DRY_RUN=true
                log_success "Dry Run mode ENABLED. Changes will only be PRINTED."
            fi
            sleep 1.5
            ;;
        6) clear; echo "Exiting script. Goodbye!"; exit 0 ;;
        *)
            clear
            print_banner
            log_error "Invalid option. Please select a number between 1 and 6."
            sleep 1
            ;;
    esac
done
