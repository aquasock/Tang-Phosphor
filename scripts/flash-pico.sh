#!/usr/bin/env bash
# Flash the Tang-Phosphor core over a Raspberry Pi Pico 2 running CMSIS-DAP
# (the "JTAG probe on Pico" firmware), wired to the FPGA SOM's debug connector.
#
# The Pico's CMSIS-DAP bit-bangs JTAG and its bulk endpoint is only 64 bytes,
# so it is far slower than the FT2232 OTG cable, and its JTAG clock must stay
# at or below 2 MHz (4 MHz and up read garbage IDCODEs). A full bitstream takes
# roughly 10-20 minutes. For routine flashing prefer scripts/flash-otg.sh; this
# script is for when only the Pico debug connector is available (or for
# GAO-style JTAG access).
#
# Usage:
#   scripts/flash-pico.sh                 # flash the default build artifact
#   scripts/flash-pico.sh path/to/foo.fs  # flash a specific bitstream
#
# Environment:
#   PICO_VID / PICO_PID   override the probe's USB VID/PID (default 2e8a:000c)
#   PICO_FREQ             JTAG frequency in Hz (default 2000000, max 2 MHz)
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fs="${1:-$project_dir/impl/pnr/tang_phosphor_console138k.fs}"

# Gowin's IDE environment breaks openFPGALoader (libbz2.so.1 and friends).
# Drop it so the flash works from any shell, even one that sourced the IDE env.
unset LD_LIBRARY_PATH LD_PRELOAD QT_QPA_PLATFORM 2>/dev/null || true

oss_cad="${OSS_CAD_SUITE:-/home/vash/tools/oss-cad-suite-20260925}"
export PATH="$oss_cad/bin:$PATH"

if ! command -v openFPGALoader >/dev/null 2>&1; then
    echo "error: openFPGALoader not found; set OSS_CAD_SUITE to your oss-cad-suite" >&2
    exit 1
fi

if [[ ! -f "$fs" ]]; then
    echo "error: bitstream not found: $fs" >&2
    echo "       build it first: scripts/build.sh (or scripts/build-variants.sh)" >&2
    exit 1
fi

if [[ "$fs" == *.bin ]]; then
    echo "error: $fs is a raw .bin bitstream." >&2
    echo "       openFPGALoader shifts a .bin into SRAM but cannot START the FPGA," >&2
    echo "       so the board stays unconfigured (no signal). Flash a .fs instead." >&2
    exit 1
fi

pico_vid="${PICO_VID:-0x2e8a}"
pico_pid="${PICO_PID:-0x000c}"
pico_freq="${PICO_FREQ:-2000000}"

echo "Flashing $fs over the Pico CMSIS-DAP probe ($pico_vid:$pico_pid @ ${pico_freq} Hz) ..."
echo "(slow: the Pico bit-bangs JTAG at <= 2 MHz with 64-byte packets)"
openFPGALoader -c cmsisdap --vid "$pico_vid" --pid "$pico_pid" \
    -b tangmega138k --freq "$pico_freq" "$fs"

echo "Done. Power-cycle the board to return to tangcore."
