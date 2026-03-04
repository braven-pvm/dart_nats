#!/usr/bin/env python3
"""
VO2 Master BLE connector.

Device: VO2 Master Health Sensors Inc.
Protocol: Nordic nRF custom GATT (built on Nordic LED Button Service UUIDs)
BLE Address: F9:1A:59:CC:BA:E7  (randomised — scan to rediscover if changed)

## Known GATT layout:
Service 0x1523 (Nordic LED Button Service base, proprietary extensions):
  0x1525  [write]          Control / command channel
  0x1526  [read, notify]   4 bytes  — likely O2 sensor value (float32 LE)
  0x1527  [read, notify]   6 bytes  — likely CO2 / flow sensor
  0x1528  [read, notify]   8 bytes  — likely multi-measurement packet
  0x1529  [read, notify]  10 bytes  — includes ambient temperature (float32[0] ~25°C)
  0x1533  [read, notify]  42 bytes  — likely full aggregated data packet

Battery Service (0x180F):
  0x2A19  [read, notify]   Battery Level %

Device Information (0x180A):
  0x2A29  Manufacturer: VO2 Master Health Sensors Inc.
  0x2A24  Model: 1.6.2
  0x2A25  Serial: 5342
  0x2A26  Firmware: 14
  0x2A27  Hardware: 15

## Protocol status:
  ✅ Connection works
  ✅ Device info readable
  ✅ Data channels identified
  ⚠️  Notifications only fire during ACTIVE MEASUREMENT (mask worn + breathing)
  ❓  Exact command to start measurement session not yet known

## To reverse-engineer the start command:
  Use nRF Sniffer for Bluetooth LE (Wireshark plugin) or
  Android/iOS BLE proxy to capture what the official VO2 Master app sends
  on connect and before data starts flowing.
"""

import asyncio
import struct
import time
from dataclasses import dataclass
from typing import Callable, Optional

from bleak import BleakClient, BleakScanner
from bleak.backends.device import BLEDevice

# ── Constants ─────────────────────────────────────────────────────────────────

DEVICE_NAME_PREFIX = "VO2 Master"

SVC_NORDIC      = "00001523-1212-efde-1523-785feabcd123"
CHAR_CTRL       = "00001525-1212-efde-1523-785feabcd123"  # write: commands
CHAR_O2         = "00001526-1212-efde-1523-785feabcd123"  # 4 bytes  (float32 LE)
CHAR_CO2_FLOW   = "00001527-1212-efde-1523-785feabcd123"  # 6 bytes
CHAR_MULTI      = "00001528-1212-efde-1523-785feabcd123"  # 8 bytes
CHAR_ENV        = "00001529-1212-efde-1523-785feabcd123"  # 10 bytes (temp at offset 0)
CHAR_AGGREGATE  = "00001533-1212-efde-1523-785feabcd123"  # 42 bytes
CHAR_BATTERY    = "00002a19-0000-1000-8000-00805f9b34fb"

NOTIFY_CHARS = [CHAR_O2, CHAR_CO2_FLOW, CHAR_MULTI, CHAR_ENV, CHAR_AGGREGATE]

# ── Data model ────────────────────────────────────────────────────────────────

@dataclass
class VO2MasterReading:
    timestamp: float
    char_uuid: str
    raw: bytes

    # Parsed fields (populated as protocol is understood)
    temperature_c: Optional[float] = None      # from CHAR_ENV float32[0]
    o2_raw: Optional[float] = None             # from CHAR_O2 float32[0]

    def __str__(self):
        parts = [f"char={self.char_uuid[4:8]}", f"raw={self.raw.hex()}"]
        if self.temperature_c is not None:
            parts.append(f"temp={self.temperature_c:.1f}°C")
        if self.o2_raw is not None:
            parts.append(f"o2_raw={self.o2_raw:.5f}")
        return " | ".join(parts)


def _parse(char_uuid: str, data: bytes) -> VO2MasterReading:
    reading = VO2MasterReading(
        timestamp=time.time(),
        char_uuid=char_uuid,
        raw=data,
    )

    if char_uuid == CHAR_ENV and len(data) >= 4:
        # Byte 0-3: float32 — consistently ~25°C in lab = ambient temperature
        reading.temperature_c = round(struct.unpack_from("<f", data, 0)[0], 2)

    if char_uuid == CHAR_O2 and len(data) >= 4:
        reading.o2_raw = struct.unpack_from("<f", data, 0)[0]

    return reading


