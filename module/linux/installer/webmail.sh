#!/bin/bash

# ==============================================================================
# WEBMAIL SERVER AUTOMATION TOOL
# Goal: Automates the setup of a Mail Server (Postfix, Dovecot, Roundcube)
# Features: Multi-distro support, Interactive Setup, Safety Backups, 
#           Dry-Run Mode, Rollback, and System Verification.
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

pause_and_clear() {
    echo ""
    read -p "  Press [Enter] to return to the main menu..." _
    clear
}

print_banner() {
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║                  WEBMAIL SERVER AUTOMATION TOOL                   ║${RESET}"
    echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_separator() {
    echo -e "${DIM}─────────────────────────────────────────────────────────────────────${RESET}"
}

# ----------------------------- Backup & Rollback -------------------------------
BACKUP_DIR="/var/backups/webmail-setup"

backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local timestamp=$(date +%Y%m%d%H%M%S)
        mkdir -p "$BACKUP_DIR"
        local backup_path="${BACKUP_DIR}/$(basename "$file").bak.${timestamp}"
        if [ "$DRY_RUN" = true ]; then
            dry_run_print "Would backup $file to $backup_path"
        else
            cp "$file" "$backup_path"
            log_info "Backed up $(basename "$file")"
        fi
    fi
}

do_rollback() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Rollback] Restoring Original Configurations${RESET}"
    print_separator

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        log_warn "No backups found in $BACKUP_DIR."
        return
    fi

    echo -e "  Available Backups:"
    ls -1 "$BACKUP_DIR" | grep "\.bak\." | nl
    echo ""
    read -p "  Enter the number of the backup to restore (or 'c' to cancel): " rb_choice
    if is_cancel "$rb_choice"; then return; fi

    local backups=()
    mapfile -t backups < <(ls "$BACKUP_DIR" 2>/dev/null | grep "\.bak\.")
    
    if [[ ! "$rb_choice" =~ ^[0-9]+$ ]] || [ "$rb_choice" -lt 1 ] || [ "$rb_choice" -gt "${#backups[@]}" ]; then
        log_error "Invalid selection."
        return
    fi

    local selected_file="${backups[$((rb_choice-1))]}"
    log_info "Selected backup: $selected_file"
    
    # Map backup filenames back to original paths
    local target=""
    if [[ "$selected_file" == *"postfix"* ]]; then target="/etc/postfix/main.cf"
    elif [[ "$selected_file" == *"10-mail.conf"* ]]; then target="/etc/dovecot/conf.d/10-mail.conf"
    elif [[ "$selected_file" == *"10-auth.conf"* ]]; then target="/etc/dovecot/conf.d/10-auth.conf"
    fi

    if [ -n "$target" ]; then
        if [ "$DRY_RUN" = true ]; then
            dry_run_print "Would restore $selected_file to $target"
        else
            cp "$BACKUP_DIR/$selected_file" "$target"
            log_success "Restored $target"
        fi
    else
        log_error "Could not determine target path for $selected_file"
    fi
}

# ----------------------------- Environment Detection ---------------------------
detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        PKG_MGR="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
    else
        log_error "Only Debian/Ubuntu (apt) and Fedora/RHEL (dnf) are currently supported."
        exit 1
    fi
    log_success "Detected package manager: ${GREEN}$PKG_MGR${RESET}"
}

# ----------------------------- Setup Wizard ------------------------------------

