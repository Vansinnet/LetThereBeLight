local mod = get_mod("LetThereBeLight")

local CameraHandler = require("scripts/managers/player/player_game_states/camera_handler")
local LightControllerExtension = require("scripts/extension_systems/light_controller/light_controller_extension")
local ShadingEnvironmentSystem = require("scripts/extension_systems/shading_environment/shading_environment_system")
local WeatherExtension = require("scripts/extension_systems/weather/weather_extension")

local INFERNO_FIRE_PARTICLES = {
    ["content/fx/particles/environment/fire_blaze_01"] = true,
    ["content/fx/particles/environment/fire_blaze_02"] = true,
    ["content/fx/particles/environment/fire_blaze_02_backdrop"] = true,
    ["content/fx/particles/environment/fire_blaze_row_03"] = true,
    ["content/fx/particles/environment/fire_blaze_row_04"] = true,
    ["content/fx/particles/environment/tank_foundry/fire_no_smoke_02"] = true,
    ["content/fx/particles/environment/tank_foundry/fire_no_smoke_03"] = true,
}

local settings_cache = {}
local inferno_fire_units = setmetatable({}, { __mode = "k" })
local inferno_theme_units = {}
local activation_message_pending = false

local function get_setting(setting_id)
    if settings_cache[setting_id] == nil then
        settings_cache[setting_id] = mod:get(setting_id)
    end

    return settings_cache[setting_id]
end

local function mutator_active(mutator_name)
    local mutator_manager = Managers.state and Managers.state.mutator

    return mutator_manager and mutator_manager:mutator(mutator_name) ~= nil
end

local function active_theme_is(theme_tag)
    local circumstance_manager = Managers.state and Managers.state.circumstance
    local circumstance_template = circumstance_manager and circumstance_manager:template()

    if circumstance_template and circumstance_template.theme_tag == theme_tag then
        return true
    end

    local difficulty_manager = Managers.state and Managers.state.difficulty
    local havoc_data = difficulty_manager and difficulty_manager:get_parsed_havoc_data()

    return havoc_data and havoc_data.theme == theme_tag
end

local function darkness_active()
    return mutator_active("mutator_darkness_los") or active_theme_is("darkness")
end

local function ventilation_purge_active()
    return mutator_active("mutator_ventilation_purge_los") or active_theme_is("ventilation_purge")
end

local function inferno_active()
    return active_theme_is("ember")
end

local function dawn_active()
    return active_theme_is("dawn")
end

local function normal_darkness_environment_active()
    return get_setting("power_interruption_mode") == "normal_environment" and darkness_active()
end

local function normalized_inferno_active()
    return get_setting("normalize_inferno") and inferno_active()
end

local function normalized_dawn_active()
    return get_setting("normalize_dawn") and dawn_active()
end

local function activation_message_id()
    if darkness_active() and get_setting("power_interruption_mode") ~= "off" then
        if normal_darkness_environment_active() then
            return "power_interruption_standard_lighting_active"
        end

        return "power_interruption_atmospheric_lighting_active"
    elseif normalized_dawn_active() then
        return "dawn_standard_environment_active"
    elseif normalized_inferno_active() then
        return "inferno_standard_environment_active"
    elseif get_setting("remove_ventilation_purge_fog") and ventilation_purge_active() then
        return "ventilation_purge_fog_removed"
    end
end

mod:hook(LightControllerExtension, "set_enabled", function(func, self, is_enabled, is_deterministic)
    if (darkness_active() and get_setting("power_interruption_mode") ~= "off")
        or normalized_inferno_active()
        or normalized_dawn_active() then
        is_enabled = true
    end

    return func(self, is_enabled, is_deterministic)
end)

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

-- Level unit components initialize after this call, so the set is ready for ParticleEffect and WeatherVolume.
mod:hook_require("scripts/game_states/game/gameplay_sub_states/gameplay_init_step_states/gameplay_init_step_extension_units", function(GameplayInitStepExtensionUnits)
    mod:hook(GameplayInitStepExtensionUnits, "_init_extension_unit_registration", function(func, self, world, shared_state, ...)
        inferno_theme_units = normalized_inferno_active()
            and collect_inferno_theme_units(shared_state.level, shared_state.level_name)
            or {}

        return func(self, world, shared_state, ...)
    end)
end)

mod:hook_require("scripts/components/particle_effect", function(ParticleEffect)
    mod:hook(ParticleEffect, "init", function(func, self, unit)
        local particle_name = self:get_data(unit, "particle")

        if INFERNO_FIRE_PARTICLES[particle_name] or inferno_theme_units[unit] then
            inferno_fire_units[unit] = true
        end

        return func(self, unit)
    end)

    mod:hook(ParticleEffect, "_create_particle", function(func, self)
        if (INFERNO_FIRE_PARTICLES[self._particle_name] or inferno_theme_units[self._unit])
            and normalized_inferno_active() then
            return
        end

        return func(self)
    end)
end)

-- Priority 0 never wins in WeatherSystem.get_current_particles, so the volume is ignored.
mod:hook(WeatherExtension, "setup_from_component", function(func, self, world_particles, screen_particles, priority)
    if inferno_theme_units[self._unit] and normalized_inferno_active() then
        return func(self, "", "", 0)
    end

    return func(self, world_particles, screen_particles, priority)
end)

mod:hook(Unit, "flow_event", function(func, unit, event_name)
    if inferno_fire_units[unit]
        and event_name == "particle_effect_component_init"
        and normalized_inferno_active() then
        return
    end

    return func(unit, event_name)
end)

mod:hook(CameraHandler, "_get_theme_shading_environment", function(func, self, themes)
    if normal_darkness_environment_active()
        or normalized_inferno_active()
        or normalized_dawn_active()
        or get_setting("remove_ventilation_purge_fog") and ventilation_purge_active() then
        return nil
    end

    return func(self, themes)
end)

mod:hook(ShadingEnvironmentSystem, "_fetch_theme_shading_environments", function(func, self, themes)
    if normal_darkness_environment_active()
        or normalized_inferno_active()
        or normalized_dawn_active()
        or get_setting("remove_ventilation_purge_fog") and ventilation_purge_active() then
        return
    end

    return func(self, themes)
end)

mod.on_setting_changed = function(setting_id)
    settings_cache[setting_id] = nil
end

mod.on_game_state_changed = function(status, state_name)
    if state_name == "StateGameplay" then
        activation_message_pending = status == "enter"

        if status == "exit" then
            inferno_theme_units = {}
        end
    end
end

mod.update = function()
    if not activation_message_pending or not mod:is_enabled() then
        return
    end

    -- Circumstance state is initialized after StateGameplay is entered.
    if not (Managers.state and Managers.state.circumstance) then
        return
    end

    activation_message_pending = false

    local message_id = activation_message_id()
    if message_id and get_setting("chat_notification") then
        mod:echo("%s", mod:localize(message_id))
    end
end
