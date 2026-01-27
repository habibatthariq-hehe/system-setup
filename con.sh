#!/bin/bash

echo "============================================================"
echo "REMINDER:"
echo "Check the network interface names BEFORE running this script."
echo "Make sure ens33 / ens34 are correct for this virtual machine."
echo "Edit the script if necessary to avoid misconfiguration."
echo "============================================================"
echo

# Save original state for rollback
ORIG_EXTERNAL=$(firewall-cmd --get-zone-of-interface=ens33 2>/dev/null)
ORIG_INTERNAL=$(firewall-cmd --get-zone-of-interface=ens34 2>/dev/null)

rollback() {
    echo "Error detected. Rolling back changes..."

    # Restore ens33
    if [ -n "$ORIG_EXTERNAL" ]; then
        firewall-cmd --permanent --zone="$ORIG_EXTERNAL" --add-interface=ens33
    else
        firewall-cmd --permanent --zone=external --remove-interface=ens33 2>/dev/null
    fi

    # Restore ens34
    if [ -n "$ORIG_INTERNAL" ]; then
        firewall-cmd --permanent --zone="$ORIG_INTERNAL" --add-interface=ens34
    else
        firewall-cmd --permanent --zone=internal --remove-interface=ens34 2>/dev/null
    fi

    firewall-cmd --reload
    echo "Rollback completed."
    exit 1
}

pause() {
    read -rp "Press Enter to continue..."
}

run() {
    "$@" || rollback
}

# ---- Script flow (unchanged logically) ----

run firewall-cmd --permanent --zone=external --add-interface=ens33
pause

run firewall-cmd --permanent --zone=internal --add-interface=ens34
pause

run firewall-cmd --reload
pause

run firewall-cmd --get-active-zones
pause

# Enable NAT (Masquerade) on Internet Interface
run firewall-cmd --permanent --zone=external --add-masquerade
pause

run firewall-cmd --reload
pause

# Allow Internal Services to Pass Through Firewall

# Allow SSH
run firewall-cmd --permanent --zone=external --add-service=ssh
pause
run firewall-cmd --reload

# Allow DNS Service
run firewall-cmd --permanent --zone=internal --add-service=dns
pause

# Allow HTTP
run firewall-cmd --permanent --zone=internal --add-service=http
pause

run firewall-cmd --permanent --zone=internal --add-service=https
pause

# Reload
run echo "Reload To Save Change"
pause
run firewall-cmd --reload
pause
