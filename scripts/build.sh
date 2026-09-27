#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
gowin_sh_path="${GOWIN_SH:-}"

if [[ -z "$gowin_sh_path" ]]; then
    gowin_sh_path="$(command -v gw_sh || true)"
fi

if [[ -z "$gowin_sh_path" ]]; then
    for candidate in \
        /home/vash/tools/gowin-1.9.11.03/IDE/bin/gw_sh \
        /opt/Gowin/Gowin_V1.9.11.03/IDE/bin/gw_sh
    do
        if [[ -x "$candidate" ]]; then
            gowin_sh_path="$candidate"
            break
        fi
    done
fi

if [[ -z "$gowin_sh_path" || ! -x "$gowin_sh_path" ]]; then
    echo "Gowin gw_sh not found; set GOWIN_SH to its full path." >&2
    exit 1
fi

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

system_freetype=/usr/lib/x86_64-linux-gnu/libfreetype.so.6
if [[ -f "$system_freetype" ]]; then
    export LD_PRELOAD="$system_freetype${LD_PRELOAD:+:$LD_PRELOAD}"
fi

cd "$project_dir"
exec "$gowin_sh_path" build.tcl
