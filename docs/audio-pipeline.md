# Audio pipeline

Tang-Phosphor recreates MiSTer-Phosphor as a Tang-native design. The MiSTer
core defines the compatibility baseline and bounded codec profiles; TangCore's
BL616 transport, Gowin memories, clocking, HDMI path, and diagnostics define
the implementation.

## Supported profile

The current player profile is intentionally limited to these CD-class formats:

| Format | Profile |
|---|---|
| WAV | PCM, 16-bit stereo, 44.1 or 48 kHz |
| FLAC | Native FLAC, 16-bit stereo, 44.1 or 48 kHz |

MP3, Ogg Vorbis, high-resolution PCM, and other codecs are outside the current
project scope. WAV playback accepts both native rates. A rate change restarts the
fractional sample timebase and the HDMI ACR measurement while playback is still
prefilling, then transmits matching ACR and IEC 60958 channel-status values.

## Stream boundary

Tang-Control starts a session, sends ordered byte frames, and ends or cancels
the session. `iosys_bl616` verifies frame CRC and offset continuity, buffers up
to 1,024 bytes, and exposes this interface to the player:

```text
stream_start / stream_end / stream_cancel
stream_id[15:0]
stream_offset[31:0]
stream_data[7:0]
stream_valid / stream_ready
```

A byte transfers only when `stream_valid && stream_ready`. Backpressure reaches
Tang-Control through the existing credit response; no byte may be advanced or
counted merely because `stream_valid` is asserted.

The BL616 owns filesystem and playlist handling. A standalone WAV or FLAC is
one stream session; each VLC-style M3U/M3U8 entry is another independent
session after the preceding track reaches the player's hardware `COMPLETE`
state. Playlists may mix WAV and FLAC. Paths are resolved against the playlist
directory, so separately stored files do not need a TAR wrapper. `#EXTINF`
duration is metadata and never controls the audio transition.

The content detector buffers at most 12 bytes: four bytes identify the FLAC
`fLaC` marker, while RIFF/WAVE identification also checks `RIFF` at byte zero
and `WAVE` at byte eight. A recognized prefix is replayed byte-for-byte from
offset zero before the remaining stream passes through. Replay applies normal
`valid/ready` backpressure, and stream end is retained until replay finishes.
Unknown or truncated signatures are drained with error `0x11`. WAV reports
format ID `1`, and FLAC reports format ID `2`. Other format IDs are reserved
without detection or planned decode behavior.

## FLAC boundary

The FLAC path implements the RFC 9639 streamable subset within the project
profile. STREAMINFO must declare stereo, 16-bit audio at 44.1 or 48 kHz and a
maximum block size no larger than 4,608 samples. Metadata blocks are bounded
and skipped after STREAMINFO. Frame headers use explicit sample-rate and
sample-size codes.

Constant, verbatim, fixed-predictor orders 0–4, and LPC orders 1–12 are
decoded. Rice methods 0 and 1, escape-coded residuals, wasted bits, and all
four stereo channel assignments are supported. Header CRC-8 and frame CRC-16
are mandatory. Two Gowin block-RAM frame banks retain provisional samples;
only a complete frame with a valid CRC-16 can enter the shared PCM FIFO.

## PCM boundary

Decoders produce signed 16-bit left and right samples with `valid/ready`, an
end-of-stream marker attached to the final sample, and a rate code. The output
path uses native source rates; sample-rate conversion is not part of the design.

The first implementation remains entirely in the 74.25 MHz logic/pixel clock
domain. A fractional accumulator produces the HDMI sample cadence, so the PCM
FIFO is currently a single-clock FIFO rather than a clock-domain crossing.
Any later independent decoder or audio clock must introduce an explicit,
separately verified asynchronous boundary.

## Buffering and pacing

The BL616's 1,024-byte receive buffer provides transport backpressure but is
empty while the acknowledgement and following frame make their round trip. A
2,048-entry stereo PCM FIFO absorbs this burst-and-gap behavior. Playback waits
for 512 decoded samples, or for a short file's final sample, before taking over
from silence. The diagnostic tones are available only before the first stream
session begins.

FIFO fullness stalls the selected decoder, which stalls the BL616 stream
without discarding or duplicating data. The FLAC decoder additionally uses two
4,608-sample provisional frame banks so CRC validation happens before output.
FIFO emptiness during active playback emits zero for that sample and increments
the underrun counter. Completion is terminal until a new stream starts,
preventing a retained EOF indication from restarting an empty player.

## Diagnostics

The debug register bank reports the player state, content format ID, selected
decoder format validity, detected rate, FIFO level, played-sample count,
underrun count, and decoder or content-front-end error code.
The original stream byte count, offset, CRC, end, and cancel counters remain
observation-only and count only accepted bytes. See
[`debug-registers.md`](debug-registers.md) for the register ABI.

The deterministic 1 kHz left and 2 kHz right tones are a startup diagnostic.
The first stream session disables them until core reset; prefill, completion,
cancellation, decoder errors, and independent-session playlist boundaries emit
silence whenever PCM is not active. The HDMI timebase retains the last valid
native rate across those boundaries, avoiding a transient return to 48 kHz while
the next track's metadata is parsed.
