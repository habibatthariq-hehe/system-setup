#!/bin/bash

# ==============================================================================
# OPENSSL ROOT CERTIFICATE AUTOMATION SCRIPT
# Features: Root CA generation, Intermediate CA, Server/Client certs,
#           Certificate inspection, Verification chain, CRL revocation,
#           PKCS#12 bundling, Trust store installation, Rollback.
#
# Usage:
#   sudo bash root-cert.sh              normal interactive run
#   sudo bash root-cert.sh --dry-run    run in simulated mode
#   sudo bash root-cert.sh --rollback   remove generated files
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

# ----------------------------- Defaults ---------------------------------------
DEFAULT_CA_DIR="/etc/ssl/custom-ca"
CA_DIR=""
ROOT_KEY=""
ROOT_CERT=""
ROOT_SERIAL=""
ROOT_INDEX=""
ROOT_CRL=""
ROOT_CRLNUM=""
INTERMEDIATE_DIR=""
INTERMEDIATE_KEY=""
INTERMEDIATE_CERT=""
INTERMEDIATE_CSR=""
INTERMEDIATE_SERIAL=""
INTERMEDIATE_INDEX=""
INTERMEDIATE_CRL=""
INTERMEDIATE_CRLNUM=""

MANIFEST=""
PKG_MANAGER=""
UPDATE_CMD=()
INSTALL_CMD=()

# ===========================================#
#       Banner and Helper Functions          #
# ===========================================#

print_banner() {
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║               OPENSSL ROOT CERTIFICATE SCRIPT                    ║${RESET}"
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
    local val="$1"
    [[ "$val" =~ ^(c|cancel|C|CANCEL|q|quit|Q|QUIT|exit|EXIT)$ ]]
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root. Use: sudo bash $0"
        exit 1
    fi
}

# ----------------------------- Package Manager --------------------------------

check_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
        UPDATE_CMD=(apt-get update -y)
        INSTALL_CMD=(apt-get install -y openssl)
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        UPDATE_CMD=(dnf check-update)
        INSTALL_CMD=(dnf install -y openssl)
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        UPDATE_CMD=(yum check-update)
        INSTALL_CMD=(yum install -y openssl)
    else
        log_error "No supported package manager (apt, dnf, yum) found."
        return 1
    fi
}

install_openssl() {
    log_info "Checking if OpenSSL is already installed..."
    if command -v openssl &> /dev/null; then
        local ver
        ver=$(openssl version 2>&1)
        log_success "OpenSSL is already installed: $ver"
        return 0
    fi

    log_info "Detecting package manager..."
    if ! check_package_manager; then
        return 1
    fi

    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would run: ${UPDATE_CMD[*]}"
        dry_run_print "Would run: ${INSTALL_CMD[*]}"
        return 0
    fi

    log_info "Installing OpenSSL using $PKG_MANAGER..."
    "${UPDATE_CMD[@]}" 2>/dev/null
    "${INSTALL_CMD[@]}"

    if command -v openssl &> /dev/null; then
        log_success "OpenSSL installed successfully! ($(openssl version))"
    else
        log_error "Failed to install OpenSSL."
        return 1
    fi
}

# ----------------------------- Manifest / Rollback ----------------------------

manifest_init() {
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would initialize manifest at $MANIFEST"
    else
        touch "$MANIFEST"
    fi
}

record() {
    local action="$1"; shift
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would record: $action | $*"
    else
        printf '%s\n' "$action|$*" >> "$MANIFEST"
    fi
}

do_rollback() {
    clear
    print_banner
    echo -e "${BOLD}  Rollback Mode${RESET}"
    print_separator

    if [ ! -f "$MANIFEST" ]; then
        log_warn "No manifest found at $MANIFEST. Nothing to rollback."
        return
    fi

    local count=0
    while IFS='|' read -r action path; do
        case "$action" in
            FILE)
                if [ -f "$path" ]; then
                    if [ "$DRY_RUN" = true ]; then
                        dry_run_print "Would remove file: $path"
                    else
                        rm -f "$path"
                        log_info "Removed: $path"
                    fi
                    ((count++))
                fi
                ;;
            DIR)
                if [ -d "$path" ]; then
                    if [ "$DRY_RUN" = true ]; then
                        dry_run_print "Would remove directory: $path"
                    else
                        rm -rf "$path"
                        log_info "Removed directory: $path"
                    fi
                    ((count++))
                fi
                ;;
            TRUST)
                if [ -f "$path" ]; then
                    if [ "$DRY_RUN" = true ]; then
                        dry_run_print "Would remove trust file: $path"
                        dry_run_print "Would run: update-ca-certificates / update-ca-trust"
                    else
                        rm -f "$path"
                        if command -v update-ca-certificates &> /dev/null; then
                            update-ca-certificates --fresh &> /dev/null
                        elif command -v update-ca-trust &> /dev/null; then
                            update-ca-trust extract &> /dev/null
                        fi
                        log_info "Removed trust entry: $path"
                    fi
                    ((count++))
                fi
                ;;
        esac
    done < "$MANIFEST"

    if [ "$count" -eq 0 ]; then
        log_warn "No files matched for rollback (already cleaned?)."
    else
        log_success "Rolled back $count item(s)."
        if [ "$DRY_RUN" != true ]; then
            : > "$MANIFEST"
        fi
    fi
}

