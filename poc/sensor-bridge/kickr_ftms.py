#!/usr/bin/env python3
"""
KICKR FTMS (Fitness Machine Service) BLE controller.

Implements the full FTMS control interface for Wahoo KICKR trainers over BLE:
  - ERG mode (target power in watts)
  - Resistance mode (0-100%)
  - Simulation mode (grade, wind, CRR, Cw)

Architecture mirrors the Kotlin FtmsController used in braven_extension.
Sensor metrics (power, cadence) are better consumed via ANT+ FE-C separately.

Usage:
    python kickr_ftms.py --watts 200
    python kickr_ftms.py --scan
    python kickr_ftms.py --address "XX:XX:XX:XX:XX:XX" --watts 250
    python kickr_ftms.py --address "XX:XX:XX:XX:XX:XX" --simulate --grade 3.5
"""

import asyncio
import struct
import time
import argparse
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional, Callable, Awaitable

from bleak import BleakClient, BleakScanner
from bleak.backends.characteristic import BleakGATTCharacteristic
from bleak.backends.device import BLEDevice

# ── FTMS UUIDs ────────────────────────────────────────────────────────────────

FTMS_SERVICE_UUID       = "00001826-0000-1000-8000-00805f9b34fb"
CONTROL_POINT_UUID      = "00002ad9-0000-1000-8000-00805f9b34fb"  # write + indicate
STATUS_UUID             = "00002ada-0000-1000-8000-00805f9b34fb"  # notify
FEATURE_UUID            = "00002acc-0000-1000-8000-00805f9b34fb"  # read
INDOOR_BIKE_DATA_UUID   = "00002ad2-0000-1000-8000-00805f9b34fb"  # notify
POWER_RANGE_UUID        = "00002ad8-0000-1000-8000-00805f9b34fb"  # read

# ── FTMS Control Point Op Codes ───────────────────────────────────────────────

OP_REQUEST_CONTROL          = 0x00
OP_RESET                    = 0x01
OP_SET_TARGET_RESISTANCE    = 0x04  # 3 bytes: op + uint16 level×10
OP_SET_TARGET_POWER         = 0x05  # 3 bytes: op + sint16 watts
OP_START_OR_RESUME          = 0x07
OP_STOP_OR_PAUSE            = 0x08
OP_SET_INDOOR_BIKE_SIM      = 0x11  # 7 bytes: op + sint16 wind×1000 + sint16 grade×100 + uint8 crr×10000 + uint8 cw×100
OP_RESPONSE_CODE            = 0x80

# ── FTMS Result Codes ─────────────────────────────────────────────────────────

RESULT_SUCCESS              = 0x01
RESULT_NOT_SUPPORTED        = 0x02
RESULT_INVALID_PARAMETER    = 0x03
RESULT_OPERATION_FAILED     = 0x04
RESULT_CONTROL_NOT_PERMITTED = 0x05

RESULT_NAMES = {
    RESULT_SUCCESS:               "Success",
    RESULT_NOT_SUPPORTED:         "Not supported",
    RESULT_INVALID_PARAMETER:     "Invalid parameter",
    RESULT_OPERATION_FAILED:      "Operation failed",
    RESULT_CONTROL_NOT_PERMITTED: "Control not permitted (another device has control)",
}

# ── State machine ─────────────────────────────────────────────────────────────

class TrainerState(Enum):
    DISCONNECTED = "DISCONNECTED"
    CONNECTING   = "CONNECTING"
    CONNECTED    = "CONNECTED"    # GATT up, services found
    CONTROLLING  = "CONTROLLING"  # REQUEST_CONTROL granted — ready for commands
    ERROR        = "ERROR"


@dataclass
class TrainerStatus:
    state: TrainerState = TrainerState.DISCONNECTED
    device_name: str    = ""
    target_power: Optional[int] = None
    error: Optional[str]        = None


# ── Main Controller ───────────────────────────────────────────────────────────

