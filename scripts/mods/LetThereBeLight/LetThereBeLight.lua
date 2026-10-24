local mod = get_mod("LetThereBeLight")

local CameraHandler = require("scripts/managers/player/player_game_states/camera_handler")
local LightControllerExtension = require("scripts/extension_systems/light_controller/light_controller_extension")
local ShadingEnvironmentSystem = require("scripts/extension_systems/shading_environment/shading_environment_system")
local WeatherExtension = require("scripts/extension_systems/weather/weather_extension")
local WwiseGameSyncSettings = require("scripts/settings/wwise_game_sync/wwise_game_sync_settings")

local INFERNO_FIRE_PARTICLES = {
    ["content/fx/particles/environment/fire_blaze_01"] = true,
    ["content/fx/particles/environment/fire_blaze_02"] = true,
    ["content/fx/particles/environment/fire_blaze_02_backdrop"] = true,
    ["content/fx/particles/environment/fire_blaze_row_03"] = true,
    ["content/fx/particles/environment/fire_blaze_row_04"] = true,
    ["content/fx/particles/environment/tank_foundry/fire_no_smoke_02"] = true,
    ["content/fx/particles/environment/tank_foundry/fire_no_smoke_03"] = true,
}

local NO_CHANGES = {}

local env = NO_CHANGES
local env_owner = nil
local inferno_theme_units = {}

local function noop() end

-- The circumstance and Havoc data are fixed once the mission's managers exist, so the decisions
-- are made once per circumstance manager (new mission) or setting change. Only the theme changes
-- what is shown: LOS mutators change what enemies see (stealth_01 has the darkness one with the
-- default theme).
local function build_env(state)
    local template = state.circumstance:template()
    local theme = template and template.theme_tag
    local havoc_data = state.difficulty and state.difficulty:get_parsed_havoc_data()
    local havoc_theme = havoc_data and havoc_data.theme

    local function theme_active(tag)
        return theme == tag or havoc_theme == tag
    end

    local darkness_mode = mod:get("power_interruption_mode")
    local darkness = darkness_mode ~= "off" and theme_active("darkness")
    local darkness_environment = darkness and darkness_mode == "normal_environment"
    local dawn = mod:get("normalize_dawn") and theme_active("dawn")
    local inferno = mod:get("normalize_inferno") and theme_active("ember")
    local purge = mod:get("remove_ventilation_purge_fog") and theme_active("ventilation_purge")
    local toxic_gas = mod:get("normalize_toxic_gas") and theme_active("toxic_gas")

    return {
        lights_on = darkness or dawn or inferno,
        remove_theme_environment = darkness_environment or dawn or inferno or purge or toxic_gas,
        inferno = inferno,
        message = darkness and (darkness_environment and "power_interruption_standard_lighting_active"
                or "power_interruption_atmospheric_lighting_active")
            or dawn and "dawn_standard_environment_active"
            or inferno and "inferno_standard_environment_active"
            or purge and "ventilation_purge_fog_removed"
            or toxic_gas and "toxic_gas_standard_environment_active",
    }
end

local function mission_env()
    local state = Managers.state
    local circumstance_manager = state and state.circumstance

    if circumstance_manager ~= env_owner then
        env_owner = circumstance_manager
        env = circumstance_manager and build_env(state) or NO_CHANGES
    end

    return env
end

-- The Inferno theme spawns as a nested level named "<theme package>.level".
local function collect_inferno_theme_units(level, level_name)
    local units = {}
    local file_path = level_name and level_name .. "_mission_themes"

    if not (level and file_path and Application.can_get_resource("lua", file_path)) then
        return units
    end

    local theme_level_names = {}

    for _, theme_name in pairs(require(file_path).ember or {}) do
        theme_level_names[theme_name .. ".level"] = true
    end

    local nested_levels = Level.nested_levels(level)

    for i = 1, #nested_levels do
        local nested_level = nested_levels[i]

        if theme_level_names[Level.name(nested_level)] then
            local nested_units = Level.units(nested_level, true)

            for j = 1, #nested_units do
                units[nested_units[j]] = true
            end
        end
    end

    return units
end

local function inferno_particle(particle_name, unit)
    return INFERNO_FIRE_PARTICLES[particle_name] or inferno_theme_units[unit]
end

-- Level unit components initialize after this call: the theme units are known before any
-- ParticleEffect or WeatherVolume runs, and every manager the decisions read exists.
mod:hook_require("scripts/game_states/game/gameplay_sub_states/gameplay_init_step_states/gameplay_init_step_extension_units", function(GameplayInitStepExtensionUnits)
    mod:hook(GameplayInitStepExtensionUnits, "_init_extension_unit_registration", function(func, self, world, shared_state, ...)
        local current = mission_env()

        inferno_theme_units = current.inferno
            and collect_inferno_theme_units(shared_state.level, shared_state.level_name)
            or {}

        if current.message and mod:get("chat_notification") then
            mod:echo("%s", mod:localize(current.message))
        end

        return func(self, world, shared_state, ...)
    end)
end)

mod:hook(LightControllerExtension, "set_enabled", function(func, self, is_enabled, is_deterministic)
    if not is_enabled and mission_env().lights_on then
        is_enabled = true
    end

    return func(self, is_enabled, is_deterministic)
end)

mod:hook(CameraHandler, "_get_theme_shading_environment", function(func, self, themes)
    if mission_env().remove_theme_environment then
        return nil
    end

    return func(self, themes)
end)

mod:hook(ShadingEnvironmentSystem, "_fetch_theme_shading_environments", function(func, self, themes)
    if mission_env().remove_theme_environment then
        return
    end

    return func(self, themes)
end)

mod:hook_require("scripts/components/particle_effect", function(ParticleEffect)
    -- The only flow event in init is "particle_effect_component_init", which starts the effect's
    -- sounds. Muting Unit.flow_event for this call avoids hooking every flow event in the game.
    mod:hook(ParticleEffect, "init", function(func, self, unit)
        if not (mission_env().inferno and inferno_particle(self:get_data(unit, "particle"), unit)) then
            return func(self, unit)
        end

        local flow_event = Unit.flow_event

        Unit.flow_event = noop
        func(self, unit)
        Unit.flow_event = flow_event
    end)

    mod:hook(ParticleEffect, "_create_particle", function(func, self)
        if mission_env().inferno and inferno_particle(self._particle_name, self._unit) then
            return
        end

        return func(self)
    end)
end)

-- Priority 0 never wins in WeatherSystem.get_current_particles, so the volume is ignored.
mod:hook(WeatherExtension, "setup_from_component", function(func, self, world_particles, screen_particles, priority)
    if mission_env().inferno and inferno_theme_units[self._unit] then
        return func(self, "", "", 0)
    end

    return func(self, world_particles, screen_particles, priority)
end)

-- WwiseGameSyncManager pushes the group's state to Wwise every update, so resetting it here keeps
-- the Inferno audio state (ember_01) off for the whole mission.
mod:hook_require("scripts/managers/wwise_game_sync/wwise_state_groups/wwise_state_group_circumstance", function(WwiseStateGroupCircumstance)
    mod:hook(WwiseStateGroupCircumstance, "on_gameplay_post_init", function(func, self, level)
        func(self, level)

        if mission_env().inferno then
            self:_set_wwise_state(WwiseGameSyncSettings.default_group_state)
        end
    end)
end)

mod.on_setting_changed = function()
    env, env_owner = NO_CHANGES, nil
end

mod.on_game_state_changed = function(status, state_name)
    if status == "exit" and state_name == "StateGameplay" then
        env, env_owner = NO_CHANGES, nil
        inferno_theme_units = {}
    end
end