# ----------------------------- Directory Setup --------------------------------

init_ca_paths() {
    ROOT_KEY="$CA_DIR/private/ca.key"
    ROOT_CERT="$CA_DIR/certs/ca.crt"
    ROOT_SERIAL="$CA_DIR/serial"
    ROOT_INDEX="$CA_DIR/index.txt"
    ROOT_CRL="$CA_DIR/crl/ca.crl.pem"
    ROOT_CRLNUM="$CA_DIR/crlnumber"
    INTERMEDIATE_DIR="$CA_DIR/intermediate"
    INTERMEDIATE_KEY="$INTERMEDIATE_DIR/private/intermediate.key"
    INTERMEDIATE_CERT="$INTERMEDIATE_DIR/certs/intermediate.crt"
    INTERMEDIATE_CSR="$INTERMEDIATE_DIR/csr/intermediate.csr"
    INTERMEDIATE_SERIAL="$INTERMEDIATE_DIR/serial"
    INTERMEDIATE_INDEX="$INTERMEDIATE_DIR/index.txt"
    INTERMEDIATE_CRL="$INTERMEDIATE_DIR/crl/intermediate.crl.pem"
    INTERMEDIATE_CRLNUM="$INTERMEDIATE_DIR/crlnumber"
    MANIFEST="$CA_DIR/.cert-manifest"
}

prompt_ca_directory() {
    echo ""
    echo -e "  ${BOLD}CA Directory Configuration${RESET}"
    print_separator
    log_info "Default CA directory: ${CYAN}$DEFAULT_CA_DIR${RESET}"
    echo ""
    read -p "  Enter CA base directory (Enter = default, 'c' = cancel): " input_dir

    if is_cancel "$input_dir"; then
        return 1
    fi

    CA_DIR="${input_dir:-$DEFAULT_CA_DIR}"
    init_ca_paths

    log_info "Using CA directory: ${CYAN}$CA_DIR${RESET}"
    return 0
}

setup_ca_directories() {
    local dirs=(
        "$CA_DIR"
        "$CA_DIR/certs"
        "$CA_DIR/crl"
        "$CA_DIR/newcerts"
        "$CA_DIR/private"
        "$CA_DIR/csr"
        "$INTERMEDIATE_DIR"
        "$INTERMEDIATE_DIR/certs"
        "$INTERMEDIATE_DIR/crl"
        "$INTERMEDIATE_DIR/newcerts"
        "$INTERMEDIATE_DIR/private"
        "$INTERMEDIATE_DIR/csr"
    )

    for d in "${dirs[@]}"; do
        if [ "$DRY_RUN" = true ]; then
            dry_run_print "Would create directory: $d"
        else
            mkdir -p "$d"
        fi
    done

    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would set permissions 700 on private directories"
        dry_run_print "Would initialize serial/index files"
    else
        chmod 700 "$CA_DIR/private" "$INTERMEDIATE_DIR/private"

        [ ! -f "$ROOT_INDEX" ]         && touch "$ROOT_INDEX"
        [ ! -f "$ROOT_SERIAL" ]        && echo "1000" > "$ROOT_SERIAL"
        [ ! -f "$ROOT_CRLNUM" ]        && echo "1000" > "$ROOT_CRLNUM"
        [ ! -f "$INTERMEDIATE_INDEX" ]  && touch "$INTERMEDIATE_INDEX"
        [ ! -f "$INTERMEDIATE_SERIAL" ] && echo "1000" > "$INTERMEDIATE_SERIAL"
        [ ! -f "$INTERMEDIATE_CRLNUM" ] && echo "1000" > "$INTERMEDIATE_CRLNUM"
    fi

    record "DIR" "$CA_DIR"
    manifest_init
    log_success "CA directory structure created."
}

# ----------------------------- OpenSSL Config Generator -----------------------

