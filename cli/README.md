# xbloom-cli

A macOS Swift CLI that loads a custom recipe into an xBloom Studio over Bluetooth LE. It connects to the machine, switches it to PRO mode, writes the recipe, and waits for the machine to arm — it does **not** start the brew.

## Requirements

- macOS 12 or later
- An xBloom Studio with Bluetooth enabled
- The official xBloom app closed (the machine accepts only one BLE link at a time)

## Build

```sh
swift build -c release
```

The binary is `.build/release/xbloom-cli`.

## Usage

```sh
xbloom-cli recipe.json          # load from a file
echo '{...}' | xbloom-cli       # or pipe JSON via stdin
```

The CLI prints a summary of the parsed recipe, connects, sends the load sequence, and exits `0` when the machine reports **armed** (state `0x1F`). It times out after 25 seconds and exits `1` if the machine never arms.

## Input Format

A single JSON object describing the brew.

### Example (manual grind)

```json
{
  "dose": 15,
  "grind": { "size": 50, "rpm": 80 },
  "pours": [
    { "ml": 100, "temp": 92, "pattern": "spiral", "agitation": true },
    { "ml": 140, "temp": 93, "pattern": "ring", "pause": 30 }
  ]
}
```

### Example (pre-ground / no grinder)

```json
{
  "pours": [{ "ml": 240, "temp": 93 }]
}
```

Omit `grind` entirely for pre-ground beans — the machine skips the grinder step.

### Fields

| Field   | Type            | Required    | Default | Description                                                  |
| ------- | --------------- | ----------- | ------- | ------------------------------------------------------------ |
| `dose`  | integer         | optional    | `15`    | Coffee dose in grams (1–25). Used to compute the brew ratio.  |
| `grind` | object          | optional    | —       | Grind setting. Omit for pre-ground beans.                     |
| `pours` | array of object | **required** | —   | One or more pour segments, in order.                          |

#### `grind`

| Field  | Type    | Required | Description                                            |
| ------ | ------- | -------- | ------------------------------------------------------ |
| `size` | integer | required | Grinder setting 1–80.                                  |
| `rpm`  | integer | required | Agitation speed: `0`, or 60–120 in steps of 10.         |

#### pour

| Field       | Type             | Required | Default      | Description                                    |
| ----------- | ---------------- | -------- | ------------ | ---------------------------------------------- |
| `ml`        | number           | **required** | —        | Pour volume in mL (1–4000). Pours over 127 mL are split automatically into multiple sub-segments. |
| `temp`      | number           | optional | `93`         | Water temperature in °C (40–95).                |
| `pattern`   | string           | optional | `"spiral"`   | One of `"spiral"`, `"ring"`, `"center"`.        |
| `agitation` | boolean          | optional | `false`      | Pour-site agitation. Not valid with `"center"`. |
| `pause`     | number           | optional | `0`          | Wait after the pour, in seconds (0–255).        |
| `flow`      | number           | optional | `3.0`        | Flow rate in mL/s (3.0–3.5).                    |

### Validation Errors

A malformed recipe aborts with exit code `1` before any BLE work. Notable rules:

- `dose` must be 1–25 g.
- `grind.size` must be 1–80; `grind.rpm` must be `0` or 60–120 in steps of 10.
- At least one pour is required.
- `center` pattern cannot have `agitation` enabled.

## What It Does

1. Parses and validates the recipe, then prints a summary.
2. Scans for the xBloom service and connects.
3. Opens a session frame (`0xA4`) and status handshake (`0x56`).
4. Forces the machine into PRO mode (the load/write commands only work in PRO mode — in AUTO mode the write is rejected with a state of `0x41`).
5. Writes the dose (`0xA6`), stage temperatures (`0xA8`), and recipe pours (`0x41` with grinder, `0x44` pre-ground).
6. Exits `0` on arming (state `0x1F`), `1` on timeout or error.

Stage temperatures (110 °C bloom / 90 °C per-pour) are fixed and not configurable.

Approve the brew on the device if you actually want to start it.

## Exit Codes

| Code | Meaning                                        |
| ---- | ---------------------------------------------- |
| `0`  | Recipe loaded; machine armed.                  |
| `1`  | Load error, BLE failure, or 25 s timeout.      |

## Protocol Reference

The command frames and payload layout are documented in [`doc/`](../doc/command-frame.md). The full load sequence is in [`doc/load-sequence.md`](../doc/load-sequence.md), and the recipe payload encoding in [`doc/recipe-payload.md`](../doc/recipe-payload.md).