class KickrFtmsController:
    """
    Async BLE FTMS controller for Wahoo KICKR trainers.

    Sequence (mirrors braven_extension FtmsController.kt):
      1. Scan / connect
      2. Enable indications on Control Point (0x2AD9)
      3. Send REQUEST_CONTROL (0x00)
      4. Wait for [0x80, 0x00, 0x01] → CONTROLLING
      5. Send ERG / resistance / simulation commands
    """

    def __init__(self, on_state_change: Optional[Callable[[TrainerStatus], None]] = None):
        self._status = TrainerStatus()
        self._on_state_change = on_state_change
        self._client: Optional[BleakClient] = None
        self._write_queue: asyncio.Queue[bytes] = asyncio.Queue()
        self._control_granted = asyncio.Event()
        self._writer_task: Optional[asyncio.Task] = None

    # ── Properties ────────────────────────────────────────

    @property
    def status(self) -> TrainerStatus:
        return self._status

    @property
    def is_controlling(self) -> bool:
        return self._status.state == TrainerState.CONTROLLING

    # ── Connection ────────────────────────────────────────

    async def scan(self, timeout: float = 10.0) -> list[BLEDevice]:
        """Scan for FTMS-capable trainers (filtered by FTMS service UUID)."""
        print(f"[KICKR] Scanning for FTMS trainers ({timeout}s)...")
        devices = await BleakScanner.discover(
            timeout=timeout,
            service_uuids=[FTMS_SERVICE_UUID],
        )
        if devices:
            print(f"[KICKR] Found {len(devices)} FTMS device(s):")
            for d in devices:
                print(f"  {d.name or 'Unknown':30s} [{d.address}]")
        else:
            print("[KICKR] No FTMS devices found.")
        return devices

    async def connect(self, address: str) -> bool:
        """
        Connect to a trainer by BLE address, run the full FTMS handshake,
        and wait until control is granted.

        Returns True if CONTROLLING state is reached.
        """
        self._update_state(TrainerState.CONNECTING)
        print(f"[KICKR] Connecting to {address}...")

        try:
            self._client = BleakClient(address, disconnected_callback=self._on_disconnected)
            await self._client.connect()
        except Exception as e:
            self._update_state(TrainerState.ERROR, error=f"Connection failed: {e}")
            return False

        device_name = self._client.address
        # Try to get a friendly name
        for svc in self._client.services:
            break  # services discovered on connect

        self._update_state(TrainerState.CONNECTED, device_name=address)
        print(f"[KICKR] Connected. Setting up FTMS...")

        # Verify FTMS service is present
        ftms_svc = self._client.services.get_service(FTMS_SERVICE_UUID)
        if ftms_svc is None:
            self._update_state(TrainerState.ERROR, error="FTMS service not found on device")
            await self._client.disconnect()
            return False

        # Log supported features (optional, informational)
        await self._read_features()

        # Start the serialized write loop
        self._control_granted.clear()
        self._writer_task = asyncio.create_task(self._write_loop())

        # Enable indications on Control Point — triggers handshake
        # bleak handles CCCD write automatically; indication and notification
        # both come through start_notify callback.
        try:
            await self._client.start_notify(CONTROL_POINT_UUID, self._on_control_point_indication)
        except Exception as e:
            self._update_state(TrainerState.ERROR, error=f"Failed to subscribe control point: {e}")
            return False

        # Subscribe to FTMS Status notifications (optional but useful)
        try:
            await self._client.start_notify(STATUS_UUID, self._on_status_notification)
        except Exception:
            pass  # Non-critical

        # Send REQUEST_CONTROL immediately after subscribing
        print("[KICKR] Requesting control...")
        await self._enqueue(bytes([OP_REQUEST_CONTROL]))

        # Wait up to 5s for control to be granted
        try:
            await asyncio.wait_for(self._control_granted.wait(), timeout=5.0)
        except asyncio.TimeoutError:
            self._update_state(TrainerState.ERROR, error="Timeout waiting for control grant")
            return False

        return True

    async def disconnect(self):
        """Disconnect cleanly."""
        if self._writer_task:
            self._writer_task.cancel()
            try:
                await self._writer_task
            except asyncio.CancelledError:
                pass
        if self._client and self._client.is_connected:
            await self._client.disconnect()
        self._update_state(TrainerState.DISCONNECTED)

    # ── Control Commands ──────────────────────────────────

    async def set_target_power(self, watts: int):
        """
        ERG mode — set target power in watts.
        Op 0x05 + sint16 LE (0-2000W range).
        """
        watts = max(0, min(2000, watts))
        data = struct.pack("<Bh", OP_SET_TARGET_POWER, watts)
        print(f"[KICKR] ERG → {watts}W")
        await self._enqueue(data)
        self._status.target_power = watts

    async def set_resistance(self, level_pct: float):
        """
        Resistance mode — set resistance level as percentage (0.0-100.0).
        Op 0x04 + uint16 LE (value = level × 10, resolution 0.1%).
        """
        level_pct = max(0.0, min(100.0, level_pct))
        raw = int(level_pct * 10)
        data = struct.pack("<BH", OP_SET_TARGET_RESISTANCE, raw)
        print(f"[KICKR] Resistance → {level_pct:.1f}%")
        await self._enqueue(data)

    async def set_simulation(
        self,
        grade_pct:   float = 0.0,
        wind_ms:     float = 0.0,
        crr:         float = 0.004,   # typical road CRR
        cw_kg_m:     float = 0.51,    # typical frontal area × drag
    ):
        """
        Simulation mode — physics-based resistance.

        Op 0x11 (7 bytes total):
          sint16 wind speed   [× 1000, m/s,   range ±32.767]
          sint16 grade        [× 100,  %,     range ±327.67]
          uint8  CRR          [× 10000,       range 0–0.0254]
          uint8  Cw (kg/m)    [× 100,         range 0–2.54]
        """
        ws_raw = int(wind_ms * 1000)
        gr_raw = int(grade_pct * 100)
        cr_raw = int(crr * 10000)
        cw_raw = int(cw_kg_m * 100)

        ws_raw = max(-32768, min(32767, ws_raw))
        gr_raw = max(-32768, min(32767, gr_raw))
        cr_raw = max(0, min(255, cr_raw))
        cw_raw = max(0, min(255, cw_raw))

        data = struct.pack("<BhhBB", OP_SET_INDOOR_BIKE_SIM, ws_raw, gr_raw, cr_raw, cw_raw)
        print(f"[KICKR] Simulate → grade={grade_pct:.1f}% wind={wind_ms:.2f}m/s crr={crr} cw={cw_kg_m}")
        await self._enqueue(data)

    async def start(self):
        """Resume paused session."""
        await self._enqueue(bytes([OP_START_OR_RESUME]))

    async def stop(self):
        """Pause active session."""
        await self._enqueue(bytes([OP_STOP_OR_PAUSE]))

    async def reset(self):
        """Reset trainer to default state."""
        await self._enqueue(bytes([OP_RESET]))

    # ── Internal: Indications / Notifications ─────────────

    def _on_control_point_indication(self, char: BleakGATTCharacteristic, data: bytearray):
        """
        FTMS Control Point indication handler.
        Response format: [0x80, request_op_code, result_code, ...]
        """
        if len(data) < 3:
            return
        response_code = data[0]
        request_op   = data[1]
        result       = data[2]

        if response_code != OP_RESPONSE_CODE:
            return

        result_name = RESULT_NAMES.get(result, f"unknown(0x{result:02X})")
        print(f"[KICKR] ← Response: op=0x{request_op:02X} result={result_name}")

        if result == RESULT_SUCCESS:
            if request_op == OP_REQUEST_CONTROL:
                print("[KICKR] Control granted — trainer ready for commands")
                self._update_state(TrainerState.CONTROLLING)
                self._control_granted.set()

        elif result == RESULT_CONTROL_NOT_PERMITTED:
            self._update_state(TrainerState.ERROR, error="Control not permitted — another device has control. Disconnect the official app.")

        elif result == RESULT_NOT_SUPPORTED:
            print(f"[KICKR] ⚠ Op 0x{request_op:02X} not supported by this trainer")

    def _on_status_notification(self, char: BleakGATTCharacteristic, data: bytearray):
        """FTMS Status characteristic — machine state events."""
        if not data:
            return
        # Status op codes (FTMS spec §4.16.1)
        STATUS_NAMES = {
            0x01: "Reset",             0x02: "Stopped (user)",
            0x03: "Stopped (safety)",  0x04: "Started/Resumed",
            0x05: "Target Speed changed",
            0x06: "Target Incline changed",
            0x07: "Target Resistance changed",
            0x08: "Target Power changed",
            0x09: "Target HR changed",
            0x0A: "Target Exp. Energy changed",
            0x0B: "Target Steps changed",
            0x12: "Indoor Bike Simulation params changed",
        }
        op = data[0]
        name = STATUS_NAMES.get(op, f"status(0x{op:02X})")
        print(f"[KICKR] ← Status: {name}")

    def _on_disconnected(self, client: BleakClient):
        print(f"[KICKR] Disconnected from {client.address}")
        self._update_state(TrainerState.DISCONNECTED)
        self._control_granted.clear()

    # ── Internal: Serialized Write Queue ──────────────────

    async def _enqueue(self, data: bytes):
        """Add a command to the write queue."""
        await self._write_queue.put(data)

    async def _write_loop(self):
        """
        Drain the write queue one command at a time.
        FTMS requires write-with-response (WRITE_TYPE_DEFAULT), so
        we wait for each write to complete before sending the next.
        """
        while True:
            data = await self._write_queue.get()
            if self._client and self._client.is_connected:
                try:
                    await self._client.write_gatt_char(
                        CONTROL_POINT_UUID,
                        data,
                        response=True,  # write-with-response (required by FTMS)
                    )
                except Exception as e:
                    print(f"[KICKR] Write error: {e}")
            self._write_queue.task_done()

    # ── Internal: Feature Read ────────────────────────────

    async def _read_features(self):
        """Read and log FTMS Feature characteristic (informational)."""
        try:
            raw = await self._client.read_gatt_char(FEATURE_UUID)
            if len(raw) >= 4:
                fitness_features = struct.unpack_from("<I", raw, 0)[0]
                target_features  = struct.unpack_from("<I", raw, 4)[0] if len(raw) >= 8 else 0
                feature_flags = {
                    "avg_speed":        bool(fitness_features & (1 << 0)),
                    "cadence":          bool(fitness_features & (1 << 1)),
                    "total_distance":   bool(fitness_features & (1 << 2)),
                    "incline":          bool(fitness_features & (1 << 3)),
                    "ramp_angle":       bool(fitness_features & (1 << 4)),
                    "step_count":       bool(fitness_features & (1 << 5)),
                    "resistance":       bool(fitness_features & (1 << 7)),
                    "heart_rate":       bool(fitness_features & (1 << 9)),
                    "power":            bool(fitness_features & (1 << 14)),
                    "target_power":     bool(target_features  & (1 << 2)),
                    "target_resistance":bool(target_features  & (1 << 5)),
                    "simulation_mode":  bool(target_features  & (1 << 13)),
                }
                supported = [k for k, v in feature_flags.items() if v]
                print(f"[KICKR] Features: {', '.join(supported)}")
        except Exception:
            pass  # non-critical

    # ── State Management ──────────────────────────────────

    def _update_state(
        self,
        state: TrainerState,
        device_name: Optional[str] = None,
        error: Optional[str] = None,
    ):
        self._status.state = state
        if device_name is not None:
            self._status.device_name = device_name
        if error is not None:
            self._status.error = error
            print(f"[KICKR] ERROR: {error}")
        if self._on_state_change:
            self._on_state_change(self._status)


