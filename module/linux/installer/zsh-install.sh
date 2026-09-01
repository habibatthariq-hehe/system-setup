#!/bin/bash

# ==============================================================================
# ZSH INSTALLER - with Rollback Support
#
# Core features (unchanged):
#   * Detects package manager (apt/dnf/yum/pacman/zypper)
#   * Installs git, wget, curl, zsh
#   * Downloads MesloLGS NF fonts (4 variants)
#   * Refreshes font cache (GUI and TTY aware)
#   * Installs Oh My Zsh
#   * Clones zsh-autosuggestions, zsh-autocomplete, zsh-syntax-highlighting,
#     powerlevel10k
#   * Updates ~/.zshrc plugins line + p10k theme source
#   * Sets zsh as default shell
#
# Quality-of-service additions:
#   * Colored UI matching dhcp-setup.sh ([INFO]/[OK]/[WARN]/[ERROR])
#   * Manifest-based rollback: every change is recorded in a manifest file;
#     run this script with --rollback to undo everything it did.
#   * Backup of ~/.zshrc taken BEFORE any modification (bug fix)
#   * curl uses --fail so failed downloads never write corrupt font files
#   * EOF/Ctrl-D at the package-manager prompt no longer falls through silently
#   * No more `exec zsh` at the end (it killed the parent menu process);
#     offers an interactive zsh subshell instead.
#
# Usage:
#   bash zsh-install.sh             normal install
#   bash zsh-install.sh --rollback  undo everything recorded in the manifest
# ==============================================================================

# NOTE: set -e intentionally omitted. download_font and clone_plugin use
# '|| log_warn' for graceful fallback; set -e would misfire the ERR trap on
# those non-fatal failures and abort the entire installation prematurely.
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

MANIFEST="${HOME}/.zsh-install-manifest"
ZSHRC="$HOME/.zshrc"

print_banner() {
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║                     ZSH INTERACTIVE INSTALLER                     ║${RESET}"
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

# ----------------------------- Manifest / Rollback engine ---------------------

manifest_init() {
    : > "$MANIFEST"
}

# record <action> <arg...>
#   action: installed_pkg | created_dir | downloaded_file | cloned_repo
#           | appended_line | modified_zshrc | backup_file | changed_shell
record() {
    local action="$1"; shift
    printf '%s\n' "$action|$*" >> "$MANIFEST"
}

do_rollback() {
    print_banner
    if [[ ! -f "$MANIFEST" ]]; then
        log_error "No manifest found at $MANIFEST - nothing to roll back."
        exit 1
    fi
    if [[ ! -s "$MANIFEST" ]]; then
        log_warn "Manifest is empty - nothing to roll back."
        exit 0
    fi

    log_info "Rolling back changes recorded in $MANIFEST ..."
    print_separator

    # Restore .zshrc FIRST (most important user file).
    local zshrc_bak
    zshrc_bak=$(grep '^backup_file|' "$MANIFEST" | tail -1 | cut -d'|' -f2- || true)
    if [[ -n "$zshrc_bak" && -f "$zshrc_bak" ]]; then
        cp "$zshrc_bak" "$ZSHRC"
        log_success "Restored $ZSHRC from $zshrc_bak"
    else
        log_warn "No .zshrc backup found in manifest; leaving .zshrc untouched."
    fi

    # Read the manifest in REVERSE so later actions are undone first.
    tac "$MANIFEST" | while IFS= read -r entry; do
        local action="${entry%%|*}"
        local args="${entry#*|}"
        case "$action" in
            changed_shell)
                local prev_shell="$args"
                if [[ -n "$prev_shell" ]]; then
                    sudo chsh -s "$prev_shell" "${SUDO_USER:-$USER}" 2>/dev/null \
                        && log_success "Default shell restored to $prev_shell" \
                        || log_warn "Could not restore previous shell ($prev_shell). Change manually with: chsh -s $prev_shell"
                fi
                ;;
            appended_line)
                local line="$args"
                if [[ -f "$ZSHRC" ]] && grep -qF "$line" "$ZSHRC"; then
                    sed -i "\|^$(printf '%s' "$line" | sed 's/[.[\*^$]/\\&/g')$|d" "$ZSHRC" 2>/dev/null \
                        && log_success "Removed appended line: ${line:0:50}..."
                fi
                ;;
            cloned_repo)
                if [[ -d "$args" ]]; then
                    rm -rf "$args"
                    log_success "Removed cloned repo: $args"
                fi
                ;;
            downloaded_file)
                if [[ -f "$args" ]]; then
                    rm -f "$args"
                    log_success "Removed downloaded file: $(basename "$args")"
                fi
                ;;
            created_dir)
                if [[ -d "$args" ]]; then
                    rmdir "$args" 2>/dev/null \
                        && log_success "Removed directory: $args" \
                        || log_info "Directory not empty, kept: $args"
                fi
                ;;
            installed_pkg)
                log_info "Package '$args' was installed. Remove manually if desired:"
                log_info "  e.g. sudo apt remove $args / sudo dnf remove $args / sudo pacman -R $args"
                ;;
            backup_file|modified_zshrc)
                ;; # handled above / informational only
        esac
    done

    : > "$MANIFEST"
    print_separator
    log_success "Rollback complete."
    exit 0
}

