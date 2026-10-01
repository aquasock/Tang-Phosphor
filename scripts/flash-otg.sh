#!/usr/bin/env bash
# Flash the Tang-Phosphor core to a Tang Console 138K over the single OTG cable.
#
# The Console 138K's OTG port is an FT2232 bridge: it carries board power,
# JTAG (used here), and a UART. This is an SRAM load - volatile - and the
# BL616 re-takes the FPGA on the next power cycle.
#
# Usage:
#   scripts/flash-otg.sh                 # flash the default build artifact
#   scripts/flash-otg.sh path/to/foo.fs  # flash a specific bitstream
#
# Build the bitstream first with scripts/build.sh or scripts/build-variants.sh.
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fs="${1:-$project_dir/impl/pnr/tang_phosphor_console138k.fs}"

# Gowin's IDE environment breaks openFPGALoader (libbz2.so.1 and friends).
# Drop it so the flash works from any shell, even one that sourced the IDE env.
unset LD_LIBRARY_PATH LD_PRELOAD QT_QPA_PLATFORM 2>/dev/null || true

# openFPGALoader ships with oss-cad-suite. Override OSS_CAD_SUITE if yours is
# installed elsewhere.
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
    echo "       so the board stays unconfigured (no signal). Flash a .fs instead:" >&2
    echo "         deployment: impl/pnr/tang_phosphor_console138k.fs" >&2
    echo "         merged:     build/merged/place<N>/tang_phosphor_merged.fs" >&2
    exit 1
fi

echo "Flashing $fs over the OTG cable (power + JTAG via the FT2232) ..."
# 'tangmega138k' is the correct board id for the Console 138K's GW5AST-138.
# If you have several FTDI devices attached and auto-detection picks the wrong
# one, add the FT2232's serial:  openFPGALoader -c ft2232 --usb-serial <...>
openFPGALoader -b tangmega138k "$fs"

echo "Done. Power-cycle the board to return to tangcore."
