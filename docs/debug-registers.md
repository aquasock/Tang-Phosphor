# Debug register map

Tang-Phosphor implements version 1 of Tang-Control's CRC-protected extended
control protocol. Registers are 32-bit and naturally aligned. Unknown reads
return `0xdeadbeef`; unknown writes have no effect.

| Address | Access | Meaning |
|---:|:---:|---|
| `0x0000` | R | Magic `0x54504830` (`TPH0`) |
| `0x0004` | R | Register ABI, currently `0x00010003` (1.3) |
| `0x0008` | R | Build date in packed hexadecimal (`0x20260927`) |
| `0x000c` | R | Core capabilities: bit 0 debug bank, bit 1 stream transport, bit 2 WAV playback, bit 3 tone fallback |
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
| `0x005c` | R | Audio status: error `[13:6]`, playback active `[5]`, WAV format valid `[4]`, state `[3:0]` |
| `0x0060` | R | Detected WAV sample rate in hertz |
| `0x0064` | R | PCM FIFO fill level in stereo samples |
| `0x0068` | R | PCM samples presented for playback in the current stream |
| `0x006c` | R | PCM FIFO underruns in the current stream |
| `0x0070` | R | Active HDMI audio sample rate in hertz |
| `0x0074` | R | Content format: `0` undetected/unknown, `1` WAV, `2` FLAC; `3` MP3 and `4` Ogg Vorbis are reserved |

Audio player states are `0` idle, `1` receiving, `2` prefilling, `3` playing,
`4` complete, `5` error, and `6` cancelled. Audio error codes are `1` invalid
RIFF/WAVE header, `2` missing or unsupported `fmt ` data, `3` a partial stereo
PCM sample in the data chunk, and `4` premature transport end.
Content-front-end error `0x10` means the stream was recognized but its decoder
is not implemented, and `0x11` means the content signature was unknown or
ended before it could be classified. FLAC currently produces `0x10`; format
recognition does not advertise FLAC decode capability.

Examples use the authoritative host client from the sibling Tang-Control
repository. Check out its `feature/usb-cdc-file-transfer` branch at `e3aa4f9`,
then run these commands from the Tang-Phosphor repository root:

```bash
python3 ../Tang-Control/scripts/tangctl.py caps
python3 ../Tang-Control/scripts/tangctl.py peek 0x0 11
python3 ../Tang-Control/scripts/tangctl.py poke 0x20 0x12345678
python3 ../Tang-Control/scripts/tangctl.py peek 0x20
python3 ../Tang-Control/scripts/tangctl.py stream music/test.wav
python3 ../Tang-Control/scripts/tangctl.py peek 0x30 6
python3 ../Tang-Control/scripts/tangctl.py peek 0x5c 7
```
