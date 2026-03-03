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

CURRENT_USER_FONT_PATH=~/.local/share/fonts/

mkdir -p "$CURRENT_USER_FONT_PATH"

echo "==== Success ===="

echo "==== Downloading Font ===="

curl -L https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf --output "${CURRENT_USER_FONT_PATH}MesloL>
curl -L https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf --output "${CURRENT_USER_FONT_PATH}MesloLGS >
curl -L https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf --output "${CURRENT_USER_FONT_PATH}MesloLG>
curl -L https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf --output "${CURRENT_USER_FONT_PATH}>

sleep 5

echo "==== Done Downloading ===="
echo "==== Refreshing Font Cache ===="
echo "==== Enter You're Password ===="
sudo fc-cache -f -v
echo "==== Done ===="

echo "=== Install Oh My Zsh ==="
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "Oh My Zsh already installed"
fi

ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}

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

if ! grep -q "powerlevel10k.zsh-theme" "$HOME/.zshrc"; then
  echo 'source ~/powerlevel10k/powerlevel10k.zsh-theme' >>~/.zshrc
fi

echo "=== Update ~/.zshrc ==="
ZSHRC="$HOME/.zshrc"

cp "$ZSHRC" "$ZSHRC.bak.$(date +%F_%T)"

if grep -q "^plugins=" "$ZSHRC"; then
  sed -i '/^plugins=/c\
plugins=(git zsh-autosuggestions zsh-autocomplete zsh-syntax-highlighting)\
' "$ZSHRC"
else
  echo 'plugins=(git zsh-autosuggestions zsh-autocomplete zsh-syntax-highlighting)' >> "$ZSHRC"
fi

echo "=== Set ZSH as default shell ==="
if [ "$SHELL" != "$(which zsh)" ]; then
  sudo chsh -s "$(which zsh)" "$USER"
fi

echo "=== Done! Reloading Zsh ==="
exec zsh
