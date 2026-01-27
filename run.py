import subprocess
import platform

def show_system_info():
    print("OS:", platform.system())
    if platform.system() == "Linux":
        subprocess.run(["uname", "-a"])
        subprocess.run(["cat", "/etc/os-release"])


def apt_menu():
    while True:
        print("\nAPT Menu:")
        print("1) Update Repository")
        print("2) Upgrade System")
        print("3) Autoremove")
        print("4) Install TimeShift")
        print("5) Install System Monitor")
        print("6) Install ZSH")
        print("7) Install rsync")
        print("8) Install DNS tools")
        print("9) Install Apache2")
        print("10) Install Dev Tools")
        print("11) Install Remote Access")
        print("0) Return to Main Menu")

        choice = input("Choose an option: ")

        if choice == "1":
            subprocess.run(["sudo", "apt", "update"])
        elif choice == "2":
            subprocess.run(["sudo", "apt", "upgrade"])
        elif choice == "3":
            subprocess.run(["sudo", "apt", "autoremove"])
        elif choice == "4":
            subprocess.run(["sudo", "apt", "install", "timeshift"])
        elif choice == "5":
            subprocess.run(["sudo", "apt", "install", "btop", "htop"])
        elif choice == "6":
            subprocess.run(["sudo", "apt", "install", "zsh"])
        elif choice == "7":
            subprocess.run(["sudo", "apt", "install", "rsync"])
        elif choice == "8":
            subprocess.run(["sudo", "apt", "install", "bind9", "bind9utils", "bind9-doc"])
        elif choice == "10":
            subprocess.run(["sudo", "apt", "install", "git", "wget", "curl", "pip"])
        elif choice == "11":
            subprocess.run(["sudo", "apt", "install", "ssh"])
        elif choice == "0":
            break
        else:
            print("Invalid choice")


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
            subprocess.run(["dnf", "upgrade"])
        elif choice == "2":
            subprocess.run(["dnf", "clean", "all"])
        elif choice == "3":
            subprocess.run(["dnf", "autoremove", "-y"])
        elif choice == "4":
            subprocess.run(["dnf", "in", "timeshift"])
        elif choice == "5":
            subprocess.run(["dnf", "in", "btop", "htop"])
        elif choice == "6":
            subprocess.run(["dnf", "in", "zsh"])
        elif choice == "7":
            subprocess.run(["dnf", "in", "pip", "npm", "git", "wget", "curl"])
        elif choice == "8":
            subprocess.run(["dnf", "upgrade", "--refresh", "akmod-nvidia", "xorg-x11-drv-nvidia"])
        elif choice == "0":
            break


# 🔧 MOVED HERE (this is the fix)
def run_tools_menu():
    print("1) Btop")
    print("2) Htop")
    print("3) Systemctl Status")
    print("4) Check Apache2 Status")
    print("5) Start Apache2 Service")
    print("0) Return TO Main Menu")

    choice = input("Choose an option: ")

    if choice == "1":
        subprocess.run(["btop"])
    elif choice == "2":
        subprocess.run(["htop"])
    elif choice == "3":
        subprocess.run(["systemctl", "status"])
    elif choice == "4":
        subprocess.run(["sudo", "systemctl", "status", "apache2"])
    elif choice == "5":
        subprocess.run(["sudo", "systemctl", "start", "apache2"])


def main():
    show_system_info()
    while True:
        print("\nSelect a Package Manager: ")
        print("1) APT")
        print("2) DNF")
        print("3) Run Tools")
        print("q) Quit")

        pkg = input("Select an option: ")

        if pkg == "1":
            apt_menu()
        elif pkg == "2":
            dnf_menu()
        elif pkg == "3":
            run_tools_menu()
        elif pkg.lower() == "q":
            print("Goodbye!")
            break
        else:
            print("Invalid selection")


if __name__ == "__main__":
    main()
