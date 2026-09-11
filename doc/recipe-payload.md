# Recipe Payload

The recipe payload encodes the pour program (per-pour volume, temperature, pattern, agitation, pause, RPM, flow rate) plus the grind setting and brew ratio. It is carried by the pours command (`0x41` with grinder ON, `0x44` no-grind) after the frame marker.

* UUID: `0000ffe1-0000-1000-8000-00805f9b34fb`
* Methods: `WRITE`
* Data Format
  * Size: `Variable`
  * Type: `Custom binary frame`

## Payload Layout (current, verified on `V12.0D.500`)

```
01 | LEN (u8 = body bytes) | <pour segments…> | grind (u8) | ratio (u8)
```

| Byte        | Field   | Description                                                    |
| ----------- | ------- | -------------------------------------------------------------- |
| 0           | Marker  | Constant `0x01`                                               |
| 1           | LEN     | Byte length of the body (all pour segments)                    |
| 2…          | Segments| One or more pour segments, see below                           |
| last - 2    | grind   | Grinder setting `1–80`, or `0xFE` = no-grind (skip grinder)    |
| last - 1    | ratio   | Brew ratio × 10 (e.g. 1:15 → `0x96`, 1:16 → `0xA0`)           |

A `grind` of `0` (recipe-level "no-grind" / pre-ground) is written on the wire as `0xFE` — an out-of-range byte the machine reads as "skip the grinder". Sending an actual `0` would grind at the finest setting.

## Pour Segment (8 bytes)

| Offset | Byte   | Meaning                                                  |
| ------ | ------ | -------------------------------------------------------- |
| 0      | `ml`     | Pour volume in mL                                        |
| 1      | `temp`   | Water temperature in °C                                  |
| 2      | `pat`    | Pattern code (see table)                                 |
| 3      | `agit`   | Agitation code (see table)                               |
| 4      | `negpause` | `(256 − pause_s) & 0xFF`                            |
| 5      | `0x00`   | Constant zero                                            |
| 6      | `rpm`    | Agitation rotation speed (0 for center)                  |
| 7      | `flow10` | Flow rate in mL/s × 10                                   |

**RPM is carried only on the first pour** — the machine zeroes it on later pours (verified byte-for-byte against the vendor app captures).

### Pattern Codes

| Pattern | Agitation | `pat` | `agit` |
| ------- | --------- | ----- | ------ |
| spiral  | true      | `0x02`| `0x02` |
| spiral  | false     | `0x02`| `0x00` |
| ring    | false     | `0x01`| `0x00` |
| center  | false     | `0x00`| `0x01` |

## Large Pours (> 127 mL)

A pour is split into **127-mL lead segments** followed by one remainder segment that carries the pause/RPM/flow:

- For each full 127-mL chunk: a 4-byte segment `[127, temp, pat, agit]` (no pause/rpm/flow).
- The remainder (`rest` mL): a full 8-byte segment `[rest, temp, pat, agit, negpause, 0x00, rpm, flow10]`.

A pour of exactly ≤ 127 mL is a single 8-byte segment.

## Ratio Byte

The trailing byte is the brew **ratio × 10** (water:coffee). The machine validates it against `Σ(pour mL) / dose` and **rejects a load whose ratio byte doesn't match** — so it must be derived from the recipe, not hard-coded.

```
ratio_byte = round(total_pour_ml / dose_g * 10) & 0xFF
```

Examples: 1:10 → `0x64`, 1:15 → `0x96`, 1:16 → `0xA0`.

## Example Data

A single 100 mL pour at 92 °C, spiral with agitation, 30 s pause, RPM 80, flow 3.0, dose 15 g (ratio 100/15 ≈ 6.9 → 1:6.9), grind 50:

```
Recipe payload: 01 08 64 5C 02 02 E2 00 50 1E 32 64
                01               marker
                08               body length = 8
                64               ml = 100
                5C               temp = 92
                02               pat = spiral
                02               agit = on
                E2               negpause = (256 − 30) & 0xFF = 0xE2
                00               constant
                50               rpm = 80
                1E               flow = 3.0 × 10
                32               grind = 50
                64               ratio = 100
```

> The ratio byte is validated by the machine: `round(Σpour_ml / dose × 10)`. Pick it to match the actual recipe (100 mL ÷ 15 g dose ≈ 1:6.9 → `0x45`; the `0x64` shown above is the wire value for a 1:10 brew). The `grind`, `ratio`, and CRC bytes should always be recomputed per recipe rather than copied from an example.

## Legacy Payload Format

PyBloom describes an older payload (from the app's classic `8001`/`8004` send, cross-validated against the XBRecipeWriter NFC card format):

```
LEN (u8 = body) | <4-byte sub-steps…> | <4-byte meta per pour…> | footer (2)
```

- Sub-step (4 bytes): `[volume, temperature, pattern, vibration]`, volume chunked at 127 mL max.
- Metadata (4 bytes): `[(-pause) & 0xFF, 0x00, rpm, flow*10]` — RPM only on the first pour.
- Footer (2 bytes): `[grind_size, total_water × 10]`.

Pattern values: `0` center, `1` circular, `2` spiral. Vibration: `0` none, `1` before, `2` after, `3` both.

```
Raw payload: 08 | 64 5C 02 00 | 00 00 50 1E | 32 64
              08        body length
              64 5C 02 00   100 mL, 92 °C, spiral, no vibration
              00 00 50 1E   pause 0, rpm 80, flow×10 = 30
              32 64         footer: grind 50, water 100×10
```

## Validation Ranges

| Field       | Range                          | Notes                               |
| ----------- | ------------------------------ | ----------------------------------- |
| `dose_g`    | 1–18 g (xbloom-ble) / 4–25 g (PyBloom) | xPod cards fixed to 15 g     |
| `grind`     | 1–80 (Studio), 0 = no-grind    | Wire `0xFE` = no-grind; lower = finer |
| `temp_c`    | 40–95 °C (1 °C steps); special RT/BP values | pour temp               |
| `stage_temps`| 40–130 °C                     | Pre-heat set-points, not pour temps  |
| `rpm`       | 0, or 60–120 (10 steps)        | 0 only valid for center pattern     |
| `flow_ml_s` | 3.0–3.5                        | 0.1 steps                           |
| `pause_s`   | 0–255                          | Wire = `256 − s`; practical cap ~99 s |
| `ml` (pour) | 1–4000                         | > 127 auto-split by protocol        |
| `pattern`   | spiral, ring, center           | Agitation only valid with spiral    |