# ── Interactive ERG session ───────────────────────────────────────────────────

async def interactive_session(controller: KickrFtmsController):
    """Simple interactive loop for testing ERG control."""
    print("\nCommands:")
    print("  <number>   Set target power in watts (e.g. 200)")
    print("  r<number>  Set resistance % (e.g. r50)")
    print("  g<number>  Set simulation grade % (e.g. g5.5)")
    print("  stop       Stop/pause trainer")
    print("  go         Start/resume trainer")
    print("  reset      Reset trainer")
    print("  quit       Disconnect and exit\n")

    loop = asyncio.get_event_loop()

    while controller.status.state in (TrainerState.CONTROLLING, TrainerState.CONNECTED):
        try:
            cmd = await loop.run_in_executor(None, input, "KICKR> ")
            cmd = cmd.strip()
        except (EOFError, KeyboardInterrupt):
            break

        if not cmd:
            continue
        elif cmd == "quit":
            break
        elif cmd == "stop":
            await controller.stop()
        elif cmd == "go":
            await controller.start()
        elif cmd == "reset":
            await controller.reset()
        elif cmd.startswith("r") and cmd[1:].replace(".", "").isdigit():
            await controller.set_resistance(float(cmd[1:]))
        elif cmd.startswith("g") and cmd[1:].lstrip("-").replace(".", "").isdigit():
            await controller.set_simulation(grade_pct=float(cmd[1:]))
        elif cmd.lstrip("-").isdigit():
            await controller.set_target_power(int(cmd))
        else:
            print(f"Unknown command: {cmd}")


