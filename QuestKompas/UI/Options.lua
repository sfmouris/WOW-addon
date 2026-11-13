-- QuestKompas: settings panel via the Settings API (spec 4.15).
-- Signatures checked in Blizzard_Settings_Shared (Forever 1.60.1):
-- RegisterVerticalLayoutCategory(name) -> category, layout;
-- RegisterVerticalLayoutSubcategory(parentCategory, name) -> category, layout;
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

local function proxy(cat, section, key, varType, label)
  local default = ns.DB.defaults[section] and ns.DB.defaults[section][key]
  if default == nil then default = (varType == "string") and "" or false end
  return Settings.RegisterProxySetting(cat, varName(section, key), varType, label, default,
    function() return ns:GetSetting(section, key) end,
    function(value) ns:SetSetting(section, key, value) end)
end

-- Every control takes its label from L[labelKey] and its tooltip from
-- L[labelKey .. "_TIP"].
local function checkbox(cat, section, key, labelKey)
  local setting = proxy(cat, section, key, Settings.VarType.Boolean, L[labelKey])
  Settings.CreateCheckbox(cat, setting, L[labelKey .. "_TIP"])
end

local function slider(cat, section, key, labelKey, minV, maxV, step, fmt)
  local setting = proxy(cat, section, key, Settings.VarType.Number, L[labelKey])
  local options = Settings.CreateSliderOptions(minV, maxV, step)
  if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
      return string.format(fmt or "%d", v)
    end)
  end
  Settings.CreateSlider(cat, setting, options, L[labelKey .. "_TIP"])
end

local function dropdown(cat, section, key, labelKey, choices)
  local setting = proxy(cat, section, key, Settings.VarType.String, L[labelKey])
  local function options()
    local container = Settings.CreateControlTextContainer()
    for _, c in ipairs(choices) do container:Add(c[1], c[2]) end
    return container:GetData()
  end
  Settings.CreateDropdown(cat, setting, options, L[labelKey .. "_TIP"])
end

local function moduleToggle(name)
  local labelKey = "MOD_" .. name:upper()
  local setting = Settings.RegisterProxySetting(category, ADDON .. "_module_" .. name, Settings.VarType.Boolean,
    L[labelKey], ns.DB.defaults.modules[name] == true,
    function() return ns.db.settings.modules[name] == true end,
    function(value)
      ns.db.settings.modules[name] = value and true or false
      ns:SetModuleEnabled(name, value)
      ns:Fire("QK_SETTING_CHANGED", "modules", name, value)
    end)
  Settings.CreateCheckbox(category, setting, L[labelKey .. "_TIP"])
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

-- Subpage under the QuestKompas entry; falls back to the main page when
-- the client has no subcategories.
local function subpage(mainLayout, name)
  if Settings.RegisterVerticalLayoutSubcategory then
    return Settings.RegisterVerticalLayoutSubcategory(category, name)
  end
  header(mainLayout, name)
  return category, mainLayout
end

local function buildMain(layout)
  header(layout, L["OPT_GENERAL"])
  dropdown(category, "general", "language", "OPT_LANGUAGE", { { "nl", "Nederlands" }, { "en", "English" },
    { "auto", L["OPT_LANG_AUTO"] } })
  local perChar = Settings.RegisterProxySetting(category, ADDON .. "_perChar", Settings.VarType.Boolean,
    L["OPT_PERCHAR"], false,
    function() return ns.cdb.perChar == true end,
    function(value) ns.cdb.perChar = value and true or nil end)
  Settings.CreateCheckbox(category, perChar, L["OPT_PERCHAR_TIP"])
  checkbox(category, "general", "minimap", "OPT_MINIMAP")
  checkbox(category, "general", "debug", "OPT_DEBUG")

  header(layout, L["OPT_MODULES"])
  for _, name in ipairs({ "Tracker", "Navigator", "Planner", "Learn", "AutoQuest", "RewardHelper", "MapPins",
                          "ItemBar", "LogTools", "Stats", "Party", "Bridges" }) do
    moduleToggle(name)
  end

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
end

