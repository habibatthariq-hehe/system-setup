#!/usr/bin/env python3
"""
runner.py
---------
The universal entry-point for the System Setup suite.
Now upgraded with enhanced QoL (User Experience) and QoS (Robustness).

Key Improvements:
1. CLI Arguments: Support for --module to jump directly to a tool.
2. Interpreter Validation: Checks if bash/powershell exists before execution.
3. Enhanced Diagnostics: Richer system summary including CPU and Memory.
4. Robust Error Handling: Graceful failure when modules are missing.
5. OS Override: Allows forcing a specific OS mode via --os.
"""

import os
import platform
import subprocess
import sys
import shutil
import argparse
from pathlib import Path

# ============================================================================
# UI COLORS & FORMATTING
# ============================================================================

class Colors:
    RED     = '\033[0;31m'
    GREEN   = '\033[0;32m'
    YELLOW  = '\033[1;33m'
    BLUE    = '\033[0;34m'
    CYAN    = '\033[0;36m'
    BOLD    = '\033[1m'
    DIM     = '\033[2m'
    RESET   = '\033[0m'

def _enable_windows_ansi():
    if os.name == 'nt':
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 0x4 | 0x2)
        except Exception:
            pass

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

def print_banner():
    clear_screen()
    print(f"{Colors.CYAN}{Colors.BOLD}╔═══════════════════════════════════════════════════════════════════╗{Colors.RESET}")
    print(f"{Colors.CYAN}{Colors.BOLD}║             SYSTEM SETUP - CROSS-PLATFORM LAUNCHER                ║{Colors.RESET}")
    print(f"{Colors.CYAN}{Colors.BOLD}╚═══════════════════════════════════════════════════════════════════╝{Colors.RESET}")
    print()

def print_separator():
    print(f"{Colors.DIM}─────────────────────────────────────────────────────────────────────{Colors.RESET}")

def log_info(msg: str)    : print(f"  {Colors.BLUE}{Colors.BOLD}[INFO]{Colors.RESET}    {msg}")
def log_success(msg: str) : print(f"  {Colors.GREEN}{Colors.BOLD}[OK]{Colors.RESET}      {msg}")
def log_warn(msg: str)    : print(f"  {Colors.YELLOW}{Colors.BOLD}[WARN]{Colors.RESET}    {msg}")
def log_error(msg: str)   : print(f"  {Colors.RED}{Colors.BOLD}[ERROR]{Colors.RESET}   {msg}")

def is_cancel(value: str) -> bool:
    return value.strip().lower() in {'c', 'cancel', 'q', 'quit', 'exit'}

# ============================================================================
# OS & SYSTEM DETECTION
# ============================================================================

OS_MAP = {
    'Linux':   'linux',
    'Windows': 'windows',
    'Darwin':  'darwin',
}

OS_PRETTY = {
    'linux':   'Linux',
    'windows': 'Windows',
    'darwin':  'macOS',
}

def detect_os() -> str:
    return OS_MAP.get(platform.system(), 'unknown')

def get_system_summary() -> dict:
    """Gathers rich system information for the summary box."""
    details = {
        'system':   platform.system(),
        'release':  platform.release(),
        'version':  platform.version(),
        'machine':  platform.machine(),
        'python':   platform.python_version(),
        'node':     platform.node() or 'localhost',
    }
    
    try:
        import psutil
        mem = psutil.virtual_memory()
        details['ram'] = f"{round(mem.total / (1024**3), 1)} GB"
        details['cpu'] = f"{platform.processor()}"
    except (ImportError, Exception):
        details['ram'] = "N/A"
        details['cpu'] = "N/A"
        
    return details

def _print_os_summary(os_key: str, details: dict):
    pretty = OS_PRETTY.get(os_key, os_key.capitalize())
    print(f"  {Colors.BOLD}OS Detected:{Colors.RESET}     {Colors.GREEN}{pretty}{Colors.RESET}")
    print(f"  {Colors.BOLD}Kernel:    {Colors.RESET}     {Colors.CYAN}{details['system']} {details['release']}{Colors.RESET}")
    print(f"  {Colors.BOLD}Arch/CPU:  {Colors.RESET}     {Colors.CYAN}{details['machine']} ({details['cpu']}){Colors.RESET}")
    print(f"  {Colors.BOLD}Memory:    {Colors.RESET}     {Colors.CYAN}{details['ram']}{Colors.RESET}")
    print(f"  {Colors.BOLD}Python:    {Colors.RESET}     {Colors.CYAN}{details['python']}{Colors.RESET}")
    print(f"  {Colors.BOLD}Hostname:  {Colors.RESET}     {Colors.CYAN}{details['node']}{Colors.RESET}")
    print_separator()

# ============================================================================
# EXECUTION ENGINE
# ============================================================================

RUNNERS = {
    'linux':   {'interpreter': 'bash', 'entry': 'main-linux.sh'},
    'windows': {'interpreter': 'powershell', 'entry': 'main-win.ps1'},
    'darwin':  {'interpreter': 'bash', 'entry': 'main-mac.sh'},
}

def _project_root() -> Path:
    return Path(__file__).resolve().parent

