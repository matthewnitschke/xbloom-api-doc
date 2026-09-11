# Command Frame

Every command sent to the machine is a single little-endian frame written to the `ffe1` command characteristic. Commands carry no units themselves; the payload values define the units (ounces/mL, °C, grams, mL/s).

* UUID: `0000ffe1-0000-1000-8000-00805f9b34fb`
* Methods: `WRITE`
* Data Format
  * Size: `Variable` (typically 12–100 Bytes)
  * Type: `Custom binary frame`

## Frame Layout

```
┌──────────┬────────┬──────────┬───────────┬──────┬───────────┬──────────┐
│ Header   │ Device │ TypeCode │ Command   │ Length │ Payload │ CRC16   │
│ 1 byte   │ 1 byte │ 1 byte   │ 2 bytes LE│ 4 bytes LE │ N bytes│2 bytes LE│
└──────────┴────────┴──────────┴───────────┴──────┴───────────┴──────────┘
```

| Offset | Field    | Size   | Description                                                    |
| ------ | -------- | ------ | -------------------------------------------------------------- |
| 0      | Header   | 1      | `0x58` for every outbound command                              |
| 1      | Device   | 1      | Device id, `0x01`                                             |
| 2      | TypeCode | 1      | `0x01` standard commands, `0x02` Studio/dial commands          |
| 3–4    | Command  | 2      | 16-bit command code, little-endian                             |
| 5–8    | Length   | 4      | Total frame length incl. header + CRC, little-endian           |
| 9      | Type     | 1      | Fixed payload marker `0x01`                                    |
| 10+    | Payload  | varies | Command-specific data (see per-command docs)                   |
| last 2 | CRC16    | 2      | CRC-16/KERMIT over bytes `0..end-3`, little-endian             |

The 16-bit `Command` value doubles as an **opcode + sequence** pair: the low byte is the opcode, the high byte is the sequence/section. For example `8001` = `0x1F41` is byte pair `41 1F` (opcode `0x41`, sequence `0x1F`).

## Payload Encodings

Command payloads are either a list of 32-bit little-endian integers or raw bytes, depending on the command:

- **Integer payload** — each value is a `u32 LE`. Used by `8102` (bypass), `8104` (cup), `8006` (grinder in), `4510` (temperature), `4506` (brewer start), `8016` (pattern). Floats that carry fractions (volume, temperature) are encoded as the **bit pattern of a float32** (`struct.pack("<I", struct.pack("<f", value)[0])`) or as **value × 10** kept as an integer.
- **Raw payload** — arbitrary bytes appended after the marker. Used by every recipe/load command (`0x41`, `0x44`, `0xA6`, `0xA8`…) and raw-pass commands (`4513`, `4512`).

## CRC-16/KERMIT

CRC-16/KERMIT, polynomial `0x8408` (reflected `0x1021`), init `0`, reflected input and output, **no final XOR**. Computed over the whole frame minus the trailing 2 CRC bytes, stored little-endian. Verifies as `0x2189` on `b"123456789"`.

```python
def crc16_kermit(data: bytes) -> int:
    crc = 0
    for byte in data:
        byte = int(f"{byte:08b}"[::-1], 2)
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return int(f"{crc:016b}"[::-1], 2)
```

## Example Data

The canonical manual-grinder packet (Grinder Start `3500`, no parameters):

```
Raw bytes (12): 58 01 01 AC 0D 0C 00 00 00 01 20 21

58                    Header
01                    Device id
01                    TypeCode (standard)
AC 0D                 Command 0x0DAC = 3500 (Grinder Start)
0C 00 00 00           Length = 12 (whole frame)
01                    Payload marker
20 21                 CRC16
```

The commit/execute packet (`8002`):

```
Raw bytes (12): 58 01 01 42 1F 0C 00 00 00 01 7F CF

58 01 01              Header + device + type
42 1F                 Command 0x1F42 = 8002 (Commit/Execute; opcode 0x42, seq 0x1F)
0C 00 00 00           Length = 12
01                    Payload marker (empty payload)
7F CF                 CRC16
```

The start packet (`0x46`):

```
Raw bytes (12): 58 01 01 46 9E 0C 00 00 00 01 80 A1

46 9E                 Command (opcode 0x46, seq 0x9E = brew phase)
0C 00 00 00           Length = 12
01                    Payload marker (empty payload)
80 A1                 CRC16
```