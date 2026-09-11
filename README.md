# XBloom Studio Bluetooth API

This repository contains reverse-engineered documentation for the bluetooth API of the [XBloom Studio](https://xbloom.com) pour-over coffee machine.

The XBloom Studio speaks a custom binary protocol over BLE rather than exposing one GATT characteristic per value. All interaction happens over a single command characteristic: the host writes command *frames* to `ffe1` and the machine pushes status/telemetry *frames* to `ffe2`.

The information here was reconstructed from two independent clean-room reverse-engineering efforts:

- [PyBloom](https://github.com/fhenwood/PyBloom) — full command/response table, recipe payload format, classic brew workflow
- [xbloom-ble](https://github.com/Janczykkkko/xbloom-ble) — byte-verified frame format, load/brew sequence, machine states and live scale telemetry (verified on firmware `V12.0D.500`)

The two projects are wire-compatible: PyBloom's command codes `8001`/`8002`/`40519` are the 16-bit values `0x1F41`/`0x1F42`/`0x9E47`, which decompose into the opcode + sequence bytes that xbloom-ble writes directly. Commands, encodings, and payloads are identical on the wire.

> ⚠️ This is unofficial, reverse-engineered documentation. It has been tested against specific firmware versions and may break (or differ) on others. Use at your own risk.

## Service

Service UUID: `0000e0ff-3c17-d293-8e48-14fe2e4da212`

The name of the device is prefixed `XBLOOM`, and the advertisement exposes the service UUID, either of which can be used to find the peripheral during a BLE scan.

There is no pairing or PIN. The connection flow is: scan → connect → subscribe to notifications on `ffe2` → write command frames to `ffe1`. The command characteristic accepts only a **Write Command** (ATT write-without-response, `0x52`); ACKs and telemetry come back as `ffe2` notifications.

> ⚠️ The machine allows a **single** BLE link. The official phone app holds it — close the app (and ideally turn the phone's Bluetooth off) before connecting from a script.

### Characteristics

| Characteristic | Description                                                   | Details                                |
| -------------- | ------------------------------------------------------------- | -------------------------------------- |
| Command        | Write command frames to the machine (`ffe1`)                  | [link](/doc/command-frame.md)          |
| Status         | Status frames, ACKs, machine states and live weights (`ffe2`) | [link](/doc/notification-frame.md)     |
| Aux            | Auxiliary notify characteristic (`ffe3`)                      | [link](/doc/notification-frame.md#aux-characteristic) |

## Command Reference

Every command is written to `ffe1` as a single frame:

```
58 01 01 | CMD (u16 LE) | LEN (u32 LE) | 01 | payload | CRC16 (u16 LE)
```

- `CMD` is the 16-bit command code (little-endian). It can be read as two bytes: **opcode** (low byte) and **sequence/section** (high byte) — e.g. `8001` = `0x1F41` = opcode `0x41`, sequence `0x1F`.
- `LEN` is the total frame length *including* the 12-byte header and 2-byte CRC.
- `CRC16` is CRC-16/KERMIT (polynomial `0x8408`, init `0`, no final XOR) over the whole frame except the trailing 2 CRC bytes.

The full format, payload encodings, and verified example frames are in [doc/command-frame.md](/doc/command-frame.md).

### Session & Recipe Loading

| Code       | Hex        | Name                          | Description                                              |
| ---------- | ---------- | ----------------------------- | -------------------------------------------------------- |
| —          | `0xA4`     | Session start                 | Opens a session; machine shows "connected"               |
| —          | `0x56`     | Status handshake              | Ask the machine to settle after connect                  |
| —          | `0xA6`     | Set dose                      | Bean dose in grams                                       |
| —          | `0xA8`     | Set stage temperatures        | Pre-heat set-points (default 110 °C / 90 °C)             |
| —          | `0x41`     | Pours + grind                 | Recipe pours with the grinder ON                         |
| —          | `0x44`     | Pours (no grind)              | Recipe pours, grinder OFF                                |

The ordered load workflow is documented in [doc/load-sequence.md](/doc/load-sequence.md).

### Brewing

| Code | Hex        | Name                  | Description                                       |
| ---- | ---------- | --------------------- | ------------------------------------------------- |
| 8002 | `0x1F42`   | Commit (execute)      | Armed → awaiting-confirm (~99 s countdown)        |
| —    | `0x46`     | Start                 | The "go" — begins brewing                         |
| 40519| `0x9E47`   | Stop / cancel (recipe)| Abort a committed or running brew                 |
| 8017 | `0x1F51`   | Start + quit          | Start a brew and immediately exit                 |

See [doc/brew-control.md](/doc/brew-control.md).

### Recipe Setup (classic workflow)

| Code | Hex      | Name               | Description                                        |
| ---- | -------- | ------------------ | -------------------------------------------------- |
| 8102 | `0x1FA6` | Set bypass         | Bypass water params **and bean dose** (needed for grinding) |
| 8104 | `0x1FA8` | Set cup            | Cup weight bounds (max, min)                       |
| 4510 | `0x119E` | Set temperature    | Brewer water temperature (°C × 10)                 |
| 8016 | `0x1F50` | Set pattern        | Pour pattern (0 center, 1 circular, 2 spiral)      |

See [doc/recipe-setup.md](/doc/recipe-setup.md).

### Brewer (manual control)

| Code | Hex      | Name         | Description             |
| ---- | -------- | ------------ | ----------------------- |
| 4506 | `0x119A` | Start        | Pour water manually     |
| 4507 | `0x119B` | Stop         | Stop pouring            |
| 8019 | `0x1F53` | Pause        | Pause brewing           |
| 8021 | `0x1F55` | Restart      | Resume brewing          |
| 8013 | `0x1F4D` | Quit         | Exit brewer mode        |

### Grinder (manual control)

| Code | Hex      | Name    | Description                             |
| ---- | -------- | ------- | --------------------------------------- |
| 8006 | `0x1F46` | In      | Move dripper to grinder; set size/speed |
| 3500 | `0x0DAC` | Start   | Start grinding (no params)              |
| 3505 | `0x0DB1` | Stop    | Stop grinding                           |
| 8018 | `0x1F52` | Pause   | Pause grinding                          |
| 8020 | `0x1F54` | Restart | Resume grinding                         |
| 8012 | `0x1F4C` | Quit    | Exit grinder mode                       |

### Scale / Dripper

| Code | Hex      | Name        | Description                    |
| ---- | -------- | ----------- | ------------------------------ |
| 2500 | `0x09C4` | SG_LEFT     | Move dripper fully left        |
| 2501 | `0x09C5` | SG_RIGHT    | Move dripper fully right       |
| 2502 | `0x09C6` | SG_VIBRATE  | Vibrate scale (settle grounds) |
| 2503 | `0x09C7` | SG_LEFT_SINGLE | Move dripper left one step  |
| 2504 | `0x09C8` | SG_RIGHT_SINGLE| Move dripper right one step |
| 2505 | `0x09C9` | SG_STOP     | Stop dripper motion            |

See [doc/dripper-scale.md](/doc/dripper-scale.md).

### Easy-Mode / Dial Presets

| Code  | Hex      | Name         | Description                                      |
| ----- | -------- | ------------ | ------------------------------------------------ |
| 11510 | `0x2CF6` | Save slot    | Write an Easy-Mode preset (A/B/C), batch of three |
| 11511 | `0x2CF7` | Set mode     | Switch PRO / AUTO dial modes                      |
| 40516 | `0x9E44` | Confirm next | Advance a recipe step (Easy mode)                 |

See [doc/easy-mode-slots.md](/doc/easy-mode-slots.md).

### Tea (legacy)

| Code | Hex      | Name              | Description                    |
| ---- | -------- | ----------------- | ------------------------------ |
| 4513 | `0x11A1` | APP_TEA_RECIP_CODE | Send a tea recipe            |
| 4512 | `0x11A0` | APP_TEA_RECIP_MAKE | Execute a tea recipe         |

The last two are the older "tea protocol" variants of send/execute used by the app SDK.

### Recipes

The recipe payload (how pours, temperatures, pause, RPM, flow rate, grind size, and ratio are encoded) is documented in [doc/recipe-payload.md](/doc/recipe-payload.md).

## Notifications & Status

The machine pushes frames to `ffe2` in a distinct shape:

```
58 02 07 | TYPE (u8) | SUB (u8) | LEN (u32 LE) | C1 | payload | CRC16 (u16 LE)
```

- `TYPE` distinguishes command ACKs, status frames (`0x57`), live scale streams (`0x15` / `0x4B`) and the machine-info dump (`0x49`).
- Status frames carry a machine *state* byte — see [doc/machine-states.md](/doc/machine-states.md).
- Live weights stream ~10×/s — see [doc/scale-telemetry.md](/doc/scale-telemetry.md).
- The info dump decodes into serial/model/firmware — see [doc/machine-info.md](/doc/machine-info.md).
- The response/status codes used by the classic workflow are listed in [doc/notification-frame.md](/doc/notification-frame.md#response-codes).

## Unknowns & Caveats

There are several areas the reverse-engineering could not fully pin down. PRs are welcome.

- **Live weight on `ffe3`** — `ffe2` carries the two brew-record weights; the *raw* aux stream on `ffe3` was tapped but not decoded. It may carry the same scale data in another form.
- **Brew-progress frames** — `TYPE 0x39` etc. carry live brew progress that has not been decoded.
- **State `0x24` vs `0x41`** — different firmware reports "coffee ready" (`0x24`, the beep) vs "complete" (`0x41`). Both mean the brew is over.
- **CRC variants** — the working implementations in both projects use CRC-16/KERMIT (init `0`, no final XOR). PyBloom's *markdown docs* show an older `0xFFFF` + final-XOR variant that does **not** match its own code.
- **Recipe payload generations** — PyBloom documents the older `LEN + 4-byte sub-steps + 2-byte footer [grind, water×10]` payload; xbloom-ble verified the newer `01 + LEN + 8-byte segments + grind + ratio` payload on `V12.0D.500`. Both are documented in `doc/recipe-payload.md`.
- **Firmware tested** — xbloom-ble was verified on `V12.0D.500`. Other firmware/hardware revisions may behave differently.

## Example Apps

The example apps use CoreBluetooth and speak the protocol directly (no third-party library).

Read the machine info (serial, model, firmware, water), then exit:
```
swift ./example/info.swift
```

Report live scale weights (Scale = classic 20501 response, Coffee = 0x15 stream, Water = 0x4B stream):
```
swift ./example/scale.swift
```
