# Status Notifications

The machine pushes status, ACK, telemetry, and state frames to the `ffe2` status characteristic as notifications. Unlike command frames (header `58 01 01`), notifications use a distinct header `58 02 07`.

* UUID: `0000ffe2-0000-1000-8000-00805f9b34fb`
* Methods: `NOTIFY`
* Data Format
  * Size: `Variable`
  * Type: `Custom binary frame`

## Frame Layout

```
58 02 07 | TYPE (u8) | SUB (u8) | LEN (u32 LE) | C1 | payload | CRC16 (u16 LE)
```

| Offset | Field   | Description                                                                    |
| ------ | ------- | ------------------------------------------------------------------------------ |
| 0–2    | Header  | Constant `58 02 07`                                                           |
| 3      | TYPE    | Frame kind, see below                                                          |
| 4      | SUB     | Sub-type (constant `0x07` on studied captures)                                 |
| 5–8    | LEN     | Total frame length incl. header + CRC, little-endian                           |
| 9      | Marker  | Constant `0xC1`                                                                |
| 10+    | Payload | Frame data                                                                     |
| last 2 | CRC16   | CRC-16/KERMIT over the frame minus the trailing 2 bytes                        |

## TYPE Values

| TYPE | Meaning                                                                   |
| ---- | ------------------------------------------------------------------------- |
| echo | **Command ACK** — equals the command byte just written (`a4/a6/a8/41/42/46`/…). The ACK for a frame is simply the notification whose offset-3 byte matches your command. |
| `0x57` | **Status frame** — the byte right after `0xC1` is the machine state. See [machine-states.md](/doc/machine-states.md). |
| `0x15` | **Scale stream** — coffee/cup weight, float32 LE in grams. See [scale-telemetry.md](/doc/scale-telemetry.md). |
| `0x4B` | **Scale stream** — water weight, float32 LE in milligrams. See [scale-telemetry.md](/doc/scale-telemetry.md). |
| `0x49` | **Machine-info dump** — serial + firmware string. See [machine-info.md](/doc/machine-info.md). |
| `0x39` | Live brew progress (not decoded).                                          |

Status notifications may arrive concatenated back-to-back in a single BLE packet — split on the header and the length field at offset 5.

> Not every notification is status: during an idle held session the machine streams status continuously (idle-state frames, scale noise). A valid scale/status frame starts with `0x58`; anything shorter than 10 bytes should be ignored.

### Aux Characteristic

`ffe3` (`0000ffe3-0000-1000-8000-00805f9b34fb`) is an auxiliary notify characteristic. It was tapped but not decoded (best-effort: some clients also subscribe it on connect). It may carry a duplicate live-scale stream. See the README for the current unknowns.

## Response Codes

In addition to the `58 02 07` session frames, the machine answers individual commands in the **classic** command/response protocol: an inbound frame that echoes the command header (`58 01 01`) but carries a *response code* in bytes 3–4, with the payload at byte 10 (`data[10:-2]`, i.e. after marker).

Response codes are 16-bit, little-endian. There is no single subscription callback — a client filters notifications by code.

### State Responses

| Code  | Name                    | Description                                        |
| ----- | ----------------------- | -------------------------------------------------- |
| 9000  | `RD_IN_GRINDER`         | Dripper arrived at grinder position                |
| 9001  | `RD_IN_BREWER`          | Dripper arrived at brewer position (vol/temp/pattern payload) |
| 9002  | `RD_IN_SCALE`           | Dripper arrived at scale position                  |
| 9003  | `RD_GRINDER_BEGIN`      | Grinding started                                   |
| 9004  | `RD_OUT_GRINDER`        | Leaving grinder position                           |
| 9005  | `RD_BREWER_BEGIN`       | Pouring started                                    |
| 9006  | `RD_OUT_BREWER`         | Leaving brewer position                            |
| 9008  | `RD_OUT_SCALE`          | Leaving scale position                             |
| 9009  | `RD_GRINDER_PAUSE`      | Grinder paused                                     |
| 9010  | `RD_BREWER_PAUSE`       | Brewer paused                                      |
| 40501 | `RD_Pods`               | Pod state                                          |
| 40502 | `RD_BREWER_COFFEE_START`| Coffee recipe started                              |
| 40507 | `RD_Grinder_Stop`       | Grinding complete                                  |
| 40510 | `RD_BLOOM`              | Bloom phase active                                 |
| 40511 | `RD_Brewer_Stop`        | Pouring complete                                   |
| 40512 | `RD_ENJOY`              | Recipe complete                                    |
| 40513 | `RD_ENJOY2`             | Recipe complete (variant)                          |
| 40517 | `RD_ErrorIdling`        | Empty grinding — no beans detected                 |
| 40522 | `RD_ErrorLackOfWater`   | Water tank empty                                   |
| 8203  | `RD_AbnormalGearPosition` | Dripper position error                            |
| 8204  | `RD_AbnormalDoseOrWater`  | Invalid dose or water parameters                   |

### Telemetry Responses

| Code  | Name                  | Payload                                       |
| ----- | --------------------- | --------------------------------------------- |
| 10507 | `RD_CURRENT_WEIGHT`   | Weight                                        |
| 20501 | `RD_CURRENT_WEIGHT2`  | Weight as float32 at offset 0                 |
| 8105  | `RD_GRINDER_SIZE`     | Grinder size setting                          |
| 8106  | `RD_GRINDER_SPEED`    | Grinder speed setting                         |
| 8107  | `RD_BREWER_MODE`      | Brewer mode                                   |
| 8108  | `RD_BREWER_TEMPERATURE`| Current water temp, `u32 LE ÷ 10` = °C        |
| 40505 | `RD_GearReport`       | Dripper position, `u32 LE`                    |
| 40521 | `RD_MachineInfo`      | Serial/model/version (see machine-info.md)    |
| 40523 | `RD_WATER_VOLUME`     | Water volume as float32 at offset 0           |
| 4508  | `RD_WaterSource`      | Water source                                  |
| 8023  | `RD_MachineActivity`  | Machine activity                              |
| 8015  | `RD_UNIT_CHANGE`      | Unit change                                   |

## Example Data

A status notification reporting the machine is armed:

```
Raw bytes (13): 58 02 07 57 07 0D 00 00 00 C1 1F 00 00 00

58 02 07              Header
57                    TYPE = status frame
07                    SUB
0D 00 00 00           LEN = 13
C1                    Payload marker
1F                    State = 0x1F (armed)
00 00 00              Trailing state bytes
00 00                 CRC16
```

The brew-record calendar shows the equivalent with the pouring state:

```
Raw bytes: 58 02 07 57 07 0D 00 00 00 C1 10 00 00 00 …

57                    TYPE = status frame
C1                    Payload marker
10                    State = 0x10 (brewing)
```

> The CRC in the examples above is illustrative; the trailing bytes shown as `00 00` are placeholders. The real CRC16 is computed per CRC-16/KERMIT and stored little-endian.