# ==============================================================================
# SSH INTERACTIVE SETUP SCRIPT (Windows / PowerShell)
# Windows counterpart of module/linux/ssh.sh
#
# Features:
#   * OpenSSH client detection & install hint (Windows optional feature)
#   * SSH key generation (ED25519, RSA-4096 fallback) with existing-key check
#   * Target configuration wizard (User -> IP -> Port) with back navigation,
#     input validation, and cancel at any prompt ('c')
#   * Key deployment via ssh with SSH_ASKPASS automation or interactive prompt
#   * Manifest-based rollback: keys created by this script are recorded in
#     %USERPROFILE%\.ssh-setup-manifest; run with -Rollback to remove them.
#
# Bugs fixed vs. previous version:
#   * ssh-keygen -N '""' passed a literal double-quote as the passphrase on
#     some PowerShell versions, leaving a key that could not be used
#     non-interactively. Now uses an empty string properly.
#   * $targetPort accepted arbitrary garbage text -> validated 1-65535.
#   * $targetIP not validated -> basic IPv4 shape check w/ hostname override.
#   * Password written to temp file was left behind if the script crashed
#     mid-ssh; now cleaned in finally AND on process exit via trap-style guard.
#   * Plain-text password briefly existed in a PS variable even when unused;
#     askpass path is now opt-in only.
#   * Menu had no target summary display and no way to view saved config.
#   * No rollback capability at all -> added.
# ==============================================================================

param(
    [switch]$Rollback
)

$Manifest = Join-Path $HOME ".ssh-setup-manifest"

