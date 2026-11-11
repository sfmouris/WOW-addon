-- QuestKompas: slash commands (spec 8.2) and small glue.
local _, ns = ...

local L, C = ns.L, ns.Compat

local function needModule(name)
  if ns:IsModuleEnabled(name) then return true end
  ns:Print(string.format(L["MODULE_OFF"], name))
  return false
end

local commands = {}

commands[""] = function() ns.Options:Open() end
commands.config = commands[""]

commands.toggle = function()
  if needModule("Tracker") then ns.Tracker:Toggle() end
end

commands.lock = function()
  if needModule("Tracker") then
    ns:Print(ns.Tracker:ToggleLock() and L["LOCKED_ON"] or L["LOCKED_OFF"])
  end
end

commands.reset = function()
  if ns.Tracker then ns.Tracker:ResetPosition() end
  if ns.Navigator then ns.Navigator:ResetPosition() end
  if ns.ItemBar then ns.ItemBar:ResetPosition() end
  ns:Print(L["POSITIONS_RESET"])
end

commands.next = function()
  if needModule("Navigator") then
    local id = ns.Navigator:Next(ns.Navigator:GetTargetQuestID())
    if not id then ns:Print(L["NEXT_NONE"]) end
  end
end

commands.way = function(rest)
  if needModule("Navigator") then ns.Navigator:Way(rest) end
end

commands.clear = function()
  if needModule("Navigator") then ns.Navigator:Clear() end
end

commands.auto = function()
  if needModule("AutoQuest") then
    ns:Print(ns.AutoQuest:Toggle() and L["AUTO_ON"] or L["AUTO_OFF"])
  end
end

commands.grey = function()
  if needModule("LogTools") then ns.LogTools:ShowGrey() end
end
commands.grijs = commands.grey

commands.find = function(rest)
  if needModule("LogTools") then ns.LogTools:Find(rest) end
end
commands.zoek = commands.find

commands.stats = function(rest)
  if not needModule("Stats") then return end
  if rest == "reset" then ns.Stats:Reset() else ns.Stats:ShowWindow() end
end

commands.export = function(rest)
  if not needModule("Learn") then return end
  local scope = (rest == "all" or rest == "alles") and "all" or "zone"
  ns.ExportFrame:ShowExport(scope)
end

commands.import = function()
  if needModule("Learn") then ns.ExportFrame:ShowImport() end
end

commands.share = function()
  if needModule("Party") then ns.Party:ShareAll() end
end
commands.deel = commands.share

commands.debug = function(rest)
  if rest == "profile" then
    if ns.Debug.profiling then
      ns.Debug:Dump(ns.Debug:StopProfile())
    else
      ns.Debug:StartProfile()
      ns:Print(L["PROFILE_STARTED"])
    end
    return
  end
  local on = not ns:GetSetting("general", "debug")
  ns:SetSetting("general", "debug", on)
  if on then ns.Debug:ShowWindow() else ns.Debug:HideWindow() end
  ns:Print(on and L["DEBUG_ON"] or L["DEBUG_OFF"])
end

commands.dump = function()
  ns.QuestData:Refresh()
  local lines = ns.QuestData:DumpLines()
  if ns:IsModuleEnabled("Navigator") then
    lines[#lines + 1] = "Locaties:"
    for _, q in ipairs(ns.QuestData:GetList()) do
      local p = ns.Navigator:ResolveQuest(q.questID, true)
      lines[#lines + 1] = string.format("  %d %s: %s", q.questID, q.title,
        p and string.format("%s map %d %.1f,%.1f", p.source, p.mapID, p.x * 100, p.y * 100) or "onbekend")
    end
  end
  if ns.Tracker and ns.Tracker.lastBuildMs then
    lines[#lines + 1] = string.format("Tracker herbouw: %.2f ms", ns.Tracker.lastBuildMs)
  end
  ns.Debug:Dump(lines)
end

commands.plan = function(rest)
  if not needModule("Planner") then return end
  if rest == "debug" then ns.Debug:Dump(ns.Planner:DebugLines()) else commands.next() end
end

commands.version = function()
  local client = C.GetClientInterface()
  local version, build = C.GetClientBuild()
  ns:Print(string.format(L["VERSION_FMT"], tostring(ns.version), ns.TOC_INTERFACE, tostring(client),
    tostring(version), tostring(build)))
  if client and client ~= ns.TOC_INTERFACE then ns:Print(L["VERSION_MISMATCH"]) end
  local bridges = ns.Bridges and ns.Bridges:LoadedList() or {}
  ns:Print(L["BRIDGES"] .. ": " .. (#bridges > 0 and table.concat(bridges, ", ") or L["NONE"]))
  if ns:IsModuleEnabled("Learn") then ns:Print(string.format(L["LEARNED_COUNT_FMT"], ns.Learn:Count())) end
end

commands.help = function()
  for _, line in ipairs({ "HELP_1", "HELP_2", "HELP_3", "HELP_4", "HELP_5", "HELP_6", "HELP_7" }) do
    ns:Print(L[line])
  end
end

function ns:HandleSlash(msg)
  msg = ns.Util.Trim(msg or "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  local fn = commands[cmd]
  if not fn then
    ns:Print(string.format(L["UNKNOWN_COMMAND"], cmd))
    commands.help()
    return
  end
  fn(rest or "")
end

-- Allowed globals (spec 13.6).
SLASH_QUESTKOMPAS1 = "/qk"
SLASH_QUESTKOMPAS2 = "/questkompas"
SlashCmdList.QUESTKOMPAS = function(msg) ns:HandleSlash(msg) end

-- Key binding labels (Bindings.xml). Blizzard reads these globals by name;
-- they are an unavoidable exception to spec 13.6.
local function bindingLabels()
  BINDING_HEADER_QUESTKOMPAS = "QuestKompas"
  BINDING_NAME_QUESTKOMPAS_TOGGLE = L["BIND_TOGGLE"]
  BINDING_NAME_QUESTKOMPAS_NEXT = L["BIND_NEXT"]
  BINDING_NAME_QUESTKOMPAS_CLEAR = L["BIND_CLEAR"]
  _G["BINDING_NAME_CLICK QuestKompasItemButton1:LeftButton"] = L["BIND_ITEM1"]
end
bindingLabels()

-- Language switch at runtime.
ns:On("QK_SETTING_CHANGED", "Slash", function(_, section, key, value)
  if section == "general" and key == "language" then L:SetLanguage(value) bindingLabels() end
  if section == nil then L:SetLanguage(ns:GetSetting("general", "language")) bindingLabels() end
end)
ns:On("QK_READY", "Slash", bindingLabels)
