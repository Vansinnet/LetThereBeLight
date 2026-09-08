local mod = get_mod("LetThereBeLight")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    allow_rehooking = true,
    options = {
        widgets = {
            {
                setting_id = "chat_notification",
                type = "checkbox",
                default_value = true,
                tooltip = "chat_notification_tooltip",
            },
            {
                setting_id = "power_interruption_mode",
                type = "dropdown",
                default_value = "lights_on",
                tooltip = "power_interruption_mode_tooltip",
                options = {
                    {
                        text = "power_interruption_mode_off",
                        value = "off",
                    },
                    {
                        text = "power_interruption_mode_lights_on",
                        value = "lights_on",
                    },
                    {
                        text = "power_interruption_mode_normal_environment",
                        value = "normal_environment",
                    },
                },
            },
            {
                setting_id = "normalize_dawn",
                type = "checkbox",
                default_value = false,
                tooltip = "normalize_dawn_tooltip",
            },
            {
                setting_id = "normalize_inferno",
                type = "checkbox",
                default_value = true,
                tooltip = "normalize_inferno_tooltip",
            },
            {
                setting_id = "remove_ventilation_purge_fog",
                type = "checkbox",
                default_value = true,
                tooltip = "remove_ventilation_purge_fog_tooltip",
            },
        },
    },
}
