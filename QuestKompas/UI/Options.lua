-- QuestKompas: settings panel via the Settings API (spec 4.15).
-- Signatures checked in Blizzard_Settings_Shared (Forever 1.60.1):
-- RegisterVerticalLayoutCategory(name) -> category, layout;
-- RegisterProxySetting(category, variable, varType, name, default, get, set);
-- CreateCheckbox / CreateSlider / CreateDropdown(category, setting, options, tooltip).
local ADDON, ns = ...

local O = {}
ns.Options = O
local L = ns.L

local category

local function varName(section, key)
  return ADDON .. "_" .. section .. "_" .. key
end

local function proxy(section, key, varType, label)
  local default = ns.DB.defaults[section] and ns.DB.defaults[section][key]
  if default == nil then default = (varType == "string") and "" or false end
  return Settings.RegisterProxySetting(category, varName(section, key), varType, label, default,
    function() return ns:GetSetting(section, key) end,
    function(value) ns:SetSetting(section, key, value) end)
end

local function checkbox(section, key, label, tooltip)
  local setting = proxy(section, key, Settings.VarType.Boolean, label)
  Settings.CreateCheckbox(category, setting, tooltip)
end

local function slider(section, key, label, minV, maxV, step, fmt, tooltip)
  local setting = proxy(section, key, Settings.VarType.Number, label)
  local options = Settings.CreateSliderOptions(minV, maxV, step)
  if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
      return string.format(fmt or "%d", v)
    end)
  end
  Settings.CreateSlider(category, setting, options, tooltip)
end

local function dropdown(section, key, label, choices, tooltip)
  local setting = proxy(section, key, Settings.VarType.String, label)
  local function options()
    local container = Settings.CreateControlTextContainer()
    for _, c in ipairs(choices) do container:Add(c[1], c[2]) end
    return container:GetData()
  end
  Settings.CreateDropdown(category, setting, options, tooltip)
end

local function moduleToggle(name, label)
  local setting = Settings.RegisterProxySetting(category, ADDON .. "_module_" .. name, Settings.VarType.Boolean,
    label, ns.DB.defaults.modules[name] == true,
    function() return ns.db.settings.modules[name] == true end,
    function(value)
      ns.db.settings.modules[name] = value and true or false
      ns:SetModuleEnabled(name, value)
      ns:Fire("QK_SETTING_CHANGED", "modules", name, value)
    end)
  Settings.CreateCheckbox(category, setting, L["OPT_MODULE_TIP"])
end

local function header(layout, text)
  if layout and CreateSettingsListSectionHeaderInitializer then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
  end
end

local function actionButton(layout, label, buttonText, onClick, tooltip)
  if layout and CreateSettingsButtonInitializer then
    layout:AddInitializer(CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true))
  end
end

