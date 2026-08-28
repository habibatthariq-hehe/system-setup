# 🛠️ Personal System-Configuration & Automation Suite

[![OS - Linux](https://img.shields.io/badge/OS-Linux-FCC624?logo=linux&logoColor=black)](#)
[![OS - Windows](https://img.shields.io/badge/OS-Windows-0078D6?logo=windows&logoColor=white)](#)
[![Python - 3.8+](https://img.shields.io/badge/Python-3.8%2B-3776AB?logo=python&logoColor=white)](#)
[![Bash - Supported](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](#)
[![PowerShell - 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](#)
[![Status - Active](https://img.shields.io/badge/Status-Active%20Development-success)](#)

A modular, automated system provisioning and configuration toolkit designed to streamline post-installation setups, server deployments, network service configurations, and desktop customization across **Linux** (Debian/Ubuntu, Fedora/RHEL) and **Windows**.

---

## 📑 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
- [Project Architecture](#-project-architecture)
- [Quick Start](#-quick-start)
  - [1. Universal Cross-Platform Launcher](#1-universal-cross-platform-launcher)
  - [2. Interactive Linux Management CLI](#2-interactive-linux-management-cli)
  - [3. Modular Linux Shell Dispatcher](#3-modular-linux-shell-dispatcher)
- [Modules & Capabilities](#-modules--capabilities)
  - [📦 Package Management & Profiles](#-package-management--profiles)
  - [⚙️ System Services & Daemon Control](#️-system-services--daemon-control)
  - [🌐 Networking & Infrastructure](#-networking--infrastructure)
  - [🎨 Desktop & Environment Customization](#-desktop--environment-customization)
  - [🔍 Live Diagnostics & Monitoring](#-live-diagnostics--monitoring)
  - [🪟 Windows Tools](#-windows-tools)
- [Configuration Templates](#-configuration-templates)
- [Safety & Dry-Run Mode](#-safety--dry-run-mode)
- [License & Disclaimer](#-license--disclaimer)

---

## 🌟 Overview

Setting up a fresh operating system installation or provisioning server services usually requires repetitive commands, manual configuration file editing, and tedious software installations. 

This repository consolidates these processes into an extensible CLI and modular script suite:
- **Zero-Friction Provisioning**: One command to launch setup wizards for desktop environments or headless servers.
- **Multi-Distro Intelligence**: Automatically detects whether your system runs `apt` (Debian/Ubuntu) or `dnf` (Fedora/RHEL/CentOS) and maps appropriate service names (e.g., `apache2` vs `httpd`, `bind9` vs `named`).
- **Production-Grade Network Automation**: Interactive wizards to configure DHCP servers, internal BIND9 DNS zones, NAT iptables routing, and SSH hardening.
- **Safety First**: Integrated **Dry-Run mode** allowing you to preview command execution paths before making system-level changes.

---

## 🚀 Key Features

- 🖥️ **Interactive Python CLI (`script.py`)**:
  - Full-featured ANSI terminal interface with menu navigation and color-coded statuses.
  - Profile selection: **Desktop** vs. **Server**.
  - Package manager abstraction supporting `apt` and `dnf`.
  - Comprehensive service management (start, stop, status, enable, disable) for 8+ major Linux services.
  - Live system resource and network diagnostics.

- 🎯 **Cross-Platform Launcher (`runner.py`)**:
  - Host OS detection (Linux, Windows, macOS).
  - Automatically dispatches to the corresponding OS subsystem (`main-linux.sh`, `main-win.ps1`).

- 🌐 **Network & Infrastructure Wizards (`module/linux/networking/`)**:
  - **DHCP Setup**: ISC-DHCP Server guided configuration wizard and automated setup with subnet declarations and interface binding.
  - **DNS Setup (BIND9)**: Forward/reverse lookup zone generator with configuration templating.
  - **NAT & IP Forwarding**: Automated iptables NAT forwarding and packet routing enablement.
  - **SSH Hardening**: Key generation, authorized keys setup, and daemon configuration.

- 🎨 **Desktop Enhancement & Installers (`module/linux/installer/`)**:
  - **ZSH & Powerlevel10k**: Automated ZSH installation, Oh-My-Zsh integration, plugins (`zsh-autosuggestions`, `zsh-syntax-highlighting`), and Powerlevel10k theme setup.
  - **Nerd Fonts**: Rapid font downloader and system font-cache rebuilder.
  - **Web Browsers & Mail**: Post-install installers for modern web clients and webmail environments.

- 🪟 **Windows Automation (`module/windows/`)**:
  - PowerShell-based administration tools, including Windows OpenSSH service setup and key management.

---

## 📂 Project Architecture

```
system-setup/
├── runner.py                    # Cross-platform entry point (detects OS & launches dispatcher)
├── script.py                    # Comprehensive interactive Python CLI for Linux
├── config/                      # Sample configurations & templates
│   ├── dhcp.conf                # ISC DHCP server configuration template
│   ├── named.conf.options       # BIND9 DNS options template
│   └── 1.db.lks.id              # Sample forward/reverse DNS zone file
├── module/
│   ├── linux/                   # Linux modular scripts
│   │   ├── main-linux.sh        # Linux interactive shell launcher
│   │   ├── installer/           # Desktop & software installation scripts
│   │   │   ├── browser.sh       # Web browser installer
│   │   │   ├── font.sh          # Nerd font installer & cache updater
│   │   │   ├── webmail.sh       # Webmail setup script
│   │   │   └── zsh-install.sh   # ZSH + Oh-My-Zsh + Powerlevel10k installer
│   │   └── networking/          # Network service configuration wizards
│   │       ├── dhcp-setup.sh    # Comprehensive ISC-DHCP wizard & validator
│   │       ├── dns-setup.sh     # BIND9 internal DNS configuration wizard
│   │       ├── nat.sh           # IPTables NAT & routing configuration
│   │       └── ssh.sh           # Linux SSH server setup & key management
│   └── windows/                 # Windows PowerShell automation modules
│       ├── main-win.ps1         # Windows entry script
│       └── tools/
│           └── win-ssh.ps1      # Windows OpenSSH client & server configuration tool
└── README.md                    # Project documentation
```

---

## ⚡ Quick Start

### 1. Universal Cross-Platform Launcher

Run the root runner with Python 3. It will detect your host OS and launch the appropriate suite:

```bash
python3 runner.py
```

### 2. Interactive Linux Management CLI

For direct access to the full-featured Linux system manager with profile selection, package installations, and systemd service controllers:

```bash
# Optional: run with sudo if installing packages or managing services
sudo python3 script.py
```

### 3. Modular Linux Shell Dispatcher

To run standalone bash automation modules on Linux directly:

```bash
cd module/linux
chmod +x main-linux.sh
./main-linux.sh
```

---

## 🔧 Modules & Capabilities

### 📦 Package Management & Profiles

Easily switch between **Desktop** and **Server** installation profiles with support for:

| Package Manager | Supported Distros | Features |
| :--- | :--- | :--- |
| **APT** | Debian, Ubuntu, Linux Mint, Pop!_OS | System update/upgrade, Timeshift, ZSH, btop/htop, BIND9, ISC DHCP, Apache2, Nginx, Samba, Tailscale, Firewalld |
| **DNF** | Fedora, RHEL, Rocky Linux, AlmaLinux | System upgrade, clean cache, RPM Fusion (Free & Non-Free), Nvidia Akmod drivers, Flatpak & Flathub, Tailscale, Developer toolchain |

### ⚙️ System Services & Daemon Control

The CLI provides unified systemd service lifecycle control (`start`, `stop`, `status`, `enable`, `disable`), automatically handling distribution-specific service naming:

| Service | Debian / Ubuntu Name | Fedora / RHEL Name |
| :--- | :--- | :--- |
| **Web Server (Apache)** | `apache2` | `httpd` |
| **Web Server (Nginx)** | `nginx` | `nginx` |
| **SSH Daemon** | `ssh` | `sshd` |
| **DNS Server (BIND9)** | `bind9` | `named` |
| **DHCP Server** | `isc-dhcp-server` | `dhcpd` |
| **DHCP Relay** | `isc-dhcp-relay` | `dhcrelay` |
| **File Sharing (Samba)**| `smbd` | `smb` |
| **Firewall** | `firewalld` | `firewalld` |
| **Network Manager** | `systemd-networkd` | `systemd-networkd` |

### 🌐 Networking & Infrastructure

- **DHCP Setup (`dhcp-setup.sh`)**: Interactive wizard supporting interface selection, IP range pools, gateway definition, subnet masks, DNS forwarders, lease time configuration, and verification tests.
- **BIND9 DNS (`dns-setup.sh`)**: Automatic creation of forward lookup zones, reverse PTR records, and upstream forwarders for local networks.
- **NAT Gateway (`nat.sh`)**: Configures kernel packet forwarding (`net.ipv4.ip_forward=1`) and sets up iptables `MASQUERADE` rules for multi-NIC routing.

### 🎨 Desktop & Environment Customization

- **ZSH & Powerlevel10k (`zsh-install.sh`)**:
  - Installs ZSH and sets it as the default user shell.
  - Deploys Oh-My-Zsh framework.
  - Automatically clones and configures Powerlevel10k, `zsh-syntax-highlighting`, and `zsh-autosuggestions`.
- **Nerd Fonts (`font.sh`)**: Downloads popular coding fonts (e.g., MesloLGS NF, JetBrains Mono) directly to `~/.local/share/fonts` and updates `fc-cache`.

### 🔍 Live Diagnostics & Monitoring

Quick inspection options built into `script.py`:
- 🌐 Network interfaces and active IP assignments (`ip a`)
- 🔌 Active listening TCP/UDP ports and sockets (`ss -tulpn`)
- 💾 Real-time disk partition usage (`df -h`)
- 🧠 Memory & swap consumption (`free -h`)
- ⚠️ Failed systemd units inspection (`systemctl --failed`)
- ⏱️ Uptime and CPU load averages (`uptime`)
- 📊 Interactive monitors (`btop`, `htop`)

### 🪟 Windows Tools

- **OpenSSH Configuration (`win-ssh.ps1`)**: Installs Windows OpenSSH capabilities, configures the `sshd` service, manages firewall rules, and assists with key generation and deployment.

---

## 🛡️ Safety & Dry-Run Mode

`script.py` includes a built-in **Dry-Run mode**:
- Press `d` from the main menu to toggle Dry-Run on or off.
- When enabled, commands will be logged with full parameters to the console without executing them on the host system.
- Ideal for testing script modifications and verifying command workflows safely.

---

## 📋 Configuration Templates

The `config/` directory includes reference configuration templates used by the automation wizards:
- `dhcp.conf`: Default ISC-DHCP server subnet and pool template.
- `named.conf.options`: BIND9 DNS forwarding and security options template.
- `1.db.lks.id`: Zone definition sample for domain resolution testing.

---

## 📄 License & Notes

This repository is maintained for personal system administration and automation workflows. Feel free to fork, adapt, and customize the scripts to fit your own operating system configurations!