def _module_dir(os_key: str) -> Path:
    return _project_root() / 'module' / os_key

def validate_interpreter(interpreter: str) -> bool:
    """Check if the required interpreter is installed on the system."""
    if interpreter == 'powershell':
        # Check for powershell or pwsh (Core)
        return shutil.which('powershell') is not None or shutil.which('pwsh') is not None
    return shutil.which(interpreter) is not None

def _invoke(interpreter: str, script_path: Path, os_key: str) -> int:
    cwd = str(script_path.parent)
    is_root = os.geteuid() == 0 if os.name != 'nt' else True # Windows handles elevation differently

    # Resolve PowerShell executable (handles both Windows PowerShell and PowerShell Core)
    if os_key == 'windows':
        pwsh = shutil.which('powershell') or shutil.which('pwsh')
        if not pwsh:
            log_error("PowerShell not found. Please install PowerShell to continue.")
            return 127
        cmd = [pwsh, '-ExecutionPolicy', 'Bypass', '-File', str(script_path)]
    elif interpreter == 'bash':
        cmd = ['bash', str(script_path)]
    else:
        cmd = [interpreter, str(script_path)]

    # QoS: Automatically prepend sudo if not running as root to ensure script functionality
    if not is_root and os_key != 'windows':
        cmd = ['sudo'] + cmd
        log_info("Elevating privileges via sudo...")

    log_info(f"Executing: {Colors.BOLD}{' '.join(cmd)}{Colors.RESET}")
    print()
    try:
        result = subprocess.run(cmd, cwd=cwd)
        return result.returncode
    except FileNotFoundError as exc:
        log_error(f"Interpreter not found: {exc}")
        return 127
    except KeyboardInterrupt:
        log_warn("Interrupted by user.")
        return 130

# ============================================================================
# MAIN LOGIC
# ============================================================================

def run_main(args):
    print_banner()

    # 1. OS Selection (Override or Detect)
    if args.os:
        os_key = args.os.lower()
        log_info(f"OS override enabled: {os_key}")
    else:
        log_info("Detecting host operating system...")
        os_key = detect_os()

    if os_key == 'unknown' or os_key not in RUNNERS:
        log_error(f"Unsupported operating system: {os_key}")
        log_warn(f"This launcher supports: {', '.join(RUNNERS.keys())}")
        return 1

    details = get_system_summary()
    _print_os_summary(os_key, details)
    log_success(f"Launcher will run the {Colors.GREEN}{OS_PRETTY.get(os_key, os_key)}{Colors.RESET} workflow.")
    print()

    # 2. Script Resolution
    config = RUNNERS[os_key]
    
    if args.module:
        # Resolve the target path (could be a directory or a specific file)
        target_path = _module_dir(os_key) / args.module
        
        if target_path.is_file():
            script_path = target_path
            interpreter = config['interpreter']
            log_info(f"Direct script access: {script_path.name}")
        elif target_path.is_dir():
            # 1. Try to find a 'main' script first
            entry_script = next(target_path.glob("main*.sh"), None) or next(target_path.glob("main*.ps1"), None)
            
            # 2. Fallback: find ANY script in that directory
            if not entry_script:
                all_scripts = list(target_path.glob("*.sh")) + list(target_path.glob("*.ps1"))
                if all_scripts:
                    entry_script = all_scripts[0]
                    log_warn(f"No 'main' script found in {args.module}. Defaulting to {entry_script.name}")
                else:
                    log_error(f"No executable scripts found in module {args.module}")
                    return 1
            
            script_path = entry_script
            interpreter = config['interpreter']
            log_info(f"Module access: {args.module} -> {script_path.name}")
        else:
            log_error(f"Module or script '{args.module}' not found in {_module_dir(os_key)}")
            return 1
    else:
        # Default to main dispatcher
        script_path = _module_dir(os_key) / config['entry']
        interpreter = config['interpreter']

    if not script_path.exists():
        log_error(f"Entry script not found: {script_path}")
        return 1

    # 3. Interpreter Validation
    if not validate_interpreter(interpreter):
        log_error(f"Required interpreter '{interpreter}' is not installed on this system.")
        return 127

    # 4. Confirmation
    try:
        answer = input(f"  Proceed and run {Colors.CYAN}{script_path.name}{Colors.RESET}? [Y/n/c]: ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        log_warn("Cancelled by user.")
        return 130

    if is_cancel(answer) or answer.lower() == 'n':
        log_warn("Cancelled by user. Nothing was executed.")
        return 0
    if answer and answer.lower() != 'y':
        log_warn("Unrecognised answer - aborting.")
        return 1

    return _invoke(interpreter, script_path, os_key)

def main() -> int:
    _enable_windows_ansi()
    
    parser = argparse.ArgumentParser(description="System Setup Cross-Platform Launcher")
    parser.add_argument('--os', type=str, help="Override detected OS (linux, windows, darwin)")
    parser.add_argument('--module', type=str, help="Directly launch a specific module (e.g. networking, installer)")
    
    args = parser.parse_args()
    return run_main(args)

if __name__ == "__main__":
    sys.exit(main())
