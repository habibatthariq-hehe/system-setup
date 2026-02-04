#!/bin/bash

set -e

echo "=== Install sudo (no sudo used here) ==="
apt update
apt install -y sudo

echo "=== Install dependencies ==="
sudo apt install -y git wget curl zsh isc-dhcp-relay

echo "=== Install Oh My Zsh ==="
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "Oh My Zsh already installed"
fi

ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}

echo "=== Install Zsh plugins ==="

# zsh-autosuggestions
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

# zsh-autocomplete
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autocomplete" ]; then
  git clone --depth 1 https://github.com/marlonrichert/zsh-autocomplete.git \
    "$ZSH_CUSTOM/plugins/zsh-autocomplete"
fi

# zsh-syntax-highlighting (HARUS TERAKHIR)
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

echo "=== Update ~/.zshrc ==="
ZSHRC="$HOME/.zshrc"

# backup zshrc
cp "$ZSHRC" "$ZSHRC.bak.$(date +%F_%T)"

# set plugin list (syntax-highlighting terakhir)
sed -i '/^plugins=/c\
plugins=(git zsh-autosuggestions zsh-autocomplete zsh-syntax-highlighting)\
' "$ZSHRC"

echo "=== Set Zsh as default shell ==="
if [ "$SHELL" != "$(which zsh)" ]; then
  sudo chsh -s "$(which zsh)" "$USER"
fi

echo "=== Done! Reloading Zsh ==="
exec zsh
