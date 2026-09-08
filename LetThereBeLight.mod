return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`LetThereBeLight` failed loading DMF.")
        new_mod("LetThereBeLight", {
            mod_script = "LetThereBeLight/scripts/mods/LetThereBeLight/LetThereBeLight",
            mod_data = "LetThereBeLight/scripts/mods/LetThereBeLight/LetThereBeLight_data",
            mod_localization = "LetThereBeLight/scripts/mods/LetThereBeLight/LetThereBeLight_localization",
        })
    end,
    packages = {},
}
