# Recipe Load Sequence

Loading a recipe onto the machine is a fixed five-frame conversation on `ffe1`, with ACKs arriving on `ffe2`. It **arms** the machine (state `0x1F`) — it does not start the brew. Starting is a separate, explicit step (see [brew-control.md](/doc/brew-control.md)).

* UUID: `0000ffe1-0000-1000-8000-00805f9b34fb`
* Methods: `WRITE`
* Data Format
  * Size: `5 frames`
  * Type: `Custom binary frame`

## The Frames

All frames use sequence `0x1F` unless noted.

### 1. `0xA4` — Session start

Payload (constant):

```
01 B9 00 00 00 01 00 00 00
```

Opens a session; the machine lights its paired/connected icon. Re-sending it is harmless.

### 2. `0x56` — Status handshake

Payload: `01`

Sent right after `A4` so the machine leaves its post-connect transitional state. Wait ~2 s after this before staging — a fresh session will not arm if the next frames arrive immediately (verified on hardware).

### 3. `0xA6` — Set dose

13-byte payload; the dose in grams is a `u8` **at offset 9**:

```
01 00 00 00 00 00 00 00 00 <dose> 00 00 00
```

### 4. `0xA8` — Set stage temperatures

Payload: `01` + `f32 LE (temp1)` + `f32 LE (temp2)`. Defaults `110.0`, `90.0`:

```
01 00 00 DC 42 | 00 00 B4 42     (110.0, 90.0)
```

These are pre-heat set-points (40–130 °C), not pour temperatures.

### 5. Pours frame — `0x41` or `0x44`

Carries the [recipe payload](/doc/recipe-payload.md): `01 | LEN(u8) | <segments> | grind | ratio`.

- `0x41` — pours **with** grinding (fresh beans)
- `0x44` — pours **without** grinding (pre-ground / no-grind recipe)

Both carry the identical body; only the opcode differs.

## After Load

The machine reports:

```
0x1D loading → 0x1F armed
```

At `armed` the machine prompts the human; the recipe can then be approved **on the device** or started remotely with commit + start.

## Example Data

Session start frame (with placeholder CRC):

```
Raw bytes: 58 01 01 A4 1F 15 00 00 00 01 01 B9 00 00 00 01 00 00 00 XX XX

A4 1F                 Command 0xA4, seq 0x1F
15 00 00 00           Length = 21 (12 header + 9 payload)
01                    Payload marker
01 B9 00 00 00 01 00 00 00   Session payload
XX XX                 CRC16 (CRC-16/KERMIT)
```

The dose frame for 15 g:

```
Raw bytes: 58 01 01 A6 1F 19 00 00 00 01 01 00 00 00 00 00 00 00 00 0F 00 00 00 XX XX

A6 1F                 Command 0xA6, seq 0x1F
19 00 00 00           Length = 25 (12 + 13 payload)
01                    Payload marker
               0F     dose = 15 g
```

> The sending client paces the writes (~0.4 s apart) rather than round-tripping each ACK: the machine needs the frames spaced out, and the machine's ACKs accumulate on `ffe2` independently.