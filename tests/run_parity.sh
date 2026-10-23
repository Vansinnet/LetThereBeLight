#!/usr/bin/env bash
# Differential run: the pre-rewrite Let There Be Light (git BASELINE, default 96866fa) against this
# working tree, same seeded missions. Usage: tests/run_parity.sh [FIRST_SEED] [LAST_SEED]   (default 1 300)
# OLD_MOD and NEW_MOD override the mod folders. parity_sim.lua filters the deliberate differences
# (DESIGN.md); tests/run_differences.sh checks them.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"
luajit="${LUAJIT:-}"; [[ -n "$luajit" ]] || { [[ -x "$root/tools/luajit/luajit" ]] && luajit="$root/tools/luajit/luajit" || luajit=luajit; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
baseline="${BASELINE:-96866fa}"
old_mod="${OLD_MOD:-$tmp/baseline}"
[[ -n "${OLD_MOD:-}" ]] || { mkdir -p "$old_mod" && git -C "$here/.." archive "$baseline" | tar -x -C "$old_mod"; } || { echo "cannot extract baseline $baseline"; exit 1; }
new_mod="${NEW_MOD:-$here/..}"
first="${1:-1}"; last="${2:-300}"; fails=0
echo "darktide-source: $(git -C "$root/darktide-source" log -1 --format=%s); baseline: ${OLD_MOD:-$baseline}"
for seed in $(seq "$first" "$last"); do
    "$luajit" "$here/parity_sim.lua" "$root" "$old_mod" LetThereBeLight "$seed" > "$tmp/old.txt" 2> "$tmp/old.err" || { echo "seed $seed: old crashed"; tail -3 "$tmp/old.err"; fails=$((fails + 1)); continue; }
    "$luajit" "$here/parity_sim.lua" "$root" "$new_mod" LetThereBeLight "$seed" > "$tmp/new.txt" 2> "$tmp/new.err" || { echo "seed $seed: new crashed"; tail -3 "$tmp/new.err"; fails=$((fails + 1)); continue; }
    if ! cmp -s "$tmp/old.txt" "$tmp/new.txt"; then
        echo "seed $seed: DIFF"; diff "$tmp/old.txt" "$tmp/new.txt" | head -10; fails=$((fails + 1))
    fi
    cat "$tmp/old.err" >> "$tmp/old_counts.txt"; cat "$tmp/new.err" >> "$tmp/new_counts.txt"
done
summarize() { awk '{ total[$1] += $2 } END { for (name in total) printf "  %s %d\n", name, total[name] }' "$1" | sort; }
echo "hook handler calls, old:"; summarize "$tmp/old_counts.txt"
echo "hook handler calls, new:"; summarize "$tmp/new_counts.txt"
echo "seeds $first-$last: $fails failing"
[[ $fails -eq 0 ]]