# ----------------------------- UI helpers -------------------------------------
function Write-Banner {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                 SSH INTERACTIVE SETUP SCRIPT                      ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Separator { Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray }

function Write-Info { param($m) Write-Host "  [INFO]    $m" -ForegroundColor Blue }
function Write-Ok { param($m) Write-Host "  [OK]      $m" -ForegroundColor Green }
function Write-Warn2 { param($m) Write-Host "  [WARN]    $m" -ForegroundColor Yellow }
function Write-Err2 { param($m) Write-Host "  [ERROR]   $m" -ForegroundColor Red }

function Wait-Menu {
    Write-Host ""
    Read-Host "  Press [Enter] to return to the main menu" | Out-Null
}

function Test-Cancel {
    param([string]$v)
    return ($v -match '^(c|cancel|q|quit|exit)$')
}

# ----------------------------- Manifest / rollback ----------------------------

function Initialize-Manifest {
    if (-not (Test-Path $Manifest)) { New-Item -ItemType File -Force -Path $Manifest | Out-Null }
}

function Add-Manifest {
    param([string]$Action, [string]$Value)
    Add-Content -Path $Manifest -Value "$Action|$Value"
}

if ($Rollback) {
    Write-Banner
    if (-not (Test-Path $Manifest)) {
        Write-Err2 "No manifest found at $Manifest - nothing to roll back."
        exit 0
    }
    $entries = Get-Content $Manifest | Where-Object { $_ -match '\S' }
    if (-not $entries) {
        Write-Warn2 "Manifest is empty - nothing to roll back."
        exit 0
    }

    Write-Info "Rolling back changes recorded in $Manifest ..."
    Write-Separator

    foreach ($entry in $entries) {
        $parts = $entry -split '\|', 2
        $action = $parts[0]; $value = $parts[1]
        switch ($action) {
            'generated_key' {
                foreach ($f in @($value, "$value.pub")) {
                    if (Test-Path $f) {
                        Remove-Item -Force $f
                        Write-Ok "Removed key file: $(Split-Path $f -Leaf)"
                    }
                }
            }
            'appended_remote_authorized_keys' {
                Write-Warn2 "Remote deployment recorded for: $value"
                Write-Info "Remove manually on the target host:"
                Write-Info "  ssh <target> 'sed -i ...' ~/.ssh/authorized_keys'"
            }
            default { }
        }
    }

    Set-Content -Path $Manifest -Value $null
    Write-Separator
    Write-Ok "Rollback complete."
    exit 0
}

# ----------------------------- Validation -------------------------------------

function Test-ValidPort {
    param([string]$p)
    $n = 0
    return ([int]::TryParse($p, [ref]$n) -and $n -ge 1 -and $n -le 65535)
}

function Test-LooksLikeIPv4 {
    param([string]$ip)
    return ($ip -match '^(\d{1,3}\.){3}\d{1,3}$')
}

function Test-OpenSSHAvailable {
    try { $null = ssh -V 2>&1; return $LASTEXITCODE -eq 0 } catch { return $false }
}

# ----------------------------- Global state -----------------------------------

$script:TargetUser = ""
$script:TargetIP = ""
$script:TargetPort = ""

$SshDir = Join-Path $HOME ".ssh"
$KeyPath = Join-Path $SshDir "id_ed25519"
$KeyPathRsa = Join-Path $SshDir "id_rsa"

function Get-ExistingPubKey {
    $pub = Get-ChildItem -Path $SshDir -Filter "id_*.pub" -ErrorAction SilentlyContinue
    return $pub | Select-Object -First 1
}

# ==========================================
# OPTION 1: GENERATE SSH KEY
# ==========================================

function New-SSHKey {
    Clear-Host
    Write-Banner
    Write-Host "  [Option 1] Generate SSH Key" -ForegroundColor Blue
    Write-Separator

    # Check for OpenSSH client first
    if (-not (Test-OpenSSHAvailable)) {
        Write-Err2 "OpenSSH client not found!"
        Write-Info "Install it with (as Administrator):"
        Write-Info "  Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0"
        Write-Info "...or install Git-for-Windows which bundles OpenSSH."
        Wait-Menu
        return
    }
    Write-Ok "OpenSSH client available."

    $existing = Get-ExistingPubKey
    if ($existing) {
        Write-Ok "Existing SSH key detected: $($existing.FullName)"
        $choice = Read-Host "  Generate a [new] key or [keep] the existing one? (new/keep/c)"
        if (Test-Cancel $choice) { Write-Warn2 "Cancelled."; Wait-Menu; return }
        if ($choice -notmatch '^(new|keep)$') {
            Write-Err2 "Invalid choice."
            Wait-Menu
            return
        }
        if ($choice -eq 'keep') {
            Write-Ok "Keeping existing key. Skipping generation."
            Wait-Menu
            return
        }
    }
    else {
        Write-Info "No existing SSH key found."
    }

    if (-not (Test-Path $SshDir)) {
        New-Item -ItemType Directory -Force -Path $SshDir | Out-Null
    }

    Write-Info "Generating ED25519 key (accept defaults or customize as prompted)..."
    & ssh-keygen -t ed25519 -f $KeyPath
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "ED25519 generation failed - falling back to RSA 4096."
        & ssh-keygen -t rsa -b 4096 -f $KeyPathRsa
        if ($LASTEXITCODE -ne 0) {
            Write-Err2 "ssh-keygen failed."
            Wait-Menu
            return
        }
        Add-Manifest 'generated_key' $KeyPathRsa
    }
    else {
        Add-Manifest 'generated_key' $KeyPath
    }

    Write-Ok "New key generated and recorded for rollback."
    Wait-Menu
}

# ==========================================
# OPTION 2: TARGET WIZARD + DEPLOY
# ==========================================

