#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d /tmp/tang-phosphor-ae350.XXXXXX)"
gowin_sh_path="${GOWIN_SH:-}"

cleanup() {
    find "$work_dir" -depth -delete
}
trap cleanup EXIT

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

if ! command -v rsync >/dev/null 2>&1; then
    echo "rsync is required for the isolated AE350 build." >&2
    exit 1
fi

rsync -a --exclude=.git --exclude=impl --exclude=build \
    "$project_dir/" "$work_dir/"

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
system_freetype=/usr/lib/x86_64-linux-gnu/libfreetype.so.6
if [[ -f "$system_freetype" ]]; then
    export LD_PRELOAD="$system_freetype${LD_PRELOAD:+:$LD_PRELOAD}"
fi

(
    cd "$work_dir"
    "$gowin_sh_path" build-ae350-smoke.tcl
)

artifact_dir="$project_dir/build/ae350-smoke"
mkdir -p "$artifact_dir"
cp --remove-destination "$work_dir/impl/pnr/tang_phosphor_ae350_smoke.bin" "$artifact_dir/"
cp --remove-destination "$work_dir/impl/pnr/tang_phosphor_ae350_smoke.rpt.txt" "$artifact_dir/"
cp --remove-destination "$work_dir/impl/pnr/tang_phosphor_ae350_smoke_tr_content.html" "$artifact_dir/"
chmod 0644 "$artifact_dir"/*

echo "AE350 smoke artifact: $artifact_dir/tang_phosphor_ae350_smoke.bin"
