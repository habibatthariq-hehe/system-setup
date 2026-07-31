#!/usr/bin/env python3
import subprocess
import platform
import shutil
import os

DRY_RUN = False
SYSTEM_PROFILE = None  # desktop | server


# =======================
# UI COLORS & STYLES
# =======================
class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    RESET = '\033[0m'
    BOLD = '\033[1m'
    DIM = '\033[2m'


def print_banner():
    os.system('cls' if os.name == 'nt' else 'clear')
    print(f"{Colors.CYAN}{Colors.BOLD}╔═════════════════════════════════════════════════════════════════╗{Colors.RESET}")
    print(f"{Colors.CYAN}{Colors.BOLD}║                   SYSTEM SETUP & MANAGEMENT CLI                 ║{Colors.RESET}")
    print(f"{Colors.CYAN}{Colors.BOLD}╚═════════════════════════════════════════════════════════════════╝{Colors.RESET}")
    profile_str = SYSTEM_PROFILE.upper() if SYSTEM_PROFILE else "NOT SELECTED"
    dry_run_str = f"{Colors.YELLOW}ENABLED{Colors.RESET}" if DRY_RUN else f"{Colors.GREEN}DISABLED{Colors.RESET}"
    print(f"  {Colors.BOLD}Profile:{Colors.RESET} {Colors.GREEN}{profile_str}{Colors.RESET}  |  {Colors.BOLD}Dry Run:{Colors.RESET} {dry_run_str}  |  {Colors.BOLD}OS:{Colors.RESET} {Colors.BLUE}{platform.system()}{Colors.RESET}")
    print(f"{Colors.DIM}───────────────────────────────────────────────────────────────────{Colors.RESET}\n")


def print_section(title):
    print(f"{Colors.BLUE}{Colors.BOLD}┌── [ {title} ]{Colors.RESET}")


def print_menu_item(key, label):
    print(f"{Colors.BLUE}│{Colors.RESET}  {Colors.CYAN}{Colors.BOLD}{key:2s}{Colors.RESET} ❯ {label}")


def print_menu_footer():
    print(f"{Colors.BLUE}└───────────────────────────────────────────────────────────────────{Colors.RESET}")


def run(cmd):
    if DRY_RUN:
        print(f"\n{Colors.YELLOW}{Colors.BOLD}[DRY RUN]{Colors.RESET} Executing: {Colors.CYAN}{' '.join(cmd)}{Colors.RESET}")
    else:
        print(f"\n{Colors.GREEN}{Colors.BOLD}[RUNNING]{Colors.RESET} {Colors.CYAN}{' '.join(cmd)}{Colors.RESET}\n")
        subprocess.run(cmd)


def pause():
    input(f"\n{Colors.DIM}Press Enter to continue...{Colors.RESET}")


def detect_package_manager():
    if shutil.which("apt"):
        return "apt"
    elif shutil.which("dnf"):
        return "dnf"
    return None


def show_system_info():
    print_banner()
    print_section("SYSTEM INFORMATION")
    print(f"{Colors.BOLD}OS:{Colors.RESET} {platform.system()}")
    if platform.system() == "Linux":
        print(f"\n{Colors.BOLD}Kernel Info:{Colors.RESET}")
        run(["uname", "-a"])
        print(f"{Colors.BOLD}OS Release:{Colors.RESET}")
        run(["cat", "/etc/os-release"])


def choose_profile():
    global SYSTEM_PROFILE
    while True:
        print_banner()
        print_section("SELECT SYSTEM PROFILE")
        print_menu_item("1", "Desktop Profile")
        print_menu_item("2", "Server Profile")
        print_menu_footer()

        choice = input(f"\n{Colors.BOLD}Choose profile [1/2]: {Colors.RESET}").strip()

        if choice == "1":
            SYSTEM_PROFILE = "desktop"
            break
        elif choice == "2":
            SYSTEM_PROFILE = "server"
            break
        else:
            print(f"{Colors.RED}Invalid choice! Please select 1 or 2.{Colors.RESET}")
            pause()

    print(f"\n{Colors.GREEN}✓ Selected profile: {SYSTEM_PROFILE.upper()}{Colors.RESET}")