# ── Scanner ───────────────────────────────────────────────────────────────────

async def find_device(timeout: float = 10.0) -> Optional[BLEDevice]:
    """Scan for a VO2 Master device and return the first found."""
    print(f"[VO2] Scanning for '{DEVICE_NAME_PREFIX}' ({timeout}s)...")
    device = await BleakScanner.find_device_by_filter(
        lambda d, adv: d.name and d.name.startswith(DEVICE_NAME_PREFIX),
        timeout=timeout,
    )
    if device:
        print(f"[VO2] Found: {device.name} at {device.address}")
    else:
        print("[VO2] Not found.")
    return device


# ── Connection & streaming ────────────────────────────────────────────────────

async def connect_and_stream(
    address: str,
    on_reading: Callable[[VO2MasterReading], None],
    duration_s: Optional[float] = None,
):
    """
    Connect to a VO2 Master and stream readings.

    Args:
        address:    BLE address (or name) of the device.
        on_reading: Callback invoked for each incoming reading.
        duration_s: How long to stream (None = until Ctrl+C).
    """
    def _notify_handler(characteristic, data: bytearray):
        reading = _parse(characteristic.uuid, bytes(data))
        on_reading(reading)

    print(f"[VO2] Connecting to {address}...")
    async with BleakClient(address) as client:
        # ── Device info ──
        info = {}
        for uuid, label in [
            ("00002a29-0000-1000-8000-00805f9b34fb", "manufacturer"),
            ("00002a24-0000-1000-8000-00805f9b34fb", "model"),
            ("00002a25-0000-1000-8000-00805f9b34fb", "serial"),
            ("00002a26-0000-1000-8000-00805f9b34fb", "firmware"),
            (CHAR_BATTERY, "battery"),
        ]:
            try:
                val = await client.read_gatt_char(uuid)
                info[label] = val[0] if label == "battery" else val.decode("utf-8", errors="replace").strip()
            except Exception:
                pass

        print(f"[VO2] {info.get('manufacturer','?')} | Model {info.get('model','?')} | "
              f"Serial {info.get('serial','?')} | FW {info.get('firmware','?')} | "
              f"Battery {info.get('battery','?')}%")

        # ── Subscribe ──
        for uuid in NOTIFY_CHARS:
            await client.start_notify(uuid, _notify_handler)

        print(f"[VO2] Subscribed to {len(NOTIFY_CHARS)} channels. Waiting for measurements...")
        print("[VO2] NOTE: Data only streams when the mask is worn and measurement is active.")
        print("[VO2] Press Ctrl+C to stop.\n")

        try:
            if duration_s:
                await asyncio.sleep(duration_s)
            else:
                while True:
                    await asyncio.sleep(1)
        except (KeyboardInterrupt, asyncio.CancelledError):
            pass
        finally:
            for uuid in NOTIFY_CHARS:
                try:
                    await client.stop_notify(uuid)
                except Exception:
                    pass
            print("\n[VO2] Disconnected.")


# ── Default print callback ────────────────────────────────────────────────────

def print_reading(reading: VO2MasterReading):
    ts = time.strftime("%H:%M:%S", time.localtime(reading.timestamp))
    print(f"[{ts}] {reading}")


# ── CLI ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse
    import os, sys

    # Ensure libusb / DLL path (in case called directly on Windows)
    _here = os.path.dirname(os.path.abspath(__file__))
    if sys.platform == "win32" and _here not in os.environ.get("PATH", ""):
        os.environ["PATH"] = _here + os.pathsep + os.environ.get("PATH", "")

    parser = argparse.ArgumentParser(description="VO2 Master BLE reader")
    parser.add_argument("--address", default=None, help="BLE address (skip scan)")
    parser.add_argument("--scan-timeout", type=float, default=10.0, help="Scan timeout in seconds")
    parser.add_argument("--duration", type=float, default=None, help="Stream duration in seconds (default: indefinite)")
    args = parser.parse_args()

    async def run():
        addr = args.address
        if not addr:
            device = await find_device(args.scan_timeout)
            if not device:
                return
            addr = device.address
        await connect_and_stream(addr, print_reading, args.duration)

    asyncio.run(run())
