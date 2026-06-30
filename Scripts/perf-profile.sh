#!/usr/bin/env bash
# Headless performance probe for the macOS app. Launches a built Donpa with a
# `-perf-scenario` hook (see PerfScenario.swift) into a known heavy state, then
# measures it two ways:
#   1. CPU% over a fixed window (mean/peak) — the regression number, from `ps`.
#   2. A Time Profiler .trace via `xctrace` — the call-tree, for diagnosis.
#
# No UI automation: the launch arg puts the app into the scenario itself, so this
# runs unattended and targets macOS (where the big-board CPU issues actually show).
#
# Usage: perf-profile.sh [scenario] [seconds]
#   scenario : perf scenario name (default: xxxl-opened)
#   seconds  : measurement window after a warm-up (default: 20)
#
# Requires a Debug build present (run `make build-mac` first). Writes the trace +
# a summary under perf-out/.
set -euo pipefail
cd "$(dirname "$0")/.."

scenario="${1:-xxxl-opened}"
window="${2:-20}"
warmup=5   # let the scenario settle (reveal floods, view mounts) before measuring

app="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type d -name "Donpa Squad.app" \
    -path "*/Build/Products/Debug/*" -not -path "*/Index.noindex/*" 2>/dev/null | head -1)"
[ -n "$app" ] || { echo "error: no Debug 'Donpa Squad.app' found — run 'make build-mac' first." >&2; exit 1; }
bin="$app/Contents/MacOS/Donpa Squad"
[ -x "$bin" ] || { echo "error: binary not found at $bin" >&2; exit 1; }

mkdir -p perf-out
stamp="$(date +%Y%m%d-%H%M%S)"
trace="perf-out/${scenario}-${stamp}.trace"
summary="perf-out/${scenario}-${stamp}.txt"

echo "▶︎ scenario=${scenario}  window=${window}s  warmup=${warmup}s"
echo "▶︎ binary: ${bin}"

# Kill any stale instance so we measure a clean launch.
pkill -f "Donpa Squad" 2>/dev/null || true
sleep 1

# Launch the EXACT Debug binary ourselves (xctrace's --launch matches by app name,
# which is ambiguous when an installed /Applications copy also exists). We own the
# pid, so the trace attaches and the CPU sampler reads the same process.
echo "▶︎ launching the scenario…"
"$bin" -perf-scenario "$scenario" -uitest-clean >/dev/null 2>&1 &
app_pid=$!
sleep "$warmup"   # settle: reveal floods, view mounts

if ! kill -0 "$app_pid" 2>/dev/null; then
    echo "error: app exited during warm-up — scenario launch failed." >&2
    exit 1
fi

# ── Record a Time Profiler trace by attaching to our process ───────────────────
total="$window"
echo "▶︎ recording Time Profiler trace (attach pid ${app_pid}) for ${total}s…"
xcrun xctrace record \
    --template 'Time Profiler' \
    --time-limit "${total}s" \
    --output "$trace" \
    --attach "$app_pid" \
    >/dev/null 2>&1 &
xctrace_pid=$!

# ── Meanwhile, sample the app's CPU% over the same window ──────────────────────
echo "▶︎ sampling CPU of pid ${app_pid} every 1s for ${window}s…"
cpu_samples=()
for _ in $(seq 1 "$window"); do
    kill -0 "$app_pid" 2>/dev/null || break
    c="$(ps -o %cpu= -p "$app_pid" | xargs)"
    [ -n "$c" ] && cpu_samples+=("$c")
    sleep 1
done

wait "$xctrace_pid" 2>/dev/null || true
kill "$app_pid" 2>/dev/null || true
pkill -f "Donpa Squad" 2>/dev/null || true

# The -uitest-clean launch leaves an ephemeral save dir behind each run; tidy them.
find /var/folders -maxdepth 4 -type d -name "donpa-uitest-*" -exec rm -rf {} + 2>/dev/null || true

# ── Summarize ─────────────────────────────────────────────────────────────────
{
    echo "Donpa perf probe — ${scenario} — ${stamp}"
    echo "window=${window}s warmup=${warmup}s  binary=Debug"
    echo
    if [ "${#cpu_samples[@]}" -gt 0 ]; then
        printf '%s\n' "${cpu_samples[@]}" | awk '
            { sum += $1; n++; if ($1 > max) max = $1 }
            END {
                printf "CPU%% over %d samples: mean=%.1f  peak=%.1f\n", n, sum/n, max
            }'
        echo "raw: ${cpu_samples[*]}"
    else
        echo "CPU%: (no samples)"
    fi
    echo
    echo "Trace: ${trace}"
    echo "  open in Instruments:  open '${trace}'"
    echo "  heaviest symbols:     Scripts/perf-profile.sh prints the trace TOC below"
} | tee "$summary"

echo
echo "▶︎ trace table of contents (schemas available to export):"
xcrun xctrace export --input "$trace" --toc 2>/dev/null | grep -iE "schema|table" | head -20 || true
echo
echo "✓ wrote ${summary} and ${trace}"
