# Grinder Control

Manual grinder commands for direct grind control (outside a recipe). These write to `ffe1` and the machine reports back with grinder responses on `ffe2`.

* UUID: `0000ffe1-0000-1000-8000-00805f9b34fb`
* Methods: `WRITE`
* Data Format
  * Size: `Variable`
  * Type: `Custom binary frame`

## Commands

| Code | Hex      | Name    | Payload                    |
| ---- | -------- | ------- | -------------------------- |
| 8006 | `0x1F46` | In      | 2 × `u32 LE`: `[size, speed]` |
| 3500 | `0x0DAC` | Start   | —                          |
| 3505 | `0x0DB1` | Stop    | —                          |
| 8018 | `0x1F52` | Pause   | —                          |
| 8020 | `0x1F54` | Restart | —                          |
| 8012 | `0x1F4C` | Quit    | —                          |

## Usage

**In (`8006`)** moves the dripper to the grinder position and stashes the grind size and speed on the machine. **Start (`3500`)** begins grinding — it takes **no parameters**; the size/speed set by `In` are used. Recommended: send `8006`, wait ~2 s for the burrs to move, then send `3500`.

```
8006 → wait 2 s → 3500
```

Stop (`3505`) and quit (`8012`) end grinding; pause/restart (`8018`/`8020`) suspend and resume.

## Parameter Ranges

- **Grind size** — Studio: `1–80` (original: `1–30`; some recipes up to 150). Lower = finer.
- **Speed (RPM)** — `{60, 70, 80, 90, 100, 110, 120}`. `0` = skip grinding entirely.
- Grind position steps are ~18.75 µm (Studio).

## Example Data

The canonical Grinder Start packet (size/speed previously set via `8006`):

```
Raw bytes (12): 58 01 01 AC 0D 0C 00 00 00 01 20 21

58 01 01              Header + device + type
AC 0D                 Command 0x0DAC = 3500
0C 00 00 00           Length = 12 (payload = 1 byte)
01                    Payload first byte (the command's single `0x01` payload byte)
20 21                 CRC16
```

Grinder In with size 50, speed 100:

```
8006 frame: 58 01 01 46 1F 18 00 00 00 01 32 00 00 00 64 00 00 00 XX XX
                         46 1F                 Command 0x1F46 = 8006
                         32 00 00 00           size = 50
                         64 00 00 00           speed = 100
```

The machine reports `9003 RD_GRINDER_BEGIN` when grinding starts and `40507 RD_Grinder_Stop` when it completes.