# VO2 Master Analyzer — Complete BLE Integration Specification

**Sources:** `VmBleServiceDescription_4_3_0.pdf` (Sep 13, 2022) + official C# SDK (Nov 2020)  
**Device under test:** Model 1.6.2, Serial 5342, FW 14, HW 15, Battery 100%  
**BLE address:** `F9:1A:59:CC:BA:E7` (random, may change — scan by name prefix `VO2 Master`)  
**Spec version:** 1.0 — March 2026

---

## 1. Overview

The VO2 Master Analyzer is a breath-by-breath metabolic analyser. It measures respiratory and
gas exchange metrics in real time over BLE. All communication uses custom GATT characteristics.
Settings do **not** persist between power cycles — the host must re-apply all settings on every connection.

### Supported firmware versions

| Release | Model prefix | Syringe calibration |
|---|---|---|
| Dec 2019 | 1.3.x | No |
| Oct 2020 | 1.4.x | No |
| May 2021–Feb 2022 | 1.4.4–1.5.3 | Yes (V1.5+) |
| Aug 2022 | 1.6.x | Yes (stricter Rf criteria) |

This document focuses on **V1.6** (our device) but notes version differences throughout.

---

## 2. BLE Services

### 2.1 Device Information Service
**UUID:** `180A`

Poll this **before** subscribing to any data characteristic. The model number string determines
which parser to use.

| Characteristic | UUID | Format |
|---|---|---|
| Manufacturer Name | `2A29` | UTF-8 string |
| Model Number | `2A24` | UTF-8 `Major.Minor.Revision` e.g. `1.6.2` |
| Serial Number | `2A25` | UTF-8 string |
| Firmware Revision | `2A26` | UTF-8 string |
| Hardware Revision | `2A27` | UTF-8 string |

**Version detection logic:**
```
major = int(model.split('.')[0])
minor = int(model.split('.')[1])
# V1.6 → major=1, minor=6
```

### 2.2 Battery Service
**UUID:** `180F`

| Characteristic | UUID | Format |
|---|---|---|
| Battery Level | `2A19` | uint8, 0–100% |

- Initially reports 100%.
- Drops to 20 when low voltage threshold is reached.
- Device transmits a diagnostic error on COM OUT before shutting off when dead.

### 2.3 VO2 Master Custom Service
**UUID:** `00001523-1212-EFDE-1523-785FEABCD123`

All proprietary characteristics live under this service.

---

## 3. Custom Service Characteristics

All UUIDs follow the pattern `000015XX-1212-EFDE-1523-785FEABCD123`.

| Short UUID | Full UUID | Direction | Description |
|---|---|---|---|
| `0x1525` | `00001525-...` | Write (no response) | **COM IN** — commands to device |
| `0x1526` | `00001526-...` | Read + Notify | **COM OUT** — responses from device |
| `0x1527` | `00001527-...` | Read + Notify | **Ventilatory** measurement |
| `0x1528` | `00001528-...` | Read + Notify | **Gas Exchange** measurement |
| `0x1529` | `00001529-...` | Read + Notify | **Environment** measurement |
| `0x1531` | `00001531-...` | Read + Notify | **Gas Calibration** data |
| `0x1532` | `00001532-...` | Read + Notify | **Syringe Flow Calibration** result |

---

## 4. Command Protocol (COM IN / COM OUT)

### 4.1 Packet format

**V1.3:** 2 bytes — `[COMMAND, VALUE]`

**V1.4 / V1.5 / V1.6** (this device):
```
Byte 0: command_low   = command & 0xFF
Byte 1: command_high  = (command >> 8) & 0xFF
Byte 2: value_low     = value & 0xFF
Byte 3: value_high    = (value >> 8) & 0xFF
```
Both command and value are **little-endian uint16**.

**Decoding COM OUT:**
```python
command = data[0] | (data[1] << 8)
value   = data[2] | (data[3] << 8)
```

### 4.2 SET / GET semantics

- **GET command** on COM IN → device responds on COM OUT with same command + value.
- **SET command** on COM IN → device applies setting, then responds on COM OUT with the
  **corresponding GET** command + echoed value (e.g. `SetVenturiSize` → device responds with `GetVenturiSize` + value).

### 4.3 Command enumeration

Valid range for V1.6: commands **0–28**.

