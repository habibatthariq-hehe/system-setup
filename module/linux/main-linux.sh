#!/bin/bash

# ==============================================================================
# LINUX SCRIPT MANAGEMENT TOOL
# Central dispatcher for modular system configuration and setup scripts.
#
# Features:
#   * Root enforcement and safety checks.
#   * Automatic path resolution for nested module directories.
#   * Unified UI with consistent coloring and banners.
#   * Robust script execution with exit code tracking.
# ==============================================================================

# ----------------------------- UI Colors & Formatting -------------------------
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'

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

# ----------------------------- Safety & Path Resolution -----------------------

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root. Use: sudo bash $0"
        exit 1
    fi
}

# Resolve the project root based on this script's location
# SCRIPT_DIR is /home/yusuf/project/system-setup/module/linux
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run a script, supporting both direct siblings and scripts in subdirectories
# Usage: run_script "relative/path/to/script.sh" "Friendly description"
run_script() {
    local relative_path="$1"
    local label="$2"
    local full_path="${SCRIPT_DIR}/${relative_path}"

    if [[ ! -f "$full_path" ]]; then
        log_error "Script not found: ${relative_path}"
        log_warn  "Expected at: ${full_path}"
        return 1
    fi

    chmod +x "$full_path"
    log_info "Launching ${label}..."
    echo ""
    
    # Execute the script. We use bash explicitly to ensure compatibility.
    bash "$full_path"
    local rc=$?
    
    echo ""
    if [[ $rc -eq 0 ]]; then
        log_success "${label} finished successfully (exit 0)."
    else
        log_warn "${label} exited with code ${rc}."
    fi
    return $rc
}

# ----------------------------- Main Logic --------------------------------------

main() {
    check_root
    clear
    print_banner
    print_separator

    while true; do
        echo -e "${BOLD}  Available actions:${RESET}"
        
        # --- Installer Modules ---
        echo -e "\n  ${BLUE}${BOLD} Installation${RESET}"
        echo "    1) Install Browser"
        echo "    2) Install ZSH"
        echo "    3) Install Fonts"
        echo "    4) Setup Webmail Server"
        
        # --- Networking Modules ---
        echo -e "\n  ${BLUE}${BOLD} Networking${RESET}"
        echo "    5) DHCP Setup Wizard"
        echo "    6) Enable NAT Gateway"
        echo "    7) BIND Internal DNS Setup"
        echo "    8) Configure Static IP"
        echo "    9) Configure SSH Server"
        
        echo ""
        echo "   0) Exit"
        print_separator

        read -p "  Enter your choice [0-9]: " choice

        case $choice in
            1) clear; print_banner; run_script "installer/browser.sh"              "Browser installer"            ;;
            2) clear; print_banner; run_script "installer/zsh-install.sh"          "ZSH installer"               ;;
            3) clear; print_banner; run_script "installer/font.sh"                 "Font installer"              ;;
            4) clear; print_banner; run_script "installer/webmail.sh"              "Webmail setup"               ;;
            5) clear; print_banner; run_script "networking/dhcp-setup.sh"           "DHCP setup wizard"           ;;
            6) clear; print_banner; run_script "networking/nat.sh"                  "NAT enabler"                 ;;
            7) clear; print_banner; run_script "networking/dns-setup.sh"              "Bind (Internal DNS) setup"   ;;
            8) clear; print_banner; run_script "networking/static-ip-setup.sh"       "Static IP setup"             ;;
            9) clear; print_banner; run_script "networking/ssh.sh"                  "SSH server setup"             ;;
            0) clear; echo "Exiting..."; exit 0 ;;
            *) clear; print_banner; echo -e "${RED}  Invalid choice. Please try again.${RESET}" ;;
        esac

        echo ""
        read -p "  Press [Enter] to return to the menu..." _
        clear
        print_banner
        print_separator
    done
}

main
