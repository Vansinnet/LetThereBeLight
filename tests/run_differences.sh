#!/usr/bin/env bash
# Checks deliberate differences 1, 2 and 6 (DESIGN.md) and that Toxic Gas stays unchanged on real circumstance templates: the pre-rewrite mod
# shows the old behavior, this working tree the new one.
# Usage: tests/run_differences.sh   (BASELINE, OLD_MOD and NEW_MOD as in run_parity.sh)
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"
luajit="${LUAJIT:-}"; [[ -n "$luajit" ]] || { [[ -x "$root/tools/luajit/luajit" ]] && luajit="$root/tools/luajit/luajit" || luajit=luajit; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
baseline="${BASELINE:-96866fa}"
old_mod="${OLD_MOD:-$tmp/baseline}"
[[ -n "${OLD_MOD:-}" ]] || { mkdir -p "$old_mod" && git -C "$here/.." archive "$baseline" | tar -x -C "$old_mod"; } || { echo "cannot extract baseline $baseline"; exit 1; }
new_mod="${NEW_MOD:-$here/..}"
fails=0; tab=$'\t'
SEED=7

run() { # scenario circumstance settings
    "$luajit" "$here/parity_sim.lua" "$root" "$old_mod" LetThereBeLight "$SEED" "$2" "$3" > "$tmp/$1.old" 2>/dev/null || { echo "$1: old crashed"; fails=$((fails + 1)); }
    "$luajit" "$here/parity_sim.lua" "$root" "$new_mod" LetThereBeLight "$SEED" "$2" "$3" > "$tmp/$1.new" 2>/dev/null || { echo "$1: new crashed"; fails=$((fails + 1)); }
}

expect() { # scenario old|new has|lacks pattern description
    local file="$tmp/$1.$2"
    if [[ "$3" == has ]] && ! grep -q -- "$4" "$file"; then echo "$1 ($2): missing $5"; fails=$((fails + 1)); fi
    if [[ "$3" == lacks ]] && grep -q -- "$4" "$file"; then echo "$1 ($2): unexpected $5"; fails=$((fails + 1)); fi
}

lights_off() { grep -c "^light${tab}unit_[0-9]*${tab}false$" "$tmp/$1.$2"; }

# 1. Darkness LOS mutator with the default theme: the rewrite leaves the mission alone.
run stealth stealth_01 "chat_notification=true,power_interruption_mode=normal_environment"
expect stealth old has "^echo${tab}Let There Be Light: Darkness visuals removed" "darkness message"
expect stealth old has "^camera_environment${tab}nil" "removed theme environment"
expect stealth new lacks "^echo" "chat message"
expect stealth new has "^camera_environment${tab}theme_environment" "kept theme environment"
[[ $(lights_off stealth old) -eq 0 && $(lights_off stealth new) -gt 0 ]] || { echo "stealth: lights should be forced only by the old mod"; fails=$((fails + 1)); }

# 2. Dawn expedition with the darkness LOS mutator: only the Dawn option decides.
run dawn_off exps_dawn_au "chat_notification=true,power_interruption_mode=lights_on,normalize_dawn=false"
expect dawn_off old has "^echo${tab}Let There Be Light: Darkness mission lights enabled" "darkness message"
expect dawn_off new lacks "^echo" "chat message"
expect dawn_off new has "^camera_environment${tab}theme_environment" "kept Dawn environment"
[[ $(lights_off dawn_off old) -eq 0 && $(lights_off dawn_off new) -gt 0 ]] || { echo "dawn_off: lights should be forced only by the old mod"; fails=$((fails + 1)); }
run dawn_on exps_dawn_au "chat_notification=true,power_interruption_mode=lights_on,normalize_dawn=true"
expect dawn_on old has "^echo${tab}Let There Be Light: Darkness mission lights enabled" "darkness message"
expect dawn_on new has "^echo${tab}Let There Be Light: Dawn replaced with standard environment" "Dawn message"
expect dawn_on new has "^camera_environment${tab}nil" "removed Dawn environment"

# Toxic Gas is never changed: its environment shows where the gas starts (user decision 2026-10-24).
run gas toxic_gas_01 "chat_notification=true"
cmp -s "$tmp/gas.old" "$tmp/gas.new" || { echo "gas: old and new differ"; diff "$tmp/gas.old" "$tmp/gas.new" | head -5; fails=$((fails + 1)); }
expect gas new has "^camera_environment${tab}theme_environment" "kept Toxic Gas environment"

# 6. Inferno audio state: reset to the default only while the Inferno option is on.
run sound_on ember_01 "normalize_inferno=true"
expect sound_on old has "^wwise_state${tab}ember_01$" "Inferno audio state"
expect sound_on new has "^wwise_state${tab}None$" "default audio state"
run sound_hunt ember_01_hunt_grou "normalize_inferno=true"
expect sound_hunt new has "^wwise_state${tab}None$" "default audio state"
expect sound_hunt new has "^wwise_event${tab}wwise/events/world/play_hunting_grounds_occasionals$" "Hunting Grounds sounds"
run sound_off ember_01 "normalize_inferno=false"
cmp -s "$tmp/sound_off.old" "$tmp/sound_off.new" || { echo "sound_off: old and new differ"; diff "$tmp/sound_off.old" "$tmp/sound_off.new" | head -5; fails=$((fails + 1)); }

echo "differences: $fails failing"
[[ $fails -eq 0 ]]
