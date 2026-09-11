# Easy-Mode Dial Presets

The machine's on-device dial has three Easy-Mode preset slots (A, B, C) that can be programmed over BLE so recipes can be brewed hands-free from the machine — no app, no recipe cards. This is a **batch-of-three, no-commit** protocol: writing slots never starts a brew.

* UUID: `0000ffe1-0000-1000-8000-00805f9b34fb`
* Methods: `WRITE`
* Data Format
  * Size: `Variable`
  * Type: `Custom binary frame`

## Save Slot (`11510` = `0x2CF6`)

Frame shape (note header TypeCode `0x02` and 4-byte LEN):

```
58 01 02 | F6 2C | LEN (u32 LE) | 01 | slot | flags | <pours blob> | CRC16 (u16 LE)
```

| Byte   | Field  | Description                                                  |
| ------ | ------ | ------------------------------------------------------------ |
| 0–2    | Header | `58 01 02` (type code `0x02` = Studio/dial)                 |
| 3–4    | CMD    | `0x2CF6` = 11510                                             |
| 5–8    | LEN    | Total frame length incl. header + CRC                        |
| 9      | Marker | `0x01`                                                       |
| 10     | slot   | `0` = A, `1` = B, `2` = C                                    |
| 11     | flags  | `0x12` scale enabled, `0x02` scale disabled (bit `0x10` = scale flag) |
| 12+    | blob   | The same pours + grind + ratio body as the `0x41` recipe frame (minus its leading `0x01`) |

### Batch-of-Three Semantics

The machine only *stores* the presets after receiving **all three** slot frames (A, B, C) back-to-back; it then saves the set **atomically**. There is no commit frame — writing a single slot (or adding a trailing commit) leaves the machine hung at state `0x43` (saving) and shows **RETRY**.

## Set Mode (`11511` = `0x2CF7`)

Frame shape:

```
58 01 02 | F7 2C | LEN (u32 LE) | 01 | <4 bytes> | CRC16 (u16 LE)
```

| Mode payload    | Effect                                  |
| --------------- | --------------------------------------- |
| `00 00 00 00`   | **PRO** mode → state `0x01` (idle); slot writes accepted |
| `91 32 78 56`   | **AUTO** mode → the A/B/C dial selector (state `0x41`)    |

Slot writes are **only accepted in PRO mode**. In AUTO mode the machine sits at `0x41` and rejects them (RETRY). So the write sequence forces PRO first, then returns to AUTO at the end so the freshly-written presets are pickable on the dial.

> PyBloom's `11511` (Easy mode toggle) sends the type-code `0x02` headers with raw payload `"01"` (easy) / `"02"` (pro) in addition to the `0x2CF7` frame above.

## Write Sequence

```
1. A4 session start  → wait for idle (state 0x01)
2. Set PRO mode (0x2CF7 → 00 00 00 00)
3. Write slot A, slot B, slot C  (0x2CF6, back-to-back; each acked)
4. Machine stores atomically: notify 0xF8 → state 0x43 (saving)
   → 0x25 (saved) → 0x01 (idle)
5. Set AUTO mode (0x2CF7 → 91 32 78 56) so presets are ready on the dial
```

## Example Data

A slot-A write (pours blob omitted for brevity):

```
Raw bytes: 58 01 02 F6 2C 1C 00 00 00 01 00 12 <blob…> XX XX

58 01 02              Header (Studio TypeCode 0x02)
F6 2C                 Command 0x2CF6 = 11510 (Save slot)
1C 00 00 00           Length = 28 incl. header + CRC
01                    Marker
00                    slot A
12                    flags: scale enabled
<blob…>               pours + grind + ratio body
XX XX                 CRC16 (CRC-16/KERMIT)
```

The machine ACKs each slot write with a `58 02 07 F6 2C … C2 D2 04` notification, then reports the atomic save via the state path `0x43 → 0x25 → 0x01`.