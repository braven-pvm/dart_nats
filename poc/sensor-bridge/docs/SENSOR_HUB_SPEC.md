# Sport Science Lab — Sensor Hub Specification

**Version:** 0.6  
**Date:** March 2026  
**Status:** All architecture and protocol decisions resolved (D1–D28). Data model stable. Ready for implementation.

---

## 1. Purpose & Scope

This document specifies the **Lab Sensor Hub** — a system consisting of:

1. A **headless Dart daemon** (`lab_daemon`) that owns all sensor connections — the only process
   that touches BLE hardware and ANT+
2. A **NATS server** (pre-built `nats-server` binary) that acts as the message bus between
   the daemon and all consumers, with JetStream persistence for session replay and catch-up
3. **Flutter client apps** (web, Android, iOS, Windows, macOS) that are pure NATS consumers —
   they subscribe to sensor data and publish control commands; they have no sensor code
4. An **ANT+ Bridge** sidecar (Python) for platforms where Dart has no ANT+ plugin
5. A **FIT writer** (Dart, NATS consumer) that produces a `.fit` file per session
6. A **Firebase Sync** consumer (Dart) that uploads session summaries to Firestore and
   FIT files to Firebase Storage, with offline buffering via JetStream

The architecture cleanly separates **sensor collection** (daemon, near the hardware) from
**display and control** (clients, anywhere on the network). Clients can join or leave at any
time without affecting the daemon. Multiple clients can observe simultaneously.

```
                     ╔══ Lab Machine / Pi (sensor proximity required) ══╗
                     ║                                                  ║
  [BLE sensors]──────╫──► BLE Manager                                  ║
  [ANT+ USB stick]───╫──► ANT+ Bridge (Python) ─────────────────────►  ║
  [Lactate HTTP]─────╫──► REST listener         Sensor Drivers (Dart)  ║
                     ║         │                      │                 ║
                     ║         └──────────────────────┘                 ║
                     ║                    │                             ║
                     ║             lab_daemon (Dart)                    ║
                     ║             FIT Writer (Dart)                    ║
                     ║             Firebase Sync (Dart)                 ║
                     ║                    │                             ║
                     ║             nats-server binary                   ║
                     ║             (JetStream enabled)                  ║
                     ╚════════════════════╪═════════════════════════════╝
                                          │
               ┌─────────────────────┼─────────┐         ┌───────────────┐
               │ TCP/IP — lab LAN  │         │         │  Firebase      │
               │                    │         │         └───────────────┘
               │                    │         │  (session upload
            ┌──▼──────────────▼──────┐  │   when online)
            │              │        │  │
   ┌────────▼────────┐  ┌─────▼────────┐  ┌─────▼────────┐
   │  Flutter Web    │  │Flutter Android/│  │Flutter Windows/│
   │  (browser)      │  │iOS tablet      │  │macOS desktop   │
   │  NATS client    │  │NATS client     │  │NATS client     │
   └─────────────────┘  └────────────────┘  └────────────────┘
```

**Key properties of this architecture:**
- The daemon is the **only process that ever touches BLE or ANT+** hardware
- All other processes are NATS clients — they speak TCP, not Bluetooth
- The NATS server is **not implemented by us** — it is a pre-built ~15 MB Go binary
  downloaded from the NATS team and run as a service
- Clients can connect from anywhere on the LAN — browser, tablet, desktop, cloud relay
- Adding a new display or analysis tool requires zero changes to the daemon
- The daemon can be redeployed to a different machine without changing any client code

---

## 2. Implementation Platform

### 2.1 Locked Architecture Decisions

These decisions are final. They are not open questions.

| Decision | Choice | Rationale |
|---|---|---|
| **Implementation language** | Dart | Shared models, parsers, and NATS client across daemon and all Flutter clients; single codebase; `dart compile exe` produces native binaries for Windows and Linux ARM64 |
| **NATS server** | Pre-built `nats-server` binary | We are a **client** of NATS, not the server implementor. The server is a separate pre-built Go binary managed as a system service. We never implement or fork it. |
| **Daemon shape** | Headless Dart process | No UI in the daemon. Runs as a background service (systemd on Linux, Windows Service or startup script on Windows). UI lives exclusively in Flutter client apps. |
| **BLE in daemon** | `bluez` Dart package on Linux, `flutter_blue_plus` on Windows/macOS | The daemon conditionally imports the appropriate BLE backend. The `SensorDriver` layer is identical regardless. |
| **ANT+ in daemon** | ANT+ Bridge sidecar (Python) on Windows/Linux/macOS; native `ant_plus` plugin on Android | Dart has no ANT+ library for desktop. The Bridge is a thin Python process that reads ANT+ and publishes to NATS using the same subject schema. The daemon never distinguishes bridge data from native data. |
| **Primary lab deployment** | Windows PC (existing lab machine) + Linux/Pi for fixed installation | Windows is the immediate target (dev machine already proven in POC). Pi 5 headless is the long-term fixed-lab target. |
| **Client architecture** | All UIs are NATS-only Flutter apps | No client app contains any BLE, ANT+, or sensor parsing code. Data flows exclusively over NATS. |
| **FIT output** | NATS consumer FIT writer, separate from daemon core | FIT writer subscribes to `lab.>` and writes `.fit` files. Fully decoupled from sensor drivers. |
| **Daemon is a hardware bridge — not a protocol engine** | All exercise protocol logic (ramp tests, interval sequences, step protocols) lives in clients. The daemon exposes raw hardware primitives only: `set_power`, `set_resistance`, `set_simulation`, device state. Clients send one `set_power` command per step; the daemon forwards it to hardware immediately. No timers, no ramp state, no knowledge of what protocol is being run. Rationale: the daemon's job is reliable hardware ownership; exercise logic is the scientist's domain and belongs in the UI/client layer where it can be iterated independently. |

### 2.2 Runtime Components

Three processes run on the **lab machine** (the machine physically near the sensors):

```
Process 1: nats-server   (pre-built binary, downloaded once)
Process 2: lab_daemon    (dart compile exe — our code)
Process 3: ant_bridge    (Python — our code, only needed if ANT+ sensors present)
```

All three are set up as system services that start on boot and restart on crash.
Client apps run anywhere with network access and connect to `nats-server` over TCP.

**nats-server** is downloaded from https://github.com/nats-io/nats-server/releases —
a single binary for each platform, ~15 MB, no installer. It is configured with a single
`nats-server.conf` file that enables JetStream and sets memory/storage limits.

```
# Minimal nats-server.conf for the lab
port: 4222
jetstream: {
  store_dir: "/var/lib/nats"
  max_memory_store: 512MB
  max_file_store: 10GB
}
```

### 2.3 Dart Project Structure

```
lab_sensor_hub/
├── packages/
│   ├── lab_models/              # Pure Dart — shared between daemon and all clients
│   │   └── lib/
│   │       ├── subjects.dart           # All NATS subject constants (typed)
│   │       ├── messages/               # Typed message classes (one per §5 schema)
│   │       │   ├── trainer_metrics.dart
│   │       │   ├── heart_rate_metrics.dart
│   │       │   ├── ventilatory_metrics.dart
│   │       │   ├── gas_exchange_metrics.dart
│   │       │   ├── lactate_sample.dart
│   │       │   ├── session_event.dart
│   │       │   └── ...                 # one file per §5 schema
│   │       └── fit/
│   │           └── fit_field_defs.dart # FIT developer field numbers + names
│   │
│   ├── lab_daemon/              # Headless Dart process — sensor hub core
│   │   ├── bin/
│   │   │   └── sensor_hub.dart         # main() entrypoint
│   │   └── lib/
│   │       ├── ble/                    # BLE transport abstraction
│   │       │   ├── ble_manager.dart            # abstract BleManager interface
│   │       │   ├── ble_manager_bluez.dart       # Linux impl (bluez package)
│   │       │   └── ble_manager_fblue.dart       # Windows/macOS/Android impl
│   │       ├── drivers/                # One driver per sensor protocol
│   │       │   ├── sensor_driver.dart          # abstract SensorDriver
│   │       │   ├── ftms_driver.dart            # BLE FTMS — trainers
│   │       │   ├── hrs_driver.dart             # BLE Heart Rate Service
│   │       │   ├── cps_driver.dart             # BLE Cycling Power Service
│   │       │   ├── vo2_master_driver.dart      # BLE VO2 Master proprietary
│   │       │   ├── core_temp_driver.dart       # BLE CORE sensor
│   │       │   └── ant_bridge_driver.dart      # NATS subscriber — ANT+ Bridge data
│   │       ├── connection/
│   │       │   ├── connection_manager.dart     # scan, connect, reconnect, registry
│   │       │   └── device_registry.dart        # DeviceConfig, device_id mapping
│   │       ├── session/
│   │       │   ├── session_manager.dart        # lifecycle: start/stop/lap/pause
│   │       │   └── session_config.dart         # athlete weight, vo2 settings, etc.
│   │       ├── nats/
│   │       │   ├── nats_publisher.dart         # publishes SensorSamples to NATS
│   │       │   └── command_subscriber.dart     # listens on lab.control.> subjects
│   │       ├── fit/
│   │       │   ├── fit_writer.dart             # NATS consumer → .fit file
│   │       │   └── fit_encoder.dart            # FIT binary encoding (fit_tool wrapper)
│   │       └── rest/
│   │           └── lactate_server.dart         # HTTP POST endpoint for manual lactate
│   │
│   └── lab_client/              # Flutter UI — runs on any platform as NATS-only client
│       └── lib/
│           ├── nats/
│           │   ├── nats_service.dart           # connection, reconnect, subscriptions
│           │   └── command_publisher.dart      # publishes lab.control.> commands
│           ├── screens/
│           │   ├── dashboard_screen.dart       # live metrics display
│           │   ├── session_screen.dart         # start/stop, lap, lactate input
│           │   ├── calibration_screen.dart     # VO2 Master calibration flow + metronome
│           │   ├── device_screen.dart          # connection status per device
│           │   └── settings_screen.dart        # athlete profile, device config
│           └── widgets/                        # charts, gauges, real-time displays
│
└── tools/
    └── ant_bridge/              # Python ANT+ sidecar (Windows / Linux / macOS)
        ├── ant_bridge.py               # extends poc/sensor-bridge/ant_scan.py
        └── requirements.txt            # openant, nats-py, libusb
```

### 2.4 Layered Architecture

```
┌────────────────── BLE Hardware + ANT+ USB ──────────────────────┐
│                                                                 │
│  ┌─────────────────────┐       ┌────────────────────────────┐  │
│  │    BLE Manager      │       │      ANT+ Bridge (Python)  │  │
│  │  (bluez / fblue)    │       │  openant → nats-py → NATS  │  │
│  └──────────┬──────────┘       └──────────────┬─────────────┘  │
│             │                                 │                │
└─────────────┼─────────────────────────────────┼────────────────┘
              │                                 │
┌─────────────▼─────────────────────────────────▼────────────────┐
│                    Sensor Drivers (Dart)                        │
│  FtmsDriver │ HrsDriver │ Vo2MasterDriver │ AntBridgeDriver ... │
│                  (each implements SensorDriver)                 │
└──────────────────────────────┬──────────────────────────────────┘
                               │  Stream<SensorSample>
┌──────────────────────────────▼──────────────────────────────────┐
│                       Hub Core (Dart)                           │
│            ConnectionManager   SessionManager                   │
│            DeviceRegistry      LactateRestServer                │
└──────────┬──────────────────────────────────────┬──────────────┘
           │                                      │
┌──────────▼──────────┐                ┌──────────▼──────────────┐
│   NATS Publisher    │                │      FIT Writer          │
│   (dart_nats)       │                │   (fit_tool wrapper)     │
│   lab.*.*.* topics  │                │   NATS consumer          │
└──────────┬──────────┘                └─────────────────────────┘
           │
┌──────────▼──────────────────────────────────────────────────────┐
│                      nats-server (pre-built)                    │
│                      JetStream enabled                          │
└──────────┬──────────────────────────────────────────────────────┘
           │  TCP — LAN / localhost
           │
     ┌─────┴────────────────────────────────┐
     │             │                        │
 ┌───▼────┐  ┌─────▼───────┐  ┌─────────────▼─────┐
 │Flutter │  │Flutter      │  │ Flutter Android/  │
 │Web     │  │Windows/macOS│  │ iOS               │
 │(NATS   │  │desktop      │  │ tablet            │
 │client) │  │(NATS client)│  │ (NATS client)     │
 └────────┘  └─────────────┘  └───────────────────┘
```

