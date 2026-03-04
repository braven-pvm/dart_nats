#!/usr/bin/env python3
"""
ANT+ training sensor scanner.

Listens for broadcasts from common training devices:
  - Heart Rate Monitor          (device type 120, channel period 8070)
  - Bicycle Power Meter         (device type 11,  channel period 8182)
  - Speed & Cadence Sensor      (device type 121, channel period 8086)
  - FE-C Smart Trainer          (device type 17,  channel period 8192)

Requires the ANT USB-m Stick with WinUSB driver (Zadig) on Windows.
"""

import sys
import time
import struct
import threading
from dataclasses import dataclass, field
from typing import Optional, Dict, Any

from openant.easy.node import Node
from openant.easy.channel import Channel

# ANT+ network key (public, from thisisant.com)
NETWORK_KEY = [0xB9, 0xA5, 0x21, 0xFB, 0xBD, 0x72, 0xC3, 0x45]

# ANT+ radio frequency offset (2400 + 57 = 2457 MHz)
ANT_PLUS_FREQ = 57

# ── Device profiles ──────────────────────────────────────────────────────────

@dataclass
class DeviceProfile:
    name: str
    device_type: int
    period: int          # ANT channel period (32768 / message_rate)
    description: str


PROFILES: Dict[str, DeviceProfile] = {
    "hrm": DeviceProfile(
        name="Heart Rate Monitor",
        device_type=120,
        period=8070,
        description="Broadcasts HR in BPM",
    ),
    "power": DeviceProfile(
        name="Bicycle Power Meter",
        device_type=11,
        period=8182,
        description="Broadcasts power (W) and cadence (RPM)",
    ),
    "speed_cadence": DeviceProfile(
        name="Speed & Cadence Sensor",
        device_type=121,
        period=8086,
        description="Broadcasts wheel speed and pedal cadence",
    ),
    "trainer": DeviceProfile(
        name="FE-C Smart Trainer",
        device_type=17,
        period=8192,
        description="Broadcasts trainer state, power, speed, grade",
    ),
}

# ── Data page parsers ─────────────────────────────────────────────────────────

def parse_hrm(data: bytes, device_id: int) -> Dict[str, Any]:
    """
    HRM broadcast: all pages share the same byte 7 for HR.
    Byte 7 = Heart Rate (BPM)
    Byte 6 = Beat count (wraps at 255)
    Bytes 4-5 = Beat event time (1/1024 s units)
    """
    if len(data) < 8:
        return {}
    return {
        "type": "heart_rate",
        "device_id": device_id,
        "heart_rate_bpm": data[7],
        "beat_count": data[6],
        "beat_event_time_ms": round((struct.unpack_from("<H", data, 4)[0] / 1024) * 1000),
    }


def parse_power(data: bytes, device_id: int) -> Optional[Dict[str, Any]]:
    """
    Power meter - page 0x10 (Standard Power Only) is the main data page.
    Byte 0  = Page number
    Byte 1  = Update event count
    Byte 2  = Pedal power % (0xFF = not used)
    Byte 3  = Instantaneous cadence (RPM, 0xFF = invalid)
    Bytes 4-5 = Accumulated power (W)
    Bytes 6-7 = Instantaneous power (W)
    """
    if len(data) < 8:
        return None
    page = data[0] & 0x7F
    if page == 0x10:
        power_w = struct.unpack_from("<H", data, 6)[0]
        cadence = data[3] if data[3] != 0xFF else None
        return {
            "type": "power",
            "device_id": device_id,
            "power_w": power_w,
            "cadence_rpm": cadence,
            "page": page,
        }
    # Other pages (calibration, pedal smoothness, etc.) — just log them
    return {
        "type": "power_raw",
        "device_id": device_id,
        "page": page,
        "raw": data.hex(),
    }


def parse_speed_cadence(data: bytes, device_id: int) -> Dict[str, Any]:
    """
    Combined Speed & Cadence sensor (device type 121).
    Bytes 0-1 = Cadence event time (1/1024 s)
    Byte 2    = Cumulative cadence revolution count
    Bytes 3-4 = Speed event time (1/1024 s)
    Bytes 5-6 = Cumulative wheel revolution count
    """
    if len(data) < 8:
        return {}
    cadence_event_time = struct.unpack_from("<H", data, 0)[0]
    cadence_rev_count  = data[2]
    speed_event_time   = struct.unpack_from("<H", data, 3)[0]
    wheel_rev_count    = struct.unpack_from("<H", data, 5)[0]
    return {
        "type": "speed_cadence",
        "device_id": device_id,
        "cadence_event_time": cadence_event_time,
        "cadence_rev_count": cadence_rev_count,
        "speed_event_time": speed_event_time,
        "wheel_rev_count": wheel_rev_count,
    }