local function buildTracker(cat, layout)
  dropdown(cat, "tracker", "sort", "OPT_SORT", { { "distance", L["SORT_DISTANCE"] },
    { "level", L["SORT_LEVEL"] }, { "zone", L["SORT_ZONE"] }, { "manual", L["SORT_MANUAL"] } })
  slider(cat, "tracker", "scale", "OPT_SCALE", 0.7, 1.5, 0.05, "%.2f")
  slider(cat, "tracker", "width", "OPT_WIDTH", 180, 420, 10)
  slider(cat, "tracker", "maxRows", "OPT_MAXROWS", 10, 60, 1)
  slider(cat, "tracker", "bgAlpha", "OPT_BGALPHA", 0, 1, 0.05, "%.2f")
  checkbox(cat, "tracker", "locked", "OPT_LOCKED")
  checkbox(cat, "tracker", "hideDone", "OPT_HIDEDONE")
  checkbox(cat, "tracker", "fadeInCombat", "OPT_FADE")
  checkbox(cat, "tracker", "showFooter", "OPT_FOOTER")
  checkbox(cat, "tracker", "hideBlizzard", "OPT_HIDEBLIZZ")

  header(layout, L["OPT_ITEMBAR"])
  slider(cat, "itembar", "max", "OPT_ITEMMAX", 1, 12, 1)
end

local function buildNav(cat)
  dropdown(cat, "nav", "mode", "OPT_NAVMODE", { { "own", L["NAV_OWN"] }, { "native", L["NAV_NATIVE"] } })
  slider(cat, "nav", "scale", "OPT_NAVSCALE", 0.7, 1.5, 0.05, "%.2f")
  checkbox(cat, "nav", "useTomTom", "OPT_TOMTOM")
  checkbox(cat, "nav", "autoAdvance", "OPT_AUTOADVANCE")
  checkbox(cat, "nav", "sound", "OPT_SOUND")
  slider(cat, "nav", "arriveYards", "OPT_ARRIVE", 5, 30, 1)
end

local function buildAuto(cat)
  checkbox(cat, "auto", "accept", "OPT_ACCEPT")
  checkbox(cat, "auto", "turnin", "OPT_TURNIN")
  dropdown(cat, "auto", "skipModifier", "OPT_SKIPMOD", { { "SHIFT", "Shift" }, { "CTRL", "Ctrl" },
    { "ALT", "Alt" } })
  checkbox(cat, "auto", "repeatable", "OPT_REPEATABLE")
  slider(cat, "auto", "maxLevelAbove", "OPT_MAXLEVEL", 0, 10, 1)
  checkbox(cat, "auto", "gossip", "OPT_GOSSIP")
  checkbox(cat, "auto", "announce", "OPT_ANNOUNCE")
  checkbox(cat, "auto", "autoReward", "OPT_AUTOREWARD")
end

local function buildMap(cat, layout)
  header(layout, L["OPT_PINS"])
  checkbox(cat, "pins", "turnin", "OPT_PIN_TURNIN")
  checkbox(cat, "pins", "hotspots", "OPT_PIN_HOTSPOTS")
  checkbox(cat, "pins", "givers", "OPT_PIN_GIVERS")
  checkbox(cat, "pins", "nav", "OPT_PIN_NAV")
  checkbox(cat, "pins", "minimap", "OPT_PIN_MINIMAP")
  checkbox(cat, "pins", "coords", "OPT_PIN_COORDS")

  header(layout, L["OPT_LEARN"])
  checkbox(cat, "learn", "enabled", "OPT_LEARN_ON")
  slider(cat, "learn", "mergeYards", "OPT_MERGE", 10, 100, 5)
  slider(cat, "learn", "maxHotspots", "OPT_MAXHOT", 4, 24, 1)

  header(layout, L["OPT_PLANNER"])
  slider(cat, "planner", "clusterYards", "OPT_CLUSTER", 50, 400, 10)
  checkbox(cat, "planner", "preferNearDone", "OPT_NEARDONE")
  checkbox(cat, "planner", "penalizeGroup", "OPT_PENALGROUP")
end

local function build()
  local layout
  category, layout = Settings.RegisterVerticalLayoutCategory("QuestKompas")
  buildMain(layout)
  buildTracker(subpage(layout, L["OPT_TRACKER"]))
  buildNav(subpage(layout, L["OPT_NAV"]))
  buildAuto(subpage(layout, L["OPT_AUTO"]))
  buildMap(subpage(layout, L["OPT_CAT_MAP"]))
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