[[ "${1:-}" == "--rollback" ]] && do_rollback

# ----------------------------- Failure trap (auto-rollback offer) -------------
on_error() {
    local exit_code=$?
    local line_no=$1
    echo ""
    log_error "Script FAILED at line $line_no (exit code $exit_code)."
    if [[ -s "$MANIFEST" ]]; then
        log_warn "Partial installation detected."
        log_info "To undo all changes made so far, run:"
        echo -e "       ${BOLD}bash $0 --rollback${RESET}"
        log_info "(manifest preserved at $MANIFEST)"
    fi
    exit "$exit_code"
}
trap 'on_error $LINENO' ERR

# ----------------------------- Step 1: Package manager detection --------------
clear
print_banner
echo -e "${BLUE}${BOLD}  [Step 1/6] Detecting Package Manager${RESET}"
print_separator

PKG_MANAGERS=()
command -v apt     >/dev/null 2>&1 && PKG_MANAGERS+=("apt")
command -v dnf     >/dev/null 2>&1 && PKG_MANAGERS+=("dnf")
command -v yum     >/dev/null 2>&1 && PKG_MANAGERS+=("yum")
command -v pacman  >/dev/null 2>&1 && PKG_MANAGERS+=("pacman")
command -v zypper  >/dev/null 2>&1 && PKG_MANAGERS+=("zypper")

if [ ${#PKG_MANAGERS[@]} -eq 0 ]; then
  log_error "No supported package manager found."
  exit 1
fi

if [ ${#PKG_MANAGERS[@]} -eq 1 ]; then
  PKG="${PKG_MANAGERS[0]}"
  log_success "Detected package manager: ${GREEN}$PKG${RESET}"
else
  log_info "Multiple package managers detected:"
  PS3="  Select one [1-${#PKG_MANAGERS[@]}]: "
  select PKG in "${PKG_MANAGERS[@]}"; do
    if [ -n "$PKG" ]; then
      break
    elif [ -z "$REPLY" ]; then
      # Empty input (Enter) or EOF -> pick the first one rather than falling through
      PKG="${PKG_MANAGERS[0]}"
      log_warn "No selection made - defaulting to: $PKG"
      break
    else
      echo "Invalid selection"
    fi
  done
fi

log_success "Using package manager: ${GREEN}$PKG${RESET}"

manifest_init

# ----------------------------- Step 2: Install dependencies -------------------
echo ""
echo -e "${BLUE}${BOLD}  [Step 2/6] Install Dependencies (git wget curl zsh)${RESET}"
print_separator

case $PKG in
  apt)
    sudo apt update
    sudo apt install -y git wget curl zsh
    ;;
  dnf)
    sudo dnf install -y git wget curl zsh
    ;;
  yum)
    sudo yum install -y git wget curl zsh
    ;;
  pacman)
    sudo pacman -Sy --noconfirm git wget curl zsh
    ;;
  zypper)
    sudo zypper install -y git wget curl zsh
    ;;
