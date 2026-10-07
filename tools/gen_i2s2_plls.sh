#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Regenerate the I2S2 revision-C PLL wrappers from the committed recipes.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$(realpath -m "${1:-$project_dir/build/i2s2-plls}")"
gowin_sh_path="${GOWIN_SH:-$(command -v gw_sh || true)}"
if [[ -z "$gowin_sh_path" ]]; then
    for candidate in /home/vash/tools/gowin-1.9.11.03/IDE/bin/gw_sh \
        /opt/Gowin/Gowin_V1.9.11.03/IDE/bin/gw_sh; do
        if [[ -x "$candidate" ]]; then
            gowin_sh_path="$candidate"
            break
        fi
    done
fi
if [[ -z "$gowin_sh_path" || ! -x "$(dirname -- "$gowin_sh_path")/GowinModGen" ]]; then
    echo "GowinModGen not found; set GOWIN_SH to the gw_sh path" >&2
    exit 1
fi
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
mkdir -p "$out_dir"
for name in pll_i2s2_ref pll_i2s2_audio; do
    python3 - "$project_dir/src/pll/$name.mod" "$out_dir/$name.mod" "$out_dir" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[2]).write_text(Path(sys.argv[1]).read_text().replace('@OUTPUT_DIR@', sys.argv[3]))
PY
    (cd "$out_dir" && "$(dirname -- "$gowin_sh_path")/GowinModGen" -do "$name.mod")
    # Keep the vendor attribution; drop only the varying generation timestamp.
    sed -i '/^\/\/Created Time:/d' "$out_dir/$name.v"
done
echo "Generated I2S2 PLL wrappers in $out_dir"