| Value | Name | Direction | Ver | Notes |
|---|---|---|---|---|
| 0 | `UnknownResponse` | — | all | Unused / parse fallback |
| 1 | `SetState` | OUT → device | all | See Device State table |
| 2 | `GetState` | both | all | Response encodes isCalibrated flag (see §5.1) |
| 3 | `SetVenturiSize` | OUT → device | all | See User Piece table |
| 4 | `GetVenturiSize` | both | all | |
| 5 | `GetCalibrationProgress` | both | all | 0–100 gas calibration % |
| 6 | `Error` | device → host | all | Value = error code (see §9) |
| 7 | `SetVolumeCorrectionMode` | OUT → device | 1.3 | Deprecated from V1.4 |
| 8 | `GetVolumeCorrectionMode` | both | 1.3 | Deprecated |
| 9 | `GetO2CellAge` | both | — | Never implemented |
| 10 | `ResetO2CellAge` | OUT → device | — | Never implemented |
| 11 | `SetIdleTimeoutMode` | OUT → device | all | 0=Enabled, 1=Disabled |
| 12 | `GetIdleTimeoutMode` | both | all | |
| 13 | `SetAutoRecalibMode` | OUT → device | — | Not used |
| 14 | `GetAutoRecalibMode` | both | — | Not used |
| 15 | `BreathStateChanged` | device → host | all | Unsolicited; see Breath State table |
| 16 | `RequestEnterDfuMode` | OUT → device | all | Firmware update mode |
| 17 | `RequestForceDiffpCalib` | OUT → device | — | Unused |
| 18 | `GetGasCalibFlags` | both | — | Unused |
| 19 | `GetGasCalibrationInfo` | both | all | Returns isCalibrated + progress |
| 20 | `SetMaskSize` | OUT → device | 1.4+ | See Mask Size table |
| 21 | `GetMaskSize` | both | 1.4+ | |
| 22 | `SetSyringeVolume` | OUT → device | 1.5+ | Volume × 1000 as uint16 |
| 23 | `GetSyringeVolume` | both | 1.5+ | Returns volume × 1000 |
| 24 | `SetSyringeBreathCount` | OUT → device | 1.5+ | 3–15, recommend ≥10 |
| 25 | `GetSyringeBreathCount` | both | 1.5+ | |
| 26 | `GetSyringeFlags` | both | 1.5+ | Bitfield; see Syringe Flags |
| 27 | `GetSubState` | both | all | See Sub-State table |
| 28 | `GetSyringeProgress` | both | 1.5+ | Encoded as `(total << 8) | current` |

---

## 5. Enumerations

### 5.1 Device State (command 1 / 2)

The COM OUT `GetState` response encodes a flag in value bit 4:
```python
IS_CALIBRATED_MASK = 0x10
is_calibrated = (value & IS_CALIBRATED_MASK) != 0
state         = value & ~IS_CALIBRATED_MASK   # strip flag before converting
```

| Value | Name | Description |
|---|---|---|
| 0 | `Idle` | Awaiting command. No data on measurement characteristics. |
| 1 | `CalibratingGas` | Calibrating O2 sensor to ambient air. Progress via command 5. Upon completion, data fires on `0x1531`. Device auto-transitions to `Recording` after. |
| 2 | `Recording` | **Active measurement.** Data fires on `0x1527`, `0x1528`, `0x1529` per breath. |
| 3 | `Unused` | — |
| 4 | `CalibrateFlowSensor` | Syringe flow calibration (V1.5+). Progress via command 28. Result fires on `0x1532`. |
| 5 | `ZeroFlowSensor` | Zero-offset calibration. Remove mask, hold still 10s. |

### 5.2 Device Sub-State (command 27)

| Value | Name | Description |
|---|---|---|
| 0 | `None` | No sub-state |
| 1 | `FlowDelay` | Waiting for minimum ventilation before calibrating (O2 calibration gate) |
| 2 | `Average` | Averaging ambient gas readings |

### 5.3 Breath State (command 15, unsolicited)

| Value | Name |
|---|---|
| 0 | `Inhale` |
| 1 | `None` |
| 2 | `Exhale` |

Ignore consecutive duplicates — device may send the same state twice.

### 5.4 User Piece (Venturi) Size (command 3 / 4)

| Value | Name | Ventilation range | Syringe Rf target (V1.6) |
|---|---|---|---|
| 0 | Unused | — Error, device selects default | — |
| 1 | `Medium` (default) | 15–180 L/min | 30 bpm ± 2.5 |
| 2 | `Large` | 25–250 L/min | 40 bpm ± 2.5 |
| 3 | Unused | — Error, device selects default | — |
| 4 | `RMR` / Resting | 3–50 L/min | 15 bpm ± 2.5 |

