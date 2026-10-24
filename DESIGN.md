# LetThereBeLight: design

Status 2026-10-24: unreleased rewrite after 1.2.1, ModID `LetThereBeLight`. Verified: static (`tools\validate.ps1`) and offline (parity and difference runs, see Tests); not yet run in game. Not pushed.
Rewritten from scratch in a local `LetThereBeLightBeta` prototype and moved here unchanged apart from the ModID; the prototype was then deleted. Parity baseline: this repository's `96866fa`, the last commit before the rewrite. Same setting ids, defaults and option values, plus a Toxic Gas option.

## Files
- `LetThereBeLight.lua`: per-mission decisions, Inferno theme-unit collection and every hook.
- `LetThereBeLight_data.lua`: widgets.
- `LetThereBeLight_localization.lua`: options, tooltips and chat messages.
- `tests/`: parity simulator, parity runner and difference checks against the pre-rewrite commit (`tests/README.md`).

## Decisions
- 2026-10-23 (user): rewrite from scratch, minimal and optimized, with the same purpose and options: switch off the visual side of mission modifiers.
- 2026-10-23: built first as the `<Mod>Beta` prototype (`darktide-new-mod`).
- 2026-10-23 (user): environments are detected from the theme only, never from LOS mutators.
- 2026-10-23 (user): add a Toxic Gas option (`normalize_toxic_gas`, default on like Ventilation Purge) that removes only the theme's shading environment.
- 2026-10-24 (user): move the rewrite into Let There Be Light (same ModID, so no settings import) for live testing; do not push.
- 2026-10-24 (user): delete the `LetThereBeLightBeta` prototype.

## Mission decisions
- The circumstance and Havoc data are fixed once the mission's managers exist: `GameplayInitStepManagers` creates the difficulty and circumstance managers before any hook below runs (`gameplay_init_step_managers.lua:99,124`).
- `mission_env()` therefore builds one table per circumstance manager: `lights_on`, `remove_theme_environment`, `inferno` and the chat `message`. A new mission has a new circumstance manager; `on_setting_changed` drops the table, so a setting changed mid-mission applies to later calls exactly as in the old mod. Hooks read one field instead of querying managers and settings on every call.
- Theme sources are the circumstance template's `theme_tag` (`circumstance_manager.lua:29-34`) and Havoc's parsed `theme` (`difficulty_manager.lua:26-28`; Havoc themes are darkness, ventilation_purge and toxic_gas, `havoc_settings.lua:18-22`). The loaded theme is what changes the visuals (`local_theme_state.lua:23-69`). `mutator_darkness_los` and `mutator_ventilation_purge_los` only change what enemies perceive (`minion_perception_extension.lua:775-779`).
- Of the 315 circumstance templates in 1.13.3, two carry an LOS mutator that does not match their theme: `stealth_01` (darkness LOS, default theme, `stealth_circumstance_template.lua:4-11`) and `exps_dawn_au` (darkness LOS, Dawn theme, `expeditions_circumstance_template.lua:269-280`). The old mod treated both as darkness.

## Toxic Gas
- The `toxic_gas` theme exists on 10 mission levels (their `_mission_themes` files under `darktide-source/content/levels/`) and is used by 33 templates, Havoc included.
- The option removes the theme's shading environment only, the same way as Ventilation Purge; lights are not forced.
- The gas clouds stay: `MutatorToxicGasVolumes` drives `ToxicGasFog` units (`mutator_toxic_gas_volumes.lua:210-237`), and each cloud draws with its own registered volumetric volume, mesh material and particles (`toxic_gas_fog.lua:37-68`), not with a theme shading environment slot. Whether the clouds look the same against the standard environment can only be seen in game.

## Hooks
- `GameplayInitStepExtensionUnits._init_extension_unit_registration` (`gameplay_init_step_extension_units.lua:51-70`): runs once per gameplay load, after the managers step (managers → Nvidia AI agent → extension units) and before level unit components initialize (time-sliced from line 69). It collects the Inferno theme's units and sends the chat message, so the mod needs no `mod.update`.
- `LightControllerExtension.set_enabled` (`light_controller_extension.lua:69`): forces `true` when lights are on for the mission; called on setup, light-group changes and server RPCs, not per frame. Destroyed destructible lights stay off (`destructible_extension.lua:579-585`).
- `CameraHandler._get_theme_shading_environment` (`camera_handler.lua:513`, from `spawn_camera` at 533) and `ShadingEnvironmentSystem._fetch_theme_shading_environments` (`shading_environment_system.lua:31`, from `on_theme_changed`, also used by Expedition locations at `expedition_spawner.lua:737-766`): skipped to drop the theme's shading environment. Volumes then fall back to their own default (`shading_environment_extension.lua:90-104`).
- `ParticleEffect.init` and `_create_particle` (`scripts/components/particle_effect.lua:5,88`): Inferno particles are the old name list plus every unit of the ember theme's nested level. `_create_particle` also covers later `create_particle` calls, for example `set_object_set_unit_visible` (line 320).
- `WeatherExtension.setup_from_component` (`weather_extension.lua:13`): the theme's weather volumes get priority 0, which never wins in `WeatherSystem.get_current_particles` (`weather_system.lua:87`).