def apt_menu():
    while True:
        print_banner()
        print_section("APT PACKAGE MANAGER MENU")
        print_menu_item("i",  "Install Sudo")
        print_menu_item("a", "Install Tailscale")
        print_menu_item("1",  "Update Repository")
        print_menu_item("2",  "Upgrade System")
        print_menu_item("3",  "Autoremove")
        print_menu_item("4",  "Install TimeShift")
        print_menu_item("5",  "Install System Monitor (btop, htop)")
        print_menu_item("6",  "Install ZSH")
        print_menu_item("7",  "Install rsync")
        print_menu_item("8",  "Install BIND9 (bind9, bind9utils, bind9-doc)")
        print_menu_item("9",  "Install Apache2")
        print_menu_item("10", "Install isc-dhcp-relay")
        print_menu_item("11", "Install Core Tools (git, wget, curl, pip)")
        print_menu_item("12", "Install SSH Server")
        print_menu_item("13", "Install isc-dhcp-server")
        print_menu_item("14", "Install Firewalld")
        print_menu_item("15", "Install Samba")
        print_menu_item("16", "Install Nginx")
        print_menu_item("0",  "Return to Main Menu")
        print_menu_footer()

        choice = input(f"\n{Colors.BOLD}Choose an option: {Colors.RESET}").strip()

        if choice == "i":
            run(["apt", "install", "-y", "sudo"])
        elif choice == "a":
            run(["sudo", "curl", "-fsSL", "https://tailscale.com/install.sh", "|", "bash"])
            run(["sudo", "tailscale", "up"])
        elif choice == "1":
            run(["sudo", "apt", "update"])
        elif choice == "2":
            run(["sudo", "apt", "upgrade", "-y"])
        elif choice == "3":
            run(["sudo", "apt", "autoremove", "-y"])
        elif choice == "4":
            run(["sudo", "apt", "install", "-y", "timeshift"])
        elif choice == "5":
            run(["sudo", "apt", "install", "-y", "btop", "htop"])
        elif choice == "6":
            run(["sudo", "apt", "install", "-y", "zsh"])
        elif choice == "7":
            run(["sudo", "apt", "install", "-y", "rsync"])
        elif choice == "8":
            run(["sudo", "apt", "install", "-y", "bind9", "bind9utils", "bind9-doc"])
        elif choice == "9":
            run(["sudo", "apt", "install", "-y", "apache2"])
        elif choice == "10":
            run(["sudo", "apt", "install", "-y", "isc-dhcp-relay"])
        elif choice == "11":
            run(["sudo", "apt", "install", "-y", "git", "wget", "curl", "pip"])
        elif choice == "12":
            run(["sudo", "apt", "install", "-y", "ssh"])
        elif choice == "13":
            run(["sudo", "apt", "install", "-y", "isc-dhcp-server"])
        elif choice == "14":
            run(["sudo", "apt", "install", "-y", "firewalld"])
        elif choice == "15":
            run(["sudo", "apt", "install", "-y", "samba"])
        elif choice == "16":
            run(["sudo", "apt", "install", "-y", "nginx"])
        elif choice == "0":
            break
        else:
            print(f"{Colors.RED}Invalid choice{Colors.RESET}")

        pause()


