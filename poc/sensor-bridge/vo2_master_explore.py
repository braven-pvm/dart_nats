#!/usr/bin/env python3
"""
VO2 Master BLE explorer — discovers services, interprets data, attempts to trigger streaming.
"""
import asyncio
import struct
import time

from bleak import BleakClient

VO2_ADDR = "F9:1A:59:CC:BA:E7"

CTRL = "00001525-1212-efde-1523-785feabcd123"

DATA_CHARS = {
    "1526": "00001526-1212-efde-1523-785feabcd123",
    "1527": "00001527-1212-efde-1523-785feabcd123",
    "1528": "00001528-1212-efde-1523-785feabcd123",
    "1529": "00001529-1212-efde-1523-785feabcd123",
    "1533": "00001533-1212-efde-1523-785feabcd123",
}


def interpret(name: str, data: bytes):
    parts = [f"hex={data.hex()}"]

    # Try float32 (little-endian) chunks — likely for sensor measurements
    floats = []
    for i in range(0, len(data) - 3, 4):
        f = struct.unpack_from("<f", data, i)[0]
        floats.append(round(f, 5))
    if floats:
        parts.append(f"float32={floats}")

    # Try uint16 chunks
    u16s = []
    for i in range(0, len(data) - 1, 2):
        v = struct.unpack_from("<H", data, i)[0]
        u16s.append(v)
    if u16s:
        parts.append(f"uint16={u16s}")

    print(f"  0x{name}: {' | '.join(parts)}")


def on_notify(characteristic, data: bytearray):
    short = characteristic.uuid[4:8]
    ts = time.strftime("%H:%M:%S")
    b = bytes(data)
    floats = [round(struct.unpack_from("<f", b, i)[0], 5) for i in range(0, len(b) - 3, 4)]
    u16s = [struct.unpack_from("<H", b, i)[0] for i in range(0, len(b) - 1, 2)]
    print(f"[{ts}] NOTIFY 0x{short}  hex={data.hex()}  float32={floats}  uint16={u16s}")


async def main():
    print(f"Connecting to VO2 Master at {VO2_ADDR}...")
    async with BleakClient(VO2_ADDR) as c:
        print("Connected.\n")

        print("=== Current characteristic values ===")
        for name, uuid in DATA_CHARS.items():
            try:
                val = await c.read_gatt_char(uuid)
                interpret(name, bytes(val))
            except Exception as e:
                print(f"  0x{name}: ERROR {e}")

        print()
        print("=== Sending candidate start commands to 0x1525 ===")
        for cmd in [b"\x01", b"\x02", b"\x03", b"\x01\x01", b"\x00\x01", b"\xff"]:
            print(f"  Writing: {cmd.hex()}")
            try:
                await c.write_gatt_char(CTRL, cmd)
            except Exception as e:
                print(f"  Error: {e}")
            await asyncio.sleep(0.3)

        print()
        print("=== Subscribing to all notify channels ===")
        for name, uuid in DATA_CHARS.items():
            await c.start_notify(uuid, on_notify)
            print(f"  Subscribed: 0x{name}")

        print()
        print("Listening for 20s — put the VO2 Master into measurement mode if possible...")
        await asyncio.sleep(20)


if __name__ == "__main__":
    asyncio.run(main())