## Inferno audio
- `WwiseStateGroupCircumstance.on_gameplay_post_init` sets the `circumstance` state group from the template's `wwise_state` (`ember_01` for every ember template) and triggers `wwise_event_init` (`wwise_state_group_circumstance.lua:13-30`). `WwiseGameSyncManager.update` pushes each group's state to Wwise every update (`wwise_game_sync_manager.lua:82-92,119-127`), and shutdown sets the default again.
- With the Inferno option on, the hook runs the original, then sets the default state (`WwiseGameSyncSettings.default_group_state`, `"None"`). `wwise_event_init` still fires, so Hunting Grounds sounds stay. What `ember_01` changes inside the Wwise project (music, ambience) is not visible in source.

## Inferno theme units
- The ember theme spawns as a nested level named `<theme package>.level`, with its packages listed under `ember` in `<level_name>_mission_themes` (`scripts/foundation/managers/package/utilities/theme_package.lua:7-20`). Runtime evidence and consumers are in `types/SOURCES.md` (LetThereBeHandicap forced mission themes). The set is replaced at every gameplay load and cleared when `StateGameplay` exits.

## No global flow-event hook
- The old mod hooked `Unit.flow_event` to drop `particle_effect_component_init` (the effect's sounds) for fire units. A DMF hook stays installed for every call in the game, and DMF's wrapper packs the return values into a new table on each call (`dmf-source/scripts/mods/dmf/modules/core/hooks.lua:195-205`); the game has 312 `Unit.flow_event(` call sites.
- That event is sent only from `ParticleEffect.init` (`particle_effect.lua:25`, the only occurrence in game source), and init makes no other flow call when `_create_particle` is blocked. The mod sets `Unit.flow_event` to a no-op only around the original `init` of a suppressed effect and restores it after. Component construction has no `pcall` (`component_extension.lua:183`), so an error inside init stops the level load either way.

## Not changed
- Theme hide sets: they decide which level units spawn, and the client's level must match the server's unit indices (`types/SOURCES.md`, LetThereBeHandicap).
- The circumstance audio state of other environments (`darkness_01`, `ventilation_purge_01` and others) still plays; only Inferno's is reset (Inferno audio).
- Sounds that theme units start from their own flow at level spawn run in the engine, not through Lua, and the Lua API has no way to stop a unit's sounds without their event ids.
- Ventilation Purge and darkness theme units (possible fog or dust particles and weather volumes) are untouched until a runtime listing shows what they contain.

## Deliberate differences
Against `96866fa`:
1. `stealth_01` (default theme, darkness LOS mutator) is left unchanged: no forced lights, no removed environment, no message. Filter: the parity pool leaves out every template whose LOS mutator does not match its theme. Check: `run_differences.sh`, scenario `stealth`.
2. `exps_dawn_au` (Dawn theme, darkness LOS mutator) follows only the Dawn option and gets the Dawn message. Same filter. Check: scenarios `dawn_off` and `dawn_on`.
3. The Toxic Gas option removes the `toxic_gas` theme environment and adds its message (last in message priority). Filter: parity runs set `normalize_toxic_gas` to false. Check: scenarios `gas_on` and `gas_off` (off matches the old mod exactly).
4. The chat message is sent from the extension-units hook instead of the first `mod.update` after the circumstance manager exists; both run during the same load. Enabling the mod in the middle of a mission no longer prints a message there, because nothing changes until the next load. The simulator keeps the enable state constant within a mission.
5. Other mods' `Unit.flow_event` hooks do not see `particle_effect_component_init` for suppressed Inferno effects. Not observable in the trace.
6. With the Inferno option on, the circumstance audio state is reset from `ember_01` to the default `None`. Filter: parity runs print no audio state for ember-theme missions. Check: scenarios `sound_on`, `sound_hunt` (Hunting Grounds sounds still start) and `sound_off` (matches the old mod).

## Source contracts
| Use | Source path:line |
|---|---|
| Managers created | `scripts/game_states/game/gameplay_sub_states/gameplay_init_step_states/gameplay_init_step_managers.lua:99,124` |
| Circumstance template | `scripts/managers/circumstance/circumstance_manager.lua:29-34` |
| Havoc theme | `scripts/managers/difficulty/difficulty_manager.lua:26-28`, `scripts/settings/havoc_settings.lua:18-22` |
| Theme loading | `scripts/loading/local_states/local_theme_state.lua:23-69` |
| LOS mutators | `scripts/extension_systems/perception/minion_perception_extension.lua:775-779` |
| Level unit registration | `scripts/game_states/game/gameplay_sub_states/gameplay_init_step_states/gameplay_init_step_extension_units.lua:51-70` |
| Mission themes file | `scripts/foundation/managers/package/utilities/theme_package.lua:7-20` |
| Particle effect component | `scripts/components/particle_effect.lua:5-33,88,320-326` |
| Weather volumes | `scripts/components/weather_volume.lua:5-21`, `scripts/extension_systems/weather/weather_extension.lua:13-17`, `weather_system.lua:76-104` |
| Light controller | `scripts/extension_systems/light_controller/light_controller_extension.lua:69-87` |
| Theme shading environment | `scripts/managers/player/player_game_states/camera_handler.lua:513-541`, `scripts/extension_systems/shading_environment/shading_environment_system.lua:13-45`, `shading_environment_extension.lua:90-104` |
| Circumstance audio state | `scripts/managers/wwise_game_sync/wwise_state_groups/wwise_state_group_circumstance.lua:13-30`, `scripts/managers/wwise_game_sync/wwise_game_sync_manager.lua:82-92,119-127` |
| Toxic gas clouds | `scripts/managers/mutator/mutators/mutator_toxic_gas_volumes.lua:210-237`, `scripts/components/toxic_gas_fog.lua:37-68` |

## Tests
- `tools\validate.ps1 -Path mods\active\LetThereBeLight` → 2026-10-24: passed, 0 diagnostics.
- `tests/run_parity.sh 1 300` → 2026-10-24: 0 differences against `96866fa` over the real templates (67-102 missions per theme); `Unit.flow_event` handler calls old 22,639, new 0. With `BASELINE=c988972` (before the Inferno theme-unit fix) 2 of seeds 1-40 differ.
- `tests/run_differences.sh` → 2026-10-24: 0 failing; against `525c228` (before the audio reset): 2 failing. On 2026-10-23 the same checks failed 9 times against the prototype before the theme-only change, which shows they detect the old detection.

## Runtime status
2026-10-24, dt-cli read-only snapshots (PID 15968), regular mission `fm_cargo` with circumstance `ember_01`, rewrite build loaded and enabled, `normalize_inferno` on:
- Theme nested level `.../fm_cargo_themes/ember_01/theme_ember_01_fm_cargo.level` found, 737 units; 330 of its ParticleEffect components, 0 with a live particle. 7 theme weather volumes, none with priority above 0; no weather particles active. Circumstance audio state `None`.
- The theme held all 299 named-list fires (none outside it) plus fire_blaze_tall, billowy smoke, chimney smoke and ash weather: the kinds the old name list missed.
- Live fire and smoke outside the theme (base level): fire_exhaust_02 x12, embers_rising_5m x11, backdrop_smoke_large x4, manhole_smoke_01 x3. The same snapshot in a standard `fm_cargo` run (circumstance `default`, same session) showed exactly the same four kinds and counts, so on this map the Inferno run's ParticleEffect fire and smoke match the standard environment.
- Not covered by the snapshot: particles a unit's flow creates without a ParticleEffect component, and sounds.

Smallest next in-game test:
1. Deploy `mods/active/LetThereBeLight`, and make sure no `LetThereBeLightBeta` folder is in the game's mods folder (AML loads every folder not prefixed with `_`). Restart the game.
2. Open the mod options: your settings are unchanged, and "Toxic Gas: Replace with standard environment" is on.
3. Start an Inferno mission (Inferno option on). Expected: chat "Inferno environment and decorative fires removed", standard lighting, no decorative fire, smoke or falling embers, and no Inferno ambience or music variant (compare with the option off).
4. Start a Toxic Gas mission. Expected: chat "Toxic Gas environment replaced with standard environment", no green haze over the map, and the gas clouds still clearly visible where they damage.
5. Start a Power Interruption mission with Dark Mission Lighting on Atmospheric Lighting. Expected: chat "Darkness mission lights enabled" and the mission lights on.
6. In the mission, run `dee census hooks --mod LetThereBeLight`. Expected: every target `dmf_hooked`, and no `Unit.flow_event` hook.

Runtime-pending: theme-unit collection in a real Inferno mission, the flow-event mute (fire sounds gone), the Inferno audio reset (no Inferno ambience or music variant), gas-cloud visibility under the standard environment, Dawn and Ventilation Purge.

## Open items
- 2026-10-23: the name list can go once the theme-unit set is confirmed to cover the seven named fire particles. 2026-10-24: confirmed on fm_cargo (299 of 299 inside the theme); other Inferno maps unchecked.
- 2026-10-23: Nurgle Manifestation (5 levels) and Noir (2 levels) themes are not covered; the same shading-environment removal would apply.
- 2026-10-23: a runtime listing of the Ventilation Purge theme's particle effects would show whether fog particles remain after its environment is removed.