def dnf_menu():
    while True:
        print_banner()
        print_section("DNF PACKAGE MANAGER MENU")
        print_menu_item("i", "Install Sudo")
        print_menu_item("a", "Install Tailscale")
        print_menu_item("1", "Upgrade System")
        print_menu_item("2", "Clean Cache")
        print_menu_item("3", "Autoremove")
        print_menu_item("4", "Install Timeshift")
        print_menu_item("5", "Install System Monitor (btop, htop)")
        print_menu_item("6", "Install ZSH")
        print_menu_item("7", "Install Developer Tools (pip, npm, git, wget, curl)")
        print_menu_item("8", "Nvidia Driver Update")
        print_menu_item("9", "Install Nvidia Driver")
        print_menu_item("10", "Install RPM Fusion (Free & Non-Free)")
        print_menu_item("11", "Install Flatpak")
        print_menu_item("12", "Install Flathub")
        print_menu_item("0", "Return to Main Menu")
        print_menu_footer()

        choice = input(f"\n{Colors.BOLD}Choose an option: {Colors.RESET}").strip()

        if choice == "i":
            run(["sudo", "dnf", "install", "-y", "sudo"])
        elif choice == "a":
            run(["sudo", "curl", "-fsSL", "https://tailscale.com/install.sh", "|", "bash"])
            run(["sudo", "tailscale", "up"])
        elif choice == "1":
            run(["sudo", "dnf", "upgrade", "-y"])
        elif choice == "2":
            run(["sudo", "dnf", "clean", "all"])
        elif choice == "3":
            run(["sudo", "dnf", "autoremove", "-y"])
        elif choice == "4":
            run(["sudo", "dnf", "install", "-y", "timeshift"])
        elif choice == "5":
            run(["sudo", "dnf", "install", "-y", "btop", "htop"])
        elif choice == "6":
            run(["sudo", "dnf", "install", "-y", "zsh"])
        elif choice == "7":
            run(["sudo", "dnf", "install", "-y", "pip", "npm", "git", "wget", "curl"])
        elif choice == "8":
            run([
                "sudo", "dnf", "upgrade", "--refresh",
                "-y", "akmod-nvidia", "xorg-x11-drv-nvidia"
            ])
        elif choice == "9":
            run (["sudo", "dnf", "install", "akmod-nvidia", "xorg-x11-drv-nvidia"])
        elif choice == "10":
            run(["sudo", "dnf", "install", "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm", "-y"])
        elif choice == "11":
            run(["sudo", "dnf", "install", "flatpak"])
        elif choice == "12":
            run(["sudo", "flatpak", "remote-add", "--if-not-exists", "flathub", "https://flathub.org/repo/flathub.flatpakrepo"])
        elif choice == "0":
            break
        else:
            print(f"{Colors.RED}Invalid choice{Colors.RESET}")

        pause()


