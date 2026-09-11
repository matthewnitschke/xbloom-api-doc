# Machine States

Status frames (`TYPE 0x57`) carry a machine state; the state byte is the first byte after the `0xC1` marker. States are integers without units.

* UUID: `0000ffe2-0000-1000-8000-00805f9b34fb`
* Methods: `NOTIFY`
* Data Format
  * Size: `1 Byte` (first byte of the status payload)
  * Type: `UInt8`

## State Values

| Byte  | Name              | Meaning                                                              |
| ----- | ----------------- | -------------------------------------------------------------------- |
| `0x01`| idle              | Idle / ready. Also seen at brew end.                                 |
| `0x0C`| no_water          | Refused: no water (checked right after commit).                      |
| `0x0F`| no_beans          | Refused: wants beans. The machine **waits** here.                    |
| `0x10`| brewing          | Live pour / brew in progress.                                        |
| `0x1D`| loading           | Recipe being received.                                               |
| `0x1F`| armed             | Recipe loaded, armed, awaiting human approval.                       |
| `0x1E`| awaiting_confirm  | Brew committed, waiting for the human confirm.                       |
| `0x22`| starting          | Post-commit: grinding / spinning up.                                 |
| `0x23`| brewing           | Mid-pour sub-state.                                                  |
| `0x24`| ready             | Coffee ready (the beep). Cup still on the scale.                     |
| `0x3B`| brewing           | Brew in progress (app-capture firmware).                             |
| `0x41`| complete          | Brew complete (Auto-mode selector).                                  |
| `0x43`| saving_slots      | Easy-Mode slot batch being stored.                                   |
| `0x25`| slots_saved       | Easy-Mode slots stored OK (then → idle).                             |

## Lifecycle

The important transitions in a normal brew:

```
idle (0x01)
  → loading (0x1D)          recipe load in progress
  → armed (0x1F)            recipe loaded, awaiting approval
  → awaiting_confirm (0x1E) commit sent (0x42), ~99 s add-beans countdown
  → starting (0x22)         grinding / spinning up (begins after confirm)
  → brewing (0x10 / 0x23 / 0x3B)
  → ready (0x24)            coffee done — the beep. Terminal signal.
  → idle (0x01)             only after the cup is lifted.
```

Terminal states — the brew is over — are `0x24`, `0x41`, and `0x01`.

> **Silent grind gap** (firmware `V12.0D.500`): after commit the machine goes `awaiting_confirm (0x1E) → starting (0x22)`, then grinds **silently** — it emits no `0x57` status frame for ~20 s (only the scale stream reading ~0) before it reports the pour as `0x10`. Do not treat that gap as a stalled brew.

## Example Data

```
Raw bytes (13): 58 02 07 57 07 0D 00 00 00 C1 25 00 00 00
                        C1 marker: 25 → slots_saved
```

The state follows the marker:

```
… C1 1F …   → armed
… C1 10 …   → brewing
… C1 24 …   → ready
```