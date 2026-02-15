#!/usr/bin/env python3
"""
Muse Device Discovery Script

Interactive CLI for discovering and selecting Muse devices via Bluetooth.
Saves the selected device address for use with the jaw clench detector.

Usage:
    ./discover.py              # Interactive discovery
    ./discover.py --list       # Just list devices, don't save
    ./discover.py --stream     # Discover, select, and start streaming
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# Config file location
CONFIG_DIR = Path.home() / ".skywalker"
CONFIG_FILE = CONFIG_DIR / "muse_config.json"


def print_pairing_instructions():
    """Print Muse S Athena (MS-03) pairing instructions."""
    print()
    print("=" * 60)
    print("MUSE S ATHENA PAIRING INSTRUCTIONS")
    print("=" * 60)
    print()
    print("1. Ensure Muse is charged and powered OFF")
    print("2. Hold the power button for 5+ seconds")
    print("3. LED will flash rapidly, then pulse WHITE (pairing mode)")
    print("4. Run discovery within 2 minutes (pairing mode times out)")
    print()
    print("Note: If Muse was previously paired, it may connect")
    print("automatically when powered on (LED pulses BLUE).")
    print("=" * 60)
    print()


def run_openmuse_find(timeout: int = 10) -> list[dict]:
    """
    Run OpenMuse find command and parse discovered devices.

    Returns:
        List of dicts with 'name' and 'address' keys
    """
    try:
        result = subprocess.run(
            ["OpenMuse", "find", "--timeout", str(timeout)],
            capture_output=True,
            text=True,
            timeout=timeout + 5
        )

        devices = []
        # Parse output lines like: "Found device Muse-AB12, MAC Address 00:55:DA:B9:FA:20"
        # Also handles macOS UUIDs like: "D24885CB-7624-7A9B-3A45-D12FAF96A9F8"
        pattern = r"Found device ([^,]+), MAC Address ([0-9A-Fa-f:-]+)"

        for line in result.stdout.splitlines():
            match = re.search(pattern, line)
            if match:
                devices.append({
                    "name": match.group(1).strip(),
                    "address": match.group(2).strip()
                })

        # Also check stderr (some output may go there)
        for line in result.stderr.splitlines():
            match = re.search(pattern, line)
            if match:
                devices.append({
                    "name": match.group(1).strip(),
                    "address": match.group(2).strip()
                })

        return devices

    except FileNotFoundError:
        print("ERROR: OpenMuse not found in PATH")
        print()
        print("Install OpenMuse:")
        print("  pip install git+https://github.com/DominiqueMakowski/OpenMuse.git")
        print()
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print("ERROR: Bluetooth scan timed out")
        sys.exit(1)


def display_devices(devices: list[dict]) -> None:
    """Display discovered devices in a numbered list."""
    if not devices:
        print("No Muse devices found.")
        print()
        print("Troubleshooting:")
        print("  - Is the Muse powered on?")
        print("  - Is it in pairing mode (LED pulsing white)?")
        print("  - Is Bluetooth enabled on this Mac?")
        print("  - Try moving closer to the Muse")
        return

    print()
    print(f"Found {len(devices)} Muse device(s):")
    print()
    for i, device in enumerate(devices, 1):
        print(f"  [{i}] {device['name']}")
        print(f"      Address: {device['address']}")
        print()


def select_device(devices: list[dict]) -> dict | None:
    """Prompt user to select a device from the list."""
    if not devices:
        return None

    if len(devices) == 1:
        response = input("Use this device? [Y/n]: ").strip().lower()
        if response in ("", "y", "yes"):
            return devices[0]
        return None

    while True:
        try:
            choice = input(f"Select device [1-{len(devices)}] or 'q' to quit: ").strip()
            if choice.lower() == 'q':
                return None
            index = int(choice) - 1
            if 0 <= index < len(devices):
                return devices[index]
            print(f"Please enter a number between 1 and {len(devices)}")
        except ValueError:
            print("Invalid input. Enter a number or 'q' to quit.")


def save_config(device: dict) -> None:
    """Save selected device to config file."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    config = {}
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE) as f:
                config = json.load(f)
        except json.JSONDecodeError:
            pass

    config["muse_address"] = device["address"]
    config["muse_name"] = device["name"]

    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)

    print(f"Saved to {CONFIG_FILE}")


def load_config() -> dict | None:
    """Load saved config if it exists."""
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE) as f:
                return json.load(f)
        except json.JSONDecodeError:
            return None
    return None


def start_streaming(address: str) -> None:
    """Start OpenMuse streaming in the foreground."""
    print()
    print("=" * 60)
    print("STARTING OPENMUSE STREAM")
    print("=" * 60)
    print(f"Address: {address}")
    print()
    print("Press Ctrl+C to stop streaming")
    print()

    try:
        # Run OpenMuse stream - this will block until interrupted
        subprocess.run(
            ["OpenMuse", "stream", "--address", address],
            check=True
        )
    except subprocess.CalledProcessError as e:
        print(f"OpenMuse stream exited with code {e.returncode}")
    except KeyboardInterrupt:
        print("\nStreaming stopped.")


def main():
    parser = argparse.ArgumentParser(
        description="Discover and configure Muse devices for Skywalker"
    )
    parser.add_argument(
        "--list", "-l",
        action="store_true",
        help="Just list devices, don't save selection"
    )
    parser.add_argument(
        "--stream", "-s",
        action="store_true",
        help="After selection, start OpenMuse streaming"
    )
    parser.add_argument(
        "--timeout", "-t",
        type=int,
        default=10,
        help="Bluetooth scan timeout in seconds (default: 10)"
    )
    parser.add_argument(
        "--no-instructions",
        action="store_true",
        help="Skip pairing instructions"
    )

    args = parser.parse_args()

    # Show current config if it exists
    current_config = load_config()
    if current_config and current_config.get("muse_address"):
        print(f"Current saved device: {current_config.get('muse_name', 'Unknown')}")
        print(f"                      {current_config['muse_address']}")
        print()

    # Show pairing instructions unless suppressed
    if not args.no_instructions:
        print_pairing_instructions()

    # Discover devices
    print(f"Scanning for Muse devices ({args.timeout} seconds)...")
    devices = run_openmuse_find(timeout=args.timeout)

    # Display results
    display_devices(devices)

    if args.list:
        # List only mode - exit after displaying
        return

    if not devices:
        sys.exit(1)

    # Interactive selection
    selected = select_device(devices)
    if not selected:
        print("No device selected.")
        sys.exit(0)

    print()
    print(f"Selected: {selected['name']} ({selected['address']})")

    # Save config
    save_config(selected)

    # Optionally start streaming
    if args.stream:
        start_streaming(selected["address"])
    else:
        print()
        print("To start streaming manually:")
        print(f"  OpenMuse stream --address {selected['address']}")
        print()
        print("Then run the detector in another terminal:")
        print("  python main.py --calibrate --verbose")


if __name__ == "__main__":
    main()