def run_tools_menu():
    while True:
        print_banner()
        print_section("SYSTEM TOOLS & SERVICE MANAGEMENT")
        print_menu_item("1",  "Btop System Monitor")
        print_menu_item("2",  "Htop Process Viewer")
        print_menu_item("3",  "Systemctl Overall Status")

        print(f"\n  {Colors.YELLOW}---- systemd-networkd ----{Colors.RESET}")
        print_menu_item("4",  "Disable systemd-networkd")
        print_menu_item("5",  "systemd-networkd Status")
        print_menu_item("6",  "Start systemd-networkd")
        print_menu_item("7",  "Stop systemd-networkd")
        print_menu_item("8",  "Enable systemd-networkd")

        print(f"\n  {Colors.YELLOW}---- Apache2 ----{Colors.RESET}")
        print_menu_item("9",  "Disable Apache2")
        print_menu_item("10", "Apache2 Status")
        print_menu_item("11", "Start Apache2")
        print_menu_item("12", "Stop Apache2")
        print_menu_item("13", "Enable Apache2")

        print(f"\n  {Colors.YELLOW}---- Firewalld ----{Colors.RESET}")
        print_menu_item("14", "Disable Firewalld")
        print_menu_item("15", "Firewalld Status")
        print_menu_item("16", "Start Firewalld")
        print_menu_item("17", "Stop Firewalld")
        print_menu_item("18", "Enable Firewalld")

        print(f"\n  {Colors.YELLOW}---- Samba ----{Colors.RESET}")
        print_menu_item("19", "Disable Samba")
        print_menu_item("20", "Samba Status")
        print_menu_item("21", "Start Samba")
        print_menu_item("22", "Stop Samba")
        print_menu_item("23", "Enable Samba")

        print(f"\n  {Colors.YELLOW}---- Nginx ----{Colors.RESET}")
        print_menu_item("24", "Disable Nginx")
        print_menu_item("25", "Nginx Status")
        print_menu_item("26", "Start Nginx")
        print_menu_item("27", "Stop Nginx")
        print_menu_item("28", "Enable Nginx")

        print(f"\n  {Colors.YELLOW}---- DHCP Server ----{Colors.RESET}")
        print_menu_item("29", "Disable DHCP Server")
        print_menu_item("30", "DHCP Status")
        print_menu_item("31", "Start DHCP Server")
        print_menu_item("32", "Stop DHCP Server")
        print_menu_item("33", "Enable DHCP Server")

        print(f"\n  {Colors.YELLOW}---- SSH ----{Colors.RESET}")
        print_menu_item("34", "Disable SSH")
        print_menu_item("35", "SSH Status")
        print_menu_item("36", "Start SSH")
        print_menu_item("37", "Stop SSH")
        print_menu_item("38", "Enable SSH")

        print(f"\n  {Colors.YELLOW}---- isc-dhcp-relay ----{Colors.RESET}")
        print_menu_item("39", "Disable isc-dhcp-relay")
        print_menu_item("40", "isc-dhcp-relay Status")
        print_menu_item("41", "Start isc-dhcp-relay")
        print_menu_item("42", "Stop isc-dhcp-relay")
        print_menu_item("43", "Enable isc-dhcp-relay")

        print(f"\n  {Colors.YELLOW}---- Bind9 ----{Colors.RESET}")
        print_menu_item("44", "Disable Bind9")
        print_menu_item("45", "Bind9 Status")
        print_menu_item("46", "Start Bind9")
        print_menu_item("47", "Stop Bind9")
        print_menu_item("48", "Enable Bind9")

        print_menu_item("0",  "Return To Main Menu")
        print_menu_footer()

        choice = input(f"\n{Colors.BOLD}Choose an option: {Colors.RESET}").strip()

        if choice == "1":
            run(["btop"])
        elif choice == "2":
            run(["htop"])
        elif choice == "3":
            run(["systemctl", "status"])

        elif choice == "4":
            run(["sudo", "systemctl", "disable", "systemd-networkd"])
        elif choice == "5":
            run(["sudo", "systemctl", "status", "systemd-networkd"])
        elif choice == "6":
            run(["sudo", "systemctl", "start", "systemd-networkd"])
        elif choice == "7":
            run(["sudo", "systemctl", "stop", "systemd-networkd"])
        elif choice == "8":
            run(["sudo", "systemctl", "enable", "systemd-networkd"])

        elif choice == "9":
            run(["sudo", "systemctl", "disable", "apache2"])
        elif choice == "10":
            run(["sudo", "systemctl", "status", "apache2"])
        elif choice == "11":
            run(["sudo", "systemctl", "start", "apache2"])
        elif choice == "12":
            run(["sudo", "systemctl", "stop", "apache2"])
        elif choice == "13":
            run(["sudo", "systemctl", "enable", "apache2"])

        elif choice == "14":
            run(["sudo", "systemctl", "disable", "firewalld"])
        elif choice == "15":
            run(["sudo", "systemctl", "status", "firewalld"])
        elif choice == "16":
            run(["sudo", "systemctl", "start", "firewalld"])
        elif choice == "17":
            run(["sudo", "systemctl", "stop", "firewalld"])
        elif choice == "18":
            run(["sudo", "systemctl", "enable", "firewalld"])

        elif choice == "19":
            run(["sudo", "systemctl", "disable", "smbd"])
        elif choice == "20":
            run(["sudo", "systemctl", "status", "smbd"])
        elif choice == "21":
            run(["sudo", "systemctl", "start", "smbd"])
        elif choice == "22":
            run(["sudo", "systemctl", "stop", "smbd"])
        elif choice == "23":
            run(["sudo", "systemctl", "enable", "smbd"])

        elif choice == "24":
            run(["sudo", "systemctl", "disable", "nginx"])
        elif choice == "25":
            run(["sudo", "systemctl", "status", "nginx"])
        elif choice == "26":
            run(["sudo", "systemctl", "start", "nginx"])
        elif choice == "27":
            run(["sudo", "systemctl", "stop", "nginx"])
        elif choice == "28":
            run(["sudo", "systemctl", "enable", "nginx"])

        elif choice == "29":
            run(["sudo", "systemctl", "disable", "isc-dhcp-server"])
        elif choice == "30":
            run(["sudo", "systemctl", "status", "isc-dhcp-server"])
        elif choice == "31":
            run(["sudo", "systemctl", "start", "isc-dhcp-server"])
        elif choice == "32":
            run(["sudo", "systemctl", "stop", "isc-dhcp-server"])
        elif choice == "33":
            run(["sudo", "systemctl", "enable", "isc-dhcp-server"])

        elif choice == "34":
            run(["sudo", "systemctl", "disable", "ssh"])
        elif choice == "35":
            run(["sudo", "systemctl", "status", "ssh"])
        elif choice == "36":
            run(["sudo", "systemctl", "start", "ssh"])
        elif choice == "37":
            run(["sudo", "systemctl", "stop", "ssh"])
        elif choice == "38":
            run(["sudo", "systemctl", "enable", "ssh"])

        elif choice == "39":
            run(["sudo", "systemctl", "disable", "bind9"])
        elif choice == "40":
            run(["sudo", "systemctl", "status", "bind9"])
        elif choice == "41":
            run(["sudo", "systemctl", "start", "bind9"])
        elif choice == "42":
            run(["sudo", "systemctl", "stop", "bind9"])
        elif choice == "43":
            run(["sudo", "systemctl", "enable", "bind9"])

        elif choice == "0":
            break
        else:
            print(f"{Colors.RED}Invalid selection{Colors.RESET}")

        pause()


