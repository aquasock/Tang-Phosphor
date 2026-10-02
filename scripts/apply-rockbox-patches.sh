#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Apply the local patches this project carries for the Rockbox submodule.
#
# The patches live in third_party/patches/ and are recorded in THIRD_PARTY.md.
# A `git submodule update` reverts them, so this script is run before any
# Rockbox source is compiled (see software/rbhost/Makefile) and is idempotent:
# an already-applied patch is reported and skipped.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
submodule="$root/third_party/rockbox"
patch_dir="$root/third_party/patches"

if [[ ! -d "$submodule/.git" && ! -f "$submodule/.git" ]]; then
    echo "apply-rockbox-patches: $submodule is not a checkout" >&2
    exit 1
fi

shopt -s nullglob
patches=("$patch_dir"/*.patch)
shopt -u nullglob

for patch in "${patches[@]}"; do
    name="$(basename "$patch")"
    if git -C "$submodule" apply --reverse --check "$patch" >/dev/null 2>&1; then
        echo "apply-rockbox-patches: $name already applied"
    elif git -C "$submodule" apply --check "$patch" >/dev/null 2>&1; then
        git -C "$submodule" apply "$patch"
        echo "apply-rockbox-patches: applied $name"
    else
        echo "apply-rockbox-patches: $name does not apply cleanly" >&2
        exit 1
    fi
done

exit 0
