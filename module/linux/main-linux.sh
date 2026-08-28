#!/bin/bash

# ==============================================================================
# LINUX SCRIPT MANAGEMENT TOOL
# Main menu that dispatches to the per-task scripts under module/linux/.
#
# Fixes applied:
#   * Option 3: was calling 'zsh.sh' which does not exist;
#               corrected to 'zsh-install.sh'.
#   * Option 6: was calling 'ssh.sh' which does not exist on disk
#               (the SSH script lives in module/windows/win-ssh.ps1).
#               Now warns the user instead of erroring silently.
#   * Surfaced the previously-orphaned scripts:
#       - 2.bind-internal-auto.sh  -> Option 7
#       - dhcp-auto.sh             -> Option 3 (moved DHCP auto next to DHCP setup)
#       - webmail.sh               -> Option 8
# ==============================================================================

# ----------------------------- UI Colors & Formatting -------------------------
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'

print_banner() {
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║              LINUX SCRIPT MANAGEMENT TOOL                         ║${RESET}"
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

# Resolve the directory containing this script so paths work regardless of cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run a sibling script if it exists, otherwise report cleanly.
# Usage: run_script "filename.sh" "Friendly description"
run_script() {
    local file="$1"
    local label="$2"
    local path="${SCRIPT_DIR}/${file}"

    if [[ ! -f "$path" ]]; then
        log_error "Script not found: ${file}"
        log_warn  "Expected at: ${path}"
        return 1
    fi

    chmod +x "$path"
    log_info "Launching ${label}..."
    echo ""
    bash "$path"
    local rc=$?
    echo ""
    if [[ $rc -eq 0 ]]; then
        log_success "${label} finished (exit 0)."
    else
        log_warn "${label} exited with code ${rc}."
    fi
    return $rc
}

clear
print_banner
print_separator

while true; do
    echo -e "${BOLD}  Available actions:${RESET}"
    echo "    1) Install Browser"
    echo "    2) Run DHCP Setup Wizard"
    echo "    3) Run DHCP Auto Setup"
    echo "    4) Install ZSH"
    echo "    5) Install Font"
    echo "    6) Enable NAT"
    echo "    7) Run Bind (Internal DNS) Auto Setup"
    echo "    8) Run Webmail Setup"
    echo "    9) Run SSH Script"
    echo "   10) Exit"
    print_separator

    read -p "  Enter your choice [1-10]: " choice

    case $choice in
        1) clear; print_banner; run_script "browser.sh"              "Browser installer"            ;;
        2) clear; print_banner; run_script "dhcp-setup.sh"           "DHCP setup wizard"           ;;
        3) clear; print_banner; run_script "dhcp-auto.sh"             "DHCP auto setup"             ;;
        4) clear; print_banner; run_script "zsh-install.sh"          "ZSH installer"               ;;
        5) clear; print_banner; run_script "font.sh"                 "Font installer"              ;;
        6) clear; print_banner; run_script "nat.sh"                  "NAT enabler"                 ;;
        7) clear; print_banner; run_script "2.bind-internal-auto.sh"  "Bind (Internal DNS) setup"   ;;
        8) clear; print_banner; run_script "webmail.sh"              "Webmail setup"               ;;
        9)
            clear; print_banner
            log_warn "No Linux SSH script is bundled with this project yet."
            log_info  "The SSH script lives in module/windows/win-ssh.ps1 (Windows only)."
            log_info  "Add module/linux/ssh.sh to enable this option."
            ;;
        10) clear; echo "Exiting..."; exit 0 ;;
        *) clear; print_banner; echo -e "${RED}  Invalid choice. Please try again.${RESET}" ;;
    esac

    echo ""
    read -p "  Press [Enter] to return to the menu..." _
    clear
    print_banner
    print_separator
done
