# Recipe Setup (Bypass & Cup)

The classic app workflow configures the brew with two setup commands before sending the recipe: **set bypass** (which carries the bean dose) and **set cup** (weight bounds for cup detection). The order is critical — the machine validates parameters and the dose drives the grinder.

* UUID: `0000ffe1-0000-1000-8000-00805f9b34fb`
* Methods: `WRITE`
* Data Format
  * Size: `Variable`
  * Type: `Custom binary frame`

## Set Bypass (`8102` = `0x1FA6`)

Payload is **3 × `u32 LE`** integers:

```
[bypassVolume_floatbits, bypassTemp×10_floatbits, dose_int]
```

| Field   | Size   | Encoding                                       |
| ------- | ------ | ---------------------------------------------- |
| Volume  | 4 Bytes| Float32 bit pattern (bypass water, `0.0` = disabled) |
| Temp    | 4 Bytes| Float32 bit pattern of `temp × 10` (`0.0` = disabled) |
| Dose    | 4 Bytes| Integer — **bean weight in grams**            |

> ⚠️ **Dose is critical.** Even when bypass water is disabled (`vol = 0`, `temp = 0`), `dose` **must** hold the bean weight — it tells the machine how many grams to grind. `dose = 0` means "grind 0 grams" = skip grinding.

## Set Cup (`8104` = `0x1FA8`)

Payload is **2 × `u32 LE`** floats (as bit patterns):

```
[cupMaxWeight_floatbits, cupMinWeight_floatbits]
```

Defaults by cup type:

| Cup Type         | Max | Min |
| ---------------- | --- | --- |
| XPod (`1`)       | 80  | 40  |
| XDripper (`2`)   | 90  | 40  |
| Other (`3`)      | 90  | 40  |

Brewing pre-ground coffee typically sets min weight to `0.0` (bypassing the cup-detection safety check).

## Command Order

The four-step classic brew (in this exact order):

```
1. set bypass 8102  — includes dose (grinding needs it)
2. set cup 8104     — weight bounds
3. send recipe 8001 (grind) / 8004 (no-grind)
4. execute 8002     — start brewing
```

## Example Data

Disabling bypass water but dosing 15 g of beans:

```
8102 frame: 58 01 01 A6 1F 18 00 00 00 01 00 00 00 00 00 00 00 00 00 00 00 0F 00 00 00 XX XX

A6 1F                 Command 0x1FA6 = 8102
18 00 00 00           Length = 24 (12 + 12 payload)
00 00 00 00           bypass volume 0.0 (float32 bits)
00 00 00 00           bypass temp 0.0 × 10 (float32 bits)
0F 00 00 00           dose = 15 g
XX XX                 CRC16 (CRC-16/KERMIT)
```

Setting an XDripper cup (max 90, min 40):

```
8104 frame: 58 01 01 A8 1F 18 00 00 00 01 00 00 B4 42 00 00 20 42 XX XX
                          A8 1F                  Command 0x1FA8 = 8104
                          B4 42 → 90.0 float32 bits
                          20 42 → 40.0 float32 bits
```

> The CRC placeholders (`XX XX`) must be computed with CRC-16/KERMIT; the byte values above are the payload fields only.