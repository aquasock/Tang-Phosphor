# Audio pipeline

Tang-Phosphor recreates MiSTer-Phosphor as a Tang-native design. The MiSTer
core defines the compatibility baseline and bounded codec profiles; TangCore's
BL616 transport, Gowin memories, clocking, HDMI path, and diagnostics define
the implementation.

## Supported profile

The completed player is intended to support the same CD-class formats as
MiSTer-Phosphor:

| Format | Profile |
|---|---|
| WAV | PCM, 16-bit stereo, 44.1 or 48 kHz |
| FLAC | Native FLAC, 16-bit stereo, 44.1 or 48 kHz |
| MP3 | MPEG-1 Layer III, mono or stereo, 32, 44.1, or 48 kHz |
| Ogg | Stereo Vorbis, 44.1 or 48 kHz, within the bounded hardware setup limits |

High-resolution PCM, MPEG-2/2.5, Opus, and other Ogg codecs are outside this
profile. WAV playback accepts both native rates. A rate change restarts the
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

The BL616 owns filesystem and playlist handling. A standalone WAV is one stream
session; each VLC-style M3U/M3U8 entry is another independent session after the
preceding track reaches the player's hardware `COMPLETE` state. Playlist paths
are resolved against the playlist directory, so separately stored files do not
need a TAR wrapper. `#EXTINF` duration is metadata and never controls the audio
transition.

Future content detection will buffer and replay the bytes it inspects so every
selected decoder sees its file beginning at offset zero. Format selection is
based on contents rather than the filename extension.

## PCM boundary

Decoders produce signed 16-bit left and right samples with `valid/ready`, an
end-of-stream marker attached to the final sample, and a rate code. Mono MP3 is
duplicated into left and right at or before this boundary. The output path uses
native source rates; sample-rate conversion is not part of the default design.

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
from the diagnostic tones.

FIFO fullness stalls the WAV parser, which stalls the BL616 stream without
discarding or duplicating data. FIFO emptiness during active playback emits
zero for that sample and increments the underrun counter. Completion is
terminal until a new stream starts, preventing a retained EOF indication from
restarting an empty player.

## Diagnostics

The debug register bank reports the player state, format validity, detected
rate, FIFO level, played-sample count, underrun count, and parser error code.
The original stream byte count, offset, CRC, end, and cancel counters remain
observation-only and count only accepted bytes. See
[`debug-registers.md`](debug-registers.md) for the register ABI.

The deterministic 1 kHz left and 2 kHz right tones remain the idle and error
fallback at the selected native rate. Valid, prefetched PCM overrides them only
for the duration of active playback.
