#!/usr/bin/env python3
"""
BLE training sensor scanner.

Discovers and reads BLE devices advertising standard cycling/fitness GATT services:
  - Heart Rate Service          (0x180D)
  - Cycling Power Service       (0x1818)
  - Cycling Speed & Cadence     (0x1816)
  - Fitness Machine Service     (0x1826)  — smart trainers

Usage:
  python ble_scan.py                  # discover all training devices nearby
  python ble_scan.py --connect <addr> # connect and stream live data
"""

import asyncio
import struct
from dataclasses import dataclass
from typing import Optional, Dict, Any

from bleak import BleakScanner, BleakClient
from bleak.backends.device import BLEDevice
from bleak.backends.scanner import AdvertisementData

# ── GATT service UUIDs (16-bit short form, expanded) ─────────────────────────

SERVICES = {
    "00001800-0000-1000-8000-00805f9b34fb": "Generic Access",
    "0000180d-0000-1000-8000-00805f9b34fb": "Heart Rate",
    "00001818-0000-1000-8000-00805f9b34fb": "Cycling Power",
    "00001816-0000-1000-8000-00805f9b34fb": "Cycling Speed & Cadence",
    "00001826-0000-1000-8000-00805f9b34fb": "Fitness Machine",
    "00001814-0000-1000-8000-00805f9b34fb": "Running Speed & Cadence",
}

# UUIDs we care about (subset used for filtering discoveries)
TRAINING_SERVICE_UUIDS = {
    "0000180d-0000-1000-8000-00805f9b34fb",  # Heart Rate
    "00001818-0000-1000-8000-00805f9b34fb",  # Cycling Power
    "00001816-0000-1000-8000-00805f9b34fb",  # Cycling Speed & Cadence
    "00001826-0000-1000-8000-00805f9b34fb",  # Fitness Machine
}

# ── GATT characteristic UUIDs ─────────────────────────────────────────────────

CHAR_HEART_RATE_MEASUREMENT = "00002a37-0000-1000-8000-00805f9b34fb"
CHAR_CYCLING_POWER_MEASUREMENT = "00002a63-0000-1000-8000-00805f9b34fb"
CHAR_CSC_MEASUREMENT = "00002a5b-0000-1000-8000-00805f9b34fb"
CHAR_FITNESS_MACHINE_STATUS = "00002ada-0000-1000-8000-00805f9b34fb"
CHAR_INDOOR_BIKE_DATA = "00002ad2-0000-1000-8000-00805f9b34fb"
CHAR_TRAINING_STATUS = "00002ad3-0000-1000-8000-00805f9b34fb"

# ── Data parsers ──────────────────────────────────────────────────────────────

def parse_heart_rate(data: bytes) -> Dict[str, Any]:
    """
    Heart Rate Measurement characteristic (0x2A37).
    Byte 0: Flags
      bit 0: HR format (0=uint8, 1=uint16)
      bit 2: Energy Expended present
      bit 3: RR-Interval present
    """
    flags = data[0]
    hr_format_16bit = bool(flags & 0x01)
    has_energy = bool(flags & 0x04)
    has_rr = bool(flags & 0x08)
    offset = 1

    if hr_format_16bit:
        heart_rate = struct.unpack_from("<H", data, offset)[0]
        offset += 2
    else:
        heart_rate = data[offset]
        offset += 1

    result: Dict[str, Any] = {
        "type": "heart_rate",
        "heart_rate_bpm": heart_rate,
    }

    if has_energy and len(data) > offset + 1:
        result["energy_expended_kj"] = struct.unpack_from("<H", data, offset)[0]
        offset += 2

    if has_rr and len(data) > offset + 1:
        rr_intervals = []
        while offset + 1 < len(data):
            rr_raw = struct.unpack_from("<H", data, offset)[0]
            rr_intervals.append(round(rr_raw / 1024 * 1000))  # convert to ms
            offset += 2
        result["rr_intervals_ms"] = rr_intervals

    return result


