# Debug register map

Tang-Phosphor implements version 1 of Tang-Control's CRC-protected extended
control protocol. Registers are 32-bit and naturally aligned. Unknown reads
return `0xdeadbeef`; unknown writes have no effect.

| Address | Access | Meaning |
|---:|:---:|---|
| `0x0000` | R | Magic `0x54504830` (`TPH0`) |
| `0x0004` | R | Register ABI, currently `0x00010000` (1.0) |
| `0x0008` | R | Build date in packed hexadecimal (`0x20260927`) |
| `0x000c` | R | Core capabilities; bit 0 indicates this debug bank |
| `0x0010` | R | Logic-clock cycles since reset, wrapping at 32 bits |
| `0x0014` | R | Video frames since reset |
| `0x0018` | R | Valid debug requests seen by the register bank |
| `0x001c` | R | Debug writes seen by the register bank |
| `0x0020` | R/W | Scratch register for end-to-end testing |
| `0x0024` | R | Requests rejected for a bad transport CRC |
| `0x0028` | R | Malformed/unsupported transport requests |
| `0x0030` | R | Stream sessions started |
| `0x0034` | R | Bytes consumed in the current stream |
| `0x0038` | R | Stream end markers consumed |
| `0x003c` | R | Stream cancellations consumed |
| `0x0040` | R | Offset of the last consumed stream byte |
| `0x0044` | R | Current CRC-32 state; finalized after the end marker |
| `0x0048` | R | FPGA USB controller 1 buttons in SNES layout |
| `0x004c` | R | FPGA USB controller 2 buttons in SNES layout |
| `0x0050` | R | BL616-provided HID controller 1 state |
| `0x0054` | R | BL616-provided HID controller 2 state |
| `0x0058` | R | USB status: `{usb2_error, usb2_type[1:0], usb1_error, usb1_type[1:0]}` |

Examples using the Tang-Control host client:

```bash
python3 scripts/tangctl.py caps
python3 scripts/tangctl.py peek 0x0 11
python3 scripts/tangctl.py poke 0x20 0x12345678
python3 scripts/tangctl.py peek 0x20
python3 scripts/tangctl.py stream music/test.wav
python3 scripts/tangctl.py peek 0x30 6
```