def run_tools_menu_dnf():
    """Systemd service manager for DNF-based / RHEL-alike distributions.

    Service name differences vs Debian/Ubuntu:
      apache2         -> httpd
      ssh             -> sshd
      isc-dhcp-server -> dhcpd
      isc-dhcp-relay  -> dhcrelay
      bind9           -> named
      smbd            -> smb
    All other services (nginx, firewalld, systemd-networkd) keep the same name.
    """
    while True:
        print_banner()
        print_section("SYSTEM TOOLS & SERVICE MANAGEMENT (DNF / RHEL)")
        print_menu_item("1",  "Btop System Monitor")
        print_menu_item("2",  "Htop Process Viewer")
        print_menu_item("3",  "Systemctl Overall Status")

        print(f"\n  {Colors.YELLOW}---- systemd-networkd ----{Colors.RESET}")
        print_menu_item("4",  "Disable systemd-networkd")
        print_menu_item("5",  "systemd-networkd Status")
        print_menu_item("6",  "Start systemd-networkd")
        print_menu_item("7",  "Stop systemd-networkd")
        print_menu_item("8",  "Enable systemd-networkd")

        print(f"\n  {Colors.YELLOW}---- Apache (httpd) ----{Colors.RESET}")
        print_menu_item("9",  "Disable httpd")
        print_menu_item("10", "httpd Status")
        print_menu_item("11", "Start httpd")
        print_menu_item("12", "Stop httpd")
        print_menu_item("13", "Enable httpd")

        print(f"\n  {Colors.YELLOW}---- Firewalld ----{Colors.RESET}")
        print_menu_item("14", "Disable Firewalld")
        print_menu_item("15", "Firewalld Status")
        print_menu_item("16", "Start Firewalld")
        print_menu_item("17", "Stop Firewalld")
        print_menu_item("18", "Enable Firewalld")

        print(f"\n  {Colors.YELLOW}---- Samba (smb) ----{Colors.RESET}")
        print_menu_item("19", "Disable smb")
        print_menu_item("20", "smb Status")
        print_menu_item("21", "Start smb")
        print_menu_item("22", "Stop smb")
        print_menu_item("23", "Enable smb")

        print(f"\n  {Colors.YELLOW}---- Nginx ----{Colors.RESET}")
        print_menu_item("24", "Disable Nginx")
        print_menu_item("25", "Nginx Status")
        print_menu_item("26", "Start Nginx")
        print_menu_item("27", "Stop Nginx")
        print_menu_item("28", "Enable Nginx")

        print(f"\n  {Colors.YELLOW}---- DHCP Server (dhcpd) ----{Colors.RESET}")
        print_menu_item("29", "Disable dhcpd")
        print_menu_item("30", "dhcpd Status")
        print_menu_item("31", "Start dhcpd")
        print_menu_item("32", "Stop dhcpd")
        print_menu_item("33", "Enable dhcpd")

        print(f"\n  {Colors.YELLOW}---- SSH (sshd) ----{Colors.RESET}")
        print_menu_item("34", "Disable sshd")
        print_menu_item("35", "sshd Status")
        print_menu_item("36", "Start sshd")
        print_menu_item("37", "Stop sshd")
        print_menu_item("38", "Enable sshd")

        print(f"\n  {Colors.YELLOW}---- DHCP Relay (dhcrelay) ----{Colors.RESET}")
        print_menu_item("39", "Disable dhcrelay")
        print_menu_item("40", "dhcrelay Status")
        print_menu_item("41", "Start dhcrelay")
        print_menu_item("42", "Stop dhcrelay")
        print_menu_item("43", "Enable dhcrelay")

        print(f"\n  {Colors.YELLOW}---- BIND (named) ----{Colors.RESET}")
        print_menu_item("44", "Disable named")
        print_menu_item("45", "named Status")
        print_menu_item("46", "Start named")
        print_menu_item("47", "Stop named")
        print_menu_item("48", "Enable named")

        print_menu_item("0",  "Return To Main Menu")
        print_menu_footer()

        choice = input(f"\n{Colors.BOLD}Choose an option: {Colors.RESET}").strip()

        if choice == "1":
            run(["btop"])
        elif choice == "2":
            run(["htop"])
        elif choice == "3":
            run(["systemctl", "status"])

        elif choice == "4":
            run(["sudo", "systemctl", "disable", "systemd-networkd"])
        elif choice == "5":
            run(["sudo", "systemctl", "status", "systemd-networkd"])
        elif choice == "6":
            run(["sudo", "systemctl", "start", "systemd-networkd"])
        elif choice == "7":
            run(["sudo", "systemctl", "stop", "systemd-networkd"])
        elif choice == "8":
            run(["sudo", "systemctl", "enable", "systemd-networkd"])

        elif choice == "9":
            run(["sudo", "systemctl", "disable", "httpd"])
        elif choice == "10":
            run(["sudo", "systemctl", "status", "httpd"])
        elif choice == "11":
            run(["sudo", "systemctl", "start", "httpd"])
        elif choice == "12":
            run(["sudo", "systemctl", "stop", "httpd"])
        elif choice == "13":
            run(["sudo", "systemctl", "enable", "httpd"])

        elif choice == "14":
            run(["sudo", "systemctl", "disable", "firewalld"])
        elif choice == "15":
            run(["sudo", "systemctl", "status", "firewalld"])
        elif choice == "16":
            run(["sudo", "systemctl", "start", "firewalld"])
        elif choice == "17":
            run(["sudo", "systemctl", "stop", "firewalld"])
        elif choice == "18":
            run(["sudo", "systemctl", "enable", "firewalld"])

        elif choice == "19":
            run(["sudo", "systemctl", "disable", "smb"])
        elif choice == "20":
            run(["sudo", "systemctl", "status", "smb"])
        elif choice == "21":
            run(["sudo", "systemctl", "start", "smb"])
        elif choice == "22":
            run(["sudo", "systemctl", "stop", "smb"])
        elif choice == "23":
            run(["sudo", "systemctl", "enable", "smb"])

        elif choice == "24":
            run(["sudo", "systemctl", "disable", "nginx"])
        elif choice == "25":
            run(["sudo", "systemctl", "status", "nginx"])
        elif choice == "26":
            run(["sudo", "systemctl", "start", "nginx"])
        elif choice == "27":
            run(["sudo", "systemctl", "stop", "nginx"])
        elif choice == "28":
            run(["sudo", "systemctl", "enable", "nginx"])

        elif choice == "29":
            run(["sudo", "systemctl", "disable", "dhcpd"])
        elif choice == "30":
            run(["sudo", "systemctl", "status", "dhcpd"])
        elif choice == "31":
            run(["sudo", "systemctl", "start", "dhcpd"])
        elif choice == "32":
            run(["sudo", "systemctl", "stop", "dhcpd"])
        elif choice == "33":
            run(["sudo", "systemctl", "enable", "dhcpd"])

        elif choice == "34":
            run(["sudo", "systemctl", "disable", "sshd"])
        elif choice == "35":
            run(["sudo", "systemctl", "status", "sshd"])
        elif choice == "36":
            run(["sudo", "systemctl", "start", "sshd"])
        elif choice == "37":
            run(["sudo", "systemctl", "stop", "sshd"])
        elif choice == "38":
            run(["sudo", "systemctl", "enable", "sshd"])

        elif choice == "39":
            run(["sudo", "systemctl", "disable", "dhcrelay"])
        elif choice == "40":
            run(["sudo", "systemctl", "status", "dhcrelay"])
        elif choice == "41":
            run(["sudo", "systemctl", "start", "dhcrelay"])
        elif choice == "42":
            run(["sudo", "systemctl", "stop", "dhcrelay"])
        elif choice == "43":
            run(["sudo", "systemctl", "enable", "dhcrelay"])

        elif choice == "44":
            run(["sudo", "systemctl", "disable", "named"])
        elif choice == "45":
            run(["sudo", "systemctl", "status", "named"])
        elif choice == "46":
            run(["sudo", "systemctl", "start", "named"])
        elif choice == "47":
            run(["sudo", "systemctl", "stop", "named"])
        elif choice == "48":
            run(["sudo", "systemctl", "enable", "named"])

        elif choice == "0":
            break
        else:
            print(f"{Colors.RED}Invalid selection{Colors.RESET}")

        pause()


