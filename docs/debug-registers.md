# Debug register map

Tang-Phosphor implements version 1 of Tang-Control's CRC-protected extended
control protocol. Registers are 32-bit and naturally aligned. Unknown reads
return `0xdeadbeef`; unknown writes have no effect.

| Address | Access | Meaning |
|---:|:---:|---|
| `0x0000` | R | Magic `0x54504830` (`TPH0`) |
| `0x0004` | R | Register ABI, currently `0x00010008` (1.8) |
| `0x0008` | R | Build date in packed hexadecimal (`0x20260927`) |
| `0x000c` | R | Core capabilities: bit 0 debug bank, bit 1 stream transport, bit 2 WAV playback, bit 3 startup diagnostic tone, bit 4 FLAC playback, bit 5 native album UI/control, bit 6 RGB332 cover artwork, bit 7 gapless session append |
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
| `0x0060` | R | Sample rate detected by the decoder session in hertz; a queued gapless successor reports its rate here before it is audible |
| `0x0064` | R | PCM FIFO fill level in stereo samples, up to 16384 |
| `0x0068` | R | PCM samples presented for playback in the audible stream |
| `0x006c` | R | PCM FIFO underruns in the audible stream |
| `0x0070` | R | Active HDMI audio sample rate in hertz |
| `0x0074` | R | Content format: `0` undetected/unknown, `1` WAV, `2` FLAC; `3` MP3 and `4` Ogg Vorbis are reserved |
| `0x0078` | R/W | Playback control: bit 0 pauses PCM consumption and outputs silence |
| `0x007c` | R/W | UI control: bit 0 visible, bit 1 playlist layout; write bit 31 to atomically publish the shadow metadata bank |
| `0x0080` | R/W | Playlist state: current track `[7:0]`, track count `[15:8]`, six-row window start `[23:16]`; writes update the unpublished shadow state |
| `0x0084` | W | Text lengths for slots 0-3, packed most-significant byte first in slot order |
| `0x0088` | W | Text lengths for slots 4-7, packed most-significant byte first in slot order |
| `0x008c` | R | Exact elapsed playback time in seconds |
| `0x0090` | R | Exact duration of the audible stream in seconds |
| `0x0094` | W | Text length for slot 8 in bits `[31:24]`; other bits are reserved |
| `0x0098` | W | Artwork control: bit 0 valid; write bit 31 to atomically publish the inactive artwork bank |
| `0x009c` | R | Gapless session boundaries crossed since reset |
| `0x00a0` | R | Sample periods of silence inserted at gapless boundaries since reset; excludes paused periods |
| `0x00a4` | R | Audible stream ID `[15:0]`: the transport session whose samples are being presented |
| `0x00a8` | R/W | Stream routing (`cpu_mode`), merged core only: bit 0 clear feeds the BL616 stream to the FPGA player, set feeds it to the AE350 program loader and routes the player from the AE350's play stream; powers up clear. At `0x00c0`, bit 0, before ABI 1.8 |
| `0x00c0` | R/W | Socket control: hold `[0]` freezes the renderer between frames, PMOD0 personality `[7:4]`, PMOD1 personality `[11:8]`, PMOD0 seated upside down `[12]`, PMOD1 `[13]`; reads add the renderer's frame selector at `[18:16]`. Personalities are `0` none, `1` OLEDrgb, `2` PmodVGA J1, `3` PmodVGA J2, `4` rotary encoder. Powers up with both sockets released |
| `0x00c4` | R | Renderer source bank `[0]` |
| `0x00c8` | R | Source frame signature |
| `0x00cc` | R | HDMI transmitter frame signature |
| `0x00d0` | R | Panel (PMOD OLED) frame signature |
| `0x00d4` | R | Frames rendered |
| `0x00d8` | R | Panel frames sent |
| `0x00dc` | R | HDMI frames sent |
| `0x00e0` | R | Rotary encoder count, centred at `0x80000000` |
| `0x00e4` | R | Rotary encoder state: raw pins `[7:4]`, switch `[3]`, button `[2]` |
| `0x00e8` | R | Keyboard link frames accepted |
| `0x00ec` | R | Keyboard link frames refused for a bad checksum |
| `0x00f0` | R | Keyboard link frames abandoned part way |
| `0x00f4` | R | Last keyboard report: modifiers `[23:16]`, first keycode `[15:8]`, second `[7:0]` |
| `0x0100-0x021c` | W | Nine 32-byte ASCII text slots in the unpublished bank; each aligned word stores four bytes most-significant byte first |
| `0x1000-0x310c` | W | One inactive 92x92 RGB332 artwork bank; each aligned word stores four pixels most-significant byte first |
| `0x4000-0x43ff` | R/W | Merged core only: the AE350 subsystem's register view (loader, log ring, bridge counters and trace), reachable while `0x00a8` bit 0 is set |

Inside the AE350 view, a running program asks the BL616 for file data through
a mailbox in its result words (`software/ae350/include/ae350_request.h`):
`0x4078` holds the byte offset, `0x407c` the length, and `0x4074` a sequence
number the program bumps after writing them. The BL616 polls `0x4074` while
the loader state at `0x4020` is RUN and answers each new sequence with one
stream session of that byte range. The same words hold `mcause`, `mepc` and
`mtval` after a trap.

In the merged image the FPGA player is `pcm_sink`, a raw-PCM sink fed by the
AE350, and several player registers read differently from the table above:
`0x0064` fills to at most 2048 stereo samples; `0x006c` counts underruns since
the core's reset rather than per stream; `0x0030` counts STARTs since the core
loaded; and `0x008c` and `0x0090` read 0, because elapsed time and duration are
not wired in that sink.

Text slots 0-2 are the current album, artist, and track; slots 3-8 are the six
visible playlist rows. Tang-Control writes all text,
lengths, and playlist state before committing `0x007c[31]`, so the pixel domain
never presents a partially updated track list. Artwork writes always target the
inactive art bank. Writing `0x0098 = 0` immediately hides stale art, while
`0x80000001` swaps in a complete image and marks it valid.

Audio player states are `0` idle, `1` receiving, `2` prefilling, `3` playing,
`4` complete, `5` error, `6` cancelled, and `7` draining. Draining means the
transport has ended the session and its final sample is queued; a START in
that state appends a gapless successor. Audio error codes are `1` invalid
RIFF/WAVE header, `2` missing or unsupported `fmt ` data, `3` a partial stereo
PCM sample in the data chunk, and `4` premature transport end.
Content-front-end error `0x10` means the stream was recognized but its decoder
is not implemented, and `0x11` means the content signature was unknown or
ended before it could be classified. FLAC errors are `0x21` unsupported
profile, `0x22` invalid frame header, `0x23` CRC failure, `0x24` invalid
subframe, `0x25` truncated stream, and `0x26` internal range failure.

Examples use the authoritative host client from the sibling Tang-Control
repository. Check out its `feature/usb-cdc-file-transfer` branch at `fbbddc6`, then run
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
