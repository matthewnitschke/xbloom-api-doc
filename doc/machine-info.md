# Machine Info

A notification carrying the machine's identity and water state. The machine pushes it in response to the `0x56` status handshake (and periodically as `TYPE 0x49` frames).

* UUID: `0000ffe2-0000-1000-8000-00805f9b34fb`
* Methods: `NOTIFY`
* Data Format
  * Size: `≥ 34 Bytes`
  * Type: `UTF-8 + UInt8` (mixed)

## Layout

The info dump arrives as a classic response frame carrying response code `40521` (`RD_MachineInfo`); the payload begins at byte 10 (`data[10:-2]`).

| Offset | Size | Field           | Encodings                                   |
| ------ | ---- | --------------- | ------------------------------------------- |
| 0      | 13   | Serial number   | UTF-8, NUL-padded                           |
| 13     | 6    | Model           | UTF-8, NUL-padded                           |
| 19     | 10   | Version         | UTF-8, NUL-padded (e.g. `V12.0D.500`)      |
| 33     | 1    | Water level OK  | `1` = ok, `0` = low                         |
| 34     | 1    | System status   | Barebyte                                     |
| 36     | 1    | Water volume    | Byte                                        |

## Example Data

Assuming an info payload of 37+ bytes:

```
Raw payload: 48 55 44 58 30 30 30 30 30 30 30 30 30 53 54 55 44 49 4F 56 31 32 2E 30 44 2E 35 30 30 00 00 00 00 01 00 00 0F

H   U   D   X  …  (serial, 13 bytes)
S   T   U   D   I   O  (model, 6 bytes)
V   1   2   .   0   D   .   5   0   0  (version, 10 bytes)
… watermark bytes …
01  (water level OK)
00  (system status)
0F  (water volume ≈ 15.0)
```

Decoded:

```
Serial:    HUDX00…
Model:     STUDIO
Version:   V12.0D.500
Water OK:  true
Water vol: 15
```