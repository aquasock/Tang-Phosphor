#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d /tmp/tang-phosphor-variants.XXXXXX)"
summary_file="$work_dir/variant-summary.tsv"

cleanup() {
    find "$work_dir" -depth -delete
}
trap cleanup EXIT

if ! command -v rsync >/dev/null 2>&1; then
    echo "rsync is required for isolated parallel builds." >&2
    exit 1
fi

mkdir -p "$work_dir/logs"
for variant in 0 1 2 3; do
    mkdir "$work_dir/p$variant"
    rsync -a --exclude=.git --exclude=impl \
        "$project_dir/" "$work_dir/p$variant/"
done

# An optional four-entry list pins each independent Gowin process to a CPU,
# for example: GOWIN_VARIANT_CPUS="0 2 8 10" scripts/build-variants.sh
read -r -a variant_cpus <<< "${GOWIN_VARIANT_CPUS:-}"
declare -a build_pids
declare -a build_status

for variant in 0 1 2 3; do
    (
        cd "$work_dir/p$variant"
        if [[ ${#variant_cpus[@]} -eq 4 ]] && command -v taskset >/dev/null 2>&1; then
            GOWIN_PLACE_OPTION="$variant" \
                taskset --cpu-list "${variant_cpus[$variant]}" ./scripts/build.sh
        else
            GOWIN_PLACE_OPTION="$variant" ./scripts/build.sh
        fi
    ) >"$work_dir/logs/option-$variant.log" 2>&1 &
    build_pids[$variant]=$!
    echo "Started Gowin placement option $variant (PID ${build_pids[$variant]})"
done

for variant in 0 1 2 3; do
    if wait "${build_pids[$variant]}"; then
        build_status[$variant]=0
        echo "Placement option $variant completed"
    else
        build_status[$variant]=$?
        echo "Placement option $variant failed with status ${build_status[$variant]}" >&2
    fi
done

html_value_after_label() {
    local report=$1
    local label=$2
    awk -v label="$label" '
        index($0, label) {
            getline
            gsub(/<[^>]*>/, "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            print
            exit
        }
    ' "$report"
}

slack_value() {
    local report=$1
    local anchor=$2
    awk -v anchor="$anchor" '
        index($0, anchor) { in_table = 1 }
        in_table && $0 == "<td>1</td>" {
            getline
            gsub(/<[^>]*>/, "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            print
            exit
        }
    ' "$report"
}

pixel_fmax() {
    local report=$1
    awk '
        /Max Frequency Summary/ { in_table = 1 }
        in_table && /clock_hdmi\/PLL_inst\/CLKOUT0.default_gen_clk/ {
            getline
            getline
            gsub(/<[^>]*>/, "")
            gsub(/\(MHz\)/, "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            print
            exit
        }
    ' "$report"
}

resource_value() {
    local report=$1
    local label=$2
    awk -F '|' -v label="$label" '
        {
            name = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
            if (name == label) {
                value = $2
                split(value, fields, "/")
                gsub(/[[:space:]]/, "", fields[1])
                print fields[1]
                exit
            }
        }
    ' "$report"
}

elapsed_value() {
    local report=$1
    local label=$2
    sed -nE "s/.*${label}:.*Elapsed time = 0h 0m ([0-9.]+)s.*/\\1/p" "$report"
}

printf 'option\tstatus\tlogic\tregisters\tcls\tbsram\tdsp\tplacement_s\trouting_s\tpnr_s\tpixel_fmax_mhz\tsetup_slack_ns\thold_slack_ns\tsetup_violations\thold_violations\n' \
    >"$summary_file"

best_variant=""
best_setup=""
best_fmax=""

for variant in 0 1 2 3; do
    pnr_report="$work_dir/p$variant/impl/pnr/tang_phosphor_console138k.rpt.txt"
    timing_report="$work_dir/p$variant/impl/pnr/tang_phosphor_console138k_tr_content.html"

    if [[ ${build_status[$variant]} -ne 0 || ! -f "$pnr_report" || ! -f "$timing_report" ]]; then
        printf '%s\tFAIL\n' "$variant" >>"$summary_file"
        continue
    fi

    logic="$(resource_value "$pnr_report" Logic)"
    registers="$(resource_value "$pnr_report" Register)"
    cls="$(resource_value "$pnr_report" CLS)"
    bsram="$(resource_value "$pnr_report" BSRAM)"
    dsp="$(resource_value "$pnr_report" DSP)"
    placement="$(elapsed_value "$pnr_report" 'Total Placement')"
    routing="$(elapsed_value "$pnr_report" 'Total Routing')"
    pnr="$(elapsed_value "$pnr_report" 'Total Time and Memory Usage')"
    fmax="$(pixel_fmax "$timing_report")"
    setup="$(slack_value "$timing_report" 'Setup_Slack_Table')"
    hold="$(slack_value "$timing_report" 'Hold_Slack_Table')"
    setup_violations="$(html_value_after_label "$timing_report" 'Numbers of Setup Violated Endpoints')"
    hold_violations="$(html_value_after_label "$timing_report" 'Numbers of Hold Violated Endpoints')"

    status=PASS
    if [[ "$setup_violations" != 0 || "$hold_violations" != 0 ]]; then
        status=TIMING_FAIL
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$variant" "$status" "$logic" "$registers" "$cls" "$bsram" "$dsp" \
        "$placement" "$routing" "$pnr" "$fmax" "$setup" "$hold" \
        "$setup_violations" "$hold_violations" >>"$summary_file"

    if [[ "$status" == PASS ]] && {
        [[ -z "$best_variant" ]] ||
        awk -v candidate="$setup" -v best="$best_setup" \
            'BEGIN { exit !(candidate > best) }' ||
        { [[ "$setup" == "$best_setup" ]] &&
          awk -v candidate="$fmax" -v best="$best_fmax" \
              'BEGIN { exit !(candidate > best) }'; }
    }; then
        best_variant=$variant
        best_setup=$setup
        best_fmax=$fmax
    fi
done

column -t -s $'\t' "$summary_file" 2>/dev/null || cat "$summary_file"

if [[ -z "$best_variant" ]]; then
    echo "No placement option completed with clean timing; no artifact selected." >&2
    exit 1
fi

# Make the selected option the ordinary deployment artifact, then retain the
# compact comparison evidence alongside it.
mkdir -p "$project_dir/impl"
rsync -a --delete "$work_dir/p$best_variant/impl/" "$project_dir/impl/"
mkdir -p "$project_dir/impl/variant-reports"
cp "$summary_file" "$project_dir/impl/variant-summary.tsv"
for variant in 0 1 2 3; do
    mkdir -p "$project_dir/impl/variant-reports/option-$variant"
    cp "$work_dir/logs/option-$variant.log" \
        "$project_dir/impl/variant-reports/option-$variant/build.log"
    if [[ -f "$work_dir/p$variant/impl/pnr/tang_phosphor_console138k.rpt.txt" ]]; then
        cp "$work_dir/p$variant/impl/pnr/tang_phosphor_console138k.rpt.txt" \
            "$project_dir/impl/variant-reports/option-$variant/pnr.rpt.txt"
    fi
    if [[ -f "$work_dir/p$variant/impl/pnr/tang_phosphor_console138k_tr_content.html" ]]; then
        cp "$work_dir/p$variant/impl/pnr/tang_phosphor_console138k_tr_content.html" \
            "$project_dir/impl/variant-reports/option-$variant/timing.html"
    fi
done

echo "Selected placement option $best_variant: setup slack ${best_setup} ns, pixel Fmax ${best_fmax} MHz"
echo "Deployment artifact: $project_dir/impl/pnr/tang_phosphor_console138k.bin"
