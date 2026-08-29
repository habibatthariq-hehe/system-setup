# ==============================================================================
# WINDOWS AUTOMATION & MANAGEMENT CLI
# Main interactive menu for Windows subsystem in system-setup suite.
# Windows counterpart of module/linux/main-linux.sh
# ==============================================================================

[CmdletBinding()]
param(
    [switch]$NoBanner
)

# Ensure UTF-8 Console Output
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# ----------------------------- UI Colors & Helper Functions --------------------
function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║             WINDOWS SYSTEM SETUP & MANAGEMENT CLI                 ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $isAdmin = Test-IsAdmin
    $adminStatus = if ($isAdmin) { "ELEVATED (Admin)" } else { "STANDARD (Non-Admin)" }
    $adminColor  = if ($isAdmin) { "Green" } else { "Yellow" }
    
    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $osName = if ($osInfo) { $osInfo.Caption } else { [System.Environment]::OSVersion.VersionString }
    $arch   = [System.Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITECTURE")
    
    Write-Host "  OS: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$osName ($arch)" -NoNewline -ForegroundColor White
    Write-Host "  |  Host: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($env:COMPUTERNAME)" -NoNewline -ForegroundColor White
    Write-Host "  |  Privilege: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$adminStatus" -ForegroundColor $adminColor
    Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Separator {
    Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
}

function Write-Section {
    param([string]$Title)
    Write-Host "┌── [ $Title ]" -ForegroundColor Blue
}

function Write-MenuItem {
    param(
        [string]$Key,
        [string]$Label,
        [string]$Subtext = ""
    )
    $paddedKey = $Key.PadLeft(2)
    Write-Host "│  " -NoNewline -ForegroundColor Blue
    Write-Host $paddedKey -NoNewline -ForegroundColor Cyan
    Write-Host " ❯ " -NoNewline -ForegroundColor DarkGray
    Write-Host $Label -NoNewline -ForegroundColor White
    if ($Subtext -ne "") {
        Write-Host " ($Subtext)" -ForegroundColor DarkCyan
    } else {
        Write-Host ""
    }
}

function Write-MenuFooter {
    Write-Host "└───────────────────────────────────────────────────────────────────" -ForegroundColor Blue
}

function Write-Info    { param([string]$m) Write-Host "  [INFO]    $m" -ForegroundColor Cyan }
function Write-Ok      { param([string]$m) Write-Host "  [OK]      $m" -ForegroundColor Green }
function Write-Warn2   { param([string]$m) Write-Host "  [WARN]    $m" -ForegroundColor Yellow }
function Write-Err2    { param([string]$m) Write-Host "  [ERROR]   $m" -ForegroundColor Red }

function Wait-Menu {
    Write-Host ""
    Write-Host "  Press [Enter] to return to the main menu..." -ForegroundColor DarkGray -NoNewline
    [void][System.Console]::ReadLine()
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Cancel {
    param([string]$v)
    if ($v -match '^(c|cancel|q|quit|exit|0)$') {
        return $true
    }
    return $false
}

# ----------------------------- Script Dispatcher ------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-SubScript {
    param(
        [string]$RelativePath,
        [string]$Description,
        [string[]]$ScriptArgs = @()
    )
    $targetPath = Join-Path $ScriptDir $RelativePath
    if (-not (Test-Path $targetPath)) {
        Write-Err2 "Target script not found: $RelativePath"
        Write-Warn2 "Expected location: $targetPath"
        Wait-Menu
        return
    }

    Write-Info "Launching $Description..."
    Write-Separator
    try {
        & $targetPath @ScriptArgs
    } catch {
        Write-Err2 "Error executing script: $_"
    }
    Wait-Menu
}

# ----------------------------- Feature Modules --------------------------------

# 1. OpenSSH Server & Client Manager
function Show-OpenSSHManager {
    Write-Banner
    Write-Host "=== OpenSSH Windows Feature & Service Manager ===" -ForegroundColor Cyan
    Write-Host ""

    $clientCap = Get-WindowsCapability -Online -Name "OpenSSH.Client~~~~0.0.1.0" -ErrorAction SilentlyContinue
    $serverCap = Get-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" -ErrorAction SilentlyContinue
    
    $clientStatus = if ($clientCap) { $clientCap.State } else { "Not installed / Unknown" }
    $serverStatus = if ($serverCap) { $serverCap.State } else { "Not installed / Unknown" }
    
    $sshdService = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
    $agentService = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
    
    Write-Host "  OpenSSH Client Capability : " -NoNewline
    Write-Host "$clientStatus" -ForegroundColor (if ($clientStatus -eq 'Installed') { 'Green' } else { 'Yellow' })
    
    Write-Host "  OpenSSH Server Capability : " -NoNewline
    Write-Host "$serverStatus" -ForegroundColor (if ($serverStatus -eq 'Installed') { 'Green' } else { 'Yellow' })
    
    if ($sshdService) {
        Write-Host "  sshd Service Status       : " -NoNewline
        Write-Host "$($sshdService.Status) (Startup: $($sshdService.StartType))" -ForegroundColor (if ($sshdService.Status -eq 'Running') { 'Green' } else { 'Yellow' })
    }
    
    if ($agentService) {
        Write-Host "  ssh-agent Service Status  : " -NoNewline
        Write-Host "$($agentService.Status) (Startup: $($agentService.StartType))" -ForegroundColor (if ($agentService.Status -eq 'Running') { 'Green' } else { 'Yellow' })
    }

    Write-Separator
    Write-Host "  Actions:"
    Write-Host "    1) Install OpenSSH Client"
    Write-Host "    2) Install OpenSSH Server"
    Write-Host "    3) Start and Enable 'sshd' Service (Port 22)"
    Write-Host "    4) Start and Enable 'ssh-agent' Service"
    Write-Host "    5) Configure SSH Windows Defender Firewall Rule"
    Write-Host "    0) Back to Main Menu"
    Write-Separator
    
    $choice = Read-Host "  Select an option [0-5]"
    if ($choice -eq '0' -or (Test-Cancel $choice)) { return }

    if (-not (Test-IsAdmin)) {
        Write-Warn2 "Managing Windows capabilities and services requires Administrator privileges."
        Write-Warn2 "Please run the script as Administrator."
        Wait-Menu
        return
    }

    switch ($choice) {
        '1' {
            Write-Info "Installing OpenSSH Client..."
            Add-WindowsCapability -Online -Name "OpenSSH.Client~~~~0.0.1.0"
            Write-Ok "OpenSSH Client installation completed."
        }
        '2' {
            Write-Info "Installing OpenSSH Server..."
            Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0"
            Write-Ok "OpenSSH Server capability installed."
        }
        '3' {
            Write-Info "Configuring sshd service..."
            Set-Service -Name "sshd" -StartupType Automatic
            Start-Service -Name "sshd"
            Write-Ok "sshd service is now running and set to Automatic startup."
        }
        '4' {
            Write-Info "Configuring ssh-agent service..."
            Set-Service -Name "ssh-agent" -StartupType Automatic
            Start-Service -Name "ssh-agent"
            Write-Ok "ssh-agent service is running and set to Automatic startup."
        }
        '5' {
            Write-Info "Configuring Windows Firewall rule for SSH (Port 22 TCP)..."
            $ruleName = "OpenSSH-Server-In-TCP"
            $existing = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
            if (-not $existing) {
                New-NetFirewallRule -Name $ruleName -DisplayName "OpenSSH SSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
                Write-Ok "Firewall rule created for inbound Port 22."
            } else {
                Enable-NetFirewallRule -Name $ruleName
                Write-Ok "Existing OpenSSH firewall rule enabled."
            }
        }
        Default {
            Write-Warn2 "Invalid selection."
        }
    }
    Wait-Menu
}

# 2. Network & IP Information
function Show-NetworkDiagnostics {
    Write-Banner
    Write-Host "=== Windows Network Diagnostics & Interfaces ===" -ForegroundColor Cyan
    Write-Host ""
    
    $adapters = Get-NetIPConfiguration | Where-Object { $_.IPv4Address -ne $null }
    foreach ($adapter in $adapters) {
        Write-Host "  Interface  : " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($adapter.InterfaceAlias) ($($adapter.InterfaceDescription))" -ForegroundColor Cyan
        Write-Host "  Status     : " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($adapter.NetAdapter.Status)" -ForegroundColor (if ($adapter.NetAdapter.Status -eq 'Up') { 'Green' } else { 'Yellow' })
        Write-Host "  IPv4 Addr  : " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($adapter.IPv4Address.IPAddress)" -ForegroundColor White
        Write-Host "  Gateway    : " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($adapter.IPv4DefaultGateway.NextHop)" -ForegroundColor White
        Write-Host "  DNS Servers: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($adapter.DNSServer.ServerAddresses -join ', ')" -ForegroundColor White
        Write-Host "  MAC Addr   : " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($adapter.NetAdapter.MacAddress)" -ForegroundColor DarkCyan
        Write-Separator
    }

    Write-Host "  Actions:"
    Write-Host "    1) Test Ping to Host/IP"
    Write-Host "    2) Test TCP Port Connectivity (Test-NetConnection)"
    Write-Host "    3) Flush DNS Resolver Cache"
    Write-Host "    0) Back to Main Menu"
    Write-Separator

    $choice = Read-Host "  Select an option [0-3]"
    if ($choice -eq '0' -or (Test-Cancel $choice)) { return }

    switch ($choice) {
        '1' {
            $target = Read-Host "  Enter IP or Hostname to ping (e.g. 1.1.1.1, google.com)"
            if (-not [string]::IsNullOrWhiteSpace($target)) {
                Write-Info "Pinging $target..."
                Test-Connection -ComputerName $target -Count 4
            }
        }
        '2' {
            $targetHost = Read-Host "  Enter Target Hostname or IP"
            $targetPort = Read-Host "  Enter Target Port (e.g. 22, 80, 443, 3389)"
            if ((-not [string]::IsNullOrWhiteSpace($targetHost)) -and ($targetPort -match '^\d+$')) {
                Write-Info "Testing TCP port $targetPort on $targetHost..."
                Test-NetConnection -ComputerName $targetHost -Port ([int]$targetPort)
            } else {
                Write-Warn2 "Invalid host or port."
            }
        }
        '3' {
            Write-Info "Flushing DNS resolver cache..."
            Clear-DnsClientCache
            Write-Ok "DNS client cache successfully flushed."
        }
        Default {
            Write-Warn2 "Invalid choice."
        }
    }
    Wait-Menu
}

# 3. Windows Firewall Quick Manager
function Show-FirewallManager {
    Write-Banner
    Write-Host "=== Windows Defender Firewall Quick Manager ===" -ForegroundColor Cyan
    Write-Host ""
    
    $profiles = Get-NetFirewallProfile
    foreach ($p in $profiles) {
        Write-Host "  Profile: " -NoNewline -ForegroundColor DarkGray
        Write-Host ("{0,-10}" -f $p.Name) -NoNewline -ForegroundColor White
        Write-Host " State: " -NoNewline -ForegroundColor DarkGray
        $enabled = $p.Enabled
        Write-Host (if ($enabled) { "ENABLED" } else { "DISABLED" }) -ForegroundColor (if ($enabled) { "Green" } else { "Red" })
    }
    Write-Separator
    
    Write-Host "  Actions:"
    Write-Host "    1) Allow ICMPv4 (Ping Responder) Inbound"
    Write-Host "    2) Block ICMPv4 (Ping Responder) Inbound"
    Write-Host "    3) List Active Listening Ports (Get-NetTCPConnection)"
    Write-Host "    0) Back to Main Menu"
    Write-Separator
    
    $choice = Read-Host "  Select an option [0-3]"
    if ($choice -eq '0' -or (Test-Cancel $choice)) { return }

    if (($choice -in @('1','2')) -and (-not (Test-IsAdmin))) {
        Write-Warn2 "Modifying firewall rules requires Administrator privileges."
        Wait-Menu
        return
    }

    switch ($choice) {
        '1' {
            Write-Info "Enabling ICMPv4 Echo Request firewall rules..."
            Enable-NetFirewallRule -Name "FPS-ICMP4-ERQ-In" -ErrorAction SilentlyContinue
            Write-Ok "ICMPv4 Echo Request rule enabled (Host will now respond to ping)."
        }
        '2' {
            Write-Info "Disabling ICMPv4 Echo Request firewall rules..."
            Disable-NetFirewallRule -Name "FPS-ICMP4-ERQ-In" -ErrorAction SilentlyContinue
            Write-Ok "ICMPv4 Echo Request rule disabled."
        }
        '3' {
            Write-Info "Fetching TCP Listening Ports..."
            Get-NetTCPConnection -State Listen | 
                Select-Object LocalAddress, LocalPort, OwningProcess | 
                Sort-Object LocalPort | 
                Format-Table -AutoSize
        }
        Default {
            Write-Warn2 "Invalid choice."
        }
    }
    Wait-Menu
}

# 4. Winget Developer Package Installer
function Show-WingetInstaller {
    Write-Banner
    Write-Host "=== Windows Package Manager (Winget) Toolchain ===" -ForegroundColor Cyan
    Write-Host ""

    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $hasWinget) {
        Write-Err2 "winget (Windows Package Manager) is not found on this system."
        Write-Info "Install 'App Installer' from the Microsoft Store or GitHub releases."
        Wait-Menu
        return
    }

    $packages = @(
        @{ Key = "1"; Id = "Git.Git"; Name = "Git for Windows" },
        @{ Key = "2"; Id = "Microsoft.VisualStudioCode"; Name = "Visual Studio Code" },
        @{ Key = "3"; Id = "Microsoft.PowerShell"; Name = "PowerShell 7 (pwsh)" },
        @{ Key = "4"; Id = "Microsoft.WindowsTerminal"; Name = "Windows Terminal" },
        @{ Key = "5"; Id = "7zip.7zip"; Name = "7-Zip Archiver" },
        @{ Key = "6"; Id = "Microsoft.PowerToys"; Name = "Microsoft PowerToys" },
        @{ Key = "7"; Id = "Neovim.Neovim"; Name = "Neovim" },
        @{ Key = "8"; Id = "Docker.DockerDesktop"; Name = "Docker Desktop" },
        @{ Key = "9"; Id = "Python.Python.3.12"; Name = "Python 3.12" },
        @{ Key = "10"; Id = "NodeJS.NodeJS"; Name = "Node.js (LTS)" }
    )

    Write-Host "  Available Software Packages:"
    foreach ($pkg in $packages) {
        Write-Host ("   {0,2}) {1,-28} [{2}]" -f $pkg.Key, $pkg.Name, $pkg.Id) -ForegroundColor White
    }
    Write-Host "    A) Install ALL Developer Essentials (1-6)" -ForegroundColor Green
    Write-Host "    0) Back to Main Menu" -ForegroundColor DarkGray
    Write-Separator

    $choice = Read-Host "  Enter choice (e.g. 1, 2, or A)"
    if ($choice -eq '0' -or (Test-Cancel $choice)) { return }

    if ($choice.ToUpper() -eq 'A') {
        $selected = $packages[0..5]
    } else {
        $selected = $packages | Where-Object { $_.Key -eq $choice }
    }

    if (-not $selected) {
        Write-Warn2 "Invalid choice selected."
        Wait-Menu
        return
    }

    foreach ($item in $selected) {
        Write-Info "Installing $($item.Name) [$($item.Id)] via winget..."
        winget install --id $item.Id --exact --accept-source-agreements --accept-package-agreements -e
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "$($item.Name) installed successfully."
        } else {
            Write-Warn2 "winget returned code $LASTEXITCODE for $($item.Name)."
        }
        Write-Separator
    }
    Wait-Menu
}

