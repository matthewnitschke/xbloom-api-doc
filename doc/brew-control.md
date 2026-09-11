# Brew Control

Starting a brew is a two-step remote sequence — commit then start — plus manual brewer commands for direct pour control. Both the remote sequence and the manual commands are written to `ffe1`.

* UUID: `0000ffe1-0000-1000-8000-00805f9b34fb`
* Methods: `WRITE`
* Data Format
  * Size: `Variable`
  * Type: `Custom binary frame`

## Remote Sequence

After a recipe is loaded (`armed`, `0x1F`), the brew is launched with two frames:

| Step  | Opcode | Seq  | Payload | State                  |
| ----- | ------ | ---- | ------- | ---------------------- |
| Commit| `0x42` | `0x1F` | `01`   | `armed` → `awaiting_confirm (0x1E)` |
| Start | `0x46` | `0x9E` | `01`   | `awaiting_confirm` → brewing (`0x10`/`0x3B`) |

- **Commit (`8002`, `0x1F42`)** — the frame the app sends when you tap "Brew". The machine shows its ~99 s add-beans countdown.
- **Start (`0x46`, `0x9E`)** — the "go". Physically dispenses near-boiling water.

Some firmware commits straight through awaiting-confirm to grinding/brewing on its own; only nudge with start (`0x46`) if the machine *stalls* in `awaiting_confirm`. Sending `0x46` into a running brew aborts it back to `armed`.

### Cancel

| Command | Hex        | Payload | Effect                                   |
| ------- | ---------- | ------- | ---------------------------------------- |
| Stop/cancel (`40519`) | `0x9E47` | `01` | Abort a committed or running brew; return toward idle. |

Legacy alias: `APP_RECIPE_STOP`.

> ⚠️ **Safety**: loading a recipe hands the decision to the machine. Commit/start dispense real near-boiling water. Only send them when the machine is ready (water, beans, cup in place) and you intend to brew.

### Verified Example Frames

```
Commit (8002):  58 01 01 42 1F 0C 00 00 00 01 7F CF
Start (0x46):   58 01 01 46 9E 0C 00 00 00 01 80 A1
Cancel (40519): 58 01 01 47 9E 0C 00 00 00 01 55 3E
```

## Manual Brewer Control

Direct, low-level pours — these bypass the loaded-recipe flow and just move water.

| Code | Hex      | Name         | Payload        |
| ---- | -------- | ------------ | -------------- |
| 4506 | `0x119A` | Start        | 5 × `u32 LE` (see below) |
| 4507 | `0x119B` | Stop         | —              |
| 8019 | `0x1F53` | Pause        | —              |
| 8021 | `0x1F55` | Restart      | —              |
| 8013 | `0x1F4D` | Quit         | —              |

`4506` (Start) payload is five little-endian 32-bit integers, each a **float32 bit pattern** except the last two:

```
[floatbits(flow_rate × 10), floatbits(volume × 10), floatbits(temp × 10), water_source, pattern]
```

| Param        | Encoding                            |
| ------------ | ----------------------------------- |
| flow_rate    | float32 bits of `flow_rate × 10`    |
| volume       | float32 bits of `volume × 10`       |
| temperature  | float32 bits of `temp_C × 10`       |
| water_source | integer (`0` = tank)                |
| pattern      | `0` center, `1` circular, `2` spiral |

### Temperature & Pattern

| Code | Hex      | Name             | Payload                    |
| ---- | -------- | ---------------- | -------------------------- |
| 4510 | `0x119E` | Set temperature  | `u32 LE` of `temp_C × 10`  |
| 8016 | `0x1F50` | Set pattern      | `u32 LE` pattern (`0/1/2`) |

### Start + Quit

| Code | Hex      | Name            | Payload |
| ---- | -------- | --------------- | ------- |
| 8017 | `0x1F51` | Start and quit  | —       |

Sends a brew-start and immediately exits the brew state — a single-shot pour.

## Classic Workflow Equivalent

The PyBloom app protocol drives the same machine with the older recipe flow:

```
set bypass 8102 → set cup 8104 → send recipe 8001/8004 → execute 8002
```

where `8002` (execute/commit `0x1F42`) is the same frame as the remote commit above, and `40519` (`0x9E47`) the cancel. See [recipe-setup.md](/doc/recipe-setup.md) for the setup commands.

## Machine Response Path

The machine reports the brew through these responses (see [notification-frame.md](/doc/notification-frame.md#response-codes)):

```
9000 IN_GRINDER → 9003 GRINDER_BEGIN → 40507 Grinder_Stop → 9004 OUT_GRINDER
→ 9001 IN_BREWER → 9005 BREWER_BEGIN → 40510 BLOOM → 40511 Brewer_Stop → 40512 ENJOY
```