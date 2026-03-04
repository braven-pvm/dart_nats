#!/usr/bin/env python3
"""
Sensor Bridge POC — unified CLI for ANT+ and BLE training sensors.

Commands:
  ant               Scan for all ANT+ training sensors
  ant --sensors     hrm power speed_cadence trainer  (pick a subset)
  ble               Discover BLE training devices nearby
  ble --connect     <address>  Stream live data from a BLE device
  ble --all         Show all BLE devices, not just training ones

Examples:
  python main.py ant
  python main.py ant --sensors hrm power
  python main.py ble
  python main.py ble --duration 20
  python main.py ble --connect AA:BB:CC:DD:EE:FF
"""

import argparse
import os
import sys

# Ensure libusb-1.0.dll (sitting alongside this file) is on the DLL search
# path so PyUSB can find it on Windows without a system-wide install.
_here = os.path.dirname(os.path.abspath(__file__))
if sys.platform == "win32" and _here not in os.environ.get("PATH", ""):
    os.environ["PATH"] = _here + os.pathsep + os.environ.get("PATH", "")


def cmd_ant(args):
    from ant_scan import scan, PROFILES
    scan(args.sensors)


def cmd_ble(args):
    import asyncio
    from ble_scan import discover, stream

    if args.connect:
        asyncio.run(stream(args.connect))
    else:
        devices = asyncio.run(discover(args.duration, args.all_devices))
        if not devices:
            if args.all_devices:
                print("[BLE] No devices found.")
            else:
                print("[BLE] No training devices found. Try: python main.py ble --all")


def main():
    parser = argparse.ArgumentParser(
        prog="sensor-bridge",
        description="Training sensor bridge — ANT+ and BLE",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # ── ant subcommand ──
    ant_parser = sub.add_parser("ant", help="Scan for ANT+ training sensors")
    ant_parser.add_argument(
        "--sensors",
        nargs="+",
        choices=["hrm", "power", "speed_cadence", "trainer"],
        default=["hrm", "power", "speed_cadence", "trainer"],
        help="Which sensor types to listen for (default: all)",
    )

    # ── ble subcommand ──
    ble_parser = sub.add_parser("ble", help="Discover / stream from BLE training devices")
    ble_parser.add_argument(
        "--connect",
        metavar="ADDRESS",
        help="Connect and stream live data from this BLE address",
    )
    ble_parser.add_argument(
        "--duration",
        type=float,
        default=10.0,
        help="Discovery scan duration in seconds (default: 10)",
    )
    ble_parser.add_argument(
        "--all",
        action="store_true",
        dest="all_devices",
        help="Show all BLE devices, not just known training services",
    )

    args = parser.parse_args()

    if args.command == "ant":
        cmd_ant(args)
    elif args.command == "ble":
        cmd_ble(args)


if __name__ == "__main__":
    main()