def parse_cycling_power(data: bytes) -> Dict[str, Any]:
    """
    Cycling Power Measurement characteristic (0x2A63).
    Bytes 0-1: Flags
    Bytes 2-3: Instantaneous Power (W, sint16)
    Optional fields per flags:
      bit 4: Wheel Revolution Data
      bit 5: Crank Revolution Data
      bit 8: Accumulated Torque
    """
    if len(data) < 4:
        return {"type": "power_raw", "raw": data.hex()}
    flags = struct.unpack_from("<H", data, 0)[0]
    power_w = struct.unpack_from("<h", data, 2)[0]  # signed int16

    result: Dict[str, Any] = {
        "type": "cycling_power",
        "power_w": power_w,
    }

    offset = 4
    if flags & 0x0010 and len(data) >= offset + 6:  # Wheel Revolution Data
        cum_wheel_revs = struct.unpack_from("<I", data, offset)[0]
        wheel_event_time = struct.unpack_from("<H", data, offset + 4)[0]
        result["wheel_revs"] = cum_wheel_revs
        result["wheel_event_time"] = wheel_event_time
        offset += 6

    if flags & 0x0020 and len(data) >= offset + 4:  # Crank Revolution Data
        cum_crank_revs = struct.unpack_from("<H", data, offset)[0]
        crank_event_time = struct.unpack_from("<H", data, offset + 2)[0]
        result["crank_revs"] = cum_crank_revs
        result["crank_event_time"] = crank_event_time

    return result


def parse_csc(data: bytes) -> Dict[str, Any]:
    """
    CSC Measurement characteristic (0x2A5B).
    Byte 0: Flags (bit 0 = wheel data present, bit 1 = crank data present)
    """
    if len(data) < 1:
        return {"type": "csc_raw", "raw": data.hex()}
    flags = data[0]
    result: Dict[str, Any] = {"type": "speed_cadence"}
    offset = 1

    if flags & 0x01 and len(data) >= offset + 6:
        result["cumulative_wheel_revs"] = struct.unpack_from("<I", data, offset)[0]
        result["last_wheel_event_time"] = struct.unpack_from("<H", data, offset + 4)[0]
        offset += 6

    if flags & 0x02 and len(data) >= offset + 4:
        result["cumulative_crank_revs"] = struct.unpack_from("<H", data, offset)[0]
        result["last_crank_event_time"] = struct.unpack_from("<H", data, offset + 2)[0]

    return result


def parse_indoor_bike_data(data: bytes) -> Dict[str, Any]:
    """
    Indoor Bike Data characteristic (0x2AD2) — FTMS / smart trainers.
    Bytes 0-1: Flags
    Fields per flags (all optional, little-endian):
      bit 0:  Instantaneous Speed (0.01 km/h)
      bit 1:  Average Speed
      bit 2:  Instantaneous Cadence (0.5 RPM)
      bit 3:  Average Cadence
      bit 5:  Resistance Level
      bit 6:  Instantaneous Power (W, sint16)
      bit 7:  Average Power
    """
    if len(data) < 2:
        return {"type": "bike_data_raw", "raw": data.hex()}
    flags = struct.unpack_from("<H", data, 0)[0]
    result: Dict[str, Any] = {"type": "indoor_bike"}
    offset = 2

    if not (flags & 0x0001) and len(data) >= offset + 2:  # bit 0 = 0 means speed IS present
        speed = struct.unpack_from("<H", data, offset)[0] * 0.01
        result["speed_kmh"] = round(speed, 2)
        offset += 2

    if flags & 0x0004 and len(data) >= offset + 2:  # instantaneous cadence
        cadence = struct.unpack_from("<H", data, offset)[0] * 0.5
        result["cadence_rpm"] = round(cadence, 1)
        offset += 2

    if flags & 0x0040 and len(data) >= offset + 2:  # instantaneous power
        result["power_w"] = struct.unpack_from("<h", data, offset)[0]
        offset += 2

    return result


# ── Subscriber map: characteristic UUID → parser ──────────────────────────────

