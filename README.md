# 🐧 Linux System Setup & Automation Toolkit

[![OS - Linux](https://img.shields.io/badge/OS-Linux-FCC624?logo=linux&logoColor=black)](#)
[![Shell - Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](#)
[![Status - Active](https://img.shields.io/badge/Status-Active-success)](#)

A modular collection of interactive Bash scripts designed to automate Linux system provisioning, post-installation tasks, network service deployments, and terminal environment setups. Some script maybe contain some bug and error cause it's still on development and testing, please backup your configuration before using it.

---

## ⚡ Quick Start

### 1. Interactive Menu (Recommended)
Launch the central menu to run any configuration or installer interactively:

```bash
git clone https://github.com/habibatthariq-hehe/system-setup.git
cd system-setup
sudo bash module/linux/main-linux.sh
```

### 2. Standalone Execution
Every module can also be executed directly on its own without going through the main menu:

```bash
# Setup WireGuard VPN
sudo bash module/linux/networking/wireguard.sh

# Configure NAT Gateway
sudo bash module/linux/networking/nat.sh

# Setup ISC-DHCP Server
sudo bash module/linux/networking/dhcp-setup.sh

# Configure Static IP
sudo bash module/linux/networking/static-ip-setup.sh

# Install ZSH + Oh-My-Zsh + Powerlevel10k
bash module/linux/installer/zsh-install.sh
```

---

## 📦 Modules Overview

### 🌐 Networking & Server Services (`module/linux/networking/`)

| Script | Description | Highlights |
| :--- | :--- | :--- |
| **`wireguard.sh`** | WireGuard VPN Setup & Management | Interactive server/client setup, key generation, peer management, and interface controls. |
| **`nat.sh`** | NAT Gateway & Packet Forwarding | Supports `nftables` & `iptables`, interface auto-detection, reboot persistence, and `--rollback`. |
| **`dhcp-setup.sh`** | ISC-DHCP Server Configuration | Guided wizard for subnet pools, interfaces, gateways, DNS forwarders, and syntax validation. |
| **`dns-setup.sh`** | BIND9 & Dnsmasq DNS Server | Internet resolve-only caching mode, forward/reverse zones, and syntax checking. |
| **`static-ip-setup.sh`** | Static IP Configuration | Automated interface IP setup, config backup, and `--dry-run` testing. |
| **`ssh.sh`** | SSH Hardening & Key Management | Key pair generation, target deployment via `ssh-copy-id`, and rollback support. |
| **`hostname-setup.sh`** | System Hostname Tool | Quick interactive tool to view and change the system hostname. |
| **`webmail.sh`** | Mail Server Setup | Automated deployment for Postfix, Dovecot, and Roundcube webmail. |

### 🎨 Desktop & Environment (`module/linux/installer/`)

| Script | Description | Highlights |
| :--- | :--- | :--- |
| **`zsh-install.sh`** | ZSH + Oh-My-Zsh + Powerlevel10k | Installs ZSH, syntax highlighting, autosuggestions, fonts, and sets default shell (with `--rollback`). |
| **`font.sh`** | MesloLGS Nerd Font Installer | Downloads required fonts for Powerlevel10k terminal icons and updates font cache. |
| **`browser.sh`** | Web Browser Installer | One-click installation for popular web browsers across `apt`, `dnf`, and `yum`. |
| **`webmail.sh`** | Webmail Client | Webmail client installer component. |

### 📁 Config Templates (`config/`)

- **`deb-*-sources.list`**: Ready-to-use repository mirror lists for Debian 10 (Buster), 11 (Bullseye), 12 (Bookworm), and 13 (Trixie).
- **`dhcp.conf`**: Baseline ISC-DHCP server configuration template.
- **`named.conf.options`**: BIND9 DNS server forwarding and access control template.
- **`1.db.lks.id`**: Sample DNS forward and reverse zone file.

---

## 🛡️ Safety & Rollback Support

Many scripts in this repository include built-in safety mechanisms:
- **Rollback**: Revert changes made by scripts using the `--rollback` flag:
  ```bash
  sudo bash module/linux/networking/nat.sh --rollback
  bash module/linux/installer/zsh-install.sh --rollback
  ```
- **Status Inspection**: Check active configurations using `--status` where supported:
  ```bash
  sudo bash module/linux/networking/nat.sh --status
  ```
- **Dry-Run Mode**: Preview changes before executing them using `--dry-run`:
  ```bash
  sudo bash module/linux/networking/static-ip-setup.sh --dry-run
  ```

---

## 📂 Project Structure

```
system-setup/
├── config/                      # Sample configurations & repository lists
│   ├── deb-10-sources.list      # Debian 10 (Buster) sources
│   ├── deb-11-sources.list      # Debian 11 (Bullseye) sources
│   ├── deb-12-sources.list      # Debian 12 (Bookworm) sources
│   ├── deb-13-sources.list      # Debian 13 (Trixie) sources
│   ├── dhcp.conf                # ISC-DHCP configuration template
│   ├── named.conf.options       # BIND9 options template
│   └── 1.db.lks.id              # Sample DNS zone configuration
├── module/
│   └── linux/
│       ├── main-linux.sh        # Interactive central dispatcher
│       ├── installer/           # Environment & software installers
│       │   ├── browser.sh       # Web browser installer
│       │   ├── font.sh          # Nerd font downloader
│       │   ├── webmail.sh       # Mail & Roundcube setup
│       │   └── zsh-install.sh   # ZSH + OMZ + P10k installer
│       └── networking/          # Network service configuration tools
│           ├── dhcp-setup.sh    # ISC-DHCP interactive wizard
│           ├── dns-setup.sh     # BIND9 / Dnsmasq setup
│           ├── hostname-setup.sh# Hostname configuration
│           ├── nat.sh           # NAT & packet forwarding (nftables/iptables)
│           ├── ssh.sh           # SSH keys & server configuration
│           ├── static-ip-setup.sh# Static IP configuration tool
│           ├── webmail.sh       # Webmail server setup
│           └── wireguard.sh     # WireGuard VPN manager
└── README.md
```

---

## 📋 Prerequisites

- **Operating System**: Linux (Debian, Ubuntu, Fedora, RHEL, CentOS, or compatible distributions)
- **Privileges**: Root or `sudo` access for system and networking configurations
- **Dependencies**: `bash`, `curl`, `wget`, `git`

---

## 📄 License & Notes

Maintained for personal system administration, server provisioning, and lab automation workflows. Adapt and customize as needed for your own environment.