# Scale Telemetry

The machine streams the two brew-record weights the phone app graphs, roughly 10×/s, as separate interleaved notifications on `ffe2`. Each carries a single float32 (little-endian) right after the `0xC1` marker.

* UUID: `0000ffe2-0000-1000-8000-00805f9b34fb`
* Methods: `NOTIFY`
* Data Format
  * Size: `4 Bytes`
  * Type: `Float32` (little-endian)

## Weights

| TYPE | Unit          | Conversion                    |
| ---- | ------------- | ----------------------------- |
| `0x4B` | Water weight | **milligrams** (÷ 1000 = grams) |
| `0x15` | Coffee / cup weight | already in **grams**    |

The weight value is a float32 right after the marker: `… C1 <f32 LE> …`. Water weight uses `scale = 0.001` to get grams, coffee uses `scale = 1.0`.

These streams look like idle "heartbeats" — they stream at idle too, reading ~0 — but they are the real weight feed. When idle or untared the scale drifts and reads noise (negative / huge / NaN), so a sane parser drops readings outside `0–2000 g`.

## Example Data

A water-weight frame:

```
Raw bytes: 58 02 07 4B 07 0D 00 00 00 C1 00 E1 E1 3D …

4B                    TYPE = water stream
C1                    Marker
00 E1 E1 3D           Float32 LE = 0.110… → 110 mg → 0.11 g
```

A coffee/cup-weight frame:

```
Raw bytes: 58 02 07 15 07 0D 00 00 00 C1 00 00 80 3F …

15                    TYPE = coffee stream
C1                    Marker
00 00 80 3F           Float32 LE = 1.0 g
```

> The `…` CRC bytes are omitted; CRC16 is computed per CRC-16/KERMIT over the frame minus the trailing 2 bytes.