generate_openssl_conf() {
    local conf_type="$1"   # "root" or "intermediate"
    local conf_dir="$2"
    local conf_file="$conf_dir/openssl.cnf"

    local ca_dir_ref="$conf_dir"
    local policy="policy_strict"
    local cert_file="$conf_dir/certs/ca.crt"
    local key_file="$conf_dir/private/ca.key"
    local default_days=7300

    if [ "$conf_type" = "intermediate" ]; then
        policy="policy_loose"
        cert_file="$conf_dir/certs/intermediate.crt"
        key_file="$conf_dir/private/intermediate.key"
        default_days=3650
    fi

    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would generate openssl.cnf for '$conf_type' at $conf_file"
        return 0
    fi

    cat > "$conf_file" << CNFEOF
# OpenSSL configuration — auto-generated by root-cert.sh
# Type: $conf_type

[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = $ca_dir_ref
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
RANDFILE          = \$dir/private/.rand
private_key       = $key_file
certificate       = $cert_file
crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/ca.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = $default_days
preserve          = no
policy            = $policy
unique_subject    = no

[ policy_strict ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca
prompt              = no

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

[ v3_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical, CA:true
keyUsage               = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical, CA:true, pathlen:0
keyUsage               = critical, digitalSignature, cRLSign, keyCertSign

[ server_cert ]
basicConstraints       = CA:FALSE
nsCertType             = server
nsComment              = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth

[ client_cert ]
basicConstraints       = CA:FALSE
nsCertType             = client, email
nsComment              = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
keyUsage               = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage       = clientAuth, emailProtection

[ crl_ext ]
authorityKeyIdentifier = keyid:always

[ ocsp ]
basicConstraints       = CA:FALSE
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, OCSPSigning
CNFEOF

    record "FILE" "$conf_file"
    log_success "Generated openssl.cnf for ${conf_type} at ${CYAN}$conf_file${RESET}"
}

# ----------------------------- Subject Prompt ---------------------------------

prompt_subject() {
    local label="$1"
    local default_cn="$2"
    echo ""
    echo -e "  ${BOLD}Certificate Subject — $label${RESET}"
    print_separator

    read -p "  Country (2-letter, e.g. US) [US]: " C
    is_cancel "$C" && return 1
    C="${C:-US}"
    if [[ ! "$C" =~ ^[A-Za-z]{2}$ ]]; then
        log_warn "Country code should be 2 letters. Using as-is: $C"
    fi

    read -p "  State/Province [California]: " ST
    is_cancel "$ST" && return 1
    ST="${ST:-California}"

    read -p "  Locality/City [San Francisco]: " L
    is_cancel "$L" && return 1
    L="${L:-San Francisco}"

    read -p "  Organization [My Organization]: " O
    is_cancel "$O" && return 1
    O="${O:-My Organization}"

    read -p "  Organizational Unit (optional) []: " OU
    is_cancel "$OU" && return 1

    read -p "  Common Name [$default_cn]: " CN
    is_cancel "$CN" && return 1
    CN="${CN:-$default_cn}"

    read -p "  Email (optional) []: " EMAIL
    is_cancel "$EMAIL" && return 1

    SUBJECT="/C=$C/ST=$ST/L=$L/O=$O"
    [ -n "$OU" ] && SUBJECT="$SUBJECT/OU=$OU"
    SUBJECT="$SUBJECT/CN=$CN"
    [ -n "$EMAIL" ] && SUBJECT="$SUBJECT/emailAddress=$EMAIL"

    log_info "Subject: ${CYAN}$SUBJECT${RESET}"
    return 0
}

# ----------------------------- Root CA ----------------------------------------

generate_root_ca() {
    clear
    print_banner
    echo -e "${BOLD}  [1] Generate Root CA${RESET}"
    print_separator

    if [ -z "$CA_DIR" ]; then
        prompt_ca_directory || return
    fi

    setup_ca_directories
    generate_openssl_conf "root" "$CA_DIR"

    echo ""
    read -p "  RSA key size (2048/4096) [4096]: " keysize
    is_cancel "$keysize" && return
    keysize="${keysize:-4096}"
    if [[ "$keysize" != "2048" && "$keysize" != "4096" ]]; then
        log_warn "Invalid key size '$keysize'. Defaulting to 4096."
        keysize=4096
    fi

    read -p "  Root CA validity in days [7300 (~20 years)]: " validity
    is_cancel "$validity" && return
    validity="${validity:-7300}"
    if ! [[ "$validity" =~ ^[0-9]+$ ]] || [ "$validity" -lt 1 ]; then
        log_warn "Invalid validity '$validity'. Defaulting to 7300."
        validity=7300
    fi

    SUBJECT=""
    prompt_subject "Root CA" "Root CA" || return

    # Generate root key
    echo ""
    log_info "Generating Root CA private key ($keysize bits)..."
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would run: openssl genrsa -aes256 -out $ROOT_KEY $keysize"
    else
        openssl genrsa -aes256 -out "$ROOT_KEY" "$keysize"
        if [ $? -ne 0 ]; then
            log_error "Failed to generate Root CA key."
            return
        fi
        chmod 400 "$ROOT_KEY"
        record "FILE" "$ROOT_KEY"
        log_success "Root CA key generated: ${CYAN}$ROOT_KEY${RESET}"
    fi

    # Generate root certificate
    log_info "Generating self-signed Root CA certificate (valid $validity days)..."
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would run: openssl req -config $CA_DIR/openssl.cnf -key $ROOT_KEY -new -x509 -days $validity -sha256 -extensions v3_ca -subj '$SUBJECT' -out $ROOT_CERT"
    else
        openssl req \
            -config "$CA_DIR/openssl.cnf" \
            -key "$ROOT_KEY" \
            -new -x509 \
            -days "$validity" \
            -sha256 \
            -extensions v3_ca \
            -subj "$SUBJECT" \
            -out "$ROOT_CERT"
        if [ $? -ne 0 ]; then
            log_error "Failed to generate Root CA certificate."
            return
        fi
        chmod 444 "$ROOT_CERT"
        record "FILE" "$ROOT_CERT"
        log_success "Root CA certificate generated: ${CYAN}$ROOT_CERT${RESET}"
    fi

    echo ""
    print_separator
    log_success "Root CA setup complete!"
    log_info "Key:  ${CYAN}$ROOT_KEY${RESET}"
    log_info "Cert: ${CYAN}$ROOT_CERT${RESET}"
    pause_menu
}

# ----------------------------- Intermediate CA --------------------------------

generate_intermediate_ca() {
    clear
    print_banner
    echo -e "${BOLD}  [2] Generate Intermediate CA${RESET}"
    print_separator

    if [ -z "$CA_DIR" ]; then
        prompt_ca_directory || return
    fi

    if [ ! -f "$ROOT_KEY" ] || [ ! -f "$ROOT_CERT" ]; then
        log_error "Root CA not found. Generate a Root CA first (option 1)."
        pause_menu
        return
    fi

    generate_openssl_conf "intermediate" "$INTERMEDIATE_DIR"

    echo ""
    read -p "  Intermediate key size (2048/4096) [4096]: " keysize
    is_cancel "$keysize" && return
    keysize="${keysize:-4096}"

    read -p "  Intermediate CA validity in days [3650 (~10 years)]: " validity
    is_cancel "$validity" && return
    validity="${validity:-3650}"
    if ! [[ "$validity" =~ ^[0-9]+$ ]] || [ "$validity" -lt 1 ]; then
        log_warn "Invalid validity. Defaulting to 3650."
        validity=3650
    fi

    SUBJECT=""
    prompt_subject "Intermediate CA" "Intermediate CA" || return

    # Generate intermediate key
    echo ""
    log_info "Generating Intermediate CA private key ($keysize bits)..."
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would run: openssl genrsa -aes256 -out $INTERMEDIATE_KEY $keysize"
    else
        openssl genrsa -aes256 -out "$INTERMEDIATE_KEY" "$keysize"
        if [ $? -ne 0 ]; then
            log_error "Failed to generate Intermediate CA key."
            return
        fi
        chmod 400 "$INTERMEDIATE_KEY"
        record "FILE" "$INTERMEDIATE_KEY"
        log_success "Intermediate key generated."
    fi

    # Generate CSR
    log_info "Generating Intermediate CA CSR..."
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would generate CSR at $INTERMEDIATE_CSR"
    else
        openssl req \
            -config "$INTERMEDIATE_DIR/openssl.cnf" \
            -new -sha256 \
            -key "$INTERMEDIATE_KEY" \
            -subj "$SUBJECT" \
            -out "$INTERMEDIATE_CSR"
        if [ $? -ne 0 ]; then
            log_error "Failed to generate Intermediate CSR."
            return
        fi
        record "FILE" "$INTERMEDIATE_CSR"
        log_success "Intermediate CSR generated."
    fi

    # Sign with Root CA
    log_info "Signing Intermediate CA certificate with Root CA..."
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would sign intermediate cert using root CA config"
    else
        openssl ca \
            -config "$CA_DIR/openssl.cnf" \
            -extensions v3_intermediate_ca \
            -days "$validity" \
            -notext -md sha256 \
            -in "$INTERMEDIATE_CSR" \
            -out "$INTERMEDIATE_CERT" \
            -batch
        if [ $? -ne 0 ]; then
            log_error "Failed to sign Intermediate certificate."
            return
        fi
        chmod 444 "$INTERMEDIATE_CERT"
        record "FILE" "$INTERMEDIATE_CERT"
        log_success "Intermediate CA certificate signed."
    fi

    # Create certificate chain
    local chain_file="$INTERMEDIATE_DIR/certs/ca-chain.crt"
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would create chain file at $chain_file"
    else
        cat "$INTERMEDIATE_CERT" "$ROOT_CERT" > "$chain_file"
        chmod 444 "$chain_file"
        record "FILE" "$chain_file"
        log_success "Certificate chain: ${CYAN}$chain_file${RESET}"
    fi

    echo ""
    print_separator
    log_success "Intermediate CA setup complete!"
    log_info "Key:   ${CYAN}$INTERMEDIATE_KEY${RESET}"
    log_info "Cert:  ${CYAN}$INTERMEDIATE_CERT${RESET}"
    log_info "Chain: ${CYAN}$chain_file${RESET}"
    pause_menu
}

# ----------------------------- Server / Client Certificates -------------------

generate_end_entity_cert() {
    local cert_type="$1"  # "server" or "client"
    local ext_name="${cert_type}_cert"
    local display_name
    display_name="$(echo "$cert_type" | sed 's/.*/\u&/') Certificate"

    clear
    print_banner
    echo -e "${BOLD}  Generate $display_name${RESET}"
    print_separator

    if [ -z "$CA_DIR" ]; then
        prompt_ca_directory || return
    fi

    # Determine signing CA
    local signing_key signing_cert signing_conf signing_label
    if [ -f "$INTERMEDIATE_CERT" ] && [ -f "$INTERMEDIATE_KEY" ]; then
        signing_key="$INTERMEDIATE_KEY"
        signing_cert="$INTERMEDIATE_CERT"
        signing_conf="$INTERMEDIATE_DIR/openssl.cnf"
        signing_label="Intermediate CA"
    elif [ -f "$ROOT_CERT" ] && [ -f "$ROOT_KEY" ]; then
        signing_key="$ROOT_KEY"
        signing_cert="$ROOT_CERT"
        signing_conf="$CA_DIR/openssl.cnf"
        signing_label="Root CA"
        log_warn "No Intermediate CA found. Signing directly with Root CA."
    else
        log_error "No CA found. Generate a Root CA first."
        pause_menu
        return
    fi
    log_info "Signing with: ${CYAN}$signing_label${RESET}"

    echo ""
    read -p "  Certificate name (e.g. webserver, api-client) [my-$cert_type]: " cert_name
    is_cancel "$cert_name" && return
    cert_name="${cert_name:-my-$cert_type}"
    # Sanitize
    cert_name=$(echo "$cert_name" | tr -cd 'a-zA-Z0-9._-')

    read -p "  Key size (2048/4096) [2048]: " keysize
    is_cancel "$keysize" && return
    keysize="${keysize:-2048}"

    read -p "  Validity in days [365]: " validity
    is_cancel "$validity" && return
    validity="${validity:-365}"
    if ! [[ "$validity" =~ ^[0-9]+$ ]] || [ "$validity" -lt 1 ]; then
        log_warn "Invalid validity. Defaulting to 365."
        validity=365
    fi

    SUBJECT=""
    prompt_subject "$display_name" "$cert_name" || return

    # SAN (Subject Alternative Names) for server certs
    local san_ext=""
    if [ "$cert_type" = "server" ]; then
        echo ""
        echo -e "  ${BOLD}Subject Alternative Names (SAN)${RESET}"
        log_info "Enter DNS names and/or IPs, comma-separated."
        log_info "Example: DNS:example.com,DNS:www.example.com,IP:192.168.1.10"
        read -p "  SAN (leave empty to skip): " san_input
        is_cancel "$san_input" && return
        if [ -n "$san_input" ]; then
            san_ext="$san_input"
        fi
    fi

    local out_dir="$CA_DIR/certs"
    local out_key="$out_dir/${cert_name}.key"
    local out_csr="$CA_DIR/csr/${cert_name}.csr"
    local out_cert="$out_dir/${cert_name}.crt"

    # Generate private key (no passphrase for end-entity by default)
    echo ""
    log_info "Generating $cert_type private key ($keysize bits)..."
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would run: openssl genrsa -out $out_key $keysize"
    else
        openssl genrsa -out "$out_key" "$keysize" 2>/dev/null
        if [ $? -ne 0 ]; then
            log_error "Failed to generate private key."
            return
        fi
        chmod 400 "$out_key"
        record "FILE" "$out_key"
        log_success "Private key: ${CYAN}$out_key${RESET}"
    fi

    # Build CSR config with SAN if provided
    local csr_conf=""
    if [ -n "$san_ext" ]; then
        csr_conf="$CA_DIR/csr/${cert_name}-csr.cnf"
        if [ "$DRY_RUN" != true ]; then
            cat > "$csr_conf" << CSRCNF
[req]
default_bits       = $keysize
distinguished_name = req_dn
req_extensions     = v3_req
prompt             = no

[req_dn]
CN = $CN

[v3_req]
subjectAltName = $san_ext
CSRCNF
            record "FILE" "$csr_conf"
        fi
    fi

    # Generate CSR
    log_info "Generating CSR..."
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would generate CSR at $out_csr"
    else
        local csr_cmd=(openssl req -new -sha256 -key "$out_key" -subj "$SUBJECT" -out "$out_csr")
        if [ -n "$csr_conf" ]; then
            csr_cmd+=(-config "$csr_conf")
        fi
        "${csr_cmd[@]}"
        if [ $? -ne 0 ]; then
            log_error "Failed to generate CSR."
            return
        fi
        record "FILE" "$out_csr"
        log_success "CSR generated."
    fi

    # Sign with CA
    log_info "Signing certificate with $signing_label..."
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would sign $cert_type cert: $out_cert"
    else
        local sign_cmd=(openssl ca -config "$signing_conf" -extensions "$ext_name" -days "$validity" -notext -md sha256 -in "$out_csr" -out "$out_cert" -batch)
        # If SAN, add extensions inline
        if [ -n "$san_ext" ] && [ -n "$csr_conf" ]; then
            sign_cmd+=(-extfile "$csr_conf" -extensions v3_req)
        fi
        "${sign_cmd[@]}"
        if [ $? -ne 0 ]; then
            log_error "Failed to sign certificate."
            return
        fi
        chmod 444 "$out_cert"
        record "FILE" "$out_cert"
        log_success "Certificate signed: ${CYAN}$out_cert${RESET}"
    fi

    echo ""
    print_separator
    log_success "$display_name created successfully!"
    log_info "Key:  ${CYAN}$out_key${RESET}"
    log_info "CSR:  ${CYAN}$out_csr${RESET}"
    log_info "Cert: ${CYAN}$out_cert${RESET}"
    pause_menu
}

# ----------------------------- Inspect Certificate ----------------------------

inspect_certificate() {
    clear
    print_banner
    echo -e "${BOLD}  [4] Inspect Certificate${RESET}"
    print_separator
    echo ""

    read -p "  Path to certificate file (.crt/.pem): " cert_path
    is_cancel "$cert_path" && return

    if [ ! -f "$cert_path" ]; then
        log_error "File not found: $cert_path"
        pause_menu
        return
    fi

    echo ""
    echo -e "  ${BOLD}Certificate Details${RESET}"
    print_separator

    openssl x509 -in "$cert_path" -text -noout 2>&1 | while IFS= read -r line; do
        echo "  $line"
    done

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log_error "Failed to parse certificate. Is it a valid X.509 file?"
    fi

    pause_menu
}

# ----------------------------- Verify Chain -----------------------------------

verify_certificate_chain() {
    clear
    print_banner
    echo -e "${BOLD}  [5] Verify Certificate Chain${RESET}"
    print_separator
    echo ""

    read -p "  Path to CA certificate (or chain file): " ca_path
    is_cancel "$ca_path" && return

    read -p "  Path to certificate to verify: " cert_path
    is_cancel "$cert_path" && return

    if [ ! -f "$ca_path" ]; then
        log_error "CA file not found: $ca_path"
        pause_menu
        return
    fi
    if [ ! -f "$cert_path" ]; then
        log_error "Certificate file not found: $cert_path"
        pause_menu
        return
    fi

    echo ""
    log_info "Verifying certificate chain..."
    local result
    result=$(openssl verify -CAfile "$ca_path" "$cert_path" 2>&1)

    if echo "$result" | grep -q ": OK"; then
        log_success "Certificate verification PASSED."
        echo -e "  ${DIM}$result${RESET}"
    else
        log_error "Certificate verification FAILED."
        echo -e "  ${RED}$result${RESET}"
    fi

    pause_menu
}

# ----------------------------- Revoke & CRL -----------------------------------

revoke_certificate() {
    clear
    print_banner
    echo -e "${BOLD}  [6] Revoke Certificate & Generate CRL${RESET}"
    print_separator
    echo ""

    if [ -z "$CA_DIR" ]; then
        prompt_ca_directory || return
    fi

    # Determine which CA to use for revocation
    local rev_conf rev_crl rev_label
    echo -e "  ${BOLD}Revoke using:${RESET}"
    echo "    1) Root CA"
    echo "    2) Intermediate CA"
    read -p "  Select [1/2]: " rev_choice

    case "$rev_choice" in
        1)
            rev_conf="$CA_DIR/openssl.cnf"
            rev_crl="$ROOT_CRL"
            rev_label="Root CA"
            ;;
        2)
            if [ ! -f "$INTERMEDIATE_DIR/openssl.cnf" ]; then
                log_error "Intermediate CA config not found."
                pause_menu
                return
            fi
            rev_conf="$INTERMEDIATE_DIR/openssl.cnf"
            rev_crl="$INTERMEDIATE_CRL"
            rev_label="Intermediate CA"
            ;;
        *)
            log_error "Invalid selection."
            pause_menu
            return
            ;;
    esac

    read -p "  Path to certificate to revoke: " cert_path
    is_cancel "$cert_path" && return

    if [ ! -f "$cert_path" ]; then
        log_error "Certificate file not found: $cert_path"
        pause_menu
        return
    fi

    echo ""
    log_warn "You are about to revoke: ${CYAN}$cert_path${RESET}"
    read -p "  Type 'yes' to confirm revocation: " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Revocation cancelled."
        pause_menu
        return
    fi

    # Revoke
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would revoke: $cert_path using $rev_label"
        dry_run_print "Would generate CRL: $rev_crl"
    else
        log_info "Revoking certificate..."
        openssl ca -config "$rev_conf" -revoke "$cert_path" 2>&1
        if [ $? -ne 0 ]; then
            log_error "Revocation failed."
            pause_menu
            return
        fi
        log_success "Certificate revoked."

        log_info "Generating CRL..."
        openssl ca -config "$rev_conf" -gencrl -out "$rev_crl" 2>&1
        if [ $? -ne 0 ]; then
            log_error "CRL generation failed."
            pause_menu
            return
        fi
        record "FILE" "$rev_crl"
        log_success "CRL generated: ${CYAN}$rev_crl${RESET}"
    fi

    pause_menu
}

