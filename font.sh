#!/bin/bash

set -e

echo "==== Starting Meslo Font Script ===="
echo "==== Making Directory ===="

CURRENT_USER_FONT_PATH="$HOME/.local/share/fonts/"

mkdir -p "$CURRENT_USER_FONT_PATH"

echo "==== Success ===="

echo "==== Downloading Font ===="

curl -L https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf --output "${CURRENT_USER_FONT_PATH}MesloLGS NF Regular.ttf"
curl -L https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf --output "${CURRENT_USER_FONT_PATH}MesloLGS NF Bold.ttf"
curl -L https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf --output "${CURRENT_USER_FONT_PATH}MesloLGS NF Italic.ttf"
curl -L https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf --output "${CURRENT_USER_FONT_PATH}MesloLGS NF Bold Italic.ttf"

echo "==== Done Downloading ===="
echo "==== Refreshing Font Cache ===="
fc-cache -f -v "$CURRENT_USER_FONT_PATH"
echo "==== Done ===="