esac

for p in git wget curl zsh; do
  command -v "$p" >/dev/null 2>&1 && record installed_pkg "$p"
done

if ! command -v zsh >/dev/null 2>&1; then
  log_error "zsh was not installed successfully. Aborting."
  exit 1
fi
log_success "All dependencies present."

# ----------------------------- Step 3: Meslo fonts ----------------------------
echo ""
echo -e "${BLUE}${BOLD}  [Step 3/6] MesloLGS NF Fonts${RESET}"
print_separator

CURRENT_USER_FONT_PATH="$HOME/.local/share/fonts/"
mkdir -p "$CURRENT_USER_FONT_PATH"
record created_dir "$(realpath "$CURRENT_USER_FONT_PATH")"

download_font() {
  local url="$1"
  local output_path="$2"
  local filename
  filename="$(basename "$output_path")"

  if [ -f "$output_path" ] && [ -s "$output_path" ]; then
    log_info "[EXISTS] $filename already exists, skipping download"
    return 0
  fi
  log_info "[DOWNLOADING] $filename ..."
  # --fail: on HTTP errors curl exits non-zero instead of writing an HTML
  # error page into the .ttf file (bug fix).
  if curl -fL --retry 3 --connect-timeout 15 "$url" --output "$output_path"; then
    record downloaded_file "$output_path"
    log_success "Downloaded $filename"
  else
    rm -f "$output_path"
    log_warn "Failed to download $filename (network error). Skipping."
  fi
}

download_font "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"    "${CURRENT_USER_FONT_PATH}MesloLGS NF Regular.ttf"
download_font "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"       "${CURRENT_USER_FONT_PATH}MesloLGS NF Bold.ttf"
download_font "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"     "${CURRENT_USER_FONT_PATH}MesloLGS NF Italic.ttf"
download_font "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf" "${CURRENT_USER_FONT_PATH}MesloLGS NF Bold Italic.ttf"

echo ""
log_info "Refreshing Font Cache..."
if command -v fc-cache >/dev/null 2>&1; then
  fc-cache -f "$CURRENT_USER_FONT_PATH" >/dev/null 2>&1 \
    && log_success "Font cache refreshed." \
    || log_warn "fc-cache reported an issue - continuing anyway."
else
  log_warn "fc-cache command not found. Skipping font cache refresh."
fi

# ----------------------------- Step 4: Oh My Zsh ------------------------------
echo ""
echo -e "${BLUE}${BOLD}  [Step 4/6] Oh My Zsh${RESET}"
print_separator

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  if RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; then
    record cloned_repo "$HOME/.oh-my-zsh"
    log_success "Oh My Zsh installed."
  else
    log_error "Oh My Zsh installer failed. Aborting before plugin setup."
    exit 1
  fi
else
  log_success "Oh My Zsh already installed - skipping."
fi

ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
mkdir -p "$ZSH_CUSTOM/plugins"

# ----------------------------- Step 5: Plugins --------------------------------
echo ""
echo -e "${BLUE}${BOLD}  [Step 5/6] ZSH Plugins & Theme${RESET}"
print_separator

clone_plugin() {
  local url="$1"
  local dir="$2"
  # BUG FIX: use an array so args with spaces are word-split correctly by the
  # shell rather than relying on unsafe unquoted variable expansion.
  local -a extra_args=()
  [ -n "${3:-}" ] && IFS=' ' read -ra extra_args <<< "${3}"
  if [ ! -d "$dir" ]; then
    if git clone "${extra_args[@]}" "$url" "$dir"; then
      record cloned_repo "$dir"
      log_success "Cloned $(basename "$dir")"
    else
      log_warn "Failed to clone $(basename "$dir") - continuing without it."
      return 1
    fi
  else
    log_info "$(basename "$dir") already present - skipping."
  fi
}