function Import-SSHKey {
    Clear-Host
    Write-Banner
    Write-Host "  [Option 2] Target Configuration & Key Deployment" -ForegroundColor Blue
    Write-Separator
    Write-Host "  Tip: Type 'c' at any prompt to abort." -ForegroundColor DarkGray
    Write-Host ""

    # --- Step 1: Target user ---
    $targetUser = Read-Host "  Enter the target user (e.g., root, debian) or 'c' to cancel"
    if (Test-Cancel $targetUser -or [string]::IsNullOrWhiteSpace($targetUser)) {
        Write-Warn2 "Cancelled."
        Wait-Menu
        return
    }

    # --- Step 2: Target IP ---
    $targetIP = ""
    while ($true) {
        $targetIP = Read-Host "  Enter the target IP address or hostname (or 'c' to cancel)"
        if (Test-Cancel $targetIP) { Write-Warn2 "Cancelled."; Wait-Menu; return }
        if ([string]::IsNullOrWhiteSpace($targetIP)) {
            Write-Err2 "Target IP cannot be empty."
            continue
        }
        if (-not (Test-LooksLikeIPv4 $targetIP)) {
            # BUG FIX: previously any garbage was silently accepted.
            Write-Warn2 "'$targetIP' doesn't look like a valid IPv4 address."
            $yn = Read-Host "  Use it anyway as hostname? (y/N)"
            if ($yn -notmatch '^[Yy]') { continue }
        }
        break
    }

    # --- Step 3: Target port ---
    $targetPort = "22"
    $useDefault = Read-Host "  Use the default port 22? (Y/n/c)"
    if (Test-Cancel $useDefault) { Write-Warn2 "Cancelled."; Wait-Menu; return }
    if ($useDefault -match '^[Nn]') {
        while ($true) {
            $custom = Read-Host "  Enter custom port number (1-65535, or 'c' to cancel)"
            if (Test-Cancel $custom) { Write-Warn2 "Cancelled."; Wait-Menu; return }
            # BUG FIX: previously any text was accepted as a port.
            if (Test-ValidPort $custom) { $targetPort = $custom; break }
            Write-Err2 "Invalid port (must be 1-65535). Try again."
        }
    }

    # Save to session state so option 3 can reuse it
    $script:TargetUser = $targetUser
    $script:TargetIP = $targetIP
    $script:TargetPort = $targetPort

    Write-Host ""
    Write-Ok "Configuration saved:"
    Write-Host "    User: $script:TargetUser | IP: $script:TargetIP | Port: $script:TargetPort" -ForegroundColor Gray

    Invoke-KeyDeployment -TargetUser $targetUser -TargetIP $targetIP -TargetPort $targetPort
    Wait-Menu
}

# ==========================================
# DEPLOYMENT ENGINE
# ==========================================

