#!/bin/bash

# Purpose: Set the hostname of the system
# Version: 1.0.0


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
    echo -e "${CYAN}${BOLD}║                 HOSTNAME INTERACTIVE SETUP TOOL                   ║${RESET}"
    echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# Separator Line

print_separator() {
    echo -e "${DIM}─────────────────────────────────────────────────────────────────────${RESET}"
}

# Root Check 

check_privileges() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script requires root privileges. Please run with sudo."
        exit 1
    fi
}

# Get current hostname
current_hostname=$(hostname)

main () {
    check_privileges
    print_banner
    print_separator
    
        while true; do
        echo "1. Set Hostname"
        echo "2. Exit"
        print_separator
        read -p "Enter your choice: " choice
        case $choice in
            1) set_hostname; break;;
            2) break;;
            *) echo "Invalid choice. Please try again.";;   
        esac  
    done  
        
    
}