# NOTE: zsh-autocomplete must be sourced LAST among plugins; the .zshrc order
# below already guarantees that.
clone_plugin "https://github.com/zsh-users/zsh-autosuggestions.git"          "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_plugin "https://github.com/marlonrichert/zsh-autocomplete.git"         "$ZSH_CUSTOM/plugins/zsh-autocomplete" "--depth 1"
clone_plugin "https://github.com/zsh-users/zsh-syntax-highlighting.git"      "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
clone_plugin "https://github.com/romkatv/powerlevel10k.git"                  "$HOME/powerlevel10k" "--depth=1"

# ----------------------------- Step 6: Configure ~/.zshrc + default shell -----
echo ""
echo -e "${BLUE}${BOLD}  [Step 6/6] Configuration (~/.zshrc & default shell)${RESET}"
print_separator

touch "$ZSHRC"

# BUG FIX: removed stray indentation from ZSHRC_BAK line (leftover from a
# removed if-block). Always take a fresh backup before any modification.
ZSHRC_BAK="$ZSHRC.bak.$(date +%Y%m%d_%H%M%S)"
cp "$ZSHRC" "$ZSHRC_BAK"
record backup_file "$ZSHRC_BAK"
log_success "Backed up .zshrc -> $(basename "$ZSHRC_BAK")"

PLUGINS_LINE='plugins=(git zsh-autosuggestions zsh-autocomplete zsh-syntax-highlighting)'
P10K_LINE='source ~/powerlevel10k/powerlevel10k.zsh-theme'

# BUG FIX: write the plugins= line BEFORE the theme source line.
# Oh My Zsh requires $ZSH/oh-my-zsh.sh to be sourced before any theme,
# so the plugins line (part of the OMZ block) must appear first. The old
# code appended P10K_LINE first, leaving it above the plugins line on fresh
# installs and breaking theme loading.
if grep -q "^[[:space:]]*plugins=" "$ZSHRC"; then
  sed -i "s|^plugins=.*|$PLUGINS_LINE|" "$ZSHRC"
  record modified_zshrc "plugins-line-replaced"
  log_success "Updated plugins line in .zshrc"
else
  echo "$PLUGINS_LINE" >> "$ZSHRC"
  record appended_line "$PLUGINS_LINE"
  log_success "Added plugins line to .zshrc"
fi

if ! grep -qF "$P10K_LINE" "$ZSHRC"; then
  echo "$P10K_LINE" >> "$ZSHRC"
  record appended_line "$P10K_LINE"
  log_success "Added powerlevel10k theme to .zshrc"
fi

ZSH_PATH="$(command -v zsh)"
CURRENT_USER="${SUDO_USER:-${USER:-$(id -un)}}"
if [ -n "$ZSH_PATH" ] && [ "$(getent passwd "$CURRENT_USER" | cut -d: -f7)" != "$ZSH_PATH" ]; then
  # BUG FIX: capture PREV_SHELL BEFORE calling chsh. The old code read the
  # shell entry after chsh had already changed it, so the rollback manifest
  # always recorded zsh as the "previous" shell instead of the real one.
  PREV_SHELL="$(getent passwd "$CURRENT_USER" | cut -d: -f7)"
  if chsh -s "$ZSH_PATH" 2>/dev/null || sudo chsh -s "$ZSH_PATH" "$CURRENT_USER"; then
    record changed_shell "$PREV_SHELL"
    log_success "Default shell set to zsh for $CURRENT_USER"
  else
    log_warn "Could not change default shell automatically."
    log_info "Run manually: chsh -s $ZSH_PATH"
  fi
else
  log_success "Default shell already zsh - skipping chsh."
fi

# ----------------------------- Summary ----------------------------------------
echo ""
print_separator
log_success "Installation complete!"
log_info "Start a new terminal (or type 'exec zsh') to use your new setup."
if [[ -s "$MANIFEST" ]]; then
  log_info "To undo everything later, run: ${BOLD}bash $0 --rollback${RESET}"
fi
echo ""

# BUG FIX: `exec zsh` replaced the parent process and killed the caller's menu.
# Offer an interactive subshell instead, which returns cleanly when exited.
read -p "  Launch an interactive zsh session now? [y/N]: " launch_now
if [[ "$launch_now" =~ ^[Yy]$ ]]; then
  zsh -i
fi

exit 0
