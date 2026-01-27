import subprocess
import platform
import shutil

DRY_RUN = False


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
        print("7) Install rsync")
        print("8) Install DNS tools")
        print("9) Install Apache2")
        print("10) Install Clone Tools")
        print("11) Install Remote Access")
        print("12) Install DHCP Server")
        print("13) Install Firewall")
        print("14) Install Samba")
        print("15) Install nginx")
        print("0) Return to Main Menu")

        choice = input("Choose an option: ")

        if choice == "i":
            run(["sudo", "apt", "install", "-y", "sudo"])
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
        elif choice == "10":
            run(["sudo", "apt", "install", "-y", "git", "wget", "curl", "pip"])
        elif choice == "11":
            run(["sudo", "apt", "install", "-y", "ssh"])
        elif choice == "12":
            run(["sudo", "apt", "install", "-y", "isc-dhcp-server"])
        elif choice == "13":
            run(["sudo", "apt", "install", "-y", "firewalld"])
        elif choice == "14":
            run(["sudo", "apt", "install", "-y", "samba"])
        elif choice == "15":
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


def run_tools_menu():
    while True:
        print("\nRun Tools:")
        print("1) Btop")
        print("2) Htop")
        print("3) Systemctl Status")
        print("4) Disable Apache2 Service")
        print("5) Check Apache2 Status")
        print("6) Start Apache2 Service")
        print("7) Stop Apache2 Service")
        print("8) Disable Firewalld Service")
        print("9) Check Firewalld Status")
        print("10) Start Firewalld Service")
        print("11) Stop Firewalld Service")
        print("12) Disable Samba Service")
        print("13) Check Samba Status")
        print("14) Start Samba Service")
        print("15) Stop Samba Service")
        print("16) Disable Nginx Service")
        print("17) Check Nginx Status")
        print("18) Start Nginx Service")
        print("19) Stop Nginx Service")
        print("20) Disable DHCP Server Service")
        print("21) Check DHCP Server Status")
        print("22) Start DHCP Server Service")
        print("23) Stop DHCP Server Service")
        print("24) Disable SSH Service")
        print("25) Check SSH Status")
        print("26) Start SSH Service")
        print("27) Stop SSH Service")
        print("28) Disable Bind9 Service")
        print("29) Check Bind9 Status")
        print("30) Start Bind9 Service")
        print("31) Stop Bind9 Service")
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
            run(["sudo", "systemctl", "disable", "firewalld"])
        elif choice == "9":
            run(["sudo", "systemctl", "status", "firewalld"])
        elif choice == "10":
            run(["sudo", "systemctl", "start", "firewalld"])
        elif choice == "11":
            run(["sudo", "systemctl", "stop", "firewalld"])
        elif choice == "12":
            run(["sudo", "systemctl", "disable", "smbd"])
        elif choice == "13":
            run(["sudo", "systemctl", "status", "smbd"])
        elif choice == "14":
            run(["sudo", "systemctl", "start", "smbd"])
        elif choice == "15":
            run(["sudo", "systemctl", "stop", "smbd"])
        elif choice == "16":
            run(["sudo", "systemctl", "disable", "nginx"])
        elif choice == "17":
            run(["sudo", "systemctl", "status", "nginx"])
        elif choice == "18":
            run(["sudo", "systemctl", "start", "nginx"])
        elif choice == "19":
            run(["sudo", "systemctl", "stop", "nginx"])
        elif choice == "20":
            run(["sudo", "systemctl", "disable", "isc-dhcp-server"])
        elif choice == "21":
            run(["sudo", "systemctl", "status", "isc-dhcp-server"])
        elif choice == "22":
            run(["sudo", "systemctl", "start", "isc-dhcp-server"])
        elif choice == "23":
            run(["sudo", "systemctl", "stop", "isc-dhcp-server"])
        elif choice == "24":
            run(["sudo", "systemctl", "disable", "ssh"])
        elif choice == "25":
            run(["sudo", "systemctl", "status", "ssh"])
        elif choice == "26":
            run(["sudo", "systemctl", "start", "ssh"])
        elif choice == "27":
            run(["sudo", "systemctl", "stop", "ssh"])
        elif choice == "28":
            run(["sudo", "systemctl", "disable", "bind9"])
        elif choice == "29":
            run(["sudo", "systemctl", "status", "bind9"])
        elif choice == "30":
            run(["sudo", "systemctl", "start", "bind9"])
        elif choice == "31":
            run(["sudo", "systemctl", "stop", "bind9"])
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

    pkg_manager = detect_package_manager()
    if not pkg_manager:
        print("No supported package manager found (APT or DNF).")
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