# ----------------------------- PKCS#12 Bundle ---------------------------------

create_pkcs12() {
    clear
    print_banner
    echo -e "${BOLD}  [7] Create PKCS#12 Bundle (.p12/.pfx)${RESET}"
    print_separator
    echo ""

    read -p "  Path to certificate (.crt): " cert_path
    is_cancel "$cert_path" && return

    read -p "  Path to private key (.key): " key_path
    is_cancel "$key_path" && return

    read -p "  Path to CA chain file (optional, Enter to skip): " chain_path
    is_cancel "$chain_path" && return

    read -p "  Output filename [bundle.p12]: " out_name
    is_cancel "$out_name" && return
    out_name="${out_name:-bundle.p12}"

    local out_dir
    if [ -n "$CA_DIR" ]; then
        out_dir="$CA_DIR/certs"
    else
        out_dir="$(pwd)"
    fi
    local out_path="$out_dir/$out_name"

    for f in "$cert_path" "$key_path"; do
        if [ ! -f "$f" ]; then
            log_error "File not found: $f"
            pause_menu
            return
        fi
    done

    echo ""
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would create PKCS#12 bundle at $out_path"
    else
        local p12_cmd=(openssl pkcs12 -export -out "$out_path" -inkey "$key_path" -in "$cert_path")
        if [ -n "$chain_path" ] && [ -f "$chain_path" ]; then
            p12_cmd+=(-certfile "$chain_path")
        fi

        log_info "Creating PKCS#12 bundle (you will be prompted for an export password)..."
        "${p12_cmd[@]}"
        if [ $? -ne 0 ]; then
            log_error "PKCS#12 bundle creation failed."
            pause_menu
            return
        fi
        record "FILE" "$out_path"
        log_success "PKCS#12 bundle: ${CYAN}$out_path${RESET}"
    fi

    pause_menu
}

