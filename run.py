import subprocess
import platform
import shutil

DRY_RUN = False
SYSTEM_PROFILE = None  # desktop | server


def run(cmd):
    if DRY_RUN:
        print("DRY RUN:", " ".join(cmd))
    else:
        subprocess.run(cmd)


def pause():
    input("\nPress Enter to continue...")


def detect_package_manager():
    if shutil.which("apt"):
        return "apt"
    elif shutil.which("dnf"):
        return "dnf"
    return None


def show_system_info():
    print("OS:", platform.system())
    if platform.system() == "Linux":
        run(["uname", "-a"])
        run(["cat", "/etc/os-release"])


def choose_profile():
    global SYSTEM_PROFILE
    while True:
        print("\nSelect System Profile:")
        print("1) Desktop")
        print("2) Server")

        choice = input("Choose profile: ")

        if choice == "1":
            SYSTEM_PROFILE = "desktop"
            break
        elif choice == "2":
            SYSTEM_PROFILE = "server"
            break
        else:
            print("Invalid choice")

    print(f"\nSelected profile: {SYSTEM_PROFILE.upper()}")


def apt_menu():
    while True:
        print("\nAPT Menu:")
        print("i) Install Sudo")
        print("1) Update Repository")
        print("2) Upgrade System")
        print("3) Autoremove")
        print("4) Install TimeShift")
        print("5) Install System Monitor")
        print("6) Install ZSH")
        print("7) Install isc-dhcp-server")
        print("8) Install isc-dhcp-relay")
        print("9) Install bind9")
        print("10) Install bind9utils")
        print("11) Install rsync")
        print("12) Install DNS tools")
        print("13) Install Apache2")
        print("14) Install Clone Tools")
        print("15) Install Remote Access")
        print("16) Install DHCP Server")
        print("17) Install Firewall")
        print("18) Install Samba")
        print("19) Install nginx")
        print("0) Return to Main Menu")

        choice = input("Choose an option: ")

        if choice == "i":
            run(["apt", "install", "-y", "sudo"])
        elif choice == "1":
            run(["apt", "update"])
        elif choice == "2":
            run(["apt", "upgrade", "-y"])
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
            print("Invalid choice")

        pause()


def dnf_menu():
    while True:
        print("\nDNF Menu:")
        print("1) Upgrade System")
        print("2) Clean Cache")
        print("3) Autoremove")
        print("4) Install Timeshift")
        print("5) Install System Monitor")
        print("6) Install ZSH")
        print("7) Developer Tools")
        print("8) Nvidia Driver Update")
        print("0) Return to Main Menu")

        choice = input("Choose an option: ")

        if choice == "1":
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
        elif choice == "0":
            break

        pause()


# =======================
# ONLY MODIFIED FUNCTION
# =======================
def run_tools_menu():
    while True:
        print("\nRun Tools:")
        print("1) Btop")
        print("2) Htop")
        print("3) Systemctl Status (summary)")

        print("---- systemd-networkd ----")
        print("4) Disable systemd-networkd")
        print("5) systemd-networkd Status")
        print("6) Start systemd-networkd")
        print("7) Stop systemd-networkd")
        print("8) Enable systemd-networkd")

        print("---- Apache2 ----")
        print("9) Disable Apache2")
        print("10) Apache2 Status")
        print("11) Start Apache2")
        print("12) Stop Apache2")
        print("13) Enable Apache2")

        print("---- Firewalld ----")
        print("14) Disable Firewalld")
        print("15) Firewalld Status")
        print("16) Start Firewalld")
        print("17) Stop Firewalld")
        print("18) Enable Firewalld")

        print("---- Samba ----")
        print("19) Disable Samba")
        print("20) Samba Status")
        print("21) Start Samba")
        print("22) Stop Samba")
        print("23) Enable Samba")

        print("---- Nginx ----")
        print("24) Disable Nginx")
        print("25) Nginx Status")
        print("26) Start Nginx")
        print("27) Stop Nginx")
        print("28) Enable Nginx")

        print("---- DHCP Server ----")
        print("29) Disable DHCP Server")
        print("30) DHCP Status")
        print("31) Start DHCP Server")
        print("32) Stop DHCP Server")
        print("33) Enable DHCP Server")

        print("---- SSH ----")
        print("34) Disable SSH")
        print("35) SSH Status")
        print("36) Start SSH")
        print("37) Stop SSH")
        print("38) Enable SSH")

        print("---- isc-dhcp-relay ----")
        print("39) Disable isc-dhcp-relay")
        print("40) isc-dhcp-relay Status")
        print("41) Start isc-dhcp-relay")
        print("42) Stop isc-dhcp-relay")
        print("43) Enable isc-dhcp-relay")

        print("---- Bind9 ----")
        print("44) Disable Bind9")
        print("45) Bind9 Status")
        print("46) Start Bind9")
        print("47) Stop Bind9")
        print("48) Enable Bind9")

        print("0) Return To Main Menu")

        choice = input("Choose an option: ")

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
            print("Invalid selection")

        pause()


def main():
    if platform.system() != "Linux":
        print("This tool only supports Linux.")
        return

    show_system_info()
    choose_profile()

    pkg_manager = detect_package_manager()
    if not pkg_manager:
        print("No supported package manager found.")
        return

    print(f"\nDetected package manager: {pkg_manager.upper()}")

    while True:
        print("\nMain Menu:")
        print("1) Package Manager")
        print("2) Run Tools")
        print("q) Quit")

        choice = input("Select an option: ")

        if choice == "1":
            if pkg_manager == "apt":
                apt_menu()
            elif pkg_manager == "dnf":
                dnf_menu()
        elif choice == "2":
            run_tools_menu()
        elif choice.lower() == "q":
            print("Goodbye!")
            break
        else:
            print("Invalid selection")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nExiting safely...")