> **V1.6 critical:** During syringe calibration, the device **rejects breaths** that fall outside the Rf window for the selected user piece. Rejected breaths do not count toward the target breath count. This is why a metronome is required.

### 5.5 Mask Size (command 20 / 21)

| Value | Name |
|---|---|
| 0 | Petite |
| 1 | Extra Small |
| 2 | Small (default) |
| 3 | Medium |
| 4 | Large |

### 5.6 Idle Timeout Mode (command 11 / 12)

| Value | Name | Description |
|---|---|---|
| 0 | `Enabled` (default) | Device powers off after 15 min idle |
| 1 | `Disabled` | Device runs until battery depleted |

### 5.7 Syringe Venturi Flags (command 26) — bitfield

| Bit | Mask | Name |
|---|---|---|
| 0 | `0x01` | `RestingIsCalibrated` |
| 1 | `0x02` | `MediumIsCalibrated` |
| 2 | `0x04` | `LargeIsCalibrated` |

```python
resting_calibrated = bool(flags & 0x01)
medium_calibrated  = bool(flags & 0x02)
large_calibrated   = bool(flags & 0x04)
```

---

## 6. Measurement Characteristic Byte Layouts (V1.6)

All values in these characteristics are **unsigned 16-bit little-endian integers** unless noted.
To recover the real value: `real = raw_uint16 * multiplier`.

### 6.1 Ventilatory — `0x1527` (6 bytes)

Fires **per breath**, during `Recording` state.

| Bytes | Field | Multiplier | Unit | Valid range |
|---|---|---|---|---|
| 0–1 | Respiratory Frequency (Rf) | 0.01 | bpm | 0 < Rf < 100 |
| 2–3 | Tidal Volume (Tv) | 0.01 | L/breath (BTPS) | 0 < Tv < 10 |
| 4–5 | Ventilation (VE) | 0.01 | L/min (BTPS) | 0 < VE < 500 |

```python
rf = int.from_bytes(data[0:2], 'little') * 0.01
tv = int.from_bytes(data[2:4], 'little') * 0.01
ve = int.from_bytes(data[4:6], 'little') * 0.01
valid = (0 < rf < 100) and (0 < tv < 10) and (0 < ve < 500)
```

### 6.2 Gas Exchange — `0x1528` (8 bytes)

Fires **per breath**, in sync with Ventilatory. Shares the same timestamp.

| Bytes | Field | Multiplier | Unit | Valid range | Notes |
|---|---|---|---|---|---|
| 0–1 | FeO2 | 0.01 | % | 0 < FeO2 < 21 | Fraction of expired O2 |
| 2–3 | (reserved) | — | — | — | FeCO2 allocated but not exposed |
| 4–5 | VO2 | 1/6 ≈ 0.1667 | mL/min | 0 < VO2 < 10000 | See note |
| 6–7 | (reserved) | — | — | — | VCO2 allocated but not exposed |

> **VO2 multiplier note:** The raw value is divided by 6 (not multiplied by a simple factor).
> `vo2 = raw * (1.0 / 6.0)` — this is from the SDK, confirmed against V1.5 PDF multiplier of 6.

> **VO2/kg:** Not transmitted. Compute client-side: `vo2_per_kg = vo2 / weight_kg`

> **Ventilation-only row:** If `feo2 == 22.0 AND vo2 == 22.0`, the gas exchange values are
> placeholder — discard FeO2/VO2 for this row but use Rf/Tv/VE from Ventilatory.

```python
feo2 = int.from_bytes(data[0:2], 'little') * 0.01
vo2  = int.from_bytes(data[4:6], 'little') * (1.0 / 6.0)
valid = (0 < feo2 < 21) and (0 < vo2 < 10000)
is_ventilation_only = (round(feo2, 1) == 22.0 and round(vo2, 1) == 22.0)
```

### 6.3 Environment — `0x1529` (10 bytes)

Fires per breath, slightly slower cadence than Ventilatory and Gas Exchange.

| Bytes | Field | Multiplier | Unit | Valid range |
|---|---|---|---|---|
| 0–1 | Ambient Pressure | 0.1 | hPa | 0 < P < 1200 |
| 2–3 | Device Temperature | 0.01 | °C | -25 < T < 85 |
| 4–5 | O2 Sensor Humidity | 0.01 | %RH | 0 ≤ H ≤ 100 |
| 6–7 | (reserved) | — | — | AmbientO2 allocated, not exposed |
| 8–9 | (reserved) | — | — | Reserved |