# ----------------------------- Install to Trust Store -------------------------

install_to_trust_store() {
    clear
    print_banner
    echo -e "${BOLD}  [8] Install CA Certificate to System Trust Store${RESET}"
    print_separator
    echo ""

    read -p "  Path to CA certificate (.crt): " cert_path
    is_cancel "$cert_path" && return

    if [ ! -f "$cert_path" ]; then
        log_error "File not found: $cert_path"
        pause_menu
        return
    fi

    local cert_basename
    cert_basename=$(basename "$cert_path")

    echo ""
    if [ "$DRY_RUN" = true ]; then
        dry_run_print "Would install $cert_basename to system trust store"
    else
        # Debian/Ubuntu
        if [ -d "/usr/local/share/ca-certificates" ]; then
            local dest="/usr/local/share/ca-certificates/$cert_basename"
            cp "$cert_path" "$dest"
            update-ca-certificates 2>&1
            if [ $? -eq 0 ]; then
                record "TRUST" "$dest"
                log_success "Installed to trust store (Debian/Ubuntu): ${CYAN}$dest${RESET}"
            else
                log_error "update-ca-certificates failed."
            fi
        # RHEL/CentOS/Fedora
        elif [ -d "/etc/pki/ca-trust/source/anchors" ]; then
            local dest="/etc/pki/ca-trust/source/anchors/$cert_basename"
            cp "$cert_path" "$dest"
            update-ca-trust extract 2>&1
            if [ $? -eq 0 ]; then
                record "TRUST" "$dest"
                log_success "Installed to trust store (RHEL/CentOS): ${CYAN}$dest${RESET}"
            else
                log_error "update-ca-trust failed."
            fi
        else
            log_error "Could not determine trust store location for this distribution."
            log_info "Manually copy $cert_path to your system's CA trust directory."
        fi
    fi

    pause_menu
}

