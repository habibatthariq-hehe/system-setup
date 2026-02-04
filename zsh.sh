#!/bin/bash
set -e

echo "=== Install sudo (no sudo used before this) ==="
apt update
apt install -y sudo

echo "=== Install dependencies ==="
sudo apt install -y git wget curl zsh

echo "=== Install Oh My Zsh ==="
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "Oh My Zsh already installed"
fi

ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
ZSHRC="$HOME/.zshrc"

echo "=== Install Zsh plugins ==="

clone_if_missing() {
  [ ! -d "$2" ] && git clone $1 "$2"
}

clone_if_missing https://github.com/zsh-users/zsh-autosuggestions \
  "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

clone_if_missing https://github.com/marlonrichert/zsh-autocomplete.git \
  "$ZSH_CUSTOM/plugins/zsh-autocomplete"

clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting.git \
  "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

echo "=== Install Powerlevel10k ==="
clone_if_missing https://github.com/romkatv/powerlevel10k.git \
  "$ZSH_CUSTOM/themes/powerlevel10k"

echo "=== Backup ~/.zshrc ==="
cp "$ZSHRC" "$ZSHRC.bak.$(date +%F_%T)"

echo "=== Auto import plugins (non-destructive) ==="

add_plugin() {
  grep -q "$1" "$ZSHRC" || \
  sed -i "/^plugins=(/ s/)/ $1)/" "$ZSHRC"
}

add_plugin zsh-autosuggestions
add_plugin zsh-autocomplete

# syntax-highlighting HARUS TERAKHIR
grep -q zsh-syntax-highlighting "$ZSHRC" || \
sed -i "/^plugins=(/ s/)/ zsh-syntax-highlighting)/" "$ZSHRC"

echo "=== Set Powerlevel10k theme ==="
sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"

echo "=== Set Zsh as default shell ==="
if [ "$SHELL" != "$(which zsh)" ]; then
  sudo chsh -s "$(which zsh)" "$USER"
fi

echo "=== Done! Reloading Zsh ==="
exec zsh