NOTIFY_PARSERS = {
    CHAR_HEART_RATE_MEASUREMENT:  parse_heart_rate,
    CHAR_CYCLING_POWER_MEASUREMENT: parse_cycling_power,
    CHAR_CSC_MEASUREMENT:         parse_csc,
    CHAR_INDOOR_BIKE_DATA:        parse_indoor_bike_data,
}

# ── Discovery ─────────────────────────────────────────────────────────────────

@dataclass
class FoundDevice:
    device: BLEDevice
    services: list[str]
    rssi: int


async def discover(duration_s: float = 10.0, all_devices: bool = False) -> list[FoundDevice]:
    """Scan for nearby BLE devices. Filters to training services unless all_devices=True."""
    print(f"\n[BLE] Scanning for {duration_s}s...\n")
    found: list[FoundDevice] = []
    seen = set()

    def on_detection(device: BLEDevice, adv: AdvertisementData):
        if device.address in seen:
            return
        service_uuids = {u.lower() for u in adv.service_uuids}
        matched = service_uuids & TRAINING_SERVICE_UUIDS
        if not matched and not all_devices:
            return
        seen.add(device.address)
        labels = [SERVICES.get(u, u) for u in matched] if matched else ["(unknown)"]
        found.append(FoundDevice(device=device, services=labels, rssi=adv.rssi))
        print(f"  [{adv.rssi:>4} dBm]  {device.address}  {device.name or '?':<30}  {', '.join(labels)}")

    scanner = BleakScanner(detection_callback=on_detection)
    await scanner.start()
    await asyncio.sleep(duration_s)
    await scanner.stop()
    return found


# ── Connection & streaming ────────────────────────────────────────────────────

async def stream(address: str):
    """Connect to a device and stream all supported training characteristics."""
    import time

    def on_notify(characteristic, data: bytearray):
        uuid = characteristic.uuid.lower()
        parser = NOTIFY_PARSERS.get(uuid)
        if parser:
            result = parser(bytes(data))
            ts = time.strftime("%H:%M:%S")
            parts = [f"{k}={v}" for k, v in result.items() if k not in ("type",)]
            print(f"[{ts}] {result.get('type','?'):<20} | {' | '.join(parts)}")

    print(f"\n[BLE] Connecting to {address}...")
    async with BleakClient(address) as client:
        print(f"[BLE] Connected. Services:")
        for svc in client.services:
            label = SERVICES.get(svc.uuid.lower(), svc.uuid)
            print(f"  {label}")

        subscribed = []
        for uuid, _ in NOTIFY_PARSERS.items():
            try:
                await client.start_notify(uuid, on_notify)
                subscribed.append(uuid)
                print(f"[BLE] Subscribed: {uuid}")
            except Exception:
                pass  # characteristic not on this device

        if not subscribed:
            print("[BLE] No supported characteristics found on this device.")
            return

        print("\n[BLE] Streaming... Press Ctrl+C to stop.\n")
        try:
            while True:
                await asyncio.sleep(1)
        except KeyboardInterrupt:
            print("\n[BLE] Stopping...")
            for uuid in subscribed:
                try:
                    await client.stop_notify(uuid)
                except Exception:
                    pass


# ── Entrypoint ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="BLE training sensor scanner")
    parser.add_argument("--connect", metavar="ADDRESS", help="Connect and stream from this BLE address")
    parser.add_argument("--duration", type=float, default=10.0, help="Scan duration in seconds (default 10)")
    parser.add_argument("--all", action="store_true", dest="all_devices", help="Show all BLE devices, not just training ones")
    args = parser.parse_args()

    if args.connect:
        asyncio.run(stream(args.connect))
    else:
        devices = asyncio.run(discover(args.duration, args.all_devices))
        if not devices:
            if args.all_devices:
                print("[BLE] No devices found.")
            else:
                print("[BLE] No training devices found. Try --all to see all BLE devices.")
        else:
            print(f"\n[BLE] Found {len(devices)} device(s).")
            print("To stream data: python ble_scan.py --connect <ADDRESS>")
