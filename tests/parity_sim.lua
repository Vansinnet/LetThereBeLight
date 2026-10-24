-- Seeded mission simulator for Let There Be Light: the pre-rewrite baseline (old) and the rewrite (new).
-- Usage: luajit parity_sim.lua <workspace_root> <mod_dir> <ModID> <seed> [<circumstance> <id=value,...>]
-- Without a circumstance it runs 2-4 missions with random real circumstance templates (parity mode).
-- With one it runs a single mission with that template and those settings (difference scenarios).
-- Real game code: circumstance templates, ParticleEffect, LightControllerExtension, WeatherExtension and
-- WeatherSystem from darktide-source. Mocked: DMF, engine natives, managers, CameraHandler,
-- ShadingEnvironmentSystem and the extension-units init step (their hooked methods only return or record).
-- stdout is the comparable trace; stderr gets hook-handler call counts.

local root, mod_dir, mod_id, seed = arg[1], arg[2], arg[3], tonumber(arg[4])
local scenario_circumstance, scenario_settings = arg[5], arg[6]
local SOURCE = root .. "/darktide-source/"
package.path = SOURCE .. "?.lua;" .. package.path
math.randomseed(seed)

local function pick(list)
    return list[math.random(#list)]
end

local function chance(p)
    return math.random() < p
end

-- Engine and game globals --------------------------------------------------------------------------

CLASS = {}
Components = {}
GameParameters = {}
DevParameters = {}
BUILD = "release"

function settings(_, data)
    return data
end
Log = { error = function() end, warning = function() end, info = function() end }
Script = { new_map = function() return {} end, callstack = function() return "" end }
Matrix4x4 = { identity = function() return "identity" end }
Vector3 = function(x, y, z) return { x, y, z } end
Vector3Box = function() return { unbox = function() return {} end } end
QuaternionBox = Vector3Box
Managers = { state = {} }

-- Like scripts/foundation/utilities/class.lua, a subclass gets copies of its base's methods.
function class(name, super_name)
    local c = { __class_name = name }
    local super = super_name and CLASS[super_name]

    if super then
        for key, value in pairs(super) do
            c[key] = value
        end

        c.super = super
    end

    c.__class_name = name
    c.__index = c
    c.new = function(self, ...)
        local object = setmetatable({}, c)

        if object.init then
            object:init(...)
        end

        return object
    end
    CLASS[name] = c

    return c
end

-- Mirrors the parts of scripts/components/components.lua that ParticleEffect uses.
function component(name)
    local c = { __component_name = name, events = {} }

    c.__index = c
    c.new = function(self, unit)
        local object = setmetatable({ unit = unit }, c)

        object:init(unit)

        return object
    end
    c.get_data = function(self, unit, key)
        local value = unit.data[key]

        if value == nil then
            local data = c.component_data and c.component_data[key]

            value = data and (data.ui_type == "struct_array" and {} or data.value)
        end

        return value
    end
    Components[name] = c

    return c
end

local function uid(unit)
    return "unit_" .. unit.id
end

Unit = {
    flow_event = function(unit, event_name)
        print("flow", uid(unit), event_name)
    end,
    has_node = function() return false end,
    world_position = function() return "pos" end,
    world_rotation = function() return "rot" end,
    world_scale = function() return "scale" end,
    world = function() return "world" end,
    is_point_inside_volume = function(unit, volume_name, position)
        return unit.inside[position] == true
    end,
}

local next_particle_id = 0

-- Parity filter for deliberate difference 7, set per mission (see run_mission).
show_lights = true

Theme = {
    light_groups = function() return { darkness = "OFF", emergency = "ON" } end,
}

WwiseWorld = {
    trigger_resource_event = function(world, event) print("wwise_event", event) end,
}

World = {
    create_particle_group = function() return "group" end,
    destroy_particle_group = function() end,
    create_particles = function(world, name)
        next_particle_id = next_particle_id + 1
        print("particles", name, next_particle_id)

        return next_particle_id
    end,
    link_particles = function() end,
    destroy_particles = function(world, id) print("destroy_particles", id) end,
    stop_spawning_particles = function(world, id) print("stop_particles", id) end,
}

Level = {
    nested_levels = function(level) return level.nested end,
    name = function(level) return level.name end,
    units = function(level) return level.units end,
}

local mission_themes = {}

Application = {
    can_get_resource = function(resource_type, name)
        return resource_type == "lua" and mission_themes[name] ~= nil
    end,
}

package.loaded["core/scripts/common/light_controller_utilities"] = {
    set_enabled = function(unit, is_enabled)
        if show_lights then
            print("light", uid(unit), tostring(is_enabled))
        end
    end,
    set_flicker = function(unit, enabled) print("flicker", uid(unit), tostring(enabled)) end,
}

-- Mocked game modules: the hooked methods behave like the originals as far as the mods can observe.
local CameraHandler = {
    _get_theme_shading_environment = function(self, themes)
        return #themes > 0 and "theme_environment" or nil
    end,
}
package.loaded["scripts/managers/player/player_game_states/camera_handler"] = CameraHandler

local ShadingEnvironmentSystem = {
    _fetch_theme_shading_environments = function(self, themes)
        self.fetched = #themes > 0
    end,
}
package.loaded["scripts/extension_systems/shading_environment/shading_environment_system"] = ShadingEnvironmentSystem

local ExtensionUnits = {
    _init_extension_unit_registration = function(self, world, shared_state)
        print("register_level_units", #shared_state.level.units)
    end,
}
package.loaded["scripts/game_states/game/gameplay_sub_states/gameplay_init_step_states/gameplay_init_step_extension_units"] = ExtensionUnits

require("scripts/foundation/utilities/table")

local CircumstanceTemplates = require("scripts/settings/circumstance/circumstance_templates")
local HavocSettings = require("scripts/settings/havoc_settings")
local ParticleEffect = require("scripts/components/particle_effect")
local LightControllerExtension = require("scripts/extension_systems/light_controller/light_controller_extension")
local WeatherExtension = require("scripts/extension_systems/weather/weather_extension")
local WeatherSystem = require("scripts/extension_systems/weather/weather_system")
local LightControllerSystem = require("scripts/extension_systems/light_controller/light_controller_system")
local WwiseStateGroupCircumstance = require("scripts/managers/wwise_game_sync/wwise_state_groups/wwise_state_group_circumstance")

-- DMF mock -----------------------------------------------------------------------------------------

local settings = {}
local handler_calls = {}
local mod = { enabled = true }
local localization

function get_mod()
    return mod
end

function mod:get(id) return settings[id] end
function mod:set(id, value) settings[id] = value end
function mod:info() end
function mod:is_enabled() return self.enabled end
function mod:localize(id) return localization[id].en end
function mod:echo(text, ...) print("echo", string.format(text, ...)) end

function mod:hook(obj, method, handler)
    local orig = obj[method]

    assert(type(orig) == "function", "missing hook target " .. method)

    obj[method] = function(...)
        if mod.enabled then
            handler_calls[method] = (handler_calls[method] or 0) + 1

            return handler(orig, ...)
        end

        return orig(...)
    end
end

function mod:hook_require(path, callback)
    callback(require(path))
end

-- Settings -----------------------------------------------------------------------------------------

local SETTING_VALUES = {
    chat_notification = { true, false },
    power_interruption_mode = { "off", "lights_on", "normal_environment" },
    normalize_dawn = { true, false },
    normalize_inferno = { true, false },
    remove_ventilation_purge_fog = { true, false },
}
local SETTING_IDS = { "chat_notification", "power_interruption_mode", "normalize_dawn", "normalize_inferno", "remove_ventilation_purge_fog" }

local forced = {}

for pair in string.gmatch(scenario_settings or "", "[^,]+") do
    local id, value = pair:match("^([%w_]+)=(.+)$")

    forced[id] = value == "true" or value ~= "false" and value
end

for _, id in ipairs(SETTING_IDS) do
    settings[id] = pick(SETTING_VALUES[id])
end

local script_dir = mod_dir .. "/scripts/mods/" .. mod_id .. "/"

localization = dofile(script_dir .. mod_id .. "_localization.lua")

local data = dofile(script_dir .. mod_id .. "_data.lua")

-- DMF writes each widget's default into unset settings after the data file returns.
for _, widget in ipairs(data.options.widgets) do
    if settings[widget.setting_id] == nil then
        settings[widget.setting_id] = widget.default_value
    end
end

for id, value in pairs(forced) do
    settings[id] = value
end

-- Parity filter for deliberate difference 3: the old mod has no Toxic Gas option.
if not scenario_circumstance and settings.normalize_toxic_gas ~= nil then
    settings.normalize_toxic_gas = false
end

dofile(script_dir .. mod_id .. ".lua")

-- Missions -----------------------------------------------------------------------------------------

local FIRE_PARTICLES = {
    "content/fx/particles/environment/fire_blaze_01",
    "content/fx/particles/environment/tank_foundry/fire_no_smoke_03",
}
local OTHER_PARTICLES = {
    "content/fx/particles/environment/circumstances/ember/fire_sphere_big_01",
    "content/fx/particles/environment/backdrop_smoke_large",
    "content/fx/particles/environment/dust_motes",
}
local HAVOC_THEMES = { "default" }

for _, theme in ipairs(HavocSettings.themes) do
    HAVOC_THEMES[#HAVOC_THEMES + 1] = theme
end

-- Parity filter for deliberate differences 1 and 2: the old mod also treated an LOS mutator as its
-- environment, so templates whose LOS mutator does not match their theme (stealth_01, exps_dawn_au)
-- are left out of the random pool.
local LOS_MUTATOR_THEMES = {
    mutator_darkness_los = "darkness",
    mutator_ventilation_purge_los = "ventilation_purge",
}

local function los_mutator_mismatch(template)
    for _, name in ipairs(template.mutators or {}) do
        local theme = LOS_MUTATOR_THEMES[name]

        if theme and template.theme_tag ~= theme then
            return true
        end
    end

    return false
end

-- Each theme (no theme included) is picked equally often, then a template within it, so rare themes
-- such as Dawn get covered.
local names_by_theme = {}

for name, template in pairs(CircumstanceTemplates) do
    if not los_mutator_mismatch(template) then
        local theme = tostring(template.theme_tag)

        names_by_theme[theme] = names_by_theme[theme] or {}
        table.insert(names_by_theme[theme], name)
    end
end

local theme_groups = {}

for theme, names in pairs(names_by_theme) do
    table.sort(names)
    theme_groups[#theme_groups + 1] = theme
end

table.sort(theme_groups)

local function pick_circumstance()
    return pick(names_by_theme[pick(theme_groups)])
end

local next_unit_id = 0

local function new_unit(data)
    next_unit_id = next_unit_id + 1

    return { id = next_unit_id, data = data or {}, inside = {} }
end

local function call_state(status)
    if mod.on_game_state_changed then
        mod.on_game_state_changed(status, "StateGameplay")
    end
end

local function update()
    if mod.update then
        mod.update(0.016)
    end
end

local function other_flow_events(units)
    for _ = 1, 20 do
        Unit.flow_event(pick(units), "lua_gameplay_event")
    end
end

local function change_setting()
    local id = pick(SETTING_IDS)
    local value = pick(SETTING_VALUES[id])

    print("set", id, tostring(value))
    mod:set(id, value)

    if mod.on_setting_changed then
        mod.on_setting_changed(id)
    end
end

local function run_mission(index)
    local circumstance_name = scenario_circumstance or pick_circumstance()
    local template = assert(CircumstanceTemplates[circumstance_name], "unknown circumstance " .. circumstance_name)
    local theme = template.theme_tag
    local havoc_theme = not scenario_circumstance and chance(0.2) and pick(HAVOC_THEMES) or nil
    local mutators = {}

    for _, name in ipairs(template.mutators or {}) do
        mutators[name] = {}
    end

    mod.enabled = scenario_circumstance ~= nil or chance(0.9)

    -- Parity filter for deliberate difference 7: the old mod forced every light on in darkness,
    -- Dawn and Inferno missions, so their light states are compared only in difference scenarios.
    local LIGHT_THEMES = { darkness = true, dawn = true, ember = true }

    show_lights = scenario_circumstance ~= nil or not (LIGHT_THEMES[theme] or LIGHT_THEMES[havoc_theme])
    print(string.format("mission %d circumstance=%s theme=%s havoc=%s enabled=%s", index, circumstance_name,
        tostring(theme), tostring(havoc_theme), tostring(mod.enabled)))

    -- Level: base units plus, for some missions, an ember theme nested level.
    local level_name = "content/levels/sim/mission_" .. index
    local theme_package = "content/levels/sim/themes/theme_ember_" .. index
    local base_units, theme_units = {}, {}

    for _ = 1, math.random(3, 6) do
        base_units[#base_units + 1] = new_unit()
    end

    local has_theme_level = theme == "ember" or havoc_theme == "ember" or chance(0.2)

    if has_theme_level then
        for _ = 1, math.random(3, 6) do
            theme_units[#theme_units + 1] = new_unit()
        end
    end

    mission_themes[level_name .. "_mission_themes"] = chance(0.9) and { ember = { theme_package } } or nil
    package.loaded[level_name .. "_mission_themes"] = mission_themes[level_name .. "_mission_themes"]

    local all_units = {}

    for _, unit in ipairs(base_units) do
        all_units[#all_units + 1] = unit
    end

    for _, unit in ipairs(theme_units) do
        all_units[#all_units + 1] = unit
    end

    local level = {
        name = level_name,
        units = all_units,
        nested = {
            { name = "content/levels/sim/other_sublevel", units = {} },
            { name = theme_package .. ".level", units = theme_units },
        },
    }

    Managers.state = {}
    call_state("enter")
    update()

    Managers.state = {
        circumstance = {
            template = function() return template end,
            circumstance_name = function() return circumstance_name end,
        },
        difficulty = { get_parsed_havoc_data = function() return havoc_theme and { theme = havoc_theme } or nil end },
        mutator = { mutator = function(_, name) return mutators[name] end },
    }
    update()
    ExtensionUnits:_init_extension_unit_registration("world", { level = level, level_name = level_name })
    update()

    -- Level unit components and extensions.
    local effects, lights, volumes = {}, {}, {}

    for _, unit in ipairs(all_units) do
        if chance(0.6) then
            unit.data.particle = chance(0.4) and pick(FIRE_PARTICLES) or pick(OTHER_PARTICLES)
            unit.data.create_particle_on_spawn = chance(0.8)
            effects[#effects + 1] = ParticleEffect:new(unit)
        end

        if chance(0.4) then
            local light = LightControllerExtension:new({ is_server = false }, unit)

            light:setup_from_component(chance(0.5), false, {}, chance(0.3), "")
            lights[#lights + 1] = light
        end

        if chance(0.3) then
            local volume = WeatherExtension:new({}, unit)

            volume:setup_from_component("world_" .. unit.id, "screen_" .. unit.id, #volumes + 1)
            volumes[#volumes + 1] = volume

            for position = 1, 3 do
                unit.inside[position] = chance(0.6)
            end
        end
    end

    -- Gameplay post-init: the circumstance audio state group picks its state.
    local wwise_group = WwiseStateGroupCircumstance:new("wwise_world", "circumstance")

    wwise_group:on_gameplay_post_init(level)

    -- Theme light groups as LightControllerSystem reads them at init.
    if show_lights then
        local groups = LightControllerSystem._extract_light_groups({}, { "theme" })

        print("light_groups", "darkness=" .. tostring(groups.darkness), "emergency=" .. tostring(groups.emergency))
    end

    -- Parity filter for deliberate difference 6: the old mod kept the Inferno audio state.
    if scenario_circumstance or theme ~= "ember" then
        print("wwise_state", wwise_group:wwise_state())
    end

    local function report()
        print("camera_environment", tostring(CameraHandler:_get_theme_shading_environment({ "theme" })))

        local shading = {}

        ShadingEnvironmentSystem._fetch_theme_shading_environments(shading, { "theme" })
        print("theme_shading_fetched", tostring(shading.fetched == true))

        local map = {}

        for _, volume in ipairs(volumes) do
            map[volume._unit] = volume
        end

        for position = 1, 3 do
            local world_particles, screen_particles = WeatherSystem.get_current_particles({ _unit_to_extension_map = map }, position)

            print("weather", position, world_particles, screen_particles)
        end

        for _, light in ipairs(lights) do
            light:set_enabled(chance(0.5), chance(0.5))
        end

        other_flow_events(all_units)
    end

    report()

    if not scenario_circumstance and chance(0.3) then
        change_setting()
        report()

        for _, effect in ipairs(effects) do
            ParticleEffect.events.set_object_set_unit_visible(effect, false)
            ParticleEffect.events.set_object_set_unit_visible(effect, true)
        end
    end

    call_state("exit")
    update()
    Managers.state = {}
end

for index = 1, scenario_circumstance and 1 or math.random(2, 4) do
    run_mission(index)
end

local names = {}

for name in pairs(handler_calls) do
    names[#names + 1] = name
end

table.sort(names)

for _, name in ipairs(names) do
    io.stderr:write(string.format("%s %d\n", name, handler_calls[name]))
end