# 5. Developer / Nerd Fonts Installer
function Show-FontInstaller {
    Write-Banner
    Write-Host "=== Developer & Nerd Fonts Installer ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Supported Fonts:"
    Write-Host "    1) Cascadia Code (Nerd Font)"
    Write-Host "    2) JetBrains Mono (Nerd Font)"
    Write-Host "    3) Fira Code (Nerd Font)"
    Write-Host "    4) Hack (Nerd Font)"
    Write-Host "    0) Back to Main Menu"
    Write-Separator

    $fontChoice = Read-Host "  Select a font to install [0-4]"
    if ($fontChoice -eq '0' -or (Test-Cancel $fontChoice)) { return }

    $fontUrls = @{
        '1' = @{ Name = "CascadiaCode"; Url = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip" }
        '2' = @{ Name = "JetBrainsMono"; Url = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" }
        '3' = @{ Name = "FiraCode"; Url = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" }
        '4' = @{ Name = "Hack"; Url = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip" }
    }

    $font = $fontUrls[$fontChoice]
    if (-not $font) {
        Write-Warn2 "Invalid selection."
        Wait-Menu
        return
    }

    $tempZip = Join-Path $env:TEMP "$($font.Name).zip"
    $tempDir = Join-Path $env:TEMP "$($font.Name)_extracted"

    try {
        Write-Info "Downloading $($font.Name) Nerd Font..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $font.Url -OutFile $tempZip -UseBasicParsing
        
        Write-Info "Extracting font archive..."
        if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
        Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force

        $fontFiles = Get-ChildItem -Path $tempDir -Filter "*.ttf" -Recurse
        $fontsFolder = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Fonts)
        $shellApp = New-Object -ComObject Shell.Application
        $targetFolder = $shellApp.Namespace(0x14)

        Write-Info "Registering $($fontFiles.Count) fonts in Windows..."
        foreach ($f in $fontFiles) {
            $destFile = Join-Path $fontsFolder $f.Name
            if (-not (Test-Path $destFile)) {
                $targetFolder.CopyHere($f.FullName, 0x10)
            }
        }
        Write-Ok "$($font.Name) installed successfully into Windows Fonts folder."
    } catch {
        Write-Err2 "Failed to install font: $_"
    } finally {
        if (Test-Path $tempZip) { Remove-Item -Force $tempZip -ErrorAction SilentlyContinue }
        if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue }
    }
    Wait-Menu
}

# 6. WSL (Windows Subsystem for Linux) Setup & Status
function Show-WSLManager {
    Write-Banner
    Write-Host "=== Windows Subsystem for Linux (WSL) Manager ===" -ForegroundColor Cyan
    Write-Host ""
    
    $hasWsl = Get-Command wsl -ErrorAction SilentlyContinue
    if (-not $hasWsl) {
        Write-Warn2 "WSL command is not found. WSL may not be enabled."
    } else {
        Write-Info "Installed WSL Distributions:"
        Write-Host ""
        wsl --list --verbose
        Write-Host ""
    }
    
    Write-Separator
    Write-Host "  Actions:"
    Write-Host "    1) Install / Update WSL Default Kernel (wsl --install / --update)"
    Write-Host "    2) Install Ubuntu Distribution (wsl --install -d Ubuntu)"
    Write-Host "    3) Install Debian Distribution (wsl --install -d Debian)"
    Write-Host "    4) Shutdown all running WSL instances (wsl --shutdown)"
    Write-Host "    0) Back to Main Menu"
    Write-Separator

    $choice = Read-Host "  Select an option [0-4]"
    if ($choice -eq '0' -or (Test-Cancel $choice)) { return }

    switch ($choice) {
        '1' {
            Write-Info "Updating WSL..."
            wsl --update
            Write-Ok "WSL update command finished."
        }
        '2' {
            Write-Info "Installing Ubuntu on WSL..."
            wsl --install -d Ubuntu
        }
        '3' {
            Write-Info "Installing Debian on WSL..."
            wsl --install -d Debian
        }
        '4' {
            Write-Info "Shutting down WSL instances..."
            wsl --shutdown
            Write-Ok "All WSL instances stopped."
        }
        Default {
            Write-Warn2 "Invalid choice."
        }
    }
    Wait-Menu
}

# 7. System Health & Performance Monitor
function Show-SystemHealth {
    Write-Banner
    Write-Host "=== System Health & Resource Monitor ===" -ForegroundColor Cyan
    Write-Host ""

    # CPU Usage
    $cpu = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
    $cpuLoad = [Math]::Round($cpu.Average, 1)

    # Memory Usage
    $os = Get-CimInstance Win32_OperatingSystem
    $totalRamMB = [Math]::Round($os.TotalVisibleMemorySize / 1KB, 1)
    $freeRamMB  = [Math]::Round($os.FreePhysicalMemory / 1KB, 1)
    $usedRamMB  = [Math]::Round($totalRamMB - $freeRamMB, 1)
    $ramPercent = [Math]::Round(($usedRamMB / $totalRamMB) * 100, 1)

    # Uptime
    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeStr = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes

    Write-Host "  CPU Average Load  : " -NoNewline
    Write-Host "$cpuLoad %" -ForegroundColor (if ($cpuLoad -gt 85) { 'Red' } elseif ($cpuLoad -gt 50) { 'Yellow' } else { 'Green' })

    Write-Host "  RAM Usage         : " -NoNewline
    Write-Host "$usedRamMB MB / $totalRamMB MB ($ramPercent %)" -ForegroundColor (if ($ramPercent -gt 85) { 'Red' } elseif ($ramPercent -gt 60) { 'Yellow' } else { 'Green' })

    Write-Host "  System Uptime     : " -NoNewline
    Write-Host "$uptimeStr (Boot: $($os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')))" -ForegroundColor Cyan
    Write-Separator

    # Disk Space
    Write-Host "  Disk Volumes:" -ForegroundColor White
    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    foreach ($d in $disks) {
        $totalGB = [Math]::Round($d.Size / 1GB, 1)
        $freeGB  = [Math]::Round($d.FreeSpace / 1GB, 1)
        $usedGB  = [Math]::Round($totalGB - $freeGB, 1)
        $pctFree = [Math]::Round(($freeGB / $totalGB) * 100, 1)
        
        Write-Host ("    Drive {0,-3} : {1,6} GB Free / {2,6} GB Total ({3,4}% free)" -f $d.DeviceID, $freeGB, $totalGB, $pctFree) -ForegroundColor (if ($pctFree -lt 15) { 'Red' } else { 'DarkCyan' })
    }
    Write-Separator

    # Top CPU Processes
    Write-Host "  Top 5 CPU-Consuming Processes:" -ForegroundColor White
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 Id, ProcessName, @{Name="CPU(s)"; Expression={[Math]::Round($_.CPU, 1)}}, @{Name="RAM(MB)"; Expression={[Math]::Round($_.WorkingSet64 / 1MB, 1)}} | Format-Table -AutoSize

    Wait-Menu
}

# 8. Windows System Maintenance (Cleanup & SFC/DISM)
function Show-SystemMaintenance {
    Write-Banner
    Write-Host "=== Windows Quick Maintenance & Health Checks ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Actions:"
    Write-Host "    1) Purge User & System Temp Directories"
    Write-Host "    2) Flush DNS Resolver Cache & Reset Winsock"
    Write-Host "    3) Run System File Checker (sfc /scannow)"
    Write-Host "    4) Run DISM Component Store Health Check"
    Write-Host "    0) Back to Main Menu"
    Write-Separator

    $choice = Read-Host "  Select an option [0-4]"
    if ($choice -eq '0' -or (Test-Cancel $choice)) { return }

    if (($choice -in @('2','3','4')) -and (-not (Test-IsAdmin))) {
        Write-Warn2 "This maintenance action requires Administrator privileges."
        Wait-Menu
        return
    }

    switch ($choice) {
        '1' {
            Write-Info "Cleaning user temporary files ($env:TEMP)..."
            Get-ChildItem -Path $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue | 
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Ok "Temporary directory cleanup complete."
        }
        '2' {
            Write-Info "Flushing DNS cache and resetting TCP/IP stack..."
            Clear-DnsClientCache
            ipconfig /flushdns
            netsh winsock reset
            Write-Ok "Network cache reset complete (Restart may be required for full effect)."
        }
        '3' {
            Write-Info "Starting System File Checker (sfc /scannow)..."
            sfc /scannow
        }
        '4' {
            Write-Info "Checking Windows Component Store with DISM..."
            DISM.exe /Online /Cleanup-Image /ScanHealth
        }
        Default {
            Write-Warn2 "Invalid choice."
        }
    }
    Wait-Menu
}

# 9. Relaunch as Administrator
function Relaunch-AsAdmin {
    if (Test-IsAdmin) {
        Write-Ok "Already running with elevated Administrator privileges."
        Start-Sleep -Seconds 1
        return
    }

    Write-Info "Requesting elevation to Administrator..."
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit", "-ExecutionPolicy Bypass", "-File `"$scriptPath`""
    exit 0
}

# ==============================================================================
# MAIN EVENT LOOP
# ==============================================================================

while ($true) {
    Write-Banner

    Write-Section "TOOLS & REMOTE ACCESS"
    Write-MenuItem "1"  "SSH Interactive Setup Wizard" "Keygen, Deploy & Manage"
    Write-MenuItem "2"  "SSH Setup Rollback"           "Remove Generated Keys & Config"
    Write-MenuItem "3"  "OpenSSH Server & Client"      "Manage Windows SSH Services"

    Write-Section "NETWORK & FIREWALL"
    Write-MenuItem "4"  "Network Diagnostics & Info"   "Adapters, IPs, Ping, Ports"
    Write-MenuItem "5"  "Windows Firewall Manager"     "Profiles, ICMP Ping, Open Ports"

    Write-Section "ENVIRONMENT & PACKAGES"
    Write-MenuItem "6"  "Winget Package Toolchain"     "Dev Tools, Git, VSCode, Terminal"
    Write-MenuItem "7"  "Developer Nerd Fonts"         "Cascadia, JetBrains, FiraCode"
    Write-MenuItem "8"  "WSL Setup & Manager"          "Ubuntu/Debian Subsystems"

    Write-Section "SYSTEM HEALTH & MAINTENANCE"
    Write-MenuItem "9"  "System Resource Monitor"      "CPU, RAM, Disks, Top Processes"
    Write-MenuItem "10" "Windows System Maintenance"   "Temp Cleanup, DNS Flush, SFC"

    Write-Section "ADMINISTRATION"
    if (-not (Test-IsAdmin)) {
        Write-MenuItem "11" "Relaunch as Administrator" "Elevate Current Session"
    }
    Write-MenuItem "0"  "Exit / Quit"
    Write-MenuFooter

    Write-Host ""
    $choice = Read-Host "  Enter your choice [0-11]"

    switch ($choice) {
        '1'  { Invoke-SubScript "tools\win-ssh.ps1" "SSH Interactive Setup Wizard" }
        '2'  { Invoke-SubScript "tools\win-ssh.ps1" "SSH Setup Rollback" @("-Rollback") }
        '3'  { Show-OpenSSHManager }
        '4'  { Show-NetworkDiagnostics }
        '5'  { Show-FirewallManager }
        '6'  { Show-WingetInstaller }
        '7'  { Show-FontInstaller }
        '8'  { Show-WSLManager }
        '9'  { Show-SystemHealth }
        '10' { Show-SystemMaintenance }
        '11' { Relaunch-AsAdmin }
        '0'  { Clear-Host; Write-Host "Exiting Windows Management Suite. Goodbye!`n" -ForegroundColor Cyan; exit 0 }
        'q'  { Clear-Host; exit 0 }
        'quit' { Clear-Host; exit 0 }
        'exit' { Clear-Host; exit 0 }
        'c'  { Clear-Host; exit 0 }
        'cancel' { Clear-Host; exit 0 }
        Default {
            Write-Warn2 "Invalid choice '$choice'. Please choose a number from the menu."
            Start-Sleep -Milliseconds 800
        }
    }
}