local function build()
  local layout
  category, layout = Settings.RegisterVerticalLayoutCategory("QuestKompas")

  header(layout, L["OPT_GENERAL"])
  dropdown("general", "language", L["OPT_LANGUAGE"], { { "nl", "Nederlands" }, { "en", "English" },
    { "auto", L["OPT_LANG_AUTO"] } }, L["OPT_LANGUAGE_TIP"])
  local perChar = Settings.RegisterProxySetting(category, ADDON .. "_perChar", Settings.VarType.Boolean,
    L["OPT_PERCHAR"], false,
    function() return ns.cdb.perChar == true end,
    function(value) ns.cdb.perChar = value and true or nil end)
  Settings.CreateCheckbox(category, perChar, L["OPT_PERCHAR_TIP"])
  checkbox("general", "debug", L["OPT_DEBUG"])

  header(layout, L["OPT_MODULES"])
  for _, name in ipairs({ "Tracker", "Navigator", "Planner", "Learn", "AutoQuest", "RewardHelper", "MapPins",
                          "ItemBar", "LogTools", "Stats", "Party", "Bridges" }) do
    moduleToggle(name, L["MOD_" .. name:upper()])
  end

  header(layout, L["OPT_TRACKER"])
  dropdown("tracker", "sort", L["OPT_SORT"], { { "distance", L["SORT_DISTANCE"] }, { "level", L["SORT_LEVEL"] },
    { "zone", L["SORT_ZONE"] }, { "manual", L["SORT_MANUAL"] } })
  slider("tracker", "scale", L["OPT_SCALE"], 0.7, 1.5, 0.05, "%.2f")
  slider("tracker", "width", L["OPT_WIDTH"], 180, 420, 10)
  slider("tracker", "maxRows", L["OPT_MAXROWS"], 10, 60, 1)
  slider("tracker", "bgAlpha", L["OPT_BGALPHA"], 0, 1, 0.05, "%.2f")
  checkbox("tracker", "locked", L["OPT_LOCKED"])
  checkbox("tracker", "hideDone", L["OPT_HIDEDONE"])
  checkbox("tracker", "fadeInCombat", L["OPT_FADE"])
  checkbox("tracker", "showFooter", L["OPT_FOOTER"])
  checkbox("tracker", "hideBlizzard", L["OPT_HIDEBLIZZ"], L["OPT_HIDEBLIZZ_TIP"])

  header(layout, L["OPT_NAV"])
  dropdown("nav", "mode", L["OPT_NAVMODE"], { { "own", L["NAV_OWN"] }, { "native", L["NAV_NATIVE"] } })
  checkbox("nav", "useTomTom", L["OPT_TOMTOM"])
  checkbox("nav", "autoAdvance", L["OPT_AUTOADVANCE"])
  checkbox("nav", "sound", L["OPT_SOUND"])
  slider("nav", "arriveYards", L["OPT_ARRIVE"], 5, 30, 1)

  header(layout, L["OPT_AUTO"])
  checkbox("auto", "accept", L["OPT_ACCEPT"])
  checkbox("auto", "turnin", L["OPT_TURNIN"])
  dropdown("auto", "skipModifier", L["OPT_SKIPMOD"], { { "SHIFT", "Shift" }, { "CTRL", "Ctrl" }, { "ALT", "Alt" } })
  checkbox("auto", "repeatable", L["OPT_REPEATABLE"])
  slider("auto", "maxLevelAbove", L["OPT_MAXLEVEL"], 0, 10, 1)
  checkbox("auto", "gossip", L["OPT_GOSSIP"], L["OPT_GOSSIP_TIP"])
  checkbox("auto", "announce", L["OPT_ANNOUNCE"])
  checkbox("auto", "autoReward", L["OPT_AUTOREWARD"], L["OPT_AUTOREWARD_TIP"])

  header(layout, L["OPT_PINS"])
  checkbox("pins", "turnin", L["OPT_PIN_TURNIN"])
  checkbox("pins", "hotspots", L["OPT_PIN_HOTSPOTS"])
  checkbox("pins", "givers", L["OPT_PIN_GIVERS"])
  checkbox("pins", "nav", L["OPT_PIN_NAV"])
  checkbox("pins", "minimap", L["OPT_PIN_MINIMAP"])
  checkbox("pins", "coords", L["OPT_PIN_COORDS"])

  header(layout, L["OPT_LEARN"])
  checkbox("learn", "enabled", L["OPT_LEARN_ON"])
  slider("learn", "mergeYards", L["OPT_MERGE"], 10, 100, 5)
  slider("learn", "maxHotspots", L["OPT_MAXHOT"], 4, 24, 1)

  header(layout, L["OPT_PLANNER"])
  slider("planner", "clusterYards", L["OPT_CLUSTER"], 50, 400, 10)
  checkbox("planner", "preferNearDone", L["OPT_NEARDONE"])
  checkbox("planner", "penalizeGroup", L["OPT_PENALGROUP"])

  header(layout, L["OPT_ITEMBAR"])
  slider("itembar", "max", L["OPT_ITEMMAX"], 1, 12, 1)

  header(layout, L["OPT_RESET"])
  for _, section in ipairs({ "tracker", "nav", "auto", "pins", "learn", "planner", "itembar" }) do
    actionButton(layout, L["OPT_SECTION_" .. section:upper()], L["RESET"], function()
      ns:ResetSection(section)
      ns:Print(string.format(L["RESET_SECTION_DONE"], L["OPT_SECTION_" .. section:upper()]))
    end)
  end
  actionButton(layout, L["OPT_RESET_ALL"], L["RESET"], function()
    ns.UI:Confirm(L["CONFIRM_RESET_ALL"], function()
      ns:ResetAllSettings()
      ns:Print(L["RESET_ALL_DONE"])
    end)
  end)

  Settings.RegisterAddOnCategory(category)
end

function O:Init()
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then
    ns.Debug:Log("Settings-API ontbreekt, geen instellingenpaneel")
    return
  end
  local ok, err = pcall(build)
  if not ok then ns.Debug:Log("instellingenpaneel fout:", tostring(err)) end
end

function O:Open()
  if C_SettingsUtil or Settings then
    ns:RunOutOfCombat(function()
      if not ns.Compat.OpenSettings(category) then ns:Print(L["NO_SETTINGS"]) end
    end, "Options.open")
  end
end

ns:On("QK_READY", "Options", function() O:Init() end)

-- Addon compartment (TOC: AddonCompartmentFunc). Allowed global, spec 13.6.
function QuestKompas_OnCompartmentClick()
  O:Open()
end