setup_webmail() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Wizard] Mail Server Installation & Configuration${RESET}"
    print_separator

    # Step 1: Hostname & Domain
    echo -e "${CYAN}${BOLD}  [Step 1/5] Hostname Configuration${RESET}"
    read -p "  Enter Mail Hostname (e.g. mail.example.com) [mail.lks.id]: " mail_hostname
    [ -z "$mail_hostname" ] && mail_hostname="mail.lks.id"
    if is_cancel "$mail_hostname"; then return; fi

    read -p "  Enter Mail Domain (e.g. example.com) [lks.id]: " mail_domain
    [ -z "$mail_domain" ] && mail_domain="lks.id"
    if is_cancel "$mail_domain"; then return; fi

    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would set hostname to $mail_hostname"
    else
        hostnamectl set-hostname "$mail_hostname"
        log_success "Hostname set to $mail_hostname"
    fi

    # Step 2: Install Packages
    echo -e "\n${CYAN}${BOLD}  [Step 2/5] Installing Mail Packages${RESET}"
    if [ "$PKG_MGR" == "apt" ]; then
        local pkgs="postfix dovecot-core dovecot-imapd dovecot-pop3d mailutils roundcube roundcube-core roundcube-mysql"
    else
        local pkgs="postfix dovecot mailutils roundcube"
    fi

    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would install packages: $pkgs"
    else
        log_info "Updating repositories..."
        $PKG_MGR update -y >/dev/null 2>&1
        log_info "Installing packages (this may take a while)..."
        $PKG_MGR install -y $pkgs
        if [ $? -eq 0 ]; then log_success "Packages installed successfully."; else log_error "Installation failed."; return 1; fi
    fi

    # Step 3: Postfix Setup
    echo -e "\n${CYAN}${BOLD}  [Step 3/5] Configuring Postfix${RESET}"
    backup_file "/etc/postfix/main.cf"
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would configure Postfix with hostname: $mail_hostname and domain: $mail_domain"
    else
        postconf -e "myhostname = $mail_hostname"
        postconf -e "mydomain = $mail_domain"
        postconf -e "myorigin = \$mydomain"
        postconf -e "inet_interfaces = all"
        postconf -e "inet_protocols = ipv4"
        postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
        postconf -e "home_mailbox = Maildir/"
        systemctl enable postfix
        systemctl restart postfix
        log_success "Postfix configured and restarted."
    fi

    # Step 4: Dovecot Setup
    echo -e "\n${CYAN}${BOLD}  [Step 4/5] Configuring Dovecot${RESET}"
    backup_file "/etc/dovecot/conf.d/10-mail.conf"
    backup_file "/etc/dovecot/conf.d/10-auth.conf"
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would configure Dovecot Maildir and Auth mechanisms"
    else
        sed -i 's|^#\?mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf
        sed -i 's/^#\?disable_plaintext_auth =.*/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
        sed -i 's/^#\?auth_mechanisms =.*/auth_mechanisms = plain login/' /etc/dovecot/conf.d/10-auth.conf
        systemctl enable dovecot
        systemctl restart dovecot
        log_success "Dovecot configured and restarted."
    fi

    # Step 5: Roundcube & Apache
    echo -e "\n${CYAN}${BOLD}  [Step 5/5] Enabling Webmail Interface${RESET}"
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would run a2enconf roundcube and restart apache2"
    else
        if command -v a2enconf >/dev/null 2>&1; then
            a2enconf roundcube >/dev/null 2>&1
            systemctl restart apache2
            log_success "Roundcube Apache config enabled."
        else
            log_warn "a2enconf not found. Manual Apache configuration for Roundcube may be required."
        fi
    fi

    echo -e "\n${GREEN}${BOLD}  === Webmail Server Setup Complete! ===${RESET}"
}

# ----------------------------- Diagnostics -----------------------------------

show_status() {
    clear
    print_banner
    echo -e "${BLUE}${BOLD}  [Status] Mail Server Service Health${RESET}"
    print_separator
    
    local services=("postfix" "dovecot" "apache2")
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc"; then
            echo -e "  ${CYAN}$svc${RESET} : ${GREEN}RUNNING${RESET}"
        else
            echo -e "  ${CYAN}$svc${RESET} : ${RED}STOPPED${RESET}"
        fi
    done
    print_separator
}

# ----------------------------- Main Menu -------------------------------------

main() {
    check_root
    detect_package_manager

    while true; do
        clear
        print_banner
        echo -e "  ${BOLD}Webmail Server Management Menu${RESET}"
        print_separator
        echo -e "  ${CYAN}1${RESET}) Full Automated Setup (Wizard)"
        echo -e "  ${CYAN}2${RESET}) Check Service Status"
        echo -e "  ${CYAN}3${RESET}) Rollback Configuration"
        echo -e "  ${RED}0${RESET}) Exit ${DIM}(or type 'c' / 'q')${RESET}"
        print_separator
        read -p "  Enter your choice [0-3]: " choice

        case $choice in
            1)
                setup_webmail
                pause_and_clear
                ;;
            2)
                show_status
                pause_and_clear
                ;;
            3)
                do_rollback
                pause_and_clear
                ;;
            0|q|Q|c|C|exit|quit)
                log_info "Exiting Webmail Setup Tool. Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid choice. Please enter a number between 0-3."
                sleep 1.2
                clear
                ;;
        esac
    done
}

main