```python
pressure    = int.from_bytes(data[0:2], 'little') * 0.1
temperature = int.from_bytes(data[2:4], 'little') * 0.01
humidity    = int.from_bytes(data[4:6], 'little') * 0.01
valid = (0 < pressure < 1200) and (-25 < temperature < 85) and (0 <= humidity <= 100)
```

### 6.4 Gas Calibration — `0x1531` (12 bytes)

Fires on completion of `CalibratingGas` state. Diagnostic / logging only.

| Bytes | Field | Multiplier | Unit |
|---|---|---|---|
| 0–1 | Raw ADC O2 reading | 1 (raw) | — |
| 2–3 | ADC O2 coefficient | 0.000002 | — |
| 4–5 | Pressure at calibration | 0.1 | hPa |
| 6–7 | Temperature at calibration | 0.01 | °C |
| 8–9 | O2 sensor thermistor temp | 0.01 | °C |
| 10–11 | Humidity at calibration | 0.01 | %RH |

```python
adc_value   = int.from_bytes(data[0:2], 'little')
adc_coef    = int.from_bytes(data[2:4], 'little') * 0.000002
pressure    = int.from_bytes(data[4:6], 'little') * 0.1
temperature = int.from_bytes(data[6:8], 'little') * 0.01
o2_therm    = int.from_bytes(data[8:10], 'little') * 0.01
humidity    = int.from_bytes(data[10:12], 'little') * 0.01
```

### 6.5 Syringe Flow Calibration — `0x1532` (14 bytes)

Fires once on successful completion of `CalibrateFlowSensor` state.

| Bytes | Field | Multiplier | Unit |
|---|---|---|---|
| 0–1 | Goal Volume | 0.001 | L |
| 2–3 | Mean Volume | 0.001 | L |
| 4–5 | Standard Deviation | 0.001 | L |
| 6–7 | Max Volume | 0.001 | L |
| 8–9 | Min Volume | 0.001 | L |
| 10–11 | Breath Count | 1 (raw) | # breaths |
| 12–13 | Venturi Size | 1 (enum) | See §5.4 |

```python
goal_volume = int.from_bytes(data[0:2],   'little') * 0.001
mean        = int.from_bytes(data[2:4],   'little') * 0.001
std_dev     = int.from_bytes(data[4:6],   'little') * 0.001
max_vol     = int.from_bytes(data[6:8],   'little') * 0.001
min_vol     = int.from_bytes(data[8:10],  'little') * 0.001
breath_count= int.from_bytes(data[10:12], 'little')
venturi     = int.from_bytes(data[12:14], 'little')  # enum value
valid = all(0 <= v <= 25 for v in [goal_volume, mean, std_dev, max_vol, min_vol]) \
        and 0 <= breath_count <= 25
```

**Encoding syringe volume for transmission:**
```python
def encode_syringe_volume(litres: float) -> int:
    return round(litres / 0.001)  # e.g. 3.0L → 3000
```

---

## 7. Connection Handshake

The device **does not stream data** until the host completes the initial handshake.

**Trigger:** When the host successfully subscribes to (enables notifications on) `COM OUT (0x1526)`,
the SDK immediately sends the initial connection commands.

### 7.1 Mandatory sequence on every connection

Send these commands in order via COM IN (`0x1525`):

```
1.  SetVenturiSize(venturi_size)         # must match the user's physical piece
2.  SetMaskSize(mask_size)               # mask being worn
3.  SetIdleTimeoutMode(timeout_mode)     # 0=auto-off, 1=run until dead
4.  SetSyringeBreathCount(breath_count)  # 3–15, recommend 10
5.  SetSyringeVolume(encode_volume(goal_litres))  # e.g. 3000 for 3L

6.  GetState                             # query current state
7.  GetSubState                          # query sub-state
8.  GetGasCalibrationInfo               # retrieve calibration status
9.  GetSyringeProgress                  # retrieve flow calibration progress
10. GetSyringeFlags                     # which venturi sizes are calibrated
```

**Recommended defaults (matching official app):**
- VenturiSize: `Medium` (1)
- MaskSize: `Small` (2)
- IdleTimeoutMode: `Disabled` (1) — prevents premature shutdown during a session
- SyringeBreathCount: `10`
- SyringeVolume: `3.0L` → `3000`

---

## 8. Operational Flows

### 8.1 Normal recording session

