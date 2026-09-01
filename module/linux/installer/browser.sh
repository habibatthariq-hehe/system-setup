#!/bin/bash

echo "========================================== Browser Installer =========================================="

# Package Manager Detection Function

echo " Detecting Package Manager "
PKG_MANAGER=""

detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
    else
        echo "Error: Package manager not found."
        exit 1
    fi
    echo " Detected Package Manager: $PKG_MANAGER"
}

detect_package_manager

detect_architecture() {
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) ARCH="amd64" ;;
  esac
  echo " Detected Architecture: $ARCH"
}

detect_architecture

#User Menu Selection

while true; do
  echo ""
  echo "Choose Browser:"
  echo "1. Firefox"
  echo "2. Google Chrome AMD64"
  echo "3. Google Chrome ARM64"
  echo "4. Brave"
  echo "5. Chromium"
  echo "6. Vivaldi"
  echo "7. Zen Browser"
  echo "8. Opera"
  echo "9. Exit"
  read -p "Enter your choice [1-9]: " choice

  # Installer Command
  case $choice in
    1)
      echo "Installing Firefox..."
      case $PKG_MANAGER in
        apt) sudo apt install firefox -y ;;
        dnf|yum) sudo $PKG_MANAGER install firefox -y ;;
        pacman) sudo pacman -S firefox --noconfirm ;;
      esac
      echo "Firefox successfully installed!"
      ;;
    2)
      echo "Installing Google Chrome..."
      if [ "$PKG_MANAGER" = "apt" ]; then
        wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
        sudo apt update
        sudo dpkg -i google-chrome-stable_current_amd64.deb
        sudo apt -f install -y
      elif [ "$PKG_MANAGER" = "dnf" ] || [ "$PKG_MANAGER" = "yum" ]; then
        sudo $PKG_MANAGER update
        wget https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
        sudo $PKG_MANAGER install google-chrome-stable -y
      elif [ "$PKG_MANAGER" = "pacman" ]; then
        sudo pacman -S google-chrome --noconfirm
      fi
      echo "Google Chrome successfully installed!"
      ;;
    3)
      echo "Installing Google Chrome ARM64..."
      if [ "$PKG_MANAGER" = "apt" ]; then
        wget https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb
        sudo apt update
        sudo dpkg -i google-chrome-stable_current_arm64.deb
        sudo apt -f install -y
      elif [ "$PKG_MANAGER" = "dnf" ] || [ "$PKG_MANAGER" = "yum" ]; then
        sudo $PKG_MANAGER update
        wget https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.rpm
        sudo $PKG_MANAGER install google-chrome-stable -y
      elif [ "$PKG_MANAGER" = "pacman" ]; then
        sudo pacman -S google-chrome --noconfirm
      fi
      echo "Google Chrome ARM64 successfully installed!"
      ;;
    4)
      echo "Installing Brave..."
      case $PKG_MANAGER in
        apt)
          sudo apt install curl -y
          sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
          echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
          sudo apt update
          sudo apt install brave-browser -y
          ;;
        dnf|yum)
          sudo $PKG_MANAGER install dnf-plugins-core -y
          sudo $PKG_MANAGER config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
          sudo $PKG_MANAGER makecache --refresh
          sudo $PKG_MANAGER install brave-browser -y
          ;;
        pacman)
          sudo pacman -S brave --noconfirm
          ;;
      esac
      echo "Brave successfully installed!"
      ;;
    5)
      echo "Installing Chromium..."
      case $PKG_MANAGER in
        apt) sudo apt install chromium-browser -y ;;
        dnf|yum) sudo $PKG_MANAGER install chromium -y ;;
        pacman) sudo pacman -S chromium --noconfirm ;;
      esac
      echo "Chromium successfully installed!"
      ;;
    6)
      echo "Installing Vivaldi..."
      case $PKG_MANAGER in
        apt) 
        sudo apt update
        wget https://downloads.vivaldi.com/stable/vivaldi-stable_8.1.4087.68-1_amd64.deb
        sudo dpkg -i vivaldi-stable_8.1.4087.68-1_amd64.deb
        sudo apt -f install -y ;;
        dnf|yum) 
          sudo $PKG_MANAGER install -y https://downloads.vivaldi.com/stable/vivaldi-stable_8.1.4087.68-1_amd64.rpm
          ;;
        pacman) sudo pacman -S vivaldi --noconfirm ;;
      esac
      echo "Vivaldi successfully installed!"
      ;;
    7)
      echo "Installing Zen Browser..."
      case $PKG_MANAGER in
        apt) curl -fsSL https://github.com/zen-browser/updates-server/raw/refs/heads/main/install.sh | $SHELL ;;
        dnf|yum) curl -fsSL https://github.com/zen-browser/updates-server/raw/refs/heads/main/install.sh | $SHELL ;;
        pacman) curl -fsSL https://github.com/zen-browser/updates-server/raw/refs/heads/main/install.sh | $SHELL ;;
      esac
      echo "Zen Browser successfully installed!"
      ;;
    8)
      echo "Installing Opera..."
      case $PKG_MANAGER in
        apt)
          # Download using official redirect URL and save directly to opera-stable.deb
          wget -O opera-stable.deb "https://download.opera.com/download/get/?partner=www&opsys=Linux&package=DEB"
          sudo apt update
          sudo dpkg -i opera-stable.deb
          sudo apt -f install -y
          rm -f opera-stable.deb
          rename_downloaded_pkg() {
    local pattern="$1"
    local target="$2"
    for file in $pattern; do
        if [ -f "$file" ]; then
            mv "$file" "$target"
            echo "Renamed '$file' -> '$target'"
            break
        fi
    done
}

# Usage:
rename_downloaded_pkg

          ;;
        dnf|yum)
          wget -O opera-stable.rpm "https://download.opera.com/download/get/?partner=www&opsys=Linux&package=RPM"
          sudo $PKG_MANAGER install -y opera-stable.rpm
          rm -f opera-stable.rpm

          rename_downloaded_pkg() {
    local pattern="$1"
    local target="$2"
    for file in $pattern; do
        if [ -f "$file" ]; then
            mv "$file" "$target"
            echo "Renamed '$file' -> '$target'"
            break
        fi
    done
}

# Usage:
rename_downloaded_pkg

          ;;
        pacman)
          sudo pacman -S opera --noconfirm
          ;;
      esac
      echo "Opera successfully installed!"
      ;;




    9)
      echo "Exiting..."
      exit 0
      ;;
    *)
      echo "Invalid choice. Please try again."
      ;;
  esac
done
