# Parked rbhost changes

Changes that work but are not built into the resident player yet.

## 0001-play-while-decoding.patch

Plays decoded PCM as the codec writes it, instead of decoding the whole track
into DDR3 and playing it afterwards, so a song starts as soon as its file has
been sent rather than after a full decode (about 18 s sooner for a 3.2 MB MP3).
It removes the 256 MB output limit while playing, and the player's CRC result
reads 0 past it.  Apply with `git apply` from the repository root.

It is parked because resident players built from changed code intermittently
fail to start a track on hardware -- the AE350 receives the file and never
decodes -- while the qualified player in use has not failed.  Builds that
played in one session failed in another, including straight after a power
cycle, so a passing bench test does not qualify a build.  See core-log
entry 73 and the core-reference record on resident player start failures.
