# LetThereBeLight offline tests

Development only: releases take just the `.mod`, `scripts/`, README and LICENSE, and `tools\validate.ps1` skips this folder. Run from any directory with bash (Git Bash, WSL, Linux); the scripts use `LUAJIT`, then `tools/luajit/luajit`, then `luajit` on `PATH`. The old side is extracted from git (`BASELINE`, default `96866fa`, the last commit before the rewrite); `OLD_MOD` and `NEW_MOD` point the scripts at other folders instead.

| Command | What it checks | Last result |
|---|---|---|
| `tests/run_parity.sh [first] [last]` | `parity_sim.lua` runs the baseline and the working tree through the same seeded missions built from the real circumstance templates and Havoc themes, each theme picked equally often. It compares the full trace: chat messages, every light state, theme shading environment, particles created and destroyed, `particle_effect_component_init` and other flow events, weather selection, the circumstance audio state, and mid-mission setting changes. Deliberate differences 1, 2 and 6 are filtered (DESIGN.md). Hook-handler call counts go to stderr. | 2026-10-24, game source 1.13.3: seeds 1-300, 0 differences, 67-102 missions per theme; old 22,639 `Unit.flow_event` handler calls, new 0. `BASELINE=c988972` (before the Inferno theme-unit fix): 2 of seeds 1-40 differ. |
| `tests/run_differences.sh` | Deliberate differences 1, 2 and 6 on real templates: `stealth_01` and `exps_dawn_au` (LOS mutator without its theme) and the Inferno audio state on `ember_01` and `ember_01_hunt_grou`; also that `toxic_gas_01` stays exactly as in the old mod. The baseline must show the old behavior, the working tree the new one. | 2026-10-24: 0 failing; against `525c228` (before the audio reset): 2 failing. |

Real game code: circumstance templates, Havoc settings, `ParticleEffect`, `LightControllerExtension`, `WeatherExtension`, `WeatherSystem` and `WwiseStateGroupCircumstance` from `darktide-source/`. Mocked: DMF (hooks, settings with widget defaults, localization, echo), engine natives, the managers, `CameraHandler`, `ShadingEnvironmentSystem` and the extension-units init step, whose hooked methods only return or record. Mod enable state is constant within a mission.

Results are offline evidence, not in-game results.
