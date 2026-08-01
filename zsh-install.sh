#!/bin/bash

set -e

echo "=== Detecting package manager ==="

PKG_MANAGERS=()

command -v apt >/dev/null 2>&1 && PKG_MANAGERS+=("apt")
command -v dnf >/dev/null 2>&1 && PKG_MANAGERS+=("dnf")
command -v yum >/dev/null 2>&1 && PKG_MANAGERS+=("yum")
command -v pacman >/dev/null 2>&1 && PKG_MANAGERS+=("pacman")
command -v zypper >/dev/null 2>&1 && PKG_MANAGERS+=("zypper")

if [ ${#PKG_MANAGERS[@]} -eq 0 ]; then
  echo "No supported package manager found."
  exit 1
fi

if [ ${#PKG_MANAGERS[@]} -eq 1 ]; then
  PKG="${PKG_MANAGERS[0]}"
  echo "Detected package manager: $PKG"
else
  echo "Multiple package managers detected:"
  select PKG in "${PKG_MANAGERS[@]}"; do
    if [ -n "$PKG" ]; then
      break
    else
      echo "Invalid selection"
    fi
  done
fi

echo "Using package manager: $PKG"
echo "=== Install dependencies ==="

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

echo "==== Starting Meslo Font Script ===="
echo "==== Making Directory ====" 

CURRENT_USER_FONT_PATH="$HOME/.local/share/fonts/"

mkdir -p "$CURRENT_USER_FONT_PATH"

echo "==== Success ===="

download_font() {
  local url="$1"
  local output_path="$2"
  local filename
  filename="$(basename "$output_path")"

  if [ -f "$output_path" ]; then
    echo "==== [EXISTS] $filename already exists, skipping download ===="
  else
    echo "==== [DOWNLOADING] $filename ... ===="
    curl -L "$url" --output "$output_path"
  fi
}

download_font "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf" "${CURRENT_USER_FONT_PATH}MesloLGS NF Regular.ttf"
download_font "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf" "${CURRENT_USER_FONT_PATH}MesloLGS NF Bold.ttf"
download_font "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf" "${CURRENT_USER_FONT_PATH}MesloLGS NF Italic.ttf"
download_font "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf" "${CURRENT_USER_FONT_PATH}MesloLGS NF Bold Italic.ttf"

sleep 5

echo "==== Done Downloading ===="
echo "==== Refreshing Font Cache ===="
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ] || [ "$XDG_SESSION_TYPE" = "x11" ] || [ "$XDG_SESSION_TYPE" = "wayland" ]; then
  echo "Desktop environment detected."
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f -v "$CURRENT_USER_FONT_PATH" || echo "Notice: fc-cache encountered an issue, continuing script execution..."
  else
    echo "Notice: fc-cache command not found. Skipping font cache refresh."
  fi
else
  echo "TTY mode detected (no GUI display environment)."
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f -v "$CURRENT_USER_FONT_PATH" 2>/dev/null || echo "Notice: fc-cache failed in TTY mode, skipping font cache refresh..."
  else
    echo "Notice: fc-cache not available in TTY mode, skipping font cache refresh."
  fi
fi
echo "==== Done ===="

echo "=== Install Oh My Zsh ==="
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "Oh My Zsh already installed"
fi

ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
ZSHRC="$HOME/.zshrc"
touch "$ZSHRC"

echo "=== Install ZSH plugins ==="

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autocomplete" ]; then
  git clone --depth 1 https://github.com/marlonrichert/zsh-autocomplete.git \
    "$ZSH_CUSTOM/plugins/zsh-autocomplete"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

if [ ! -d "$HOME/powerlevel10k" ]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k
fi

if ! grep -q "powerlevel10k.zsh-theme" "$ZSHRC"; then
  echo 'source ~/powerlevel10k/powerlevel10k.zsh-theme' >> "$ZSHRC"
fi

echo "=== Update ~/.zshrc ==="

cp "$ZSHRC" "$ZSHRC.bak.$(date +%F_%T)"

if grep -q "^plugins=" "$ZSHRC"; then
  sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-autocomplete zsh-syntax-highlighting)/' "$ZSHRC"
else
  echo 'plugins=(git zsh-autosuggestions zsh-autocomplete zsh-syntax-highlighting)' >> "$ZSHRC"
fi

echo "=== Set ZSH as default shell ==="
ZSH_PATH="$(command -v zsh)"
if [ "$SHELL" != "$ZSH_PATH" ] && [ -n "$ZSH_PATH" ]; then
  sudo chsh -s "$ZSH_PATH" "$USER"
fi

echo "=== Done! Reloading Zsh ==="
exec zsh