### 2.5 Conditional BLE Import Strategy

The daemon must work on both Linux (using the `bluez` Dart package) and Windows/macOS
(using `flutter_blue_plus`). This is handled via Dart conditional imports — the same
pattern already established in this `dart_nats` repo's transport layer:

```dart
// lib/ble/ble_manager.dart
import 'ble_manager_stub.dart'
  if (dart.library.io) 'ble_manager_io.dart';  // selects bluez vs flutter_blue

abstract class BleManager {
  Future<void> startScan(List<String> serviceUuids);
  Stream<BleDevice> get scanResults;
  Future<BleConnection> connect(String deviceId);
}
```

All sensor drivers depend only on `BleManager` — they are identical on all platforms.
The platform-specific BLE code is isolated to two files.

### 2.6 Platform Support Matrix

The table below shows coverage for each sensor category on each deployment platform.
BLE is handled by `flutter_blue_plus` (WinRT on Windows, BlueZ on Linux, CoreBluetooth on
macOS/iOS). ANT+ is handled natively on Android or via the ANT+ Bridge elsewhere.

| Sensor | Protocol | Android | Windows | macOS | Linux daemon | iOS | Web |
|---|---|---|---|---|---|---|---|
| KICKR (FTMS metrics + ERG control) | BLE | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Heart Rate (HRS) | BLE | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| VO2 Master | BLE | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Power Meter (CPS) | BLE | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| CORE Body Temp | BLE | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Moxy SmO2 | ANT+ only | — | — | — | — | — | ❌ | **Out of scope (D27)** — no Moxy in lab; Bridge architecture retained for future use |
| HR strap (fallback) | ANT+ | ✅ native | ✅ Bridge | ✅ Bridge | ✅ Bridge | ⚠️ Bridge | ❌ |
| Lactate (manual) | REST | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Dashboard / control UI | NATS | ✅ | ✅ | ✅ | — | ✅ | ✅ |

**Windows is fully covered.** BLE works natively via WinRT (confirmed with KICKR + VO2 Master in
testing). ANT+ sensors use the ANT+ Bridge (Python process already proven on this machine in POC).
No sensor category has a gap on Windows.

**Linux daemon** = headless Dart process (no Flutter UI). BLE works via BlueZ; ANT+ via Bridge.
Suitable for a dedicated lab box (NUC, Pi 5) where the UI is served from a web dashboard.
Flutter desktop on Linux is not a target — BlueZ support in `flutter_blue_plus` is
community-maintained and not reliable enough for production.

### 2.7 Windows — Full Coverage Detail

Windows 10 (1703+) / Windows 11:

**BLE:** `flutter_blue_plus` uses the WinRT Bluetooth LE APIs (`Windows.Devices.Bluetooth`).
No drivers required. All GATT roles (central, notify, write-with-response, indications) are
supported. Up to ~7 simultaneous BLE connections per adapter. A dedicated USB BLE adapter
(Plugable USB-BT4LE, ASUS BT500, or Intel AX210 if discrete) is recommended over the built-in
adapter for stability with 5 concurrent connections.

**ANT+:** No Flutter/Dart plugin exists for Windows. The **ANT+ Bridge** covers this
(see §2.5). It is already proven working from the POC phase on this machine:
- USB stick VID_0FCF/PID_1009, WinUSB driver via Zadig
- `openant` + `libusb` via Python 3.12 / uv venv at `poc/sensor-bridge/`
- `libusb-1.0.dll` present at `poc/sensor-bridge/libusb-1.0.dll`

**Coverage on Windows:**
```
KICKR FTMS     → BLE WinRT    ✅  (tested: KICKR BIKE SHIFT E8:FC:1D:1B:9E:43)
VO2 Master     → BLE WinRT    ✅  (tested: F9:1A:59:CC:BA:E7)
HR strap       → BLE WinRT    ✅
Power meter    → BLE WinRT    ✅
Moxy SmO2      → ANT+ Bridge  —  (D27 — out of scope; architecture retained for extensibility)
HR fallback    → ANT+ Bridge  ✅
```
No sensor has a gap on Windows. The only overhead is running the ANT+ Bridge as a second
process alongside the Dart app — both communicate via NATS, so the app is unaware.

### 2.8 Linux — Headless Dart Daemon Pattern

Linux is **not** a Flutter desktop UI target. It is, however, the best platform for a
dedicated headless lab box (NUC / Raspberry Pi 5), running the sensor hub as a background daemon.

**BLE on Linux:** BlueZ is the Linux BLE stack — mature, well-tested, production-grade.
`flutter_blue_plus` has a Linux backend via BlueZ D-Bus but it's community-maintained.
For a headless daemon the options are:
1. `flutter_blue_plus` in a Flutter Linux app (functional but overkill; Flutter Linux desktop is
   production-stable as of Flutter 3.x, just less polished than mobile)
2. Pure Dart using the `bluez` pub.dev package (wraps BlueZ D-Bus directly; no Flutter required)
   — this is the **recommended approach** for a Linux headless daemon

```
Headless on Linux:
  BLE  → Dart + bluez package (BlueZ D-Bus)    ✅  standard BlueZ stack
  ANT+ → ANT+ Bridge (Python openant)           ✅  openant is Linux-native (its home platform)
  NATS → dart_nats                              ✅
  UI   → none; served via Flutter Web on NATS   ✅
```

**Raspberry Pi 5** is a credible deployment target: 4-core ARM64, built-in BLE (for near-device use),
USB port for ANT+ stick, runs Debian/Ubuntu. The headless Dart daemon approach works without
modification on ARM64.

**Linux BLE note:** BlueZ requires the user running the process to be in the `bluetooth` group,
or the process must run as root, or D-Bus policy must be configured to allow unprivileged BLE access.
This is a one-time setup step on a dedicated lab machine.

### 2.9 ANT+ Bridge (Windows / macOS / Linux desktop)

A lightweight sidecar process that translates ANT+ to NATS. Runs alongside the Dart hub on
any platform where native ANT+ is unavailable in Dart, and also as the Linux daemon's ANT+ source.

- Codebase: `poc/sensor-bridge/ant_scan.py` (extend to full bridge)
- Transport: `openant` + `libusb` / PyUSB
- NATS client: `nats-py`
- Publishes: `lab.{category}.{device_id}.metrics` — same schema as native drivers
- The Dart hub subscribes to these subjects identically to any other driver

**On Linux this is particularly clean:** `openant` was designed for Linux; no WinUSB/Zadig
ceremony; just `pip install openant` and plug in the USB stick.

### 2.10 Flutter & Dart Dependencies

```yaml
dependencies:
  flutter_blue_plus: ^1.x     # BLE on Android/iOS/macOS/Windows (+ Linux Flutter app)
  bluez: ^0.x                  # BLE on Linux headless daemon (pure Dart, no Flutter needed)
  nats_dart: ^1.x             # NATS JetStream (this repo)
  fit_tool: ^0.x              # FIT file encoding

# ANT+ on Android only (native plugin):
  ant_plus: ^1.x              # Garmin Android ANT+ SDK wrapper

# ANT+ Bridge (all non-Android platforms) — separate Python process:
#   openant, nats-py, libusb  (see poc/sensor-bridge/)
```

---

## 3. Lab Device Inventory

### Primary devices (always present)