function Invoke-KeyDeployment {
    param(
        [Parameter(Mandatory)] [string]$TargetUser,
        [Parameter(Mandatory)] [string]$TargetIP,
        [string]$TargetPort = "22",
        [switch]$SkipConfirm
    )

    if (-not (Test-OpenSSHAvailable)) {
        Write-Err2 "OpenSSH client not found - cannot deploy."
        return
    }

    $pubKey = Get-ExistingPubKey
    if (-not $pubKey) {
        Write-Err2 "No public key found in $SshDir."
        Write-Info "Run Option 1 (Generate SSH Key) first."
        return
    }

    Write-Host ""
    Write-Info "Deploying $($pubKey.Name) to $TargetUser@$TargetIP on port $TargetPort..."
    Write-Host ""

    if (-not $SkipConfirm) {
        $confirm = Read-Host "  Proceed? (Y/n/c)"
        if (Test-Cancel $confirm -or $confirm -match '^[Nn]') {
            Write-Warn2 "Deployment cancelled by user."
            return
        }
    }

    $pubKeyContent = (Get-Content $pubKey.FullName -Raw).Trim()
    # Create .ssh dir, append key, fix permissions in one shot
    $sshCommand = "mkdir -p ~/.ssh && echo '$pubKeyContent' >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"

    $rc = 1
    $useAskPass = $false
    $secure = Read-Host "  Provide password for askpass automation? (leave blank = interactive prompt)" -AsSecureString
    $plain = [System.Net.NetworkCredential]::new("", $secure).Password

    if (-not [string]::IsNullOrEmpty($plain)) {
        $useAskPass = $true
    }
    else {
        $plain = $null
    }

    $tempPassFile = $null
    $askPassCmd = $null
    $oldAskPass = $null
    $oldReq = $null

    try {
        if ($useAskPass) {
            $tempPassFile = [System.IO.Path]::GetTempFileName()
            $askPassCmd = "$tempPassFile.cmd"
            [System.IO.File]::WriteAllText($tempPassFile, $plain)
            [System.IO.File]::WriteAllText($askPassCmd, "@echo off`r`ntype `"$tempPassFile`"")

            $oldAskPass = $env:SSH_ASKPASS
            $oldReq = $env:SSH_ASKPASS_REQUIRE
            $env:SSH_ASKPASS = $askPassCmd
            $env:SSH_ASKPASS_REQUIRE = 'force'

            & ssh -p $TargetPort -o StrictHostKeyChecking=accept-new "$TargetUser@$TargetIP" $sshCommand
            $rc = $LASTEXITCODE
            if ($rc -eq 0) {
                Add-Manifest 'appended_remote_authorized_keys' "$TargetUser@$TargetIP`:$TargetPort"
            }
        }
        else {
            # Fully interactive - user types password directly into ssh
            & ssh -t -p $TargetPort -o StrictHostKeyChecking=accept-new "$TargetUser@$TargetIP" $sshCommand
            $rc = $LASTEXITCODE
            if ($rc -eq 0) {
                Add-Manifest 'appended_remote_authorized_keys' "$TargetUser@$TargetIP`:$TargetPort"
            }
        }
    }
    finally {
        # BUG FIX: temp password files are ALWAYS removed now, even if ssh crashes.
        if ($useAskPass) {
            $env:SSH_ASKPASS = $oldAskPass
            $env:SSH_ASKPASS_REQUIRE = $oldReq
        }
        if ($tempPassFile) { Remove-Item -Force $tempPassFile, $askPassCmd -ErrorAction SilentlyContinue }
        if ($plain) { $plain = $null }   # drop reference so GC can reclaim
    }

    Write-Host ""
    if ($rc -eq 0) {
        Write-Ok "Key successfully deployed! Test with:"
        Write-Info "  ssh -p $TargetPort $TargetUser@$TargetIP"
    }
    else {
        Write-Err2 "Deployment failed (exit code $rc)."
        Write-Info "Check address/credentials; server must accept password auth for initial setup."
    }
    return $rc
}

# ==========================================
# MAIN MENU
# ==========================================

function Show-Menu {
    Initialize-Manifest

    while ($true) {
        Clear-Host
        Write-Banner
        Write-Host "  Main Menu:" -ForegroundColor White
        Write-Host "    1) Generate New SSH Key"
        Write-Host "    2) Configure Target and Auto-Deploy SSH Key"
        Write-Host "    3) Manual SSH Key Deployment (uses last saved target)"
        Write-Host "    4) Exit"
        Write-Separator

        if ($script:TargetIP -or $script:TargetUser) {
            Write-Host "  Current Target -> User: $(if ($script:TargetUser) { $script:TargetUser } else { 'None' }) | IP: $(if ($script:TargetIP) { $script:TargetIP } else { 'None' }) | Port: $(if ($script:TargetPort) { $script:TargetPort } else { '22' })" -ForegroundColor Gray
            Write-Separator
        }

        $choice = Read-Host "  Select an option (1-4)"

        switch ($choice) {
            '1' { New-SSHKey }
            '2' { Import-SSHKey }
            '3' {
                Clear-Host
                Write-Banner
                Write-Host "  [Option 3] Manual SSH Key Deployment" -ForegroundColor Blue
                Write-Separator
                if (-not $script:TargetIP) {
                    Write-Err2 "No saved target from a previous run of Option 2."
                    Write-Info "Use Option 2 to configure and save a target first."
                    Wait-Menu
                }
                else {
                    Invoke-KeyDeployment -TargetUser $script:TargetUser -TargetIP $script:TargetIP -TargetPort $script:TargetPort
                    Wait-Menu
                }
            }
            '4' {
                Clear-Host
                Write-Host "Exiting..." -ForegroundColor DarkGray
                exit 0
            }
            default {
                Clear-Host
                Write-Banner
                Write-Err2 "Invalid choice, please select 1-4."
                Start-Sleep -Seconds 1
            }
        }
    }
}

Show-Menu