```
host → Connect to device
host → Read Device Information (model, serial, firmware)
host → Subscribe to: COM OUT, Ventilatory, GasExchange, Environment
host → Send handshake sequence (§7.1)

device → COM OUT: GetState(Recording=2, isCalibrated=true)   # if already calibrated
  → Data starts flowing on 0x1527, 0x1528, 0x1529 per breath

# If not calibrated, device may be in CalibratingGas first:
device → COM OUT: GetState(CalibratingGas=1)
device → COM OUT: GetCalibrationProgress(0..100) periodically
device → transitions automatically to Recording when done
device → COM OUT: GetState(Recording=2, isCalibrated=true)
```

### 8.2 Manual gas (O2) calibration

```
host → SetState(CalibratingGas=1)         # command 1, value 1
host → Poll GetCalibrationProgress(5)     # or subscribe and wait
# User breathes normally with mask off (ambient air)
device → COM OUT: GetCalibrationProgress(N) periodically
device → fires Gas Calibration notification on 0x1531 on completion
device → auto-transitions: GetState(Recording=2)
```

### 8.3 Flow (syringe) calibration — full sequence

```
host → SetVenturiSize(1)                  # Medium, must match physical piece
host → SetSyringeVolume(3000)             # 3L syringe
host → SetSyringeBreathCount(10)
host → Subscribe to: 0x1532 (Flow Calibration result)
host → SetState(CalibrateFlowSensor=4)   # arms calibration

# HOST starts metronome at target cadence (see §8.4):

device → COM OUT: BreathStateChanged(Inhale=0)   # push detected
device → COM OUT: BreathStateChanged(Exhale=2)   # pull detected
device → COM OUT: GetSyringeProgress(value)
  # value encoding: current = value & 0xFF, total = value >> 8
  # e.g. value=0x050A → current=5, total=10 → "5 of 10"

# If breath rejected (Rf out of range): BreathStateChanged fires but
# progress does NOT increment → show "breath not counted" feedback

# On completion (10 valid breaths):
device → notification on 0x1532 → VmSyringeCalibrationMeasure
device → auto-transitions to Idle or Recording
```

### 8.4 Metronome cadence for flow calibration

| User Piece | Target Rf | Tolerance | Cadence | Stroke duration |
|---|---|---|---|---|
| Medium | 30 bpm | ±2.5 | 1 beat/second | 1.0s push, 1.0s pull |
| Large | 40 bpm | ±2.5 | ~0.75 beats/s | 0.75s push, 0.75s pull |
| RMR (Resting) | 15 bpm | ±2.5 | 0.5 beats/s | 2.0s push, 2.0s pull |

> **UX note:** The device silently rejects out-of-range breaths. Show live Rf feedback so  
> the user can adjust pace. Use `BreathStateChanged` timing to compute actual Rf:  
> `actual_rf = 60.0 / (time_between_same_state_events)`

### 8.5 Zero flow sensor

```
host → Instruct user to remove mask, hold breath, keep device still
host → SetState(ZeroFlowSensor=5)
# Device needs ~10 seconds of stillness
# Error code fires if too much vibration/noise detected
device → auto-transitions back to previous state
```

### 8.6 Abort any calibration

```
host → SetState(Idle=0)
```

---

## 9. Error Codes

Received unsolicited on COM OUT as `Error(value=error_code)`.

### Fatal errors (code < 50) — device shuts down

| Code | Description |
|---|---|
| 1 | Initialization error |
| 2 | Too hot — shutting off |
| 3 | Too cold — shutting off |
| 4 | Idle timeout — shutting off |
| 5–7 | Battery depleted — shutting off |
| 8 | Failed to initialize environmental sensor |
| 9 | Failed to initialize oxygen sensor |
| 10 | Failed to initialize flow sensor |
| 11 | Failed to initialize sensor communication |
| 12–13 | Flash memory error |
| 14 | CO2 sensor disconnected |
| 15 | Self-test failed |
| 16–17 | O2 sensor thermistor disconnected |

### Warnings (code 50–119) — show to user

| Code | Description |
|---|---|
| 54 | Analyzer is very hot |
| 55 | Analyzer is very cold |
| 57 | Oxygen sensor too humid |
| 58 | Oxygen sensor was too humid and has now dried |
| 59 | Remove analyzer / hold breath for ≥10s to complete flow zeroing |
| 61 | Low battery |
| 71 | Humidity approaching dangerous level at gas sensors |
| 72 | Pump disabled for a long time — possible issue |

### Diagnostics (code ≥ 120) — log only, do not show user