| ID | Device | Category | Protocol | Connection method |
|---|---|---|---|---|
| `trainer_1` | Wahoo KICKR BIKE SHIFT | Smart Trainer | BLE FTMS | Scan by FTMS service UUID `0x1826` |
| `trainer_2` | Wahoo KICKR (standard) | Smart Trainer | BLE FTMS | Scan by FTMS service UUID `0x1826` |
| `hr_1` | Polar H10 | Heart Rate | BLE HRS | Scan by HRS service UUID `0x180D`. Broadcasts RR intervals. ANT+ type 120 also available on H10 but BLE used (D8 pattern). |
| `vo2_1` | VO2 Master 1.6.2 (#5342) | Metabolic | BLE Proprietary | Scan by name prefix `VO2 Master` |
| `lactate` | Manual Lactate Reader | Lactate | REST API (manual input) | HTTP POST to Sensor Hub |

### Secondary / occasional devices

| Category | Protocol | BLE version available? | Notes |
|---|---|---|---|
| Secondary Power Meter | BLE CPS (`0x1818`) | ✅ All modern power meters | Dual-recording, left/right power |
| Core Body Temperature | BLE Proprietary (CORE sensor) | **Deferred (D28)** — no unit in lab | Skin + core temp |
| Muscle Oxygen (SmO2) | ANT+ type 31 | ❌ Moxy is ANT+-only | Requires ANT+ stick or ANT+ Bridge on desktop |
| Additional HR Sensor | BLE HRS or ANT+ type 120 | ✅ | Multi-athlete scenarios |

---

## 4. Protocol Coverage

### 4.1 BLE Standard Profiles (Bluetooth SIG)

One implementation covers all compliant brands.

| Profile | Service UUID | Characteristic UUID | Data |
|---|---|---|---|
| **Heart Rate Service (HRS)** | `0x180D` | `0x2A37` notify | HR (bpm), RR intervals (ms), energy (kJ) |
| **Cycling Power Service (CPS)** | `0x1818` | `0x2A63` notify | Power (W), cadence (RPM), wheel/crank events |
| **Cycling Speed & Cadence (CSC)** | `0x1816` | `0x2A5B` notify | Wheel revs, crank revs (speed/cadence derivable) |
| **Fitness Machine Service (FTMS)** | `0x1826` | `0x2AD2` notify | Indoor Bike: speed, cadence, power |
| | | `0x2AD9` write+indicate | Control Point: ERG, resistance, simulation |
| | | `0x2ADA` notify | Machine status events |
| | | `0x2ACC` read | Feature flags (which modes are supported) |

### 4.2 BLE Proprietary — VO2 Master

See [VO2_MASTER_SPEC.md](./VO2%20Master/VO2_MASTER_SPEC.md) for full byte layout.

| Service UUID | `00001523-1212-EFDE-1523-785FEABCD123` |
|---|---|
| Control (write) | `0x1525` |
| Control responses | `0x1526` notify |
| Ventilatory | `0x1527` notify — 6 bytes: Rf, Tv, VE |
| Gas Exchange | `0x1528` notify — 8 bytes: FeO2, VO2 |
| Environment | `0x1529` notify — 10 bytes: pressure, temp, humidity |
| Gas Calibration | `0x1531` notify — fires on gas cal complete |
| Flow Calibration | `0x1532` notify — fires on syringe cal complete |

### 4.3 ANT+ Profiles

ANT+ is used **only where no BLE equivalent exists** or as a fallback.
Moxy SmO2 is **out of scope** (D27) so ANT+ is not required for v1 — the Bridge sidecar
architecture is retained for extensibility but need not be deployed on day 1.
On Android, the `ant_plus` plugin handles ANT+ natively if ever needed.

Requires ANT USB-m stick (VID_0FCF/PID_1009, WinUSB driver via Zadig on Windows; OTG adapter on Android).

| Profile | Device Type | Channel Period | Platform | Use |
|---|---|---|---|---|
| Heart Rate Monitor | 120 | 8070 | Android / Bridge | HR fallback (Polar H10 used via BLE in v1) |
| Bicycle Power | 11 | 8182 | Android / Bridge | Secondary power meter (if ANT+-only model) |
| Speed & Cadence | 121 | 8086 | Android / Bridge | Wheel/crank sensors |
| Muscle Oxygen | 31 | 8192 | Android / Bridge | Moxy SmO2 — **out of scope (D27)** |
| FE-C Trainer | 17 | 8192 | Read-only only | Trainer metrics read; control via BLE FTMS |

**Note on FTMS vs ANT+ FE-C control:** ERG control over ANT+ FE-C requires sending
acknowledged messages from a master device channel — significantly more complex than BLE FTMS.
The lab uses **BLE FTMS for all trainer control**. ANT+ FE-C is read-only (metrics) if used at all.

---

## 5. Unified Data Model

All events published to NATS conform to this envelope. Fields are always present; 
metric-specific payloads are in `data`. Units are fixed — no ambiguity downstream.

```json
{
  "ts":        1741824000.123,    // Unix timestamp (float, seconds since epoch, UTC)
  "device_id": "trainer_1",       // stable identifier from device registry
  "category":  "trainer",         // see Device Categories below
  "stream":    "metrics",         // stream type within device (see §5)
  "seq":       4821,              // monotonic sequence number per device
  "data": { }                     // metric-specific payload (see §4.x below)
}
```

### Device Categories
`trainer` | `heart_rate` | `metabolic` | `power` | `temperature` | `speed_cadence` | `session`

---

### 5.1 Trainer Metrics (`category: trainer`, `stream: metrics`)

```json
{
  "power_w":         245,        // instantaneous power, watts (int)
  "cadence_rpm":     92,         // pedal cadence, RPM (float, 0.5 resolution from FTMS)
  "speed_kmh":       32.4,       // speed km/h (float)
  "target_power_w":  250,        // current ERG target (int, null if not in ERG mode)
  "mode":            "erg"       // "erg" | "resistance" | "simulation" | "free"
}
```

Source priority: FTMS Indoor Bike Data (`0x2AD2`). Cadence is `raw × 0.5` RPM.

### 5.2 Trainer State (`category: trainer`, `stream: state`)

```json
{
  "connection": "controlling",   // "disconnected" | "connecting" | "connected" | "controlling" | "error"
  "ftms_status": "started",      // last FTMS status event (string)
  "error":       null,           // error message or null
  "battery_pct": 87              // null if not available
}
```

### 5.3 Heart Rate (`category: heart_rate`, `stream: metrics`)

```json
{
  "hr_bpm":          162,        // heart rate, BPM (int)
  "rr_intervals_ms": [371, 369], // R-R intervals in ms (array, 1+ values per BLE notification). Polar H10 always populates this.
  "energy_kj":       null        // accumulated energy (int or null)
}
```

Source: BLE HRS `0x2A37`. RR intervals populated by Polar H10 on every notification.
The H10 typically sends 1–2 RR values per notification depending on heart rate.
Do not treat an empty array as an error — it can occur on the first notification after connection.

### 5.4 Ventilatory — per breath (`category: metabolic`, `stream: ventilatory`)

```json
{
  "rf_bpm":    15.4,    // respiratory frequency, breaths/min (float, 0.01 resolution)
  "tv_l":      2.84,    // tidal volume, litres/breath BTPS (float, 0.01 resolution)
  "ve_l_min":  43.7,    // minute ventilation, L/min BTPS (float, 0.01 resolution)
  "breath_no": 1042     // cumulative breath counter (int, monotonic within session)
}
```

### 5.5 Gas Exchange — per breath (`category: metabolic`, `stream: gas_exchange`)

```json
{
  "feo2_pct":       16.82,   // fraction of expired oxygen, % (float, 0.01 resolution)
  "vo2_ml_min":     3248.5,  // oxygen consumption, mL/min (float, ÷6 from raw uint16)
  "vo2_ml_min_kg":  46.4,    // VO2 relative to body weight (float, computed client-side)
  "breath_no":      1042,    // matches ventilatory breath_no for correlation
  "ventilation_only": false  // true if feo2==22.0 && vo2==22.0 (sentinel row, gas invalid)
}
```

**VO2/kg:** Computed by Sensor Hub using athlete body weight from session config.
**CO2:** Not available — FeCO2/VCO2 bytes are reserved in the VO2 Master V1.6 protocol.

### 5.6 Environment (`category: metabolic`, `stream: environment`)

```json
{
  "pressure_hpa":   1013.2,  // ambient pressure, hPa (float, ×0.1 from raw)
  "temperature_c":  22.1,    // device internal temperature, °C (float, ×0.01)
  "humidity_rh":    58.3     // O2 sensor humidity, %RH (float, ×0.01)
}
```

### 5.7 Metabolic Device State (`category: metabolic`, `stream: state`)

```json
{
  "connection":    "controlling",
  "device_state":  "recording",    // "idle" | "recording" | "calibrating_gas" | "calibrating_flow" | "zeroing_flow"
  "sub_state":     "none",         // "none" | "flow_delay" | "average"
  "breath_state":  "exhale",       // "inhale" | "exhale" | "none" — live breath phase
  "is_calibrated": true,           // gas calibration status
  "gas_cal_progress_pct": 100,     // 0-100
  "syringe_flags": {
    "resting_calibrated": false,
    "medium_calibrated":  true,
    "large_calibrated":   false
  },
  "battery_pct":   100,
  "error":         null            // error message or null
}
```

### 5.8 Lactate (`category: metabolic`, `stream: lactate`)

```json
{
  "lactate_mmol_l":   4.2,     // measured lactate, mmol/L (float)
  "offset_s":         -120,    // time offset from submission to actual measurement (int, seconds)
  "note":             "end of 5W/kg interval"  // optional free-text annotation
}
```

Source: REST POST from lab tablet/PC (manual input). The `offset_s` field compensates for
the delay between when blood was drawn and when the result was entered.

### 5.9 Power Meter (`category: power`, `stream: metrics`)

```json
{
  "power_w":        312,     // instantaneous power, watts (int, signed — CPS allows negative)
  "cadence_rpm":    94,      // null if not available from this sensor
  "balance_pct":    51.2,    // left/right balance % (null if not available)
  "torque_nm":      null     // average torque (null if not available)
}
```

Source: BLE CPS `0x2A63` or ANT+ type 11.

### 5.10 Core Body Temperature (`category: temperature`, `stream: metrics`)

```json
{
  "core_temp_c":  37.8,   // CORE sensor — core body temperature estimate, °C
  "skin_temp_c":  33.2    // skin temperature from device, °C
}
```

Source: CORE sensor BLE proprietary service + HRS skin temp field.

### 5.11 Calibration Progress (`category: metabolic`, `stream: calibration`)

```json
{
  "type":           "gas",           // "gas" | "flow_syringe" | "flow_zero"
  "progress_pct":   67,              // 0-100
  "current_breath": 5,               // flow only: breaths completed
  "total_breaths":  10,              // flow only: target breath count
  "result": null                     // null during calibration, populated on completion:
                                     // { "mean_l": 2.984, "std_dev_l": 0.021, "passed": true }
}
```

### 5.12 Session Events (`category: session`, `stream: events`)

```json
{
  "event":      "started",         // "started" | "paused" | "resumed" | "stopped" | "lap"
  "session_id": "20260304_143022", // always present
  "athlete_id": "athlete_1",       // athlete identifier from session config (present in "started")
  "duration_s": null,              // total session duration (present in "stopped", null otherwise)
  "fit_path":   null,              // local path to finalised FIT file (present in "stopped", null otherwise)
  "note":       null               // optional free-text annotation (e.g. lap reason)
}
```

---

## 6. NATS Protocol — Subjects, Messaging Patterns & Control

### 6.1 NATS Is Fully Bidirectional

NATS has no concept of server/client roles at the application level. Any connected
process can publish to any subject and subscribe to any subject simultaneously.
The daemon publishes sensor data and subscribes to control commands. Flutter clients
subscribe to sensor data and publish control commands. The `nats-server` just routes.

Two messaging patterns are used, chosen per command based on whether acknowledgement matters:

**Pub/Sub (fire-and-forget):** Publisher sends, all subscribers receive. No reply.
Used for: streaming sensor data, lap markers, lactate submission.

**Request/Reply:** Publisher sends with a reply-to inbox address. Daemon processes
the command, then publishes a result to that inbox. The caller's `request()` call
returns the result as a `Future` — equivalent to an HTTP call but over NATS.
Used for: all commands where the caller needs to know if it succeeded.

NATS generates a unique `_INBOX.{random}` address per request automatically.
`dart_nats` exposes this as `connection.request(subject, payload, timeout: ...)`.

### 6.2 Standard Reply Envelope

All request/reply responses from the daemon use this JSON envelope:

```json
{
  "ok":    true,
  "error": null,
  "data":  { }
}
```

On success: `ok: true`, `error: null`, `data` contains command-specific fields (may be `{}`).  
On failure: `ok: false`, `error` is a string describing the failure, `data` is `{}`.

**Standard error codes** (carried in `error` field as string prefix):

| Prefix | Meaning |
|---|---|
| `DEVICE_DISCONNECTED` | Target device is not currently connected |
| `DEVICE_NOT_READY` | Device connected but not in a state that accepts this command |
| `INVALID_PARAMS` | Request payload failed validation (out of range, missing field) |
| `HARDWARE_REJECTED` | Device received the command but returned a hardware-level error |
| `TIMEOUT` | Hardware did not respond within the expected window |
| `SESSION_NOT_ACTIVE` | Command requires an active session (e.g. lap without a started session) |
| `SESSION_ALREADY_ACTIVE` | session.start received when a session is already running |

Example failure reply:
```json
{ "ok": false, "error": "DEVICE_DISCONNECTED: trainer_1 is not connected", "data": {} }
```

### 6.3 Data Subjects (daemon → clients, pub/sub)

Pattern: `lab.{category}.{device_id}.{stream}`

All data subjects are **pub/sub only** — the daemon publishes, any number of clients
subscribe. No reply expected. Messages are also captured by JetStream streams (§6.6).

```
# Smart trainers
lab.trainer.trainer_1.metrics          # TrainerMetrics — 1 Hz
lab.trainer.trainer_1.state            # TrainerState — on change
lab.trainer.trainer_2.metrics
lab.trainer.trainer_2.state

# Heart rate
lab.hr.hr_1.metrics                    # HrMetrics — on each beat

# Metabolic (VO2 Master)
lab.metabolic.vo2_1.ventilatory        # VentilatoryMetrics — per breath
lab.metabolic.vo2_1.gas_exchange       # GasExchangeMetrics — per breath
lab.metabolic.vo2_1.environment        # EnvironmentMetrics — 0.2 Hz
lab.metabolic.vo2_1.calibration        # CalibrationProgress — on change
lab.metabolic.vo2_1.state              # MetabolicState — on change
lab.metabolic.lactate                  # LactateSample — on submission (no device_id — manual)

# Secondary sensors
lab.power.power_2.metrics              # PowerMetrics — 1 Hz
lab.temperature.core_1.metrics         # TempMetrics — 1 Hz

# Session
lab.session.events                     # SessionEvent — on lifecycle change
```

### 6.4 Control Subjects (clients → daemon, request/reply unless noted)

Pattern: `lab.control.{category}.{device_id}.{command}`

Commands marked **[pub/sub]** do not use request/reply — they are fire-and-forget.
All others use request/reply with the standard reply envelope (§6.2).

#### Session lifecycle

| Subject | Pattern | Request payload | Reply `data` | Notes |
|---|---|---|---|---|
| `lab.control.session.start` | Request/Reply | `{ "athlete_id": "...", "weight_kg": 70.0, "ftp_w": 280, "protocol": "ramp_test" }` | `{ "session_id": "20260304_143022" }` | Creates JetStream stream, starts FIT writer. VO2 Master must be configured beforehand via `set_venturi` / `set_mask`. |
| `lab.control.session.stop` | Request/Reply | `{}` | `{ "session_id": "...", "duration_s": 3612 }` | Finalises FIT, triggers Firebase Sync |
| `lab.control.session.pause` | Request/Reply | `{}` | `{}` | Pauses FIT timer, keeps sensors active |
| `lab.control.session.resume` | Request/Reply | `{}` | `{}` | Resumes FIT timer |
| `lab.control.session.lap` | **[pub/sub]** | `{ "note": "end of 5W/kg" }` | — | Lap marker; low latency, no confirm needed |

#### Trainer control

| Subject | Pattern | Request payload | Reply `data` | Notes |
|---|---|---|---|---|
| `lab.control.trainer.{id}.set_power` | Request/Reply | `{ "watts": 250 }` | `{ "watts": 250 }` | Confirmed after FTMS ack `[0x80,0x05,0x01]`. Range 0–2000 W |
| `lab.control.trainer.{id}.set_resistance` | Request/Reply | `{ "level_pct": 50.0 }` | `{ "level_pct": 50.0 }` | Confirmed after FTMS ack. Range 0.0–100.0 |
| `lab.control.trainer.{id}.set_simulation` | Request/Reply | `{ "grade_pct": 5.0, "wind_speed_ms": 0.0, "crr": 0.004, "cw": 0.51 }` | `{ "grade_pct": 5.0, ... }` | Sim mode. Grade: –40 to +40%, wind: –30 to +30 m/s |
| `lab.control.trainer.{id}.set_mode` | Request/Reply | `{ "mode": "erg" \| "resistance" \| "simulation" \| "free" }` | `{ "mode": "erg" }` | Switches active control mode |
| `lab.control.trainer.{id}.start` | Request/Reply | `{}` | `{}` | FTMS Start/Resume op `[0x07]` |
| `lab.control.trainer.{id}.stop` | Request/Reply | `{}` | `{}` | FTMS Stop op `[0x08, 0x01]` |
| `lab.control.trainer.{id}.reset` | Request/Reply | `{}` | `{}` | FTMS Reset op `[0x01]` |

#### VO2 Master control

| Subject | Pattern | Request payload | Reply `data` | Notes |
|---|---|---|---|---|
| `lab.control.metabolic.{id}.set_state` | Request/Reply | `{ "state": "idle" \| "recording" \| "calibrating_gas" \| "calibrating_flow" \| "zeroing_flow" }` | `{ "state": "recording", "sub_state": "none" }` | Confirmed after COM OUT response |
| `lab.control.metabolic.{id}.set_venturi` | Request/Reply | `{ "size": "resting" \| "medium" \| "large" }` | `{ "size": "medium" }` | Must match syringe to be used for flow cal |
| `lab.control.metabolic.{id}.set_mask` | Request/Reply | `{ "size": "xs" \| "s" \| "m" \| "l" \| "xl" }` | `{ "size": "s" }` | Mask ID codes from SDK enum |
| `lab.control.metabolic.{id}.set_idle_timeout` | Request/Reply | `{ "enabled": false }` | `{ "enabled": false }` | Disable auto-sleep during lab sessions |
| `lab.control.metabolic.{id}.start_gas_cal` | Request/Reply | `{}` | `{ "progress_pct": 0 }` | Reply comes immediately; progress on `lab.metabolic.{id}.calibration` |
| `lab.control.metabolic.{id}.start_flow_cal` | Request/Reply | `{ "syringe_l": 3.0, "breaths": 10 }` | `{ "current_breath": 0, "total_breaths": 10 }` | Reply immediately; progress on `calibration` subject |
| `lab.control.metabolic.{id}.abort_calibration` | Request/Reply | `{}` | `{}` | Sets device to Idle |
| `lab.control.metabolic.{id}.zero_flow` | Request/Reply | `{}` | `{}` | SetState(ZeroingFlow=5) |

#### Lactate input

| Subject | Pattern | Request payload | Reply `data` | Notes |
|---|---|---|---|---|
| `lab.control.metabolic.lactate.submit` | **[pub/sub]** | `{ "mmol_l": 4.2, "offset_s": -120, "note": "end of interval" }` | — | `offset_s` < 0 means blood drawn before entry. Daemon re-publishes to `lab.metabolic.lactate` and writes to Firestore |

#### Device management

The daemon auto-connects all devices listed in `config/devices.json` on startup (see §8.2).
These commands exist for **recovery and diagnostics only** — not normal operation.

| Subject | Pattern | Request payload | Reply `data` | Notes |
|---|---|---|---|---|
| `lab.control.devices.scan` | Request/Reply | `{ "timeout_s": 10 }` | `{ "found": [ { "device_id", "name", "rssi" }, ... ] }` | Manual BLE scan — use when a device failed to auto-connect on startup |
| `lab.control.devices.connect` | Request/Reply | `{ "device_id": "trainer_1" }` | `{ "device_id": "trainer_1", "state": "connected" }` | Explicit connect for a device currently in DISCONNECTED state |
| `lab.control.devices.disconnect` | Request/Reply | `{ "device_id": "trainer_1" }` | `{ "device_id": "trainer_1", "state": "disconnected" }` | Explicit disconnect (e.g. to hand off to another app) |
| `lab.control.devices.status` | Request/Reply | `{}` | `{ "devices": [ { "device_id", "state", "battery_pct" }, ... ] }` | Poll all device states |

### 6.5 Request/Reply Timeout Policy

| Command category | Timeout | Rationale |
|---|---|---|
| Session start/stop | 5 000 ms | Must create JetStream stream and confirm |
| Trainer ERG/mode | 3 000 ms | BLE write + FTMS ack round-trip |
| VO2 Master state change | 5 000 ms | BLE write + device state transition + COM OUT response |
| VO2 Master calibration start | 3 000 ms | BLE write only; long-running progress via pub/sub |
| Device scan | `timeout_s` + 1 000 ms | Caller-specified |
| Device connect/disconnect | 10 000 ms | BLE connection establishment can be slow |

If the daemon does not reply within the timeout, the NATS client library surfaces a
`TimeoutException`. The caller should treat this as `TIMEOUT` and surface an error to the user.
The daemon is responsible for never silently dropping a request — it must always reply,
even if the reply is `{ "ok": false, "error": "..." }`.

### 6.6 JetStream Streams

#### How JetStream consumers work

A **stream** stores messages on disk/memory server-side. Each **consumer** of a stream
tracks its own independent read position (sequence number), stored on the server. This
makes JetStream true 1:M with full catch-up on reconnect:

- The FIT writer, Firebase Sync consumer, and three dashboard clients are all independent
  consumers of the session stream; each replays from its own position after reconnect
- Reconnecting consumers resume exactly where they left off — **no missed messages**
- Message retention is controlled by the stream's policy, not by consumer state
- Control reply messages (to `_INBOX.*`) are **not** captured by streams — only
  `lab.*` data subjects are persisted

**Consumer types used:**
- **Push consumer** (server delivers to subscriber) — used by FIT writer and dashboards
- **Pull consumer** (consumer fetches batches) — used by Firebase Sync (allows rate control during upload)

#### Stream definitions

| Stream | Subject filter | Retention | Max age | Purpose |
|---|---|---|---|---|
| `SESSION_{yyyyMMdd_HHmmss}` | `lab.>` | `LimitsPolicy` | Until Firebase ack + 7 days | Full session record. Created at `session.start`, deleted after cloud sync confirms. One stream per session. |
| `LAB_STATE` | `lab.*.*.state`, `lab.session.events` | `LimitsPolicy`, last value per subject | 24 h | Current device state. Late-joining clients get instant current state via this stream. |
| `LAB_CALIBRATION` | `lab.*.*.calibration` | `LimitsPolicy` | 30 days | Calibration audit trail across sessions. |
| `LAB_CONTROL` | `lab.control.>` | `LimitsPolicy` | 4 h | Command audit log. Note: control reply messages to `_INBOX.*` are not captured. |

**Per-session stream details:**
```
Name:          SESSION_20260304_143022
Subjects:      lab.>
Storage:       File (disk)
Retention:     LimitsPolicy
Max age:       0 (no expiry until explicit delete after Firebase ack)
Max msg size:  64 KB
Discard:       DiscardOld (when limits hit, oldest dropped — should never happen at 1.6 MB/session)
```

The daemon creates this stream on `session.start` and deletes it after Firebase Sync
publishes `lab.session.events { event: "synced" }`.

### 6.7 Message Serialisation

All NATS message payloads are **UTF-8 encoded JSON**. No binary encoding, no protobuf.
Rationale: human-readable for debugging, no schema compilation step, adequate throughput
for the data rates involved (~1 Hz per channel).

NATS message headers (the `NATS-` header namespace) are not used by the application layer —
all metadata lives in the JSON body. The exception is JetStream's own internal headers
(`Nats-Sequence`, `Nats-Time-Stamp`) which are added by the server automatically.

**Dart types:**  All message classes in `lab_models` have `toJson()` / `fromJson()` generated
by `json_serializable`. The `lab_models` package is the single source of truth for all
message schemas — no ad-hoc JSON construction anywhere in the daemon or clients.

---

## 7. Control Interface Specification

### 7.0 NATS Messaging Layer — How Control Commands Work

This section describes the full round-trip for every control command, from client to daemon
to hardware and back. The BLE byte-level detail for each subsystem then follows in §7.1–§7.5.

#### 7.0.1 Daemon command handler algorithm (all request/reply commands)

The daemon follows this sequence for every command it receives on a `lab.control.*` subject:

```
1. Receive NATS message on lab.control.*.*.*
   - msg.replyTo contains the _INBOX.{id} address to reply to
   - msg.payload is UTF-8 JSON

2. Validate payload
   - Parse JSON; reject if malformed → reply { ok: false, error: "INVALID_PARAMS: ..." }
   - Check required fields and ranges → reply { ok: false, error: "INVALID_PARAMS: {field}" }

3. Check daemon state guards (see §7.0.3)
   - Device must exist → reject if unknown device_id
   - Device must be in required state → reply { ok: false, error: "DEVICE_NOT_READY: ..." }
   - Session required? → reply { ok: false, error: "SESSION_NOT_ACTIVE" }

4. Send BLE command (or internal action e.g. create JetStream stream)
   - Set a per-command hardware timeout (see §6.5 timeout table)
   - Await BLE characteristic notification / indication

5a. Hardware acked success →
   - Update internal device state
   - Publish updated state to lab.*.*.state (pub/sub, for subscribers)
   - Reply to msg.replyTo: { ok: true, data: { ... } }

5b. Hardware returned error code →
   - Reply: { ok: false, error: "HARDWARE_REJECTED: {device} returned {code}" }

5c. Hardware timeout (no ack within limit) →
   - Reply: { ok: false, error: "TIMEOUT: no ack from {device} within {ms}ms" }

5d. BLE write failed (device disconnected mid-command) →
   - Mark device DISCONNECTED in registry
   - Trigger reconnect
   - Reply: { ok: false, error: "DEVICE_DISCONNECTED: {device}" }
```

**The daemon NEVER leaves a request unanswered.** Every code path must call
`nats.publish(msg.replyTo, ...)` exactly once before the handler exits.

#### 7.0.2 Pub/Sub commands (fire-and-forget)

Fire-and-forget subjects (`session.lap`, `metabolic.lactate.submit`) do not have a reply-to.
The daemon subscribes, receives, processes, and does not reply. No timeout applies.
If the daemon does not process the message (e.g. it is offline), the message is lost —
that is acceptable for lap markers and manual lactate timing, which are non-critical.

If loss-free lap marking is required in future, the subject can be promoted to request/reply by
changing the subscriber in the daemon without changing any other protocol decision.

#### 7.0.3 Guard conditions table

| Command | Condition | Error if violated |
|---|---|---|
| `trainer.*.set_power` / `set_resistance` / `set_simulation` | Device state = `CONTROLLING` | `DEVICE_DISCONNECTED` if disconnected; `DEVICE_NOT_READY: trainer_1 is not in CONTROLLING state` if connected but handshake incomplete |
| `trainer.*.start` / `stop` / `reset` | Device state ≥ `CONNECTED` | `DEVICE_NOT_READY` |
| `metabolic.*.set_state` | `device_state` ∈ `{"idle", "recording"}` (i.e. not already calibrating) | `DEVICE_NOT_READY: vo2_1 is not in a commandable state` |
| `metabolic.*.start_gas_cal` / `start_flow_cal` | `device_state` = `"idle"` or `"recording"` | `DEVICE_NOT_READY` |
| `metabolic.*.abort_calibration` | `device_state` ∈ `{"calibrating_gas", "calibrating_flow", "zeroing_flow"}` | `DEVICE_NOT_READY: vo2_1 is not calibrating` |
| `session.stop` / `pause` / `resume` / `lap` | A session is active (`sessionState != idle`) | `SESSION_NOT_ACTIVE` |
| `session.start` | No session active | `SESSION_ALREADY_ACTIVE: session {id} is running` |
| `devices.connect` / `disconnect` | No additional guards — always attempt | — |

#### 7.0.4 Full round-trip flows — annotated examples

**Example A: Trainer set_power (success)**
```
Client:
  reply = await nats.request(
    'lab.control.trainer.trainer_1.set_power',
    '{"watts": 250}',
    timeout: Duration(milliseconds: 3000),
  )
  // reply.payload = '{"ok":true,"error":null,"data":{"watts":250}}'

Daemon (receives on lab.control.trainer.trainer_1.set_power):
  1. Parse: watts=250 ✓ range 0–2000 ✓
  2. Guard: trainer_1.state == CONTROLLING ✓
  3. BLE write to Control Point [0x05, 0xFA, 0x00]
  4. Await indication on Control Point within 3000ms
  5. Receive [0x80, 0x05, 0x01] → success
  6. Update daemon state: targetPowerW = 250
  7. Publish to lab.trainer.trainer_1.state { ..., "target_power_w": 250 }
  8. Publish to _INBOX.{id}: {"ok":true,"error":null,"data":{"watts":250}}
```

**Example B: Trainer set_power (device not in CONTROLLING state / disconnected)**
```
Client:
  reply = await nats.request(
    'lab.control.trainer.trainer_1.set_power',
    '{"watts": 250}',
    timeout: Duration(milliseconds: 3000),
  )
  // If DISCONNECTED:
  // reply.payload = '{"ok":false,"error":"DEVICE_DISCONNECTED: trainer_1 is not connected","data":{}}'
  // If CONNECTED but handshake not yet complete (not yet CONTROLLING):
  // reply.payload = '{"ok":false,"error":"DEVICE_NOT_READY: trainer_1 is not in CONTROLLING state","data":{}}'

Daemon:
  1. Parse: watts=250 ✓
  2. Guard: trainer_1.state == DISCONNECTED → reply DEVICE_DISCONNECTED immediately
     Guard: trainer_1.state != CONTROLLING → reply DEVICE_NOT_READY (connected but not controlling)
  3. Publish to _INBOX.{id}: {"ok":false,"error":"DEVICE_DISCONNECTED: ...","data":{}}
  // No BLE write attempted
```

**Example C: Trainer set_power (BLE timeout)**
```
Client:
  reply = await nats.request(...)
  // reply.payload = '{"ok":false,"error":"TIMEOUT: no ack from trainer_1 within 3000ms","data":{}}'

Daemon:
  1. Parse OK, guard OK
  2. BLE write sent
  3. 3000ms passes with no indication from KICKR
  4. Publish TIMEOUT error reply to _INBOX.{id}
```

**Example D: Session start (success)**
```
Client:
  reply = await nats.request(
    'lab.control.session.start',
    '{"athlete_id":"athlete_1","weight_kg":70.5,"ftp_w":285,"protocol":"ramp_test"}',
    // No vo2_settings — VO2 Master configured beforehand via set_venturi / set_mask
    timeout: Duration(milliseconds: 5000),
  )
  // reply.payload = '{"ok":true,"error":null,"data":{"session_id":"20260304_143022"}}'

Daemon:
  1. Parse payload ✓
  2. Guard: sessionState == idle ✓
  3. Create JetStream stream SESSION_20260304_143022 with subjects ["lab.>"]
  4. Set sessionState = ACTIVE, sessionId = "20260304_143022"
  5. Start FIT writer consumer on session stream
  6. Publish to lab.session.events { "event": "started", "session_id": "...", "athlete_id": "..." }
  7. Reply to _INBOX.{id}: {"ok":true,"error":null,"data":{"session_id":"20260304_143022"}}
```

**Example E: VO2 Master set_state to recording (success)**
```
Client:
  reply = await nats.request(
    'lab.control.metabolic.vo2_1.set_state',
    '{"state":"recording"}',
    timeout: Duration(milliseconds: 5000),
  )
  // reply.payload = '{"ok":true,"error":null,"data":{"state":"recording","sub_state":"none"}}'

Daemon:
  1. Parse: state="recording" ✓
  2. Guard: vo2_1.device_state ∈ {"idle","recording"} ✓  (not already calibrating)
  3. BLE write to COM IN [0x01, 0x00, 0x02, 0x00]  (SetState, Recording=2)
  4. Await COM OUT notification within 5000ms
  5. Receive [0x02, 0x00, 0x12, 0x00]  (GetState response, value=0x0012 = Recording|IsCalibrated)
  6. Parse: deviceState=Recording, isCalibrated=true
  7. Publish to lab.metabolic.vo2_1.state { "device_state": "recording", "is_calibrated": true }
  // device_state is one of: "idle" | "recording" | "calibrating_gas" | "calibrating_flow" | "zeroing_flow"
  // is_calibrated reflects gas calibration status (separate concept from device_state)
  8. Reply to _INBOX.{id}: {"ok":true,"error":null,"data":{"state":"recording","sub_state":"none"}}
```

**Example F: VO2 flow calibration start (async progress)**
```
Client:
  // Step 1 — start calibration (request/reply for the start confirmation only)
  reply = await nats.request(
    'lab.control.metabolic.vo2_1.start_flow_cal',
    '{"syringe_l":3.0,"breaths":10}',
    timeout: Duration(milliseconds: 3000),
  )
  // reply.payload = '{"ok":true,"error":null,"data":{"current_breath":0,"total_breaths":10}}'

  // Step 2 — subscribe for async progress (pub/sub, no reply)
  nats.subscribe('lab.metabolic.vo2_1.calibration').listen((msg) {
    final data = jsonDecode(msg.payload);
    // { "type": "flow_progress", "current_breath": 3, "total_breaths": 10, "breath_rejected": false }
    // ... update UI progress bar
  });

  // Final progress message when calibration completes:
  // { "type": "flow_complete", "success": true, "result": { "slope": 1.003, "offset": 0.001 } }
  // Or: { "type": "flow_complete", "success": false, "error": "..." }

Daemon:
  1. Parse, guards ✓
  2. SetSyringeVolume(3000), SetSyringeBreathCount(10), SetState(CalibrateFlowSensor=4)
  3. Reply immediately to _INBOX.{id}: {"ok":true,...,"data":{"current_breath":0,"total_breaths":10}}
  4. Start metronome goroutine / Dart Timer at target Rf
  5. Per breath (COM OUT BreathStateChanged + GetSyringeProgress):
       Publish to lab.metabolic.vo2_1.calibration { "type": "flow_progress", ... }
  6. On 0x1532 completion notification:
       Publish to lab.metabolic.vo2_1.calibration { "type": "flow_complete", ... }
```

---

### 7.1 Trainer (FTMS) — BLE byte detail

**ERG command bytes:** `[0x05, watts_low, watts_high]` — sint16 little-endian, 0–2000 W.

**Resistance command bytes:** `[0x04, level_low, level_high]` — uint16, value = level × 10, range 0–1000 (0–100%).

**Simulation command bytes:** `[0x11, ws_low, ws_high, gr_low, gr_high, crr, cw]`
- wind speed: sint16 LE × 1000 → resolution 0.001 m/s, range ±30 m/s
- grade: sint16 LE × 100 → resolution 0.01%, range ±40%
- CRR: uint8 LE × 10000 → typical values 0.004 (tyre to asphalt)
- Cw: uint8 LE × 100 → typical values 0.3–0.7 kg/m

**Set target power example — 250 W:**
```
[0x05, 0xFA, 0x00]
 OP   LSB   MSB     250 = 0x00FA  → little-endian LSB first
```

**Start/Resume op:** `[0x07]`  
**Stop op:** `[0x08, 0x01]` (0x01 = cool-down, 0x02 = spin-down alternative)  
**Reset op:** `[0x01]`

**FTMS indication byte meanings (response on 0x2AD9):**
```
[0x80, op_code, result_code]
  0x80 = response opcode
  op_code = echo of the command that was sent
  result_code:
    0x01 = Success
    0x02 = OpCode Not Supported
    0x03 = Invalid Parameter
    0x04 = Operation Failed
    0x05 = Control Not Permitted
```

### 7.2 FTMS handshake (required on every connection)

```
1. Connect to KICKR BIKE SHIFT (scan filter: service UUID 00001826-0000-1000-8000-00805f9b34fb)
2. Enable indications on Fitness Machine Control Point (0x2AD9)
3. Enable notifications on Fitness Machine Status (0x2ADA)
4. Enable notifications on Indoor Bike Data (0x2AD2)
5. Send [0x00] to Control Point                      → REQUEST_CONTROL
6. Wait for indication [0x80, 0x00, 0x01]            → control granted, now in CONTROLLING state
7. Set daemon device state: trainer_1 = CONTROLLING
```

**If response is [0x80, 0x00, 0x05]** (CONTROL_NOT_PERMITTED):
- Another application has control (Wahoo app, Zwift, etc.)
- Daemon marks device state = ERROR, publishes to `lab.trainer.trainer_1.state`
- Subsequent control commands fail with `DEVICE_NOT_READY` until reconnect

**After reconnect:** full handshake re-executes automatically before any command is sent.

### 7.3 VO2 Master — BLE byte detail

**All VO2 Master BLE I/O appears on two characteristics:**
- `COM IN`  = `0x1525` — write (daemon → device) — `[cmd_low, cmd_high, val_low, val_high]`
- `COM OUT` = `0x1526` — notify (device → daemon) — `[resp_low, resp_high, val_low, val_high]`
- `CAL RESULT` = `0x1532` — notify (device → daemon, calibration complete notifications only)

Both `cmd_high` and `val_*` are uint16 little-endian. Command IDs are 16-bit.

**Key command IDs (from SDK):**

| Command | ID (hex) | Direction | Value meaning |
|---|---|---|---|
| `GetState` | `0x0002` | Write; device replies on COM OUT with same ID | Reply value = state enum |
| `SetState` | `0x0001` | Write; device publishes GetState on COM OUT | Value = new state enum |
| `SetVenturiSize` | `0x000A` | Write; no immediate notify — confirmed by GetState | Value = venturi enum |
| `SetMaskSize` | `0x000B` | Write | Value = mask enum |
| `SetIdleTimeoutMode` | `0x000E` | Write | 0 = disabled |
| `SetSyringeBreathCount` | `0x000C` | Write | Value = breath count |
| `SetSyringeVolume` | `0x000D` | Write | Value = volume in mL |
| `GetGasCalibrationInfo` | `0x0006` | Write; reply on COM OUT | Value = packed flags |
| `GetSyringeProgress` | `0x0009` | Write; reply on COM OUT | `current = val & 0xFF`, `total = val >> 8` |
| `GetSyringeFlags` | `0x000F` | Write; reply on COM OUT | Bitfield of syringe status |
| `GetSubState` | `0x0003` | Write; reply on COM OUT | Sub-state enum |
| `BreathStateChanged` | `0x0008` | Notify (device → daemon spontaneously) | 0=Inhale, 2=Exhale |

**State enum values (used in SetState / GetState):**

| Value | Name | Meaning |
|---|---|---|
| 0 | Idle | Device powered but not measuring |
| 1 | Recording | Measuring breath-by-breath |
| 3 | CalibratingGas | Gas calibration in progress |
| 4 | CalibrateFlowSensor | Flow calibration in progress |
| 5 | ZeroingFlow | Zeroing flow sensor (nose clip required) |

**Example SetState(Recording):**
```
Write to COM IN: [0x01, 0x00, 0x02, 0x00]
                  cmd=0x0001 (SetState)  val=0x0002 (Recording)
Device publishes on COM OUT: [0x02, 0x00, 0x12, 0x00]
                              cmd=0x0002 (GetState)  val=0x0012 = 0b00010010 = Recording(0x02) | IsCalibrated(0x10)
```

**Mandatory connection handshake (every power cycle / reconnect):**
```
Phase 1 — Configure (write, no response wait needed except timing):
  SetVenturiSize(configured_venturi)      → 0x000A
  SetMaskSize(configured_mask)            → 0x000B
  SetIdleTimeoutMode(0)                   → 0x000E (disable auto-sleep)
  SetSyringeBreathCount(10)               → 0x000C
  SetSyringeVolume(3000)                  → 0x000D (3 L syringe default)

Phase 2 — Read state (write command, await COM OUT notify):
  GetState          → await [0x02, 0x00, *, *]  (parse state + is_calibrated flags)
  GetSubState       → await [0x03, 0x00, *, *]  (parse sub-state)
  GetGasCalibrationInfo → await [0x06, 0x00, *, *]  (gas cal freshness)
  GetSyringeProgress    → await [0x09, 0x00, *, *]  (if flow cal was interrupted)
  GetSyringeFlags       → await [0x0F, 0x00, *, *]  (syringe size validation)

After handshake: device state = READY; publish to lab.metabolic.vo2_1.state
```

The daemon caches all polled values from Phase 2 in its device model; subsequent
control commands use these cached values for guard checks (e.g. `is_calibrated`).

### 7.4 Flow calibration sequence (full detail)

#### 7.4.1 Client interaction

```
// 1. Initiate — request/reply (confirms calibration started, returns initial progress)
reply = await nats.request(
  'lab.control.metabolic.vo2_1.start_flow_cal',
  '{"syringe_l": 3.0, "breaths": 10}',
  timeout: Duration(milliseconds: 3000),
)
// {"ok":true,"error":null,"data":{"current_breath":0,"total_breaths":10}}

// 2. Monitor progress — pub/sub subscription (fire before or after step 1; messages arrive on this subject throughout)
nats.subscribe('lab.metabolic.vo2_1.calibration').listen((msg) {
  final json = jsonDecode(msg.payload);
  switch (json['type']) {
    case 'flow_progress':
      // { "type":"flow_progress", "current_breath":3, "total_breaths":10, "breath_state":"exhale", "rejected":false }
      break;
    case 'breath_rejected':
      // { "type":"breath_rejected", "reason":"out_of_window" }
      break;
    case 'flow_complete':
      // { "type":"flow_complete", "success":true, "result":{"slope":1.003,"offset":0.001} }
      // Or: { "type":"flow_complete", "success":false, "error":"CAL_FAILED: device aborted" }
      break;
  }
});

// 3. Abort at any time — request/reply
abort = await nats.request(
  'lab.control.metabolic.vo2_1.abort_calibration',
  '{}',
  timeout: Duration(milliseconds: 3000),
)
// {"ok":true,"error":null,"data":{}}
```

#### 7.4.2 Daemon-side sequence for start_flow_cal

```
Receive: lab.control.metabolic.vo2_1.start_flow_cal {"syringe_l": 3.0, "breaths": 10}

1. Validate: syringe_l ∈ {0.5, 1.0, 2.0, 3.0}; breaths ∈ [3, 30]; device READY ✓
2. Write SetSyringeVolume(3000) → [0x0D, 0x00, 0xB8, 0x0B]  (3000 mL = 0x0BB8)
3. Write SetSyringeBreathCount(10) → [0x0C, 0x00, 0x0A, 0x00]
4. Write SetState(CalibrateFlowSensor=4) → [0x01, 0x00, 0x04, 0x00]
5. Reply to _INBOX.{id}: {"ok":true,"error":null,"data":{"current_breath":0,"total_breaths":10}}
6. Start metronome Timer for target Rf (see §7.5 for beat period per venturi size)

Loop (per COM OUT BreathStateChanged notification from device):
  a. Receive [0x08, 0x00, breath_state, 0x00]
     breath_state: 0=Inhale, 2=Exhale
  b. Send GetSyringeProgress: [0x09, 0x00, 0x00, 0x00]
  c. Receive GetSyringeProgress notify: value = [0x09, 0x00, cur, tot]
     current_breath = cur, total_breaths = tot
  d. If cur == prev_cur → breath rejected (syringe did not advance)
       Publish to lab.metabolic.vo2_1.calibration: { "type": "breath_rejected", "reason": "out_of_window" }
  e. Else:
       Publish to lab.metabolic.vo2_1.calibration: { "type": "flow_progress", ... }

On CAL RESULT notification (0x1532):
  Parse slope + offset from notification payload
  Stop metronome
  Publish to lab.metabolic.vo2_1.calibration: { "type": "flow_complete", "success": true, "result": {...} }
  Update device model: isFlowCalibrated = true
  Write SetState(Idle=0)

On abort_calibration received:
  Write SetState(Idle=0)
  Stop metronome
  Publish to lab.metabolic.vo2_1.calibration: { "type": "flow_complete", "success": false, "error": "aborted" }
  Reply to _INBOX.{abort_id}: {"ok":true,"error":null,"data":{}}
```

### 7.5 Metronome cadence (V1.6 Rf validation windows)

The VO2 Master V1.6 firmware validates each syringe stroke against an expected Rf
(respiratory frequency) window. The daemon runs a software metronome to guide the technician
— it publishes audio/visual cue events on `lab.metabolic.vo2_1.calibration` as
`{ "type": "metronome_beat", "action": "push" | "pull" }`.

| Venturi setting | Target Rf | Rejection window | Beat period | Metronome publish interval |
|---|---|---|---|---|
| Medium (default) | 30 bpm | < 27.5 or > 32.5 | 1.0 s | 1.0 s (alternating push/pull) |
| Large | 40 bpm | < 37.5 or > 42.5 | 0.75 s | 0.75 s |
| Resting | 15 bpm | < 12.5 or > 17.5 | 2.0 s | 2.0 s |

Breath-reject detection:
- `BreathStateChanged` fires (step d above) but `GetSyringeProgress.current` does not change
- → breath was rejected by firmware, likely out-of-window stroke timing
- Daemon logs + publishes `breath_rejected` event; increments a local rejection counter
- If rejections > 50% of attempts, the daemon publishes a warning flag in the next progress event

### 7.6 Session lifecycle state machine

```
                    session.start ──────────
                          ▼                 │ (guard: no session active)
         ┌──────────── ACTIVE ─────────────┐
         │                │                │
    session.pause    session.lap      session.stop
         │         (pub/sub, no state    │
         ▼            change)            ▼
       PAUSED                          IDLE (initial state)
         │
    session.resume
         │
         ▼
       ACTIVE
```

**Session state transitions:**

| Current | Command | New state | Guard |
|---|---|---|---|
| IDLE | `session.start` | ACTIVE | None (daemon idle required) |
| ACTIVE | `session.stop` | IDLE | — |
| ACTIVE | `session.pause` | PAUSED | — |
| PAUSED | `session.resume` | ACTIVE | — |
| PAUSED | `session.stop` | IDLE | — |
| ACTIVE or PAUSED | `session.lap` | unchanged (pub/sub) | — |
| IDLE | `session.stop` / `pause` / `resume` | — | Error: `SESSION_NOT_ACTIVE` |
| ACTIVE | `session.start` | — | Error: `SESSION_ALREADY_ACTIVE` |

**On `session.stop`:**
1. FIT writer consumer finalises file (writes activity summary record, closes file)
2. Daemon publishes `lab.session.events { "event": "stopped", "session_id": "...", "duration_s": N, "fit_path": "..." }`
3. Firebase Sync consumer begins pull-consuming the session JetStream stream → upload to Firebase Storage
4. When upload complete: Firebase Sync publishes `lab.session.events { "event": "synced", "session_id": "..." }`
5. Daemon deletes JetStream stream `SESSION_{id}` after verifying sync ack

---

## 8. Connection & Lifecycle Management

### 8.1 Device states

```
UNKNOWN → SCANNING → FOUND → CONNECTING → CONNECTED → READY → ERROR
                                                      ↑           ↓
                                                      └── RECONNECTING ←─┘
```

- **READY**: device is fully operational and streaming data
- **RECONNECTING**: auto-retry with exponential backoff (1s, 2s, 4s, 8s, max 30s)
- Sensors that require a handshake (VO2 Master, FTMS) re-send it after each reconnect

### 8.2 Device registry

Devices are declared in `config/devices.json` on the lab machine. The daemon reads this
file on startup and immediately begins scanning and connecting all listed devices —
no client interaction required to bring devices online.

**Startup connection sequence:**
```
1. Daemon starts, reads config/devices.json
2. For each device: scan using its filter → connect → run handshake → mark READY
3. Publishes lab.*.*.state for each device as it becomes READY
4. Flutter client opens and immediately sees current device states
   via the LAB_STATE JetStream stream (last-value cache per subject)
```

If a device is not found within the scan window it is marked `DISCONNECTED` and
the daemon retries with exponential backoff (§8.1). The Flutter operator app can use
`lab.control.devices.scan` and `lab.control.devices.connect` to trigger a manual
retry outside the automatic backoff schedule.

Each device has a stable `device_id` assigned at configuration time (not derived from
BLE address, which can change). The registry maps:

```json
{
  "trainer_1": {
    "label": "KICKR BIKE SHIFT",
    "category": "trainer",
    "protocol": "ble_ftms",
    "scan_filter": { "service_uuid": "00001826-0000-1000-8000-00805f9b34fb" },
    "scan_name_prefix": "KICKR BIKE SHIFT"
  },
  "vo2_1": {
    "label": "VO2 Master #5342",
    "category": "metabolic",
    "protocol": "ble_vo2master",
    "scan_filter": { "name_prefix": "VO2 Master" }
  },
  "hr_1": {
    "label": "Polar H10",
    "category": "heart_rate",
    "protocol": "ble_hrs",
    "scan_filter": { "service_uuid": "0000180d-0000-1000-8000-00805f9b34fb" }
  }
}
```

### 8.3 Session config

Injected at session start — provides context that the sensors themselves don't know:

```json
{
  "athlete_id": "athlete_001",
  "weight_kg":  70.0,
  "ftp_w":      280,
  "protocol":   "ramp_test"
}
// Note: VO2 Master is configured before session start via dedicated set_venturi and set_mask
// commands. session.start carries no VO2 configuration — the device retains its last-set
// venturi size, mask size, and idle timeout from the connection handshake.
```

`weight_kg` is used to compute `vo2_ml_min_kg` in gas exchange messages.

---

## 9. FIT File Output

The Sensor Hub writes a standard `.fit` file per session as a secondary, compatibility output.
The FIT writer is a NATS consumer — it subscribes to the lab NATS subjects and merges data
into FIT records. It is completely decoupled from the driver layer.

### 9.1 Architecture

```
NATS subjects (§6.1)  →  FIT Writer  →  activity_{timestamp}.fit
```

- FIT writer subscribes to: `lab.*.*.metrics`, `lab.*.*.ventilatory`, `lab.*.*.gas_exchange`,
  `lab.metabolic.lactate`, `lab.temperature.*.metrics`, `lab.session.events`
- Writes standard FIT record messages at **1 Hz** (merged snapshot of all latest values)
- Writes per-breath ventilatory/gas exchange records at **breath resolution** (event-based)
- Writes lap records on `lab.session.events` with `event: lap`
- Finalises file with session summary on `event: stopped`

### 9.2 Standard FIT record fields used

Fields that map directly to official FIT record message fields (no developer extension needed):

| FIT field name | FIT field # | Type | Units | Source |
|---|---|---|---|---|
| `timestamp` | 253 | uint32 | s since FIT epoch | All records |
| `heart_rate` | 3 | uint8 | bpm | `lab.hr.*.metrics` |
| `cadence` | 4 | uint8 | rpm | `lab.trainer.*.metrics` or `lab.power.*.metrics` |
| `power` | 7 | uint16 | W | `lab.trainer.*.metrics` (primary trainer) |
| `speed` | 6 | uint16 | m/s × 1000 | `lab.trainer.*.metrics` |
| `left_right_balance` | 30 | uint8 | % | `lab.power.*.metrics` (if available) |
| `temperature` | 13 | sint8 | °C | `lab.metabolic.*.environment` (ambient) |
| `total_cycles` | 11 | uint32 | cycles | Cumulative cadence strokes |

### 9.3 Developer data fields — definition

All non-standard metrics use FIT developer data fields. The hub registers a single developer
data namespace identified by a fixed UUID, then defines each field via `FieldDescription` messages
written at the start of every FIT file.

**Developer App UUID:** `b5f4e2a1-c3d7-4f8b-9e2c-1a6d5f7b3c9e` (lab sensor hub app)

| Field # | Name | FIT base type | Units | Scale | Source stream |
|---|---|---|---|---|---|
| 0 | `respiratory_frequency` | float32 | bpm | 1.0 | `ventilatory.rf_bpm` |
| 1 | `tidal_volume` | float32 | L | 1.0 | `ventilatory.tv_l` |
| 2 | `minute_ventilation` | float32 | L/min | 1.0 | `ventilatory.ve_l_min` |
| 3 | `feo2` | float32 | % | 1.0 | `gas_exchange.feo2_pct` |
| 4 | `vo2_absolute` | float32 | mL/min | 1.0 | `gas_exchange.vo2_ml_min` |
| 5 | `vo2_relative` | float32 | mL/min/kg | 1.0 | `gas_exchange.vo2_ml_min_kg` |
| 6 | `breath_number` | uint32 | — | 1 | `ventilatory.breath_no` / `gas_exchange.breath_no` |
| 7 | `lactate` | float32 | mmol/L | 1.0 | `lab.metabolic.lactate` |
| 8 | `core_body_temperature` | float32 | °C | 1.0 | `temperature.core_temp_c` |
| 9 | `skin_temperature` | float32 | °C | 1.0 | `temperature.skin_temp_c` |
| 10 | `ambient_pressure` | float32 | hPa | 1.0 | `environment.pressure_hpa` |
| 11 | `ambient_humidity` | float32 | % | 1.0 | `environment.humidity_rh` |
| 12 | `trainer_2_power` | uint16 | W | 1 | `lab.trainer.trainer_2.metrics` (second bike) |
| 13 | `trainer_2_cadence` | uint8 | rpm | 1 | `lab.trainer.trainer_2.metrics` |
| 14 | `left_power` | uint16 | W | 1 | Computed: `power.metrics.power_w × balance_pct ÷ 100` (if `balance_pct` available) |
| 15 | `right_power` | uint16 | W | 1 | Computed: `power.metrics.power_w × (1 − balance_pct ÷ 100)` (if `balance_pct` available) |

### 9.4 FIT record cadence strategy

The FIT writer emits two types of records interleaved in timestamp order:

**1 Hz merged records** — written every second for continuous time series data:
- Standard fields: HR, cadence, power, speed
- Developer fields: core temp, skin temp, humidity, pressure
- Developer fields: trainer 2 power/cadence (if second trainer active)
- Developer fields: left/right power (if secondary power meter active)

**Per-breath records** — written immediately on each `ventilatory` or `gas_exchange` event:
- Standard fields: HR (snapshot), cadence (snapshot), power (snapshot)
- Developer fields: Rf, Tv, VE, FeO2, VO2 absolute, VO2 relative, breath_number
- These records may appear at 10–40 per minute (faster than 1 Hz during high-intensity exercise)

**Lap records** — written on `lab.session.events` with `event: lap`:
- Standard FIT lap fields: lap_start_time, total_elapsed_time, total_timer_time
- Developer field: lactate (most recent value at lap time)
- Usage: lab protocol stages (each interval = one lap)

### 9.5 FIT file structure

```
FileHeader (14 bytes)
FileId message          (type=activity, manufacturer=development, serial=athlete_id hash)
DevDataId message       (app_uuid, developer_data_index=0)
FieldDescription × 16   (one per developer field in §9.3 table)
Event message           (timer_trigger=manual, event_type=start)
[ per session: ]
  Record messages       (1 Hz + per-breath, interleaved by timestamp)
  Lap message           (on each lap event)
Event message           (timer_trigger=manual, event_type=stop_disable)
Session message         (summary: total time, total distance, avg/max power, avg/max HR)
Activity message        (num_sessions=1, type=manual)
CRC (2 bytes)
```

### 9.6 Compatibility targets

The FIT file is tested to import correctly into:
- Garmin Connect (web + app)
- TrainingPeaks (standard fields + developer fields shown in custom charts)
- WKO5 (standard fields import; developer fields visible via data channel mapping)
- GoldenCheetah (full developer field support)

Coaching software that does not support developer fields will still import the standard
fields (power, HR, cadence, speed, lap markers) without error — developer fields are
gracefully ignored by non-aware parsers.

---

## 10. Persistence & Cloud Sync

### 10.1 Persistence Tiers

Data flows through three persistence tiers:

```
[Sensors]
    │
    ▼
[NATS JetStream]  ←─ Local on-machine persistence. Session stream retained until
    │                  Firebase Sync confirms upload. Survives daemon restart.
    │                  Acts as offline buffer when internet is unavailable.
    │
    ├──► [FIT File]      ←─ Written locally at session end. Single binary file,
    │                       full resolution, all sensor data. Primary analysis artifact.
    │
    └──► [Firebase]      ←─ Cloud persistence. Uploaded by Firebase Sync consumer.
                            Session metadata + summary in Firestore.
                            FIT file binary in Firebase Storage.
```

### 10.2 What Goes Where in Firebase

Firestore and Firebase Storage serve different purposes. **Raw time-series data is never
written to Firestore** — the FIT file is the full-resolution record.

| Data | Firebase service | Resolution | Notes |
|---|---|---|---|
| Session metadata | Firestore | Once per session | athlete, protocol, start/end timestamps, device IDs |
| Session summary | Firestore | Once per session | avg/max power, avg/max HR, avg VO2, total time, lap splits |
| Lap splits | Firestore sub-collection | Once per lap | lap number, start offset, duration, avg metrics |
| Lactate readings | Firestore sub-collection | Per measurement | mmol/L + timestamp + note |
| Gas calibration results | Firestore sub-collection | Per calibration | pass/fail + stats |
| FIT file (full data) | Firebase Storage | Once per session | Uploaded at session end |
| FIT file download URL | Firestore (field on session doc) | Once, after upload | Stored after Storage upload completes |

**Not in Firestore:** 1Hz power/HR/speed records, per-breath ventilatory/gas exchange. These are
fully captured in the FIT file and in JetStream during the session.

### 10.3 Firestore Document Structure

```
Firestore:
  /athletes/{athlete_id}/
    /sessions/{session_id}/              ← session metadata + summary
      protocol: "ramp_test"
      started_at: Timestamp
      ended_at: Timestamp
      fit_file_url: "gs://..."
      summary: { avg_power_w, max_hr_bpm, avg_vo2_ml_kg, ... }
      /laps/{lap_n}/                     ← lap splits
        duration_s, avg_power_w, avg_hr_bpm, avg_vo2_ml_kg, ...
      /lactate/{timestamp}/              ← manual lactate readings
        mmol_l, offset_s, note
      /calibrations/{timestamp}/         ← calibration events
        type, passed, mean_l, std_dev_l
```

### 10.4 Firebase Sync Consumer

A separate Dart process (or isolate within the daemon) that:

1. Subscribes to the session JetStream stream as a **durable push consumer**
2. On `lab.session.events { event: stopped }`: computes session summary from accumulated data,
   writes Firestore session doc, uploads FIT file to Firebase Storage, stores download URL
3. On individual `lab.metabolic.lactate` events: writes Firestore sub-document in real-time
   (lactate is low-frequency — fine to write each one directly)
4. On calibration completion events (`lab.metabolic.*.calibration` with result): writes
   Firestore calibration sub-document
5. Acks each JetStream message only after Firestore write succeeds — if Firebase is
   unreachable, the consumer pauses and retries; JetStream buffers the session data on disk

**Offline-first guarantee:** The session JetStream stream is retained on the lab machine
until the Firebase Sync consumer has fully acked all messages. If the machine has no internet
during a session, the stream accumulates locally. When connectivity returns, the consumer
catches up and uploads. The session is never lost.

**Firebase auth:** Service account JSON key, injected as an environment variable
(`FIREBASE_SERVICE_ACCOUNT_JSON`). Never hardcoded. Auth token refreshed automatically
(Firebase REST tokens expire every 60 minutes; the sync consumer handles refresh).

**Firebase SDK in the daemon:** `FlutterFire` requires Flutter; not suitable for the headless
daemon. The Firebase Sync consumer uses the **Firebase REST API** directly via Dart's
`dart:io` `HttpClient` — no SDK dependency. Firestore and Firebase Storage both expose full
REST APIs, and Firebase Auth (service account) is a standard OAuth2 token exchange.

### 10.5 FIT File Lifecycle

```
Session start
  └─ FIT writer opens output file: sessions/{session_id}.fit

During session
  └─ FIT writer appends 1Hz records + per-breath records + lap records
     (subscribes directly to NATS; does not use JetStream consumer — real-time only)

Session stop (lab.session.events { event: stopped })
  └─ FIT writer finalises file: writes Session + Activity messages + CRC
  └─ Publishes: lab.session.events { event: fit_ready, path: "sessions/{id}.fit" }

Firebase Sync receives fit_ready
  └─ Uploads file to Firebase Storage: gs://bucket/sessions/{athlete_id}/{session_id}.fit
  └─ Writes download URL to Firestore session doc
  └─ Records upload timestamp in local metadata: sessions/{session_id}.fit.meta
  └─ Local FIT file retained for 90 days after confirmed upload, then auto-deleted
     (daemon runs a daily cleanup pass: delete .fit files where upload_confirmed AND age > 90d)
```

### 10.6 Remote Live Dashboard via Firebase Realtime Database *(deferred — no current use-case)*

> **Status: Deferred indefinitely (D25).** No concrete remote-viewing requirement exists. The
> infrastructure complexity and ongoing Firebase Realtime Database cost are not justified.
> The design below is retained as a reference if this requirement ever emerges — do not implement.

For coaches or analysts watching remotely (not on the lab LAN), Firebase Realtime Database
provides a low-latency push channel without exposing the lab's NATS port to the internet:

- A lightweight **Firebase Realtime Bridge** process subscribes to NATS and writes selected
  metrics to Firebase Realtime Database at 1 Hz (HR, power, VO2, pace — the fields the
  remote viewer actually needs)
- The remote Flutter Web app reads from Firebase Realtime Database — not from NATS
- Lab LAN clients still connect to NATS directly for lowest latency
- Firebase Realtime Database write cost at 1 Hz for summary metrics is negligible

This is optional for v1; the lab LAN NATS dashboard is sufficient for local use.

### 10.7 JetStream Storage Sizing

Estimate for a 2-hour maximal session with all sensors active:

| Stream | Rate | 2h volume |
|---|---|---|
| Trainer metrics (×2) | 1 Hz, ~100 bytes/msg | ~720 KB |
| HR metrics | 1 Hz, ~60 bytes/msg | ~430 KB |
| VO2 ventilatory + gas (per breath) | ~25/min, ~100 bytes/msg | ~300 KB |
| Environment | 0.2 Hz, ~80 bytes/msg | ~115 KB |
| Control commands | Sparse | ~10 KB |
| **Total per session** | | **~1.6 MB** |

A 256 GB SD card on a Pi 5 can hold ~150,000 sessions before the JetStream store fills,
assuming no purging. With a 7-day purge policy on completed sessions, storage is negligible.
Recommended JetStream config for the Pi: `max_file_store: 10GB`.

---

## 11. Extensibility — Adding New Sensor Categories

The hub is designed so each device type is an independent **driver** with a standard interface:

```dart
abstract class SensorDriver {
  Future<void> connect(String deviceId, DeviceConfig config);
  Future<void> disconnect(String deviceId);
  DeviceState getStatus(String deviceId);
  Stream<SensorSample> get dataStream;        // fires for every measurement
  Stream<DeviceState> get stateStream;        // fires on connection state changes
  Future<void> sendCommand(String deviceId, String command, Map<String, dynamic> params);
}
```

Adding a new device (e.g. Moxy SmO2 sensor) requires:
1. Implement `SensorDriver` for ANT+ muscle oxygen (device type 31) — or use the ANT+ Bridge
2. Add to device registry with `protocol: ant_muscle_oxygen`
3. Define `lab.smo2.{device_id}.metrics` subject and data schema (§5)
4. Optionally register new FIT developer fields (§9.3) if the data is not already mapped
5. No changes to existing drivers, NATS topology, or control layer

---

## 12. Decisions Log

### Resolved

| # | Decision | Choice | Section |
|---|---|---|---|
| D1 | Implementation language | **Dart** — shared models + NATS client across daemon and all clients | §2.1 |
| D2 | NATS server | **Pre-built `nats-server` binary** — we are clients, not server implementors | §2.1, §2.2 |
| D3 | Daemon UI | **Headless** — no UI in daemon; all UIs are separate NATS-client Flutter apps | §2.1, §2.4 |
| D4 | BLE library (Linux) | **`bluez` Dart package** — wraps BlueZ D-Bus; no Flutter required for headless daemon | §2.5, §2.8 |
| D5 | BLE library (Windows/macOS) | **`flutter_blue_plus`** — WinRT on Windows, CoreBluetooth on macOS | §2.6, §2.7 |
| D6 | ANT+ on desktop/Linux | **ANT+ Bridge sidecar** (Python `openant` → NATS) — no Dart ANT+ library for desktop | §2.6, §2.8 |
| D7 | Primary lab deployment | **Windows PC** (immediate, dev machine proven) + **Linux Pi 5** (fixed-lab target) | §2.7, §2.8 |
| D8 | Trainer control | **BLE FTMS only** — no ANT+ FE-C control; BLE gives metrics + control simultaneously | §4.3, §7 |
| D9 | FIT output | **NATS consumer FIT writer** — decoupled from sensor drivers | §9 |
| D10 | Client role | **NATS-only** — no client app contains BLE/ANT+/sensor parsing code | §1, §2.4 |
| D11 | Cloud persistence | **Firebase** — Firestore for session metadata/summaries, Firebase Storage for FIT files | §10 |
| D12 | Raw time-series in cloud | **FIT file only** — raw 1Hz data not written to Firestore; Firestore holds summaries/laps/lactate | §10.2 |
| D13 | Firebase SDK in daemon | **Firebase REST API** (plain HTTP via `dart:io`) — FlutterFire requires Flutter; incompatible with headless daemon | §10.4 |
| D14 | Offline resilience | **JetStream as offline buffer** — session stream retained until Firebase Sync acks upload; sessions never lost without internet | §10.4 |
| D15 | Session boundary in JetStream | **Per-session named stream** (`SESSION_{id}`) — clean replay boundary, deleted after cloud sync | §6.3 |
| D16 | ERG ramp / exercise protocol logic | **Clients own all exercise protocol logic.** Daemon is a stateless hardware bridge — it exposes `set_power`, `set_resistance`, `set_simulation` as raw primitives. Flutter (or any client) issues one `set_power` per ramp step on its own timer. Daemon has no ramp state, no timers, no knowledge of protocols. | §2.1, §6.4 |
| D17 | Simultaneous athletes / sessions | **One athlete, one session at a time.** The lab has two trainers but uses only one per session. No multi-athlete routing, no parallel sessions, no `athlete_id` namespacing in subjects required. Current subject hierarchy (`lab.{category}.{device_id}.*`) is sufficient. | §6.3, §6.4 |
| D18 | VO2 Master configuration at session start | **No `vo2_settings` in `session.start`.** Venturi size, mask size, and idle timeout are set via dedicated `set_venturi` / `set_mask` / `set_idle_timeout` commands before the session begins (part of the operator setup flow). `session.start` carries only athlete metadata (`athlete_id`, `weight_kg`, `ftp_w`, `protocol`). Consistent with D16 — daemon is a stateless bridge. | §6.4, §8.3 |
| D19 | Device connection model | **Auto-connect on startup from config file.** Daemon reads `config/devices.json` on startup and connects all listed devices automatically, before any client connects. The `scan` and `connect` commands exist for recovery and diagnostics only — not normal operation. Flutter opens to find devices already READY. | §6.4, §8.2 |
| D20 | VO2 Master device state representation | **Single `device_state` field; no separate `is_calibrating` flag.** `device_state` is one of `"idle"`, `"recording"`, `"calibrating_gas"`, `"calibrating_flow"`, `"zeroing_flow"` — directly mapping VO2 Master `GetState` responses. Guards on calibration commands use `device_state` value directly. `is_calibrated` (boolean) is a separate field covering gas calibration readiness. | §5.7, §7.0.3 |
| D21 | Heart rate strap | **Polar H10** — already in the lab. BLE HRS, UUID `0x180D`, characteristic `0x2A37`. Broadcasts RR intervals on every notification (1–2 values per packet depending on HR). `rr_intervals_ms` is a first-class field in `HrMetrics`, never a stub. ANT+ capability of H10 is not used (BLE preferred per D8 pattern). | §3, §5.3, §8.2 |
| D22 | VO2 Master count | **One unit** (`vo2_1`). A second unit (`vo2_2`) is not in scope. `config/devices.json` contains a single VO2 Master entry. | §3, §8.2 |
| D23 | FIT developer field UUID registration | **Fixed UUID, no Garmin registration.** FIT files stay entirely within the lab ecosystem and will never be uploaded to Garmin Connect or third-party platforms. The fixed UUID `b5f4e2a1-c3d7-4f8b-9e2c-1a6d5f7b3c9e` in §9.3 is sufficient. Developer field names are embedded in each FIT file via `FieldDescription` messages and are readable by any FIT-aware tool. | §9.3 |
| D24 | iOS client support | **iOS is a fully valid client platform.** Clients are NATS-only (D10) — an iOS Flutter app connects to `nats-server` over TCP, subscribes to `lab.*` data subjects, and publishes control commands. It never touches BLE or ANT+ directly. The daemon owns all hardware. ANT+/BLE platform considerations are irrelevant for clients. | §1, §2.4 |
| D25 | Remote live dashboard | **Deferred indefinitely.** No current use-case justifies the infrastructure complexity (Firebase Realtime Database bridge process) or ongoing cost. All dashboard clients connect to NATS directly on the lab LAN. Re-evaluate only if a concrete remote-viewing requirement emerges. §10.6 is retained in the spec as a design note but is not in scope for any implementation phase. | §10.6 |
| D26 | Local FIT file retention after upload | **Keep for 90 days after confirmed upload, then auto-delete.** Firebase Sync records the upload timestamp in a sidecar `.fit.meta` file. The daemon runs a daily cleanup pass and deletes `.fit` files where upload is confirmed and age exceeds 90 days. Files not yet uploaded are never deleted. At ~1.6 MB/session this is negligible storage. | §10.5 |
| D27 | Moxy SmO2 | **Out of scope.** No Moxy unit in the lab; no SmO2 use-case identified. ANT+ Muscle Oxygen profile (type 31) is not implemented in v1. The ANT+ Bridge sidecar architecture is retained for extensibility but need not be deployed on day 1 since all v1 sensors (KICKR, VO2 Master, Polar H10) are BLE. | §4.3, §13 |
| D28 | CORE body temperature sensor | **Deferred — no unit in lab.** The `temperature` subject namespace, `TempMetrics` schema, FIT developer fields 8–9, and `core_temp_driver.dart` stub are retained in the spec for when a CORE sensor is acquired. Model (Gen 1 ANT+-only vs Gen 2 BLE+ANT+) to be determined at procurement time. Driver can be added without changing any other part of the protocol. | §3, §4, §5.10 |

### Still Open

| # | Question | Impact |
|---|---|---|
| Q1 | **BLE USB dongle spec for Windows:** Which model for 5 simultaneous connections? | Hardware procurement |
| ~~Q2~~ | ~~Moxy SmO2 in v1 scope?~~ | Resolved → D27 (out of scope) |
| ~~Q3~~ | ~~Second athlete simultaneous sessions?~~ | Resolved → D17 |
| ~~Q4~~ | ~~CORE sensor model~~ | Resolved → D28 (deferred — no unit in lab) |
| ~~Q5~~ | ~~ERG ramp logic location~~ | Resolved → D16 |
| ~~Q6~~ | ~~VO2 Master count~~ | Resolved → D22 |
| ~~Q7~~ | ~~FIT UUID registration~~ | Resolved → D23 |
| ~~Q8~~ | ~~iOS in scope?~~ | Resolved → D24 |
| ~~Q9~~ | ~~Remote live dashboard (Firebase Realtime Database bridge)?~~ | Resolved → D25 (deferred) |
| ~~Q10~~ | ~~Local FIT file retention policy~~ | Resolved → D26 |

---

## 13. Out of Scope (this spec)

- Dashboard / display layer (separate spec)
- Firebase Realtime Database bridge for remote viewers (optional, see Q9)
- Athlete management / profile UI
- Analysis algorithms (VO2max, VT1, VT2 detection)
- Karoo extension compatibility layer
- ANT+ FE-C bidirectional trainer control (BLE FTMS covers this entirely)
- FIT file upload to third-party platforms (TrainingPeaks, Garmin Connect APIs) — user downloads from Firebase Storage and uploads manually