def run_script_helper(script_name):
    script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), script_name)
    if not os.path.exists(script_path):
        print(f"{Colors.RED}Error: Script {script_name} not found at {script_path}{Colors.RESET}")
        return
    run(["chmod", "+x", script_path])
    run(["bash", script_path])


def automation_scripts_menu():
    while True:
        print_banner()
        print_section("AUTOMATION SCRIPTS MENU")
        print_menu_item("1", "Font Installation (font.sh)")
        print_menu_item("2", "ZSH + Powerlevel10k Setup (zsh-install.sh)")
        print_menu_item("3", "SSH Key Setup (ssh.sh)")
        print_menu_item("4", "Firewall Automation (fw-auto.sh)")
        print_menu_item("5", "DHCP Server Automation (dhcp-auto.sh)")
        print_menu_item("6", "BIND9 DNS Automation (2.bind-internal-auto.sh)")
        print_menu_item("7", "Webmail Automation (webmail.sh)")
        print_menu_item("0", "Return to Main Menu")
        print_menu_footer()

        choice = input(f"\n{Colors.BOLD}Select an option: {Colors.RESET}").strip()

        if choice == "1":
            run_script_helper("font.sh")
        elif choice == "2":
            run_script_helper("zsh-install.sh")
        elif choice == "3":
            run_script_helper("ssh.sh")
        elif choice == "4":
            run_script_helper("fw-auto.sh")
        elif choice == "5":
            run_script_helper("dhcp-auto.sh")
        elif choice == "6":
            run_script_helper("2.bind-internal-auto.sh")
        elif choice == "7":
            run_script_helper("webmail.sh")
        elif choice == "0":
            break
        else:
            print(f"{Colors.RED}Invalid selection{Colors.RESET}")

        pause()


