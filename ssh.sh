#!/bin/bash

# Global variables to store the target configuration
TARGET_HOST=""
TARGET_IP=""
TARGET_USER=""
TARGET_PORT=""

# ==========================================
# CORE FUNCTION: Package Manager & SSH Keygen
# ==========================================
run_core_function() {
  clear
  echo "=== Detecting package manager ==="

  PKG_MANAGERS=()

  command -v apt >/dev/null 2>&1 && PKG_MANAGERS+=("apt")
  command -v dnf >/dev/null 2>&1 && PKG_MANAGERS+=("dnf")
  command -v yum >/dev/null 2>&1 && PKG_MANAGERS+=("yum")
  command -v pacman >/dev/null 2>&1 && PKG_MANAGERS+=("pacman")
  command -v zypper >/dev/null 2>&1 && PKG_MANAGERS+=("zypper")

  if [ ${#PKG_MANAGERS[@]} -eq 0 ]; then
    echo "No supported package manager found."
    echo "Press [Enter] to return to Main Menu..."
    read
    return 1
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

  echo ""
  echo "==== SSH-KEY CHECKER ===="
  # Check if any public keys already exist in the .ssh directory
  if ls ~/.ssh/id_*.pub 1> /dev/null 2>&1; then
    echo "Existing SSH key(s) detected in ~/.ssh/"
    while true; do
      read -p "Do you want to generate a [new] key or [keep] the existing one? (new/keep): " key_choice
      if [[ "$key_choice" == "new" ]]; then
        echo "==== SSH-KEYGEN STARTED ===="
        ssh-keygen
        break
      elif [[ "$key_choice" == "keep" ]]; then
        echo "Keeping the existing SSH key. Skipping generation."
        break
      else
        echo "Invalid choice. Please type 'new' or 'keep'."
      fi
    done
  else
    echo "No existing SSH key found."
    echo "==== SSH-KEYGEN STARTED ===="
    ssh-keygen
  fi
  
  echo ""
  echo "Press [Enter] to return to Main Menu..."
  read
}

# ==========================================
# DEPLOY SSH KEY TO TARGET
# ==========================================
deploy_ssh_key() {
  clear
  echo "=== Deploy SSH Key to Target ==="
  
  # Check if a target is configured
  if [ -z "$TARGET_IP" ] && [ -z "$TARGET_HOST" ]; then
    echo "Error: No target configured!"
    echo "Please configure the Target first (Main Menu Option 2)."
    echo ""
    echo "Press [Enter] to return to Main Menu..."
    read
    return
  fi

  # Check if an SSH key actually exists before trying to copy
  if ! ls ~/.ssh/id_*.pub 1> /dev/null 2>&1; then
    echo "Error: No SSH key found on this system!"
    echo "Please run the Core Setup (Main Menu Option 1) to generate a key first."
    echo ""
    echo "Press [Enter] to return to Main Menu..."
    read
    return
  fi

  # Prefer IP if provided, otherwise fallback to Hostname
  local target_address="${TARGET_IP:-$TARGET_HOST}"
  
  # Prefer configured Target User, otherwise fallback to current system user
  local ssh_user="${TARGET_USER:-$USER}"

  # Prefer configured Target Port, otherwise default to 22
  local ssh_port="${TARGET_PORT:-22}"

  echo "Target Address : $target_address"
  echo "Target Username: $ssh_user"
  echo "Target Port    : $ssh_port"
  echo ""
  echo "Attempting to copy SSH key to $ssh_user@$target_address on port $ssh_port..."
  echo "Note: You may be prompted for the remote user's password."
  echo "--------------------------------------------------------"

  # Use ssh-copy-id if available, fallback to manual pipe if not
  if command -v ssh-copy-id >/dev/null 2>&1; then
    ssh-copy-id -p "$ssh_port" "$ssh_user@$target_address"
  else
    echo "[!] ssh-copy-id not found. Attempting manual copy..."
    # Grabs the public key and appends it to authorized_keys on the remote server safely using the custom port
    cat ~/.ssh/id_*.pub | ssh -p "$ssh_port" "$ssh_user@$target_address" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
  fi

  echo "--------------------------------------------------------"
  echo "Deployment attempt finished."
  echo "Press [Enter] to return to Main Menu..."
  read
}

# ==========================================
# TARGET CONFIGURATION WIZARD
# ==========================================
configure_target() {
  local step=1
  
  while true; do
    clear
    echo "=== Target Configuration Wizard ==="
    
    # STEP 1: TARGET HOST
    if [ $step -eq 1 ]; then
      echo "--- Step 1: Target Host ---"
      echo "Current Target Host: ${TARGET_HOST:-[Not Set]}"
      echo ""
      echo "Options:"
      echo "  1) Input/Change Target Host"
      echo "  2) Next Step (Target IP)"
      echo "  3) Cancel & Return to Main Menu"
      read -p "Select an option [1-3]: " choice
      
      case $choice in
        1) read -p "Enter Target Hostname: " TARGET_HOST ;;
        2) step=2 ;;
        3) return ;; # Returns to Main Menu
        *) echo "Invalid selection." ; sleep 1 ;;
      esac
      
    # STEP 2: TARGET IP
    elif [ $step -eq 2 ]; then
      echo "--- Step 2: Target IP ---"
      echo "Current Target IP: ${TARGET_IP:-[Not Set]}"
      echo ""
      echo "Options:"
      echo "  1) Input/Change Target IP"
      echo "  2) Previous Step (Back to Host)"
      echo "  3) Next Step (Target Username)"
      echo "  4) Cancel & Return to Main Menu"
      read -p "Select an option [1-4]: " choice
      
      case $choice in
        1) read -p "Enter Target IP: " TARGET_IP ;;
        2) step=1 ;;
        3) step=3 ;;
        4) return ;;
        *) echo "Invalid selection." ; sleep 1 ;;
      esac

    # STEP 3: TARGET USERNAME
    elif [ $step -eq 3 ]; then
      echo "--- Step 3: Target Username ---"
      echo "Current Target Username: ${TARGET_USER:-[Not Set]}"
      echo ""
      echo "Options:"
      echo "  1) Input/Change Target Username"
      echo "  2) Previous Step (Back to IP)"
      echo "  3) Next Step (Target Port)"
      echo "  4) Cancel & Return to Main Menu"
      read -p "Select an option [1-4]: " choice
      
      case $choice in
        1) read -p "Enter Target Username: " TARGET_USER ;;
        2) step=2 ;;
        3) step=4 ;;
        4) return ;;
        *) echo "Invalid selection." ; sleep 1 ;;
      esac
      
    # STEP 4: TARGET PORT
    elif [ $step -eq 4 ]; then
      echo "--- Step 4: Target Port ---"
      echo "Current Target Port: ${TARGET_PORT:-22 (Default)}"
      echo ""
      echo "Are you using the default SSH port (22) or a different port?"
      echo "Options:"
      echo "  1) Use Default Port (22)"
      echo "  2) Input Custom Port"
      echo "  3) Previous Step (Back to Username)"
      echo "  4) Finish & Automatically Export SSH Key"
      echo "  5) Cancel & Return to Main Menu"
      read -p "Select an option [1-5]: " choice
      
      case $choice in
        1) TARGET_PORT=22 ;;
        2) read -p "Enter Custom Target Port: " TARGET_PORT ;;
        3) step=3 ;;
        4) 
          echo ""
          echo "Configuration saved!"
          echo "Host: $TARGET_HOST | IP: $TARGET_IP | User: $TARGET_USER | Port: ${TARGET_PORT:-22}"
          sleep 2
          # Automatically export the key to the target
          deploy_ssh_key
          return 
          ;;
        5) return ;;
        *) echo "Invalid selection." ; sleep 1 ;;
      esac
    fi
  done
}

# ==========================================
# MAIN MENU LOOP
# ==========================================
while true; do
  clear
  echo "====================================="
  echo "         MAIN SETUP SCRIPT           "
  echo "====================================="
  echo "1. Run Core Setup (Package Manager & SSH-Keygen)"
  echo "2. Configure Target and Auto-Export SSH Key"
  echo "3. Manual SSH Key Export"
  echo "4. Exit"
  echo "====================================="
  
  # Display current target info if it has been set
  if [ -n "$TARGET_HOST" ] || [ -n "$TARGET_IP" ] || [ -n "$TARGET_USER" ] || [ -n "$TARGET_PORT" ]; then
    echo "Current Target -> Host: ${TARGET_HOST:-None} | IP: ${TARGET_IP:-None} | User: ${TARGET_USER:-None} | Port: ${TARGET_PORT:-22}"
    echo "====================================="
  fi
  
  read -p "Please choose an option [1-4]: " main_choice
  
  case $main_choice in
    1) run_core_function ;;
    2) configure_target ;;
    3) deploy_ssh_key ;;
    4)
      echo "Exiting script. Goodbye!"
      exit 0
      ;;
    *)
      echo "Invalid option. Please select 1, 2, 3, or 4."
      sleep 1
      ;;
  esac
done