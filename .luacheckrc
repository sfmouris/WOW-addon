-- luacheck config for QuestKompas (spec 12.3). Run: luacheck .
std = "lua51"
max_line_length = 120
codes = true
exclude_files = { "QuestKompas/Libs/**", ".luarocks/**" }
ignore = {
  "212/self",   -- unused self in methods is fine
  "212/_.*",    -- unused arguments starting with _
  "432/self",   -- methods defined inside methods
}

-- The only globals the addon may set (spec 13.6), plus the binding labels
-- and the named secure button that WoW requires by name.
globals = {
  "QuestKompasDB", "QuestKompasCharDB", "QuestKompas_OnCompartmentClick",
  "SLASH_QUESTKOMPAS1", "SLASH_QUESTKOMPAS2", "SlashCmdList",
  "BINDING_HEADER_QUESTKOMPAS", "BINDING_NAME_QUESTKOMPAS_TOGGLE", "BINDING_NAME_QUESTKOMPAS_NEXT",
  "BINDING_NAME_QUESTKOMPAS_CLEAR",
}

read_globals = {
  -- Lua extensions in WoW
  "wipe", "strsplit", "tinsert", "tremove", "date", "time", "debugprofilestop", "bit",
  "geterrorhandler", "hooksecurefunc", "issecretvalue",
  -- Frames and UI
  "CreateFrame", "UIParent", "GameTooltip", "DEFAULT_CHAT_FRAME", "UIErrorsFrame", "WorldMapFrame",
  "ObjectiveTrackerFrame", "QuestInfoRewardsFrame", "GossipFrame", "QuestFrame", "MenuUtil",
  "GameFontHighlightSmall", "Settings", "C_SettingsUtil", "MinimalSliderWithSteppersMixin",
  "CreateSettingsListSectionHeaderInitializer", "CreateSettingsButtonInitializer", "ChatFrameUtil",
  "ClearOverrideBindings", "SetOverrideBindingClick", "UiMapPoint", "CreateVector2D", "Item",
  "QuestDifficultyColors", "SOUNDKIT", "PlaySound", "Enum", "LibStub", "QuestieLoader", "TomTom",
  "HBD_PINS_WORLDMAP_SHOW_CONTINENT", "Minimap", "GetCursorPosition",
  -- API namespaces
  "C_AddOns", "C_QuestLog", "C_TaskQuest", "C_Map", "C_SuperTrack", "C_GossipInfo", "C_Item", "C_ChatInfo",
  "C_Timer",
  -- Global API
  "GetTime", "InCombatLockdown", "GetBuildInfo", "IsInInstance", "IsInGroup", "GetNumGroupMembers",
  "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown", "UnitLevel", "UnitXP", "UnitXPMax", "GetXPExhaustion",
  "GetMoney", "UnitFactionGroup", "UnitClass", "UnitRace", "UnitGUID", "UnitName", "GetInventoryItemLink",
}

files["tests/**"] = {
  globals = { "stub", "T", "arg" },
  read_globals = { "os", "io" },
  max_line_length = 150,
  ignore = { "111", "112", "113", "121", "122", "142", "143", "211", "212", "213", "311", "542" },
}
files["tools/**"] = { std = "lua51" }