def diagnostics_menu():
    while True:
        print_banner()
        print_section("SYSTEM DIAGNOSTICS & NETWORK TOOLS")
        print_menu_item("1", "Network Interfaces & IP Addresses (ip a)")
        print_menu_item("2", "Active Listening Ports (ss -tulpn)")
        print_menu_item("3", "Disk Space Usage (df -h)")
        print_menu_item("4", "RAM Memory Usage (free -h)")
        print_menu_item("5", "Failed Systemd Services (systemctl --failed)")
        print_menu_item("6", "System Uptime & Load Average (uptime)")
        print_menu_item("7", "Btop System Monitor")
        print_menu_item("8", "Htop Process Viewer")
        print_menu_item("0", "Return to Main Menu")
        print_menu_footer()

        choice = input(f"\n{Colors.BOLD}Select an option: {Colors.RESET}").strip()

        if choice == "1":
            run(["ip", "a"])
        elif choice == "2":
            run(["ss", "-tulpn"])
        elif choice == "3":
            run(["df", "-h"])
        elif choice == "4":
            run(["free", "-h"])
        elif choice == "5":
            run(["systemctl", "--failed"])
        elif choice == "6":
            run(["uptime"])
        elif choice == "7":
            run(["sudo", "btop"])
        elif choice == "8":
            run(["sudo", "htop"])
        elif choice == "0":
            break
        else:
            print(f"{Colors.RED}Invalid selection{Colors.RESET}")

        pause()