# ── CLI Entry Point ───────────────────────────────────────────────────────────

async def main():
    parser = argparse.ArgumentParser(description="KICKR FTMS BLE controller")
    parser.add_argument("--scan",    action="store_true",   help="Scan for FTMS trainers and exit")
    parser.add_argument("--address", default=None,          help="BLE address to connect to (skips scan)")
    parser.add_argument("--watts",   type=int, default=None, help="Set ERG target power (W) and enter interactive mode")
    parser.add_argument("--grade",   type=float, default=None, help="Set simulation grade (%)")
    parser.add_argument("--resistance", type=float, default=None, help="Set resistance level (0-100%%)")
    parser.add_argument("--interactive", action="store_true", help="Enter interactive command loop")
    args = parser.parse_args()

    controller = KickrFtmsController()

    if args.scan:
        await controller.scan(timeout=10.0)
        return

    address = args.address
    if not address:
        devices = await controller.scan(timeout=8.0)
        if not devices:
            print("[KICKR] No devices found. Try --address XX:XX:XX:XX:XX:XX")
            return
        if len(devices) == 1:
            address = devices[0].address
            print(f"[KICKR] Auto-selecting: {devices[0].name} [{address}]")
        else:
            print("\nMultiple devices found. Use --address to select one.")
            return

    connected = await controller.connect(address)
    if not connected:
        print("[KICKR] Failed to reach CONTROLLING state.")
        return

    print(f"\n[KICKR] Ready. State: {controller.status.state.value}\n")

    try:
        # Apply any one-shot commands
        if args.watts is not None:
            await controller.set_target_power(args.watts)
        elif args.grade is not None:
            await controller.set_simulation(grade_pct=args.grade)
        elif args.resistance is not None:
            await controller.set_resistance(args.resistance)

        # Enter interactive loop if requested or if no one-shot command
        if args.interactive or (args.watts is None and args.grade is None and args.resistance is None):
            await interactive_session(controller)
        else:
            # One-shot: hold connection briefly to ensure command is sent
            await asyncio.sleep(2.0)

    except KeyboardInterrupt:
        pass
    finally:
        print("\n[KICKR] Disconnecting...")
        await controller.disconnect()


if __name__ == "__main__":
    import os, sys
    _here = os.path.dirname(os.path.abspath(__file__))
    if sys.platform == "win32" and _here not in os.environ.get("PATH", ""):
        os.environ["PATH"] = _here + os.pathsep + os.environ.get("PATH", "")

    asyncio.run(main())
