# Tang-Phosphor on the Tang Console 138K — User Guide

This is a user-facing guide to developing, flashing, and controlling the
Tang-Phosphor core on a Sipeed **Tang Console 138K** (Gowin GW5AST-138 FPGA +
BL616 MCU). It assumes no familiarity with the internals.

---

## The two repos, in one line

- **Tang-Control** — the *firmware* (runs on the BL616) and its PC client
  (`tangctl.py`). It owns the SD card, the USB, the menu, and the two-wire
  control path.
- **Tang-Phosphor** — the *FPGA core* (music player + AE350/DDR3) and the
  tools that talk to the FPGA directly (one-wire path).

---

## The two cables / two modes

The board has two independent USB paths to two different chips. Everything
follows from this.

| Mode | Cable(s) | Talks to | What it can do |
|------|----------|----------|----------------|
| **One wire** | FT2232/OTG cable only | the **FPGA** (JTAG + UART) | flash a core, `peek`/`poke`/`stream` directly, run programs |
| **Two wire** | power + CDC cable | the **BL616** (USB CDC) | SD files, firmware update, core loading, relayed control |

- **One wire** bypasses the BL616 entirely, so it works no matter what the
  BL616 is running.
- **Two wire** goes through the BL616, so it **requires our Tang-Control
  firmware** (the stock nand2mario firmware has none of the tangctl console).

---

## Quick start

### 1. Flash a core (one wire)

Plug in **only the FT2232/OTG cable**, then:

```bash
# deployment core (Phosphor player, no AE350)
scripts/flash-otg.sh

# merged core (player + AE350 + DDR3, the MP3 build)
scripts/flash-otg.sh build/merged/place4/tang_phosphor_merged.fs
```

> **Always flash a `.fs` file, never a `.bin`.** openFPGALoader shifts a `.bin`
> into SRAM but cannot *start* the FPGA, so the board stays unconfigured (no
> signal, silent). The `.fs` flash stream starts it correctly.

### 2. Talk to the core

```bash
# one-wire: direct UART (no firmware needed)
python3 tools/fpga_uart.py peek 0        # expect 0x54504830 ("TPH0")

# two-wire: through the BL616 (needs our firmware + power + CDC cable)
python3 ../Tang-Control/scripts/tangctl.py peek 0
```

### 3. Run the MP3 demo (merged core, one wire)

```bash
python3 scripts/mp3_single_cable.py --tpi build/rbhost/bench/mp3play.tpi
```

Or, more generally, run any packaged AE350 program:

```bash
python3 tools/ae350_run.py --direct --base 0x4000 --cpu run <program.tpi>
```

---

## Two-wire commands (`tangctl.py`)

All of these need **two-wire** (power + CDC) and **our firmware**. Run from
the `Tang-Control` repo: `python3 scripts/tangctl.py <command>`.

| Command | What it does |
|---------|--------------|
| `ping` | verify the command channel |
| `status` | board + loader state |
| `rxstats [--reset]` | FPGA UART RX health counters |
| `caps` | FPGA transport capabilities *(needs Phosphor core)* |
| `peek <addr> [n]` | read debug register(s) *(needs Phosphor core)* |
| `poke <addr> <val>` | write a debug register *(needs Phosphor core)* |
| `baud <2\|5>` | switch FPGA UART rate *(needs Phosphor core)* |
| `stream <sd-path>` | stream an SD file to the active core |
| `bench [--size N]` | throughput benchmark |
| `put <local> <remote>` | upload a file to the SD card |
| `get <remote> <local>` | download a file from the SD card |
| `ls [path]` | list an SD directory |
| `rm <path>` | remove an SD file/directory |
| `mkdir <path>` | create an SD directory |
| `firmware <image>` | install a BL616 firmware image |

There is **no `rename`**; rename = `get` + `put` (new name) + `rm`.

---

## One-wire tools (Tang-Phosphor)

These talk to the FPGA directly and are **firmware-independent**.

| Tool | Purpose |
|------|---------|
| `scripts/flash-otg.sh [fs]` | flash via the FT2232 (fast, ~1 min) |
| `scripts/flash-pico.sh [fs]` | flash via a Pico 2 CMSIS-DAP probe (slow) |
| `tools/fpga_uart.py` | direct-UART transport (`peek`/`poke`/`stream`) |
| `tools/ae350_run.py --direct …` | load/run/status/restart AE350 programs |
| `scripts/mp3_single_cable.py` | one-purpose MP3 player |
| `scripts/uart_probe.py` | raw UART `listen`/`inject`/`contend` diagnostics |

### Pico 2 JTAG probe

The Pico 2 (`2e8a:000c`, CMSIS-DAP) works but has two limits:
- JTAG clock must stay **≤ 2 MHz** (4 MHz and up read garbage IDCODEs).
- Its bulk endpoint is only **64 bytes**, so a full flash takes ~10–20 minutes.

Use `scripts/flash-pico.sh` (or the FT2232 for routine flashing). The Pico's
real value is **GAO** (Gowin's internal logic analyzer) over the FPGA SOM
debug connector, not bulk flashing.

---

## Which commands need what

| Command(s) | Cable | Firmware | Phosphor core |
|------------|-------|----------|---------------|
| `flash-otg.sh` / `flash-pico.sh` | 1-wire | not needed | not needed |
| `fpga_uart.py`, `uart_probe.py`, `mp3_single_cable.py` | 1-wire | not needed | yes |
| `ae350_run.py --direct` | 1-wire | not needed | merged core |
| `ping`/`status`/`rxstats`/`ls`/`get`/`put`/`rm`/`mkdir`/`firmware`/`stream`/`bench` | 2-wire | our firmware | no |
| `caps`/`peek`/`poke`/`baud` | 2-wire | our firmware | yes |

---

## Common gotchas

1. **`.bin` vs `.fs`** — always flash `.fs`. A `.bin` loads but never starts
   the FPGA.
2. **Two-wire needs our firmware** — the stock nand2mario firmware has no
   tangctl console. Flash the Tang-Control `feature/usb-cdc-file-transfer`
   image first.
3. **`caps`/`peek`/`poke`/`baud` need a Phosphor core loaded** — they speak the
   extended debug protocol (`0x10`), which only the Phosphor core implements.
   The stock menu/game cores don't answer it.
4. **One wire doesn't power the SD/DDR3 rails** — the menu shows no cores and
   the merged (DDR3) core won't come up on FT2232 power alone; add the power
   cable for those.
5. **Stream speed** — two-wire (USB CDC) is ~4× faster than one-wire (2 Mbaud
   UART) for bulk data.

---

## Repos

- Core + one-wire tools: **this repo** (`Tang-Phosphor`)
- Firmware + two-wire client: **Tang-Control** (sibling, `feature/usb-cdc-file-transfer`)