# ----------------------------- Quick Summary ----------------------------------

show_ca_summary() {
    clear
    print_banner
    echo -e "${BOLD}  CA Environment Summary${RESET}"
    print_separator
    echo ""

    if [ -z "$CA_DIR" ]; then
        log_warn "CA directory not set. Use option 1 to generate a Root CA first."
        pause_menu
        return
    fi

    echo -e "  ${BOLD}Directory:${RESET}   ${CYAN}$CA_DIR${RESET}"
    echo ""

    # Root CA status
    echo -e "  ${BOLD}Root CA:${RESET}"
    if [ -f "$ROOT_CERT" ]; then
        local root_subj root_expiry
        root_subj=$(openssl x509 -in "$ROOT_CERT" -noout -subject 2>/dev/null | sed 's/subject=//')
        root_expiry=$(openssl x509 -in "$ROOT_CERT" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
        echo -e "    Subject: ${CYAN}$root_subj${RESET}"
        echo -e "    Expires: ${CYAN}$root_expiry${RESET}"
        log_success "  Root CA is present."
    else
        log_warn "  Root CA not generated yet."
    fi

    echo ""

    # Intermediate CA status
    echo -e "  ${BOLD}Intermediate CA:${RESET}"
    if [ -f "$INTERMEDIATE_CERT" ]; then
        local int_subj int_expiry
        int_subj=$(openssl x509 -in "$INTERMEDIATE_CERT" -noout -subject 2>/dev/null | sed 's/subject=//')
        int_expiry=$(openssl x509 -in "$INTERMEDIATE_CERT" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
        echo -e "    Subject: ${CYAN}$int_subj${RESET}"
        echo -e "    Expires: ${CYAN}$int_expiry${RESET}"
        log_success "  Intermediate CA is present."
    else
        log_warn "  Intermediate CA not generated yet."
    fi

    echo ""

    # List end-entity certs
    echo -e "  ${BOLD}Issued Certificates:${RESET}"
    local cert_count=0
    if [ -d "$CA_DIR/certs" ]; then
        while IFS= read -r -d '' cfile; do
            local bname
            bname=$(basename "$cfile")
            # Skip the CA certs themselves
            if [[ "$bname" == "ca.crt" || "$bname" == "ca-chain.crt" ]]; then
                continue
            fi
            local c_subj c_exp
            c_subj=$(openssl x509 -in "$cfile" -noout -subject 2>/dev/null | sed 's/subject=//')
            c_exp=$(openssl x509 -in "$cfile" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
            echo -e "    ${CYAN}$bname${RESET} — $c_subj (expires: $c_exp)"
            ((cert_count++))
        done < <(find "$CA_DIR/certs" -maxdepth 1 -name "*.crt" -print0 2>/dev/null)
    fi
    if [ -d "$INTERMEDIATE_DIR/certs" ]; then
        while IFS= read -r -d '' cfile; do
            local bname
            bname=$(basename "$cfile")
            if [[ "$bname" == "intermediate.crt" || "$bname" == "ca-chain.crt" ]]; then
                continue
            fi
            local c_subj c_exp
            c_subj=$(openssl x509 -in "$cfile" -noout -subject 2>/dev/null | sed 's/subject=//')
            c_exp=$(openssl x509 -in "$cfile" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
            echo -e "    ${CYAN}$bname${RESET} — $c_subj (expires: $c_exp)"
            ((cert_count++))
        done < <(find "$INTERMEDIATE_DIR/certs" -maxdepth 1 -name "*.crt" -print0 2>/dev/null)
    fi

    if [ "$cert_count" -eq 0 ]; then
        log_info "  No end-entity certificates issued yet."
    fi

    pause_menu
}

# ==========================================#
#           M A I N   M E N U               #
# ==========================================#

main() {
    check_root
    install_openssl || exit 1

    # If --rollback was passed, run rollback and exit
    if [ "$DO_ROLLBACK" = true ]; then
        if [ -z "$CA_DIR" ]; then
            prompt_ca_directory || exit 0
        fi
        do_rollback
        exit 0
    fi

    while true; do
        clear
        print_banner

        dry_run_status=""
        if [ "$DRY_RUN" = true ]; then
            dry_run_status="${YELLOW}[ON]${RESET}"
        else
            dry_run_status="${DIM}[OFF]${RESET}"
        fi

        echo -e "${BOLD}  Main Menu:${RESET}"
        echo "    1) Generate Root CA"
        echo "    2) Generate Intermediate CA"
        echo "    3) Generate Server Certificate"
        echo "    4) Generate Client Certificate"
        echo "    5) Inspect a Certificate"
        echo "    6) Verify Certificate Chain"
        echo "    7) Revoke Certificate & Generate CRL"
        echo "    8) Create PKCS#12 Bundle (.p12/.pfx)"
        echo "    9) Install CA to System Trust Store"
        echo "   10) View CA Summary"
        echo "   11) Rollback All Generated Files"
        echo -e "   12) Toggle Dry Run Mode $dry_run_status"
        echo "   13) Exit"
        print_separator

        if [ -n "$CA_DIR" ]; then
            echo -e "  ${BOLD}Active CA:${RESET} ${CYAN}$CA_DIR${RESET}"
            local status_parts=""
            [ -f "$ROOT_CERT" ]         && status_parts="${GREEN}Root ✓${RESET}"      || status_parts="${DIM}Root ✗${RESET}"
            [ -f "$INTERMEDIATE_CERT" ] && status_parts="$status_parts  ${GREEN}Intermediate ✓${RESET}" || status_parts="$status_parts  ${DIM}Intermediate ✗${RESET}"
            echo -e "  ${BOLD}Status:${RESET}    $status_parts"
            print_separator
        fi

        read -p "  Please choose an option [1-13]: " main_choice

        case $main_choice in
            1) generate_root_ca ;;
            2) generate_intermediate_ca ;;
            3) generate_end_entity_cert "server" ;;
            4) generate_end_entity_cert "client" ;;
            5) inspect_certificate ;;
            6) verify_certificate_chain ;;
            7) revoke_certificate ;;
            8) create_pkcs12 ;;
            9) install_to_trust_store ;;
            10) show_ca_summary ;;
            11)
                do_rollback
                pause_menu
                ;;
            12)
                if [ "$DRY_RUN" = true ]; then
                    DRY_RUN=false
                    log_success "Dry Run mode DISABLED. Changes will be APPLIED."
                else
                    DRY_RUN=true
                    log_success "Dry Run mode ENABLED. Changes will only be PRINTED."
                fi
                sleep 1.5
                ;;
            13) clear; echo "Exiting script. Goodbye!"; exit 0 ;;
            *)
                clear
                print_banner
                log_error "Invalid option. Please select a number between 1 and 13."
                sleep 1
                ;;
        esac
    done
}

main "$@"
