# Tang-Phosphor Standards Reference

This file records the external standards and primary technical references used
for implementation decisions. A reference entry does not expand the project's
supported profile. Project-specific limits remain implementation limits.

---

## HDMI Audio Transport

### HDMI 1.4/2.0 Transmitter Subsystem Product Guide (AMD PG235)

- Source: https://docs.amd.com/r/en-US/pg235-v-hdmi-tx-ss/Audio-Clock-Regeneration-Interface
- Authority: AMD primary documentation for its standards-based HDMI transmitter subsystem.
- Relevant rule: Audio Clock Regeneration uses 20-bit `CTS` and `N` values, and a transmitter consumes them only when both are stable.
- Tang-Phosphor use: Change the selected rate atomically, restart the measurement interval, and do not emit a new-rate ACR event until its matching `CTS` measurement is complete.

### HDMI Audio Pipeline (AMD UG1442)

- Source: https://docs.amd.com/r/en-US/ug1442-vck190-base-trd/HDMI-Audio-Pipeline
- Authority: AMD primary reference-design documentation.
- Relevant rule: The transmit-side ACR controller calculates `CTS` by counting transmit TMDS clock cycles for a defined audio-clock interval.
- Tang-Phosphor use: The HDMI packetizer measures pixel/TMDS-clock cycles across `N / 128` audio samples instead of relying on an unrelated fixed delay.

### Local HDMI packetizer provenance

- Source: `src/hdmi/audio_clock_regeneration_packet.sv`, `src/hdmi/audio_sample_packet.sv`, and `src/hdmi/packet_picker.sv`.
- Authority: Implementation reference derived from Sameer Puri's HDMI 1.4a transmitter; not a substitute for the HDMI specification.
- Relevant behavior: The existing ACR algorithm selects `N = 6272` for 44.1 kHz and `N = 6144` for 48 kHz, counts `N / 128` audio samples, and encodes the rate in IEC 60958 channel status.
- Tang-Phosphor use: Preserve that proven packet layout while making the bounded 44.1/48 kHz selection runtime-controlled and resetting partial measurements at a rate transition.

---

## IEC Consumer PCM Channel Status

### IEC 60958-3:2021

- Source: https://webstore.iec.ch/en/publication/71069
- Authority: Current IEC international standard for consumer applications of the IEC 60958 digital audio interface.
- Relevant scope: Consumer PCM channel-status representation used inside HDMI Audio Sample packets.
- Access note: The normative field tables are licensed material and are not reproduced in this repository. The local packetizer's existing 44.1 kHz code `0000` and 48 kHz code `0010` remain implementation mappings pending direct verification against a licensed copy if conformance questions arise.

---
