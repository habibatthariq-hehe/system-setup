#!/bin/bash

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


echo "==== SSH-KEYGEN STARTED ===="
ssh-keygen
sleep 3
echo "==== COPY SSH KEY TO SERVER ===="
ssh-copy-id -i ~/.ssh/id_ed25519.pub debian@192.168.1.65
echo "==== PROCESS COMPLETE ===="