def parse_trainer(data: bytes, device_id: int) -> Optional[Dict[str, Any]]:
    """
    FE-C trainer - page 0x19 (General FE Data) and 0x25 (Specific Trainer Data).
    Page 0x19:
      Byte 2    = Equipment type
      Bytes 3-4 = Elapsed time (0.25 s units)
      Bytes 5-6 = Distance travelled (m)
      Bytes 7:0-11 = Speed (0.001 m/s units, 12 bits)
    Page 0x25:
      Bytes 4-5 = Instantaneous power (W)
      Byte 6    = Trainer status flags
    """
    if len(data) < 8:
        return None
    page = data[0] & 0x7F
    if page == 0x19:
        speed_raw = ((data[7] & 0x0F) << 8) | data[6]  # 12-bit, 0.001 m/s units
        return {
            "type": "trainer_general",
            "device_id": device_id,
            "speed_ms": round(speed_raw * 0.001, 2),
            "speed_kmh": round(speed_raw * 0.001 * 3.6, 1),
            "elapsed_time_s": round(struct.unpack_from("<H", data, 3)[0] * 0.25, 2),
        }
    elif page == 0x25:
        power_w = struct.unpack_from("<H", data, 4)[0] & 0x0FFF
        return {
            "type": "trainer_power",
            "device_id": device_id,
            "power_w": power_w,
            "trainer_status": hex(data[6]),
        }
    return {
        "type": "trainer_raw",
        "device_id": device_id,
        "page": page,
        "raw": data.hex(),
    }


# ── Channel setup ─────────────────────────────────────────────────────────────

def make_channel(node: Node, profile: DeviceProfile, channel_num: int, parser_fn):
    """Open a wildcard slave channel for the given ANT+ device profile."""
    channel = node.new_channel(Channel.Type.BIDIRECTIONAL_RECEIVE, 0, channel_num)
    channel.set_id(0, profile.device_type, 0)   # 0 = wildcard device number
    channel.set_search_timeout(255)               # 255 = never time out
    channel.set_period(profile.period)
    channel.set_rf_freq(ANT_PLUS_FREQ)

    def on_data(data):
        device_id = 0  # will be updated once paired
        result = parser_fn(bytes(data), device_id)
        if result:
            _print_sensor(profile.name, result)

    channel.on_broadcast_data = on_data
    channel.on_burst_data = on_data
    channel.open()
    print(f"[ANT+] Listening for {profile.name} (device type {profile.device_type}) on channel {channel_num}")
    return channel


# ── Output ────────────────────────────────────────────────────────────────────

def _print_sensor(sensor_name: str, data: Dict[str, Any]):
    ts = time.strftime("%H:%M:%S")
    parts = [f"{k}={v}" for k, v in data.items() if k not in ("type", "device_id", "raw", "page")]
    print(f"[{ts}] {sensor_name:<28} | {' | '.join(parts)}")


# ── Main ──────────────────────────────────────────────────────────────────────

def scan(profiles: list[str] = None):
    """
    Start scanning for ANT+ training sensors.

    Args:
        profiles: list of profile keys to listen for (default: all).
                  Options: "hrm", "power", "speed_cadence", "trainer"
    """
    active = {k: PROFILES[k] for k in (profiles or PROFILES.keys())}

    print(f"\n[ANT+] Initialising stick (VID=0x0FCF, PID=0x1009)...")
    node = Node()
    node.set_network_key(0, NETWORK_KEY)

    parsers = {
        "hrm":           parse_hrm,
        "power":         parse_power,
        "speed_cadence": parse_speed_cadence,
        "trainer":       parse_trainer,
    }

    channels = []
    for i, (key, profile) in enumerate(active.items()):
        ch = make_channel(node, profile, i, parsers[key])
        channels.append(ch)

    print(f"[ANT+] Scanning for: {', '.join(p.name for p in active.values())}")
    print("[ANT+] Press Ctrl+C to stop.\n")

    try:
        node.start()
    except KeyboardInterrupt:
        print("\n[ANT+] Stopping...")
    finally:
        for ch in channels:
            ch.close()
        node.stop()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="ANT+ training sensor scanner")
    parser.add_argument(
        "--sensors",
        nargs="+",
        choices=list(PROFILES.keys()),
        default=list(PROFILES.keys()),
        help="Which sensors to listen for (default: all)",
    )
    args = parser.parse_args()
    scan(args.sensors)