def toggle_dry_run():
    global DRY_RUN
    DRY_RUN = not DRY_RUN
    status = "ENABLED" if DRY_RUN else "DISABLED"
    print(f"\n{Colors.GREEN}✓ Dry-Run Mode is now {Colors.BOLD}{status}{Colors.RESET}")


def main():
    if platform.system() != "Linux":
        print(f"{Colors.RED}This tool only supports Linux.{Colors.RESET}")
        return

    show_system_info()
    choose_profile()

    pkg_manager = detect_package_manager()
    if not pkg_manager:
        print(f"{Colors.RED}No supported package manager found.{Colors.RESET}")
        return

    while True:
        print_banner()
        print_section("MAIN MENU")
        print_menu_item("1", f"Package Manager ({pkg_manager.upper()})")
        print_menu_item("2", "Run Tools & Services Manager")
        print_menu_item("3", "Automation Scripts Manager")
        print_menu_item("4", "System Diagnostics & Network Tools")
        print_menu_item("d", f"Toggle Dry-Run Mode ({'ENABLED' if DRY_RUN else 'DISABLED'})")
        print_menu_item("q", "Quit")
        print_menu_footer()

        choice = input(f"\n{Colors.BOLD}Select an option: {Colors.RESET}").strip()

        if choice == "1":
            if pkg_manager == "apt":
                apt_menu()
            elif pkg_manager == "dnf":
                dnf_menu()
        elif choice == "2":
            if pkg_manager == "dnf":
                run_tools_menu_dnf()
            else:
                run_tools_menu()
        elif choice == "3":
            automation_scripts_menu()
        elif choice == "4":
            diagnostics_menu()
        elif choice.lower() == "d":
            toggle_dry_run()
            pause()
        elif choice.lower() == "q":
            print(f"\n{Colors.GREEN}{Colors.BOLD}Goodbye! Have a great day!{Colors.RESET}\n")
            break
        else:
            print(f"{Colors.RED}Invalid selection{Colors.RESET}")
            pause()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n\n{Colors.YELLOW}Exiting safely... Goodbye!{Colors.RESET}\n")
