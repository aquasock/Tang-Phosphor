# Debug register map

Tang-Phosphor implements version 1 of Tang-Control's CRC-protected extended
control protocol. Registers are 32-bit and naturally aligned. Unknown reads
return `0xdeadbeef`; unknown writes have no effect.

| Address | Access | Meaning |
|---:|:---:|---|
| `0x0000` | R | Magic `0x54504830` (`TPH0`) |
| `0x0004` | R | Register ABI, currently `0x00010006` (1.6) |
| `0x0008` | R | Build date in packed hexadecimal (`0x20260927`) |
| `0x000c` | R | Core capabilities: bit 0 debug bank, bit 1 stream transport, bit 2 WAV playback, bit 3 startup diagnostic tone, bit 4 FLAC playback, bit 5 native album UI/control, bit 6 RGB332 cover artwork |
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
| `0x005c` | R | Audio status: error `[13:6]`, playback active `[5]`, selected decoder format valid `[4]`, state `[3:0]` |
| `0x0060` | R | Detected audio sample rate in hertz |
| `0x0064` | R | PCM FIFO fill level in stereo samples |
| `0x0068` | R | PCM samples presented for playback in the current stream |
| `0x006c` | R | PCM FIFO underruns in the current stream |
| `0x0070` | R | Active HDMI audio sample rate in hertz |
| `0x0074` | R | Content format: `0` undetected/unknown, `1` WAV, `2` FLAC; `3` MP3 and `4` Ogg Vorbis are reserved |
| `0x0078` | R/W | Playback control: bit 0 pauses PCM consumption and outputs silence |
| `0x007c` | R/W | UI control: bit 0 visible, bit 1 playlist layout; write bit 31 to atomically publish the shadow metadata bank |
| `0x0080` | R/W | Playlist state: current track `[7:0]`, track count `[15:8]`, six-row window start `[23:16]`; writes update the unpublished shadow state |
| `0x0084` | W | Text lengths for slots 0-3, packed most-significant byte first in slot order |
| `0x0088` | W | Text lengths for slots 4-7, packed most-significant byte first in slot order |
| `0x008c` | R | Exact elapsed playback time in seconds |
| `0x0090` | R | Exact decoded stream duration in seconds |
| `0x0094` | W | Text length for slot 8 in bits `[31:24]`; other bits are reserved |
| `0x0098` | W | Artwork control: bit 0 valid; write bit 31 to atomically publish the inactive artwork bank |
| `0x0100-0x021c` | W | Nine 32-byte ASCII text slots in the unpublished bank; each aligned word stores four bytes most-significant byte first |
| `0x1000-0x310c` | W | One inactive 92x92 RGB332 artwork bank; each aligned word stores four pixels most-significant byte first |

Text slots 0-2 are the current album, artist, and track; slots 3-8 are the six
visible playlist rows. Tang-Control writes all text,
lengths, and playlist state before committing `0x007c[31]`, so the pixel domain
never presents a partially updated track list. Artwork writes always target the
inactive art bank. Writing `0x0098 = 0` immediately hides stale art, while
`0x80000001` swaps in a complete image and marks it valid.

Audio player states are `0` idle, `1` receiving, `2` prefilling, `3` playing,
`4` complete, `5` error, and `6` cancelled. Audio error codes are `1` invalid
RIFF/WAVE header, `2` missing or unsupported `fmt ` data, `3` a partial stereo
PCM sample in the data chunk, and `4` premature transport end.
Content-front-end error `0x10` means the stream was recognized but its decoder
is not implemented, and `0x11` means the content signature was unknown or
ended before it could be classified. FLAC errors are `0x21` unsupported
profile, `0x22` invalid frame header, `0x23` CRC failure, `0x24` invalid
subframe, `0x25` truncated stream, and `0x26` internal range failure.

Examples use the authoritative host client from the sibling Tang-Control
repository. Check out its `feature/usb-cdc-file-transfer` branch at `26a6ff7`, then run
these commands from the Tang-Phosphor repository root:

```bash
python3 ../Tang-Control/scripts/tangctl.py caps
python3 ../Tang-Control/scripts/tangctl.py peek 0x0 11
python3 ../Tang-Control/scripts/tangctl.py poke 0x20 0x12345678
python3 ../Tang-Control/scripts/tangctl.py peek 0x20
python3 ../Tang-Control/scripts/tangctl.py stream music/test.wav
python3 ../Tang-Control/scripts/tangctl.py peek 0x30 6
python3 ../Tang-Control/scripts/tangctl.py peek 0x5c 7
```
