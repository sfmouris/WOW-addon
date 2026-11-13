-- Minimal imitation of the WoW client API, enough to load QuestKompas and
-- exercise its logic outside the game (spec 12.4). Frames are mocks: any
-- unknown method is a no-op. This is NOT a substitute for in-game testing.
local stub = {}
_G.stub = stub

local ADDON_DIR = (arg and arg[0] and arg[0]:match("^(.*)/tests/") or ".") .. "/QuestKompas/"
stub.ADDON_DIR = ADDON_DIR

----------------------------------------------------------------------------
-- Lua 5.1 helpers that WoW provides
----------------------------------------------------------------------------
function _G.wipe(t) for k in pairs(t) do t[k] = nil end return t end
_G.strsplit = function(sep, s)
  local out = {}
  for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = p end
  return unpack(out)
end
_G.tinsert, _G.tremove = table.insert, table.remove
_G.date = os.date
_G.time = os.time
_G.debugprofilestop = function() return os.clock() * 1000 end
_G.bit = _G.bit or {}

----------------------------------------------------------------------------
-- Clock and timers
----------------------------------------------------------------------------
local timers = {}

local function addTimer(delay, fn, interval)
  local t = { at = stub.now + delay, fn = fn, interval = interval, cancelled = false }
  function t:Cancel() self.cancelled = true end
  function t:IsCancelled() return self.cancelled end
  timers[#timers + 1] = t
  return t
end

_G.GetTime = function() return stub.now end
_G.C_Timer = {
  After = function(delay, fn) addTimer(delay, fn) end,
  NewTimer = function(delay, fn) return addTimer(delay, fn) end,
  NewTicker = function(delay, fn) return addTimer(delay, fn, delay) end,
}

-- Moves the clock forward and runs due timers in order.
function stub.Advance(dt)
  local target = stub.now + dt
  while true do
    local nextT, nextI
    for i, t in ipairs(timers) do
      if not t.cancelled and t.at <= target and (not nextT or t.at < nextT.at) then nextT, nextI = t, i end
    end
    if not nextT then break end
    stub.now = math.max(stub.now, nextT.at)
    if nextT.interval then
      nextT.at = nextT.at + nextT.interval
    else
      table.remove(timers, nextI)
    end
    nextT.fn(nextT)
  end
  stub.now = target
  for i = #timers, 1, -1 do if timers[i].cancelled then table.remove(timers, i) end end
end

----------------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------------
local eventFrames = {}
local function noop() end

local regionMethods = {}
function regionMethods:Show() self._shown = true end
function regionMethods:Hide() self._shown = false end
function regionMethods:SetShown(v) self._shown = v and true or false end
function regionMethods:IsShown() return self._shown end
function regionMethods:IsVisible() return self._shown end
function regionMethods:SetText(t) self._text = t end
function regionMethods:GetText() return self._text end
function regionMethods:SetPoint(...) self._points = self._points or {} table.insert(self._points, { ... }) end
function regionMethods:ClearAllPoints() self._points = {} end
function regionMethods:GetPoint()
  local p = self._points and self._points[1]
  if not p then return "CENTER", nil, "CENTER", 0, 0 end
  if type(p[2]) == "table" then return p[1], p[2], p[3], p[4], p[5] end
  return p[1], nil, p[1], p[2], p[3]
end
function regionMethods:SetSize(w, h) self._w, self._h = w, h end
function regionMethods:SetWidth(w) self._w = w end
function regionMethods:SetHeight(h) self._h = h end
function regionMethods:GetWidth() return self._w or 100 end
function regionMethods:GetHeight() return self._h or 20 end
function regionMethods:GetStringHeight() return 12 end
function regionMethods:SetScript(name, fn) self._scripts[name] = fn end
function regionMethods:GetScript(name) return self._scripts[name] end
function regionMethods:HookScript(name, fn) self._scripts[name] = fn end
function regionMethods:SetAttribute(k, v) self._attr[k] = v end
function regionMethods:GetAttribute(k) return self._attr[k] end
function regionMethods:GetID() return self._id or 0 end
function regionMethods:SetID(id) self._id = id end
function regionMethods:IsMouseOver() return false end
function regionMethods:GetName() return self._name end
function regionMethods:RegisterEvent(event)
  if stub.unknownEvents[event] then error("Attempt to register unknown event \"" .. event .. "\"") end
  self._events[event] = true
  eventFrames[self] = true
end
function regionMethods:UnregisterEvent(event) self._events[event] = nil end
function regionMethods:IsEventRegistered(event) return self._events[event] == true end

local frameMT
local function newRegion(kind, name)
  local r = setmetatable({ _kind = kind, _shown = true, _scripts = {}, _attr = {}, _events = {}, _name = name },
    frameMT)
  return r
end

frameMT = {
  __index = function(_, key)
    local m = regionMethods[key]
    if m then return m end
    if key == "CreateTexture" or key == "CreateFontString" or key == "CreateAnimationGroup"
      or key == "CreateAnimation" then
      return function() return newRegion("region") end
    end
    -- WoW widget methods start with an upper-case letter; other keys are
    -- plain fields and read as nil.
    if type(key) == "string" and key:match("^%u") then return noop end
    return nil
  end,
}

_G.CreateFrame = function(kind, name, parent, template)
  local f = newRegion(kind, name)
  f._parent, f._template = parent, template
  if name then _G[name] = f end
  stub.frames[#stub.frames + 1] = f
  return f
end

-- Fires a client event on every frame that registered it.
function stub.FireEvent(event, ...)
  for f in pairs(eventFrames) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end

----------------------------------------------------------------------------
-- Quest log with configurable fake data
----------------------------------------------------------------------------
-- stub.log = { { header = "Westfall" }, { questID = 1, title = "...", level = 12, ... } }
local function logEntry(i) return stub.log[i] end
local function findQuest(id)
  for i, e in ipairs(stub.log) do if e.questID == id then return e, i end end
end

_G.C_QuestLog = {
  GetNumQuestLogEntries = function()
    local n = 0
    for _, e in ipairs(stub.log) do if e.questID then n = n + 1 end end
    return #stub.log, n
  end,
  GetInfo = function(i)
    local e = logEntry(i)
    if not e then return nil end
    if e.header then return { title = e.header, isHeader = true, questID = 0, level = 0 } end
    return { title = e.title, questID = e.questID, level = e.level or 1, difficultyLevel = e.level or 1,
             suggestedGroup = e.group or 0, isHeader = false, isHidden = false, frequency = e.frequency,
             questLogIndex = i }
  end,
  GetQuestObjectives = function(id)
    local e = findQuest(id)
    local out = {}
    for k, o in ipairs(e and e.objectives or {}) do
      out[k] = { text = o.text, type = o.type or "monster", numFulfilled = o.done, numRequired = o.need,
                 finished = o.done >= o.need }
    end
    return out
  end,
  IsComplete = function(id) local e = findQuest(id) return e and e.complete or false end,
  ReadyForTurnIn = function(id) local e = findQuest(id) return e and e.complete or false end,
  IsFailed = function() return false end,
  GetQuestTagInfo = function(id)
    local e = findQuest(id)
    if e and e.tagID then return { tagID = e.tagID, tagName = "", isElite = e.elite } end
    return nil
  end,
  GetSuggestedGroupSize = function(id) local e = findQuest(id) return e and e.group or 0 end,
  GetQuestDifficultyLevel = function(id) local e = findQuest(id) return e and e.level or 0 end,
  GetDistanceSqToQuest = function(id)
    local e = findQuest(id)
    if e and e.dist then return e.dist * e.dist, true end
    return nil, false
  end,
  GetLogIndexForQuestID = function(id) local _, i = findQuest(id) return i end,
  GetQuestIDForLogIndex = function(i) local e = logEntry(i) return e and e.questID end,
  IsQuestFlaggedCompleted = function(id) return stub.completed[id] == true end,
  IsOnQuest = function(id) return findQuest(id) ~= nil end,
  RequestLoadQuestByID = function(id) stub.loadRequests[#stub.loadRequests + 1] = id end,
  GetTitleForQuestID = function(id) local e = findQuest(id) return e and e.title end,
  IsRepeatableQuest = function() return false end,
  GetTimeAllowed = function() return nil end,
  GetQuestWatchType = function(id) local e = findQuest(id) return e and e.watched and 0 or nil end,
  GetMaxNumQuestsCanAccept = function() return stub.maxQuests end,
  GetNextWaypoint = function(id)
    local e = findQuest(id)
    if e and e.waypoint then return unpack(e.waypoint) end
    return nil
  end,
  GetQuestsOnMap = function() return {} end,
  IsPushableQuest = function() return true end,
  SetSelectedQuest = function(id) stub.selected = id end,
  GetSelectedQuest = function() return stub.selected end,
  SetAbandonQuest = function() stub.abandonPending = stub.selected end,
  AbandonQuest = function()
    stub.abandoned[#stub.abandoned + 1] = stub.abandonPending
    stub.abandonPending = nil
  end,
}
_G.C_TaskQuest = { GetQuestsOnMap = function() return {} end }
_G.GetQuestLogSpecialItemInfo = function(i)
  local e = logEntry(i)
  if e and e.item then return e.item, 134400, 1, false end
  return nil
end
_G.GetQuestLogRewardXP = function(id) local e = findQuest(id) return e and e.xp or 0 end
_G.GetQuestLogRewardMoney = function(id) local e = findQuest(id) return e and e.money or 0 end
_G.GetQuestLink = function(id) return "|cffffff00|Hquest:" .. id .. "|h[quest]|h|r" end

----------------------------------------------------------------------------
-- NPC interaction (configurable through stub.npc)
----------------------------------------------------------------------------
_G.C_GossipInfo = {
  GetAvailableQuests = function() return stub.npc.available or {} end,
  GetActiveQuests = function() return stub.npc.active or {} end,
  SelectAvailableQuest = function(id) stub.calls[#stub.calls + 1] = "SelectAvailable:" .. id end,
  SelectActiveQuest = function(id) stub.calls[#stub.calls + 1] = "SelectActive:" .. id end,
  GetOptions = function() return stub.npc.options or {} end,
  SelectOption = function(id) stub.calls[#stub.calls + 1] = "SelectOption:" .. id end,
}
_G.GetQuestID = function() return stub.npc.questID or 0 end
_G.GetTitleText = function() return stub.npc.title end
_G.QuestGetAutoAccept = function() return false end
_G.QuestFlagsPVP = function() return false end
_G.AcceptQuest = function() stub.calls[#stub.calls + 1] = "AcceptQuest" end
_G.AcknowledgeAutoAcceptQuest = function() stub.calls[#stub.calls + 1] = "Acknowledge" end
_G.IsQuestCompletable = function() return stub.npc.completable end
_G.CompleteQuest = function() stub.calls[#stub.calls + 1] = "CompleteQuest" end
_G.GetQuestMoneyToGet = function() return stub.npc.moneyToGet or 0 end
_G.GetNumQuestChoices = function() return stub.npc.choices or 0 end
_G.GetNumQuestCurrencies = function() return 0 end
_G.GetNumQuestItems = function() return #(stub.npc.required or {}) end
_G.GetQuestItemInfo = function(kind, i)
  local it = stub.npc.required and stub.npc.required[i]
  if kind == "required" and it then return it.name, 0, it.count or 1, 1, true, it.itemID end
  return nil
end
_G.GetQuestReward = function(i) stub.calls[#stub.calls + 1] = "GetQuestReward:" .. tostring(i) end
_G.GetNumActiveQuests = function() return 0 end
_G.GetNumAvailableQuests = function() return 0 end

----------------------------------------------------------------------------
-- Player, map, misc
----------------------------------------------------------------------------
_G.InCombatLockdown = function() return stub.combat end
_G.UnitLevel = function() return stub.level end
_G.UnitEffectiveLevel = function() return stub.level end
_G.UnitQuestTrivialLevelRange = function() return 5 end
_G.UnitXP = function() return stub.xp end
_G.UnitXPMax = function() return stub.xpMax end
_G.UnitName = function(unit) return stub.unitNames[unit] end
_G.UnitGUID = function(unit) return stub.unitGUIDs[unit] end
_G.UnitFactionGroup = function() return "Alliance" end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitRace = function() return "Human", "Human" end
_G.UnitExists = function(unit) return stub.unitGUIDs[unit] ~= nil end
_G.GetMoney = function() return 0 end
_G.GetMaxPlayerLevel = function() return 60 end
_G.IsInInstance = function() return stub.inInstance, stub.inInstance and "party" or "none" end
_G.IsInGroup = function() return stub.inGroup end
_G.GetNumGroupMembers = function() return stub.inGroup and 2 or 0 end
_G.IsShiftKeyDown = function() return stub.shift end
_G.IsControlKeyDown = function() return false end
_G.IsAltKeyDown = function() return false end
_G.GetPlayerFacing = function() return stub.facing end
_G.GetBuildInfo = function() return "1.60.1", "70888", "Nov 10 2026", 16001 end
_G.PlaySound = noop
_G.SOUNDKIT = { MAP_PING = 3175 }
_G.hooksecurefunc = function(a, b, c)
  if type(a) == "table" then
    local orig = a[b]
    a[b] = function(...) local r = { orig(...) } c(...) return unpack(r) end
  end
end
_G.C_AddOns = {
  GetAddOnMetadata = function(_, field) if field == "Version" then return "test" end end,
  IsAddOnLoaded = function(name) return stub.loadedAddons[name] == true end,
}
_G.C_Map = {
  GetBestMapForUnit = function() return stub.pos and stub.pos[1] end,
  GetPlayerMapPosition = function()
    if not stub.pos then return nil end
    return { GetXY = function() return stub.pos[2], stub.pos[3] end }
  end,
  GetMapInfo = function(id) return stub.maps[id] end,
  -- 1000 x 1000 yards per map, every map on continent 0 (tests only)
  GetWorldPosFromMapPos = function(mapID, vec)
    local info = stub.maps[mapID]
    if not info then return nil end
    local ox, oy = info.ox or 0, info.oy or 0
    return 0, { GetXY = function() return -(vec.y * 1000 + oy), -(vec.x * 1000 + ox) end }
  end,
}
_G.CreateVector2D = function(x, y) return { x = x, y = y } end
_G.C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, msg, channel) stub.sent[#stub.sent + 1] = { prefix, msg, channel } end,
}
_G.C_Item = {
  GetItemInfoInstant = function(item)
    if stub.items[item] then return unpack(stub.items[item]) end
    return nil
  end,
  GetItemInfo = function() return nil end,
  GetItemCount = function() return 1 end,
}
_G.Enum = { ItemClass = { Questitem = 12 } }
_G.QuestDifficultyColors = nil
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) stub.chat[#stub.chat + 1] = msg end }
_G.UIErrorsFrame = { AddMessage = function(_, msg) stub.center[#stub.center + 1] = msg end }
_G.geterrorhandler = function() return function(err) stub.errors[#stub.errors + 1] = tostring(err) end end
_G.SlashCmdList = {}
_G.GameTooltip = setmetatable({}, frameMT)
_G.GameFontHighlightSmall = {}
_G.ClearOverrideBindings = noop
_G.SetOverrideBindingClick = noop
_G.IsLoggedIn = function() return false end

-- Settings API with argument checks against the verified 1.60.1 signatures.
local function assertType(v, t, what) assert(type(v) == t, what .. " expected " .. t .. ", got " .. type(v)) end
_G.Settings = {
  VarType = { Boolean = "boolean", String = "string", Number = "number" },
  RegisterVerticalLayoutCategory = function(name)
    assertType(name, "string", "category name")
    return { GetID = function() return 42 end }, { AddInitializer = function(_, i) assert(i) end }
  end,
  RegisterVerticalLayoutSubcategory = function(parent, name)
    assertType(parent, "table", "parent category") assertType(name, "string", "subcategory name")
    stub.subcategories[#stub.subcategories + 1] = name
    return { GetID = function() return 43 end }, { AddInitializer = function(_, i) assert(i) end }
  end,
  RegisterProxySetting = function(cat, variable, varType, name, default, get, set)
    assertType(cat, "table", "category") assertType(variable, "string", "variable")
    assertType(varType, "string", "varType") assertType(name, "string", "name")
    assert(type(default) == varType, "default type for " .. variable)
    assertType(get, "function", "getValue") assertType(set, "function", "setValue")
    assert(type(get()) == varType or get() == nil, "getter type for " .. variable)
    stub.settings[variable] = { get = get, set = set }
    return { GetVariableType = function() return varType end, GetName = function() return name end }
  end,
  CreateCheckbox = function(cat, setting, tooltip)
    assert(cat and setting)
    stub.tooltips[setting.GetName()] = tooltip
  end,
  CreateSlider = function(cat, setting, options, tooltip)
    assert(cat and setting and options)
    stub.tooltips[setting.GetName()] = tooltip
  end,
  CreateDropdown = function(cat, setting, options, tooltip)
    assert(cat and setting) assertType(options, "function", "dropdown options")
    stub.tooltips[setting.GetName()] = tooltip
    options()
  end,
  CreateSliderOptions = function(minV, maxV, rate)
    assert(type(minV) == "number" and type(maxV) == "number" and type(rate) == "number")
    return { SetLabelFormatter = function(_, _, fn) assert(type(fn("1") or "") == "string") end }
  end,
  CreateControlTextContainer = function()
    local data = {}
    return { Add = function(_, v, label) data[#data + 1] = { v, label } end, GetData = function() return data end }
  end,
  RegisterAddOnCategory = function(cat) assert(cat) end,
  OpenToCategory = function(id) stub.calls[#stub.calls + 1] = "OpenSettings:" .. tostring(id) end,
}
_G.MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
_G.CreateSettingsListSectionHeaderInitializer = function(name) assertType(name, "string", "header") return {} end
_G.CreateSettingsButtonInitializer = function(name, text, fn)
  assertType(name, "string", "button name") assertType(text, "string", "button text")
  assertType(fn, "function", "button click")
  return {}
end

----------------------------------------------------------------------------
-- Reset and addon loader
----------------------------------------------------------------------------
function stub.Reset()
  stub.now = 1000
  wipe(timers)
  for f in pairs(eventFrames) do eventFrames[f] = nil end
  stub.frames = {}
  stub.log = {}
  stub.completed = {}
  stub.loadRequests = {}
  stub.abandoned = {}
  stub.maxQuests = 25
  stub.npc = {}
  stub.calls = {}
  stub.combat = false
  stub.level = 12
  stub.xp, stub.xpMax = 100, 1000
  stub.unitNames, stub.unitGUIDs = {}, {}
  stub.inInstance, stub.inGroup, stub.shift = false, false, false
  stub.facing = 0
  stub.pos = nil
  stub.maps = { [52] = { name = "Westfall", mapType = 3 }, [37] = { name = "Elwynn Forest", mapType = 3, ox = 2000 } }
  stub.loadedAddons = {}
  stub.sent, stub.chat, stub.center, stub.errors = {}, {}, {}, {}
  stub.items = {}
  stub.settings = {}
  stub.subcategories, stub.tooltips = {}, {}
  stub.unknownEvents = {}
  _G.QuestKompasDB, _G.QuestKompasCharDB = nil, nil
  _G.SlashCmdList = {}
end

-- Loads every file from the TOC except HereBeDragons (needs the real map
-- data). Returns the addon namespace.
function stub.LoadAddon(opts)
  opts = opts or {}
  local ns = {}
  local toc = assert(io.open(ADDON_DIR .. "QuestKompas.toc"))
  for line in toc:lines() do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^##") and not line:match("^#") then
      local path = line:gsub("\\", "/")
      if not path:find("HereBeDragons", 1, true) then
        local chunk = assert(loadfile(ADDON_DIR .. path))
        chunk("QuestKompas", ns)
      end
    end
  end
  toc:close()
  if opts.savedDB then _G.QuestKompasDB = opts.savedDB end
  if opts.savedCharDB then _G.QuestKompasCharDB = opts.savedCharDB end
  if opts.login ~= false then
    stub.FireEvent("ADDON_LOADED", "QuestKompas")
    stub.FireEvent("PLAYER_LOGIN")
    stub.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    stub.Advance(1)
  end
  return ns
end

stub.Reset()
return stub
