#!/usr/bin/env python3
"""
runner.py
---------
Entry-point script that:
  1. Detects the operating system the user is running.
  2. Automatically runs the appropriate main execution script for
     the detected OS from `module/<os>/main.*`.
  3. Provides a clean, colorful terminal UI inspired by
     `module/linux/dhcp-setup.sh`.

Usage:
    python runner.py
"""

import os
import platform
import subprocess
import sys
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


# Enable ANSI colors on Windows (Windows 10+ supports VT sequences natively,
# older builds need a small enable call — `colorama` would also work but we
# keep this stdlib-only).
def _enable_windows_ansi():
    if os.name == 'nt':
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            # ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x4
            kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 0x4 | 0x2)
        except Exception:
            pass


# ============================================================================
# UI HELPERS
# ============================================================================

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
    """True if the user's input signals 'cancel / quit'."""
    return value.strip().lower() in {'c', 'cancel', 'q', 'quit', 'exit'}


# ============================================================================
# OS DETECTION
# ============================================================================

# Map of platform.system() values to the folder name used under `module/`.
OS_MAP = {
    'Linux':   'linux',
    'Windows': 'windows',
    'Darwin':  'darwin',   # macOS
}

# Friendly human-readable name for the detected OS.
OS_PRETTY = {
    'linux':   'Linux',
    'windows': 'Windows',
    'darwin':  'macOS',
}


def detect_os() -> str:
    """
    Detect the host operating system.

    Returns one of:
        'linux' | 'windows' | 'darwin' | 'unknown'
    """
    return OS_MAP.get(platform.system(), 'unknown')


def detect_os_details() -> dict:
    """Return richer info about the host OS, useful for logging."""
    return {
        'system':   platform.system(),       # e.g. 'Linux'
        'release':  platform.release(),      # e.g. '5.15.0-105-generic'
        'version':  platform.version(),      # e.g. '#109~20.04.1-Ubuntu SMP ...'
        'machine':  platform.machine(),      # e.g. 'x86_64'
        'python':   platform.python_version(),
        'node':     platform.node() or 'localhost',
    }


# ============================================================================
# MAIN-RUNNER (auto-launches the per-OS entry script)
# ============================================================================

# Per-OS: which interpreter and which entry file under `module/<os>/` to run.
# You can extend this dict as you add more operating systems.
RUNNERS = {
    'linux':   {'interpreter': 'bash', 'entry': 'main-linux.sh'},
    'windows': {'interpreter': 'powershell', 'entry': 'main-win.ps1'},
    'darwin':  {'interpreter': 'bash', 'entry': 'main-mac.sh'},
}


def _project_root() -> Path:
    """Resolve the project root (directory containing this runner.py)."""
    return Path(__file__).resolve().parent


def _module_dir(os_key: str) -> Path:
    """Return the absolute path to `module/<os_key>/`."""
    return _project_root() / 'module' / os_key


def _resolve_entry(os_key: str):
    """Return (interpreter, entry_script_path) for the given OS, or None if missing."""
    config = RUNNERS.get(os_key)
    if not config:
        return None

    entry_path = _module_dir(os_key) / config['entry']
    if not entry_path.exists():
        return None

    return config['interpreter'], entry_path


def _print_os_summary(os_key: str, details: dict):
    """Pretty-print a small OS-detection summary box (matches dhcp-setup.sh style)."""
    pretty = OS_PRETTY.get(os_key, os_key.capitalize())
    print(f"  {Colors.BOLD}OS Detected:{Colors.RESET}     {Colors.GREEN}{pretty}{Colors.RESET}")
    print(f"  {Colors.BOLD}Kernel:    {Colors.RESET}     {Colors.CYAN}{details['system']} {details['release']}{Colors.RESET}")
    print(f"  {Colors.BOLD}Arch:      {Colors.RESET}     {Colors.CYAN}{details['machine']}{Colors.RESET}")
    print(f"  {Colors.BOLD}Python:    {Colors.RESET}     {Colors.CYAN}{details['python']}{Colors.RESET}")
    print(f"  {Colors.BOLD}Hostname:  {Colors.RESET}     {Colors.CYAN}{details['node']}{Colors.RESET}")
    print_separator()


def _invoke(interpreter: str, script_path: Path, os_key: str) -> int:
    """
    Execute the per-OS entry script with the correct interpreter.

    Returns the subprocess exit code.
    """
    cwd = str(script_path.parent)

    if os_key == 'windows':
        # PowerShell script. -ExecutionPolicy Bypass so it runs without
        # requiring the user to pre-allow unsigned scripts.
        cmd = ['powershell', '-ExecutionPolicy', 'Bypass', '-File', str(script_path)]
    elif interpreter == 'bash':
        cmd = ['bash', str(script_path)]
    else:
        cmd = [interpreter, str(script_path)]

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


def run_main(os_key: str | None = None) -> int:
    """
    Detect the host OS (unless `os_key` is supplied) and run the matching
    main execution script under `module/<os_key>/`.

    Returns the exit code of the spawned script, or 1 on failure.
    """
    print_banner()

    if os_key is None:
        log_info("Detecting host operating system...")
        os_key = detect_os()

    if os_key == 'unknown':
        log_error("Unsupported operating system.")
        log_warn("This launcher supports: Linux, Windows, macOS.")
        return 1

    details = detect_os_details()
    _print_os_summary(os_key, details)
    log_success(f"Launcher will run the {Colors.GREEN}{OS_PRETTY[os_key]}{Colors.RESET} workflow.")
    print()

    resolved = _resolve_entry(os_key)
    if resolved is None:
        log_error(f"No entry script found for {OS_PRETTY[os_key]}.")
        log_warn(f"Expected one of: {', '.join(r['entry'] for r in RUNNERS.values())}")
        log_warn(f"Inside: {_module_dir(os_key)}")
        return 1

    interpreter, script_path = resolved

    # Quick confirmation prompt so the user can back out if desired.
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


# ============================================================================
# ENTRY POINT
# ============================================================================

def main() -> int:
    """Top-level entry point used by `python runner.py`."""
    _enable_windows_ansi()
    return run_main()


if __name__ == "__main__":
    sys.exit(main())
