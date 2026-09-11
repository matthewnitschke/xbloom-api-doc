# Scale & Dripper

Manual commands that move the dripper (which doubles as the scale tray) between the grinder and brewer positions, and vibrate it to settle grounds. Commands are written to `ffe1`.

* UUID: `0000ffe1-0000-1000-8000-00805f9b34fb`
* Methods: `WRITE`
* Data Format
  * Size: `12 Bytes` (no payload)
  * Type: `Custom binary frame`

## Commands

| Code | Hex      | Name            | Action                                          |
| ---- | -------- | --------------- | ----------------------------------------------- |
| 2500 | `0x09C4` | `SG_LEFT`       | Move dripper fully left (to grinder)            |
| 2501 | `0x09C5` | `SG_RIGHT`      | Move dripper fully right (to brewer)            |
| 2502 | `0x09C6` | `SG_VIBRATE`    | Vibrate the scale (settle grounds)              |
| 2503 | `0x09C7` | `SG_LEFT_SINGLE`| Move dripper left one step                      |
| 2504 | `0x09C8` | `SG_RIGHT_SINGLE`| Move dripper right one step                    |
| 2505 | `0x09C9` | `SG_STOP`       | Stop dripper motion                             |

The registered count for "left" / "right" is a single motor step (or the full travel for `SG_LEFT`/`SG_RIGHT`).

> Practically, `2503`/`2504` (SG_LEFT_SINGLE / SG_RIGHT_SINGLE) are the reliable single-step moves; `2500`/`2501` are treated as continuous / ignored by some firmware. Both sets share the same empty payload.

## Example Data

```
Raw bytes (12): 58 01 01 C4 09 0C 00 00 00 01 XX XX

58 01 01              Header + device + type
C4 09                 Command 0x09C4 = 2500 (SG_LEFT)
0C 00 00 00           Length = 12 (whole frame; payload = 1 byte)
01                    Payload first byte (the command's single `0x01` payload byte)
XX XX                 CRC16 (CRC-16/KERMIT)
```

The single-step variants are the same frame with opcode `0x09C7`/`0x09C8`.