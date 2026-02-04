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
        print("14) Install Remote Access")
        print("12) Install DHCP Server")
        print("13) Install Firewall")
        print("14) Install Samba")
        print("15) Install nginx")
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

        print("---- Apache2 ----")
        print("4) Disable Apache2")
        print("5) Apache2 Status")
        print("6) Start Apache2")
        print("7) Stop Apache2")
        print("8) Enable Apache2")

        print("---- Firewalld ----")
        print("9) Disable Firewalld")
        print("10) Firewalld Status")
        print("11) Start Firewalld")
        print("12) Stop Firewalld")
        print("13) Enable Firewalld")

        print("---- Samba ----")
        print("14) Disable Samba")
        print("15) Samba Status")
        print("16) Start Samba")
        print("17) Stop Samba")
        print("18) Enable Samba")

        print("---- Nginx ----")
        print("19) Disable Nginx")
        print("20) Nginx Status")
        print("21) Start Nginx")
        print("22) Stop Nginx")
        print("23) Enable Nginx")

        print("---- DHCP Server ----")
        print("24) Disable DHCP Server")
        print("25) DHCP Status")
        print("26) Start DHCP Server")
        print("27) Stop DHCP Server")
        print("28) Enable DHCP Server")

        print("---- SSH ----")
        print("29) Disable SSH")
        print("30) SSH Status")
        print("31) Start SSH")
        print("32) Stop SSH")
        print("33) Enable SSH")

        print("---- isc-dhcp-relay ----")
        print("34) Disable isc-dhcp-relay")
        print("35) isc-dhcp-relay Status")
        print("36) Start isc-dhcp-relay")
        print("37) Stop isc-dhcp-relay")
        print("38) Enable isc-dhcp-relay")

        print("---- Bind9 ----")
        print("39) Disable Bind9")
        print("40) Bind9 Status")
        print("41) Start Bind9")
        print("42) Stop Bind9")
        print("43) Enable Bind9")

        print("0) Return To Main Menu")

        choice = input("Choose an option: ")

        if choice == "1":
            run(["btop"])
        elif choice == "2":
            run(["htop"])
        elif choice == "3":
            run(["systemctl", "status"])

        elif choice == "4":
            run(["sudo", "systemctl", "disable", "apache2"])
        elif choice == "5":
            run(["sudo", "systemctl", "status", "apache2"])
        elif choice == "6":
            run(["sudo", "systemctl", "start", "apache2"])
        elif choice == "7":
            run(["sudo", "systemctl", "stop", "apache2"])
        elif choice == "8":
            run(["sudo", "systemctl", "enable", "apache2"])

        elif choice == "9":
            run(["sudo", "systemctl", "disable", "firewalld"])
        elif choice == "10":
            run(["sudo", "systemctl", "status", "firewalld"])
        elif choice == "11":
            run(["sudo", "systemctl", "start", "firewalld"])
        elif choice == "12":
            run(["sudo", "systemctl", "stop", "firewalld"])
        elif choice == "13":
            run(["sudo", "systemctl", "enable", "firewalld"])

        elif choice == "14":
            run(["sudo", "systemctl", "disable", "smbd"])
        elif choice == "15":
            run(["sudo", "systemctl", "status", "smbd"])
        elif choice == "16":
            run(["sudo", "systemctl", "start", "smbd"])
        elif choice == "17":
            run(["sudo", "systemctl", "stop", "smbd"])
        elif choice == "18":
            run(["sudo", "systemctl", "enable", "smbd"])

        elif choice == "19":
            run(["sudo", "systemctl", "disable", "nginx"])
        elif choice == "20":
            run(["sudo", "systemctl", "status", "nginx"])
        elif choice == "21":
            run(["sudo", "systemctl", "start", "nginx"])
        elif choice == "22":
            run(["sudo", "systemctl", "stop", "nginx"])
        elif choice == "23":
            run(["sudo", "systemctl", "enable", "nginx"])

        elif choice == "24":
            run(["sudo", "systemctl", "disable", "isc-dhcp-server"])
        elif choice == "25":
            run(["sudo", "systemctl", "status", "isc-dhcp-server"])
        elif choice == "26":
            run(["sudo", "systemctl", "start", "isc-dhcp-server"])
        elif choice == "27":
            run(["sudo", "systemctl", "stop", "isc-dhcp-server"])
        elif choice == "28":
            run(["sudo", "systemctl", "enable", "isc-dhcp-server"])

        elif choice == "29":
            run(["sudo", "systemctl", "disable", "ssh"])
        elif choice == "30":
            run(["sudo", "systemctl", "status", "ssh"])
        elif choice == "31":
            run(["sudo", "systemctl", "start", "ssh"])
        elif choice == "32":
            run(["sudo", "systemctl", "stop", "ssh"])
        elif choice == "33":
            run(["sudo", "systemctl", "enable", "ssh"])

        elif choice == "34":
            run(["sudo", "systemctl", "disable", "bind9"])
        elif choice == "35":
            run(["sudo", "systemctl", "status", "bind9"])
        elif choice == "36":
            run(["sudo", "systemctl", "start", "bind9"])
        elif choice == "37":
            run(["sudo", "systemctl", "stop", "bind9"])
        elif choice == "38":
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