| Code | Description |
|---|---|
| 120 | Calibration: waiting for user to start breathing |
| 121 | Breath rejected: too jittery |
| 122 | Breath rejected: segment too short |
| 123 | Breath rejected: breath too short |
| 124 | Breath rejected: breath too small |
| 125 | Breath rejected: Rf out of range |
| 126 | Breath rejected: Tv out of range |
| 127 | Breath rejected: VE out of range |
| 128 | Breath rejected: FeO2 out of range |
| 129 | Breath rejected: VO2 out of range |
| 130 | Analyzer initialized |
| 132 | O2 sensor calibration waveform is volatile |
| 149 | User turned off device with power button |
| 160 | Breath rejected: FeCO2 out of range |
| 161 | Breath rejected: VCO2 out of range |
| 170 | Breath rejected: RER out of range |
| 196 | Breath rejected: Rf out of range (V1.6 syringe) |
| 197 | Breath rejected: Tv out of range (V1.6 syringe) |

---

## 10. Derived Metrics (compute client-side)

These are calculated by the official app but not transmitted by the device:

| Metric | Formula | Notes |
|---|---|---|
| VO2/kg | `vo2 / weight_kg` | Requires user body weight input |
| VE/VO2 | `ve / vo2 * 1000` | mL unit alignment |
| EqO2 | SDK calculates from Ve, VO2, Pressure | Ventilatory equivalent |

---

## 11. Data Timing & Architecture

- **Ventilatory (0x1527)** fires first, once per breath exhalation
- **Gas Exchange (0x1528)** fires immediately after, same breath — shares Ventilatory timestamp
- **Environment (0x1529)** fires at slower cadence (not every breath, typically every few breaths)
- **COM OUT (0x1526)** fires asynchronously for commands/events

**Recommended architecture:**
```
Subscribe to all characteristics.
On Ventilatory notification → record timestamp, store Rf/Tv/VE, wait for GasExchange.
On GasExchange notification → attach to current Ventilatory, emit complete breath record.
On Environment notification → update ambient context; apply to next breath record.
On COM OUT notification → dispatch to command handler (state machine events).
```

---

## 12. Known Limitations

- **CO2 not exposed:** FeCO2 and VCO2 bytes are present in the packet but zeroed / reserved. No CO2 metrics available via BLE.
- **Settings not persisted:** All settings reset on power cycle. Must re-send full handshake every connection.
- **No streaming without mask:** Device only fires measurement notifications when active gas flow is detected. Idle device produces no measurement data.
- **Syringe calibration per-piece:** Each venturi size must be calibrated separately. Calibration is lost on power cycle.
- **V1.6 stricter Rf:** Syringe calibration is significantly harder to pass in V1.6 due to the tight Rf windows (±2.5 bpm). A precisely timed metronome is mandatory.

---

## 13. Quick Reference — Characteristic Summary

| What | UUID | Bytes | When fires |
|---|---|---|---|
| Write commands | `0x1525` | 4 (V1.4+) | Host → device |
| Read responses/events | `0x1526` | 4 (V1.4+) | Device → host async |
| Breathing metrics | `0x1527` | 6 | Per breath, Recording state |
| O2 / VO2 metrics | `0x1528` | 8 | Per breath, Recording state |
| Environment | `0x1529` | 10 | Every few breaths |
| Gas calibration data | `0x1531` | 12 | On gas calibration complete |
| Flow calibration result | `0x1532` | 14 | On syringe calibration complete |

---

## 14. Implementation Checklist

- [ ] Read Device Information before subscribing to data
- [ ] Confirm model ≥ 1.6 before using syringe calibration commands (22–28)
- [ ] Subscribe to COM OUT **first** — this triggers the handshake
- [ ] Send all 10 handshake commands (§7.1) on every connection
- [ ] Set `IdleTimeoutMode=Disabled` during active sessions
- [ ] Handle `GetState` response: strip bit 4 (`0x10`) to get state, check `isCalibrated`
- [ ] Handle `GetSyringeProgress`: `current = value & 0xFF`, `total = value >> 8`
- [ ] Detect ventilation-only rows in Gas Exchange: `feo2 == 22.0 AND vo2 == 22.0`
- [ ] Ignore duplicate `BreathStateChanged` events (same state twice in a row)
- [ ] Match metronome cadence to venturi size (Medium=1Hz, Large=0.75Hz, Resting=0.5Hz)
- [ ] Compute VO2/kg client-side with user's body weight
- [ ] Show breath-reject feedback: BreathStateChanged fired but SyringeProgress did not increment
- [ ] Abort calibration: `SetState(Idle=0)`
