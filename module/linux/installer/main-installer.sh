#!/bin/bash

# ==============================================================================
# MAIN INSTALLER SCRIPT
# Central interactive menu for desktop and environment installers:
#   * Browser Installer (Firefox, Chrome, Brave, Chromium, Vivaldi, Zen, Opera)
#   * Font Installer (MesloLGS Nerd Font for terminal & Powerlevel10k)
#   * ZSH Installer (Oh My Zsh, Powerlevel10k, plugins, rollback support)
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

# ----------------------------- UI & Logging Helpers ---------------------------

print_banner() {
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║                   INSTALLER SCRIPT MAIN MENU                      ║${RESET}"
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
    [[ "$val" =~ ^(c|cancel|C|CANCEL|q|quit|Q|QUIT|exit|EXIT|0)$ ]]
}

# ----------------------------- Path Resolution & Execution --------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_script() {
    local script_name="$1"
    local label="$2"
    shift 2
    local full_path="${SCRIPT_DIR}/${script_name}"

    if [[ ! -f "$full_path" ]]; then
        log_error "Script not found: ${script_name}"
        log_warn  "Expected at: ${full_path}"
        return 1
    fi

    chmod +x "$full_path"
    log_info "Launching ${label}..."
    echo ""

    bash "$full_path" "$@"
    local rc=$?

    echo ""
    if [[ $rc -eq 0 ]]; then
        log_success "${label} finished successfully (exit 0)."
    else
        log_warn "${label} exited with code ${rc}."
    fi
    return $rc
}

# ----------------------------- Installer Handlers -----------------------------

Browser-Installer() {
    log_info "Preparing Browser Installer..."
    run_script "browser.sh" "Browser Installer" "$@"
}

Font-Installer() {
    log_info "Preparing Font Installer..."
    run_script "font.sh" "Font Installer" "$@"
}

ZSH-Installer() {
    # If arguments are passed directly (e.g. from CLI), bypass sub-menu
    if [[ $# -gt 0 ]]; then
        run_script "zsh-install.sh" "ZSH Installer" "$@"
        return $?
    fi

    while true; do
        echo ""
        print_separator
        echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}${BOLD}║                     ZSH INSTALLATION OPTIONS                      ║${RESET}"
        echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
        print_separator
        echo -e "  ${GREEN}${BOLD}[1]${RESET} Install ZSH (Oh My Zsh + Powerlevel10k + Plugins)"
        echo -e "  ${YELLOW}${BOLD}[2]${RESET} Rollback ZSH Installation (--rollback)"
        echo -e "  ${DIM}[b]${RESET} Back to Main Menu"
        echo ""
        print_separator
        read -p "  Enter your choice [1-2] or 'b' to return: " zsh_choice

        if is_cancel "$zsh_choice" || [[ "$zsh_choice" =~ ^(b|B|back|BACK)$ ]]; then
            return 0
        fi

        case "$zsh_choice" in
            1)
                run_script "zsh-install.sh" "ZSH Installer"
                break
                ;;
            2)
                run_script "zsh-install.sh" "ZSH Rollback" "--rollback"
                break
                ;;
            *)
                log_warn "Invalid choice. Please try again."
                ;;
        esac
    done
}

# ----------------------------- Main Menu --------------------------------------

main_menu() {
    print_banner
    print_separator
    log_info "Available Scripts:"
    print_separator
    echo -e "  ${GREEN}${BOLD}[1]${RESET} Browser Installer"
    echo -e "  ${GREEN}${BOLD}[2]${RESET} Font Installer"
    echo -e "  ${GREEN}${BOLD}[3]${RESET} ZSH Installer"
    echo ""
    echo -e "  ${DIM}[c]${RESET} Exit"

    echo ""
    print_separator
    read -p "  Enter your choice [1-3] or 'c' to exit: " choice

    if is_cancel "$choice"; then
        echo ""
        log_info "Exiting Installer Menu. Goodbye!"
        exit 0
    fi

    case "$choice" in
        1)
            Browser-Installer
            ;;
        2)
            Font-Installer
            ;;
        3)
            ZSH-Installer
            ;;
        *)
            log_warn "Invalid choice. Please try again."
            ;;
    esac
}

# ----------------------------- Main Execution ---------------------------------

main() {
    # Support direct command-line arguments (e.g. ./main-installer.sh browser)
    if [[ $# -gt 0 ]]; then
        case "$1" in
            1|browser|Browser|--browser)
                Browser-Installer "${@:2}"
                exit $?
                ;;
            2|font|Font|--font)
                Font-Installer "${@:2}"
                exit $?
                ;;
            3|zsh|ZSH|--zsh)
                ZSH-Installer "${@:2}"
                exit $?
                ;;
            -h|--help|help)
                echo "Usage: $0 [browser | font | zsh [args] | --help]"
                echo "Run without arguments to launch the interactive menu."
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Usage: $0 [browser | font | zsh | --help]"
                exit 1
                ;;
        esac
    fi

    # Interactive Loop
    while true; do
        clear 2>/dev/null || true
        main_menu
        echo ""
        read -p "  Press [Enter] to return to the menu..." _
    done
}

main "$@"
