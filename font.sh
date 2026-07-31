#!/bin/bash

set -e

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

echo "==== Checking & Downloading Fonts ===="

download_font "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf" "${CURRENT_USER_FONT_PATH}MesloLGS NF Regular.ttf"
download_font "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf" "${CURRENT_USER_FONT_PATH}MesloLGS NF Bold.ttf"
download_font "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf" "${CURRENT_USER_FONT_PATH}MesloLGS NF Italic.ttf"
download_font "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf" "${CURRENT_USER_FONT_PATH}MesloLGS NF Bold Italic.ttf"

echo "==== Done Downloading / Checking ===="
echo "==== Refreshing Font Cache ===="
fc-cache -f -v "$CURRENT_USER_FONT_PATH"
echo "==== Done ===="
