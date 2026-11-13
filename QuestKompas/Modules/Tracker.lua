-- QuestKompas: own quest window (spec 4.3).
local ADDON, ns = ...

local T = ns:RegisterModule("Tracker")
local C, U, L = ns.Compat, ns.Util, ns.L

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\UI\\Media\\"
local ICON_SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:12:12|t"
local ICON_LOCK = "|TInterface\\LFGFrame\\UI-LFG-ICON-LOCK:12:12|t"
local ICON_CLOCK = "|TInterface\\Icons\\INV_Misc_PocketWatch_01:12:12|t"
local TITLE_H, OBJ_H, HEADER_H, PAD = 15, 13, 16, 6

----------------------------------------------------------------------------
-- Pure logic: sorting and grouping (tests/spec_tracker.lua)
----------------------------------------------------------------------------
-- distFn(q) -> yards or nil. manual: array of questIDs.
function T.SortQuests(list, mode, distFn, manual)
  local out = {}
  for i = 1, #list do out[i] = list[i] end
  local logPos = {}
  for i, q in ipairs(list) do logPos[q.questID] = i end
  local key = {}
  if mode == "distance" then
    for _, q in ipairs(out) do key[q.questID] = distFn and distFn(q) or nil end
    table.sort(out, function(a, b)
      local da, db = key[a.questID], key[b.questID]
      if da and db and da ~= db then return da < db end
      if da and not db then return true end
      if db and not da then return false end
      return logPos[a.questID] < logPos[b.questID]
    end)
  elseif mode == "level" then
    table.sort(out, function(a, b)
      if a.level ~= b.level then return a.level < b.level end
      return logPos[a.questID] < logPos[b.questID]
    end)
  elseif mode == "zone" then
    table.sort(out, function(a, b)
      local za, zb = a.zoneHeader or "", b.zoneHeader or ""
      if za ~= zb then return za < zb end
      return logPos[a.questID] < logPos[b.questID]
    end)
  elseif mode == "manual" then
    local pos = {}
    for i, id in ipairs(manual or {}) do pos[id] = i end
    table.sort(out, function(a, b)
      local pa, pb = pos[a.questID], pos[b.questID]
      if pa and pb and pa ~= pb then return pa < pb end
      if pa and not pb then return true end
      if pb and not pa then return false end
      return logPos[a.questID] < logPos[b.questID]
    end)
  end
  return out
end

-- Splits sorted quests into: ready to turn in, current zone, other zones.
function T.Group(sorted, zoneName, mapID)
  local ready, here, other = {}, {}, {}
  for _, q in ipairs(sorted) do
    if q.isComplete then
      ready[#ready + 1] = q
    elseif (zoneName and q.zoneHeader == zoneName) or (mapID and q.mapID == mapID) or q.isHere then
      here[#here + 1] = q
    else
      other[#other + 1] = q
    end
  end
  return ready, here, other
end

-- Footer: "17/25".
function T.CountText(n, max)
  return string.format("%d/%d", n, max)
end

----------------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------------
local frame, content, footer, nextBtn
local headerPool, questPool, objPool = {}, {}, {}
local used = { header = 0, quest = 0, obj = 0 }
local shownQuestRows = {}
local flashUntil = {}

local function savePosition()
  local point, _, relPoint, x, y = frame:GetPoint(1)
  ns.cdb.positions.tracker = { point, x, y, relPoint }
end

local function applyPosition()
  frame:ClearAllPoints()
  local pos = ns.cdb.positions.tracker
  if pos then
    frame:SetPoint(pos[1], UIParent, pos[4] or pos[1], pos[2], pos[3])
  else
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -220)
  end
end

local function questTooltip(row)
  local q = row.quest and ns.QuestData:Get(row.quest.questID)
  if not q then return end
  local tip = GameTooltip
  tip:SetOwner(row, "ANCHOR_LEFT")
  local col = U.DifficultyColor(q.difficulty)
  tip:AddLine(string.format("[%d] %s", q.level, q.title), col.r, col.g, col.b)
  local desc = C.GetQuestDescription(q.questID)
  if desc then tip:AddLine(desc, 1, 1, 1, true) end
  for _, o in ipairs(q.objectives) do
    local r, g, b = 0.9, 0.9, 0.9
    if o.finished then r, g, b = 0.5, 0.5, 0.5 end
    tip:AddLine("- " .. o.text, r, g, b, true)
  end
  local rewards = {}
  if q.xpReward and q.xpReward > 0 then
    rewards[#rewards + 1] = string.format(L["XP_FMT"], U.FormatShort(q.xpReward))
  end
  if q.moneyReward and q.moneyReward > 0 then rewards[#rewards + 1] = U.FormatMoney(q.moneyReward) end
  if #rewards > 0 then tip:AddLine(L["REWARDS"] .. ": " .. table.concat(rewards, ", "), 1, 0.82, 0) end
  if q.suggestedGroup and q.suggestedGroup > 1 then
    tip:AddLine(string.format(L["GROUP_SUGGESTED"], q.suggestedGroup), 1, 0.5, 0.25)
  end
  local p = ns:IsModuleEnabled("Navigator") and ns.Navigator:ResolveQuest(q.questID)
  if p then
    tip:AddLine(string.format(L["LOCATION_SOURCE"], L["SOURCE_" .. p.source:upper()]), 0.6, 0.8, 1)
  else
    tip:AddLine(L["LOCATION_UNKNOWN"], 0.6, 0.6, 0.6)
  end
  if ns:IsModuleEnabled("Learn") then
    local info = ns.Learn:Describe(q.questID)
    if info then tip:AddLine(info, 0.6, 0.8, 1, true) end
  end
  if ns:IsModuleEnabled("Party") then
    for _, line in ipairs(ns.Party:DescribeProgress(q.questID)) do tip:AddLine(line, 0.5, 1, 0.5) end
  end
  local note = ns.db.notes[q.questID]
  if note then tip:AddLine(L["NOTE"] .. ": " .. note, 1, 1, 0.6, true) end
  tip:AddLine(L["TRACKER_HINT"], 0.5, 0.5, 0.5, true)
  tip:Show()
end

local function moveManual(questID, delta)
  local order = ns.cdb.manualOrder
  local present = {}
  for _, id in ipairs(order) do present[id] = true end
  for _, q in ipairs(ns.QuestData:GetList()) do
    if not present[q.questID] then order[#order + 1] = q.questID end
  end
  for i, id in ipairs(order) do
    if id == questID then
      local j = i + delta
      if j >= 1 and j <= #order then order[i], order[j] = order[j], order[i] end
      break
    end
  end
  T:RequestRebuild()
end

local function contextMenu(row)
  local q = row.quest
  if not (q and MenuUtil and MenuUtil.CreateContextMenu) then return end
  local id = q.questID
  MenuUtil.CreateContextMenu(row, function(_, root)
    root:CreateTitle(q.title)
    root:CreateButton(L["MENU_NAVIGATE"], function() ns.Navigator:SetQuest(id) end)
    root:CreateButton(L["MENU_OPEN_LOG"], function() C.OpenQuestDetails(id) end)
    if C.IsPushableQuest(id) and C.IsInGroup() then
      root:CreateButton(L["MENU_SHARE"], function() C.ShareQuest(id) end)
    end
    if q.suggestedGroup and q.suggestedGroup > 1 then
      root:CreateButton(L["MENU_LFM"], function() T.PostLFM(id) end)
    end
    if q.isWatched then
      root:CreateButton(L["MENU_UNWATCH"], function() C.RemoveQuestWatch(id) end)
    else
      root:CreateButton(L["MENU_WATCH"], function() C.AddQuestWatch(id) end)
    end
    root:CreateButton(L["MENU_NOTE"], function() ns.LogTools:EditNote(id) end)
    if ns.db.blacklist[id] then
      root:CreateButton(L["MENU_UNBLACKLIST"], function() ns.db.blacklist[id] = nil end)
    else
      root:CreateButton(L["MENU_BLACKLIST"], function() ns.db.blacklist[id] = true end)
    end
    if ns:GetSetting("tracker", "sort") == "manual" then
      root:CreateButton(L["MENU_UP"], function() moveManual(id, -1) end)
      root:CreateButton(L["MENU_DOWN"], function() moveManual(id, 1) end)
    end
    root:CreateDivider()
    root:CreateButton(L["MENU_ABANDON"], function() ns.LogTools:ConfirmAbandon(id) end)
  end)
end

-- Group-finder line in the chat input; the player presses Enter (2.5).
function T.PostLFM(questID)
  local q = ns.QuestData:Get(questID)
  if not q then return end
  local kind = q.isElite and L["ELITE"] or (q.tagName or L["GROUP"])
  local link = C.GetQuestLink(questID) or ("[" .. q.title .. "]")
  C.OpenChatWithText(string.format(L["LFM_FMT"], link, kind:lower(), math.max(q.suggestedGroup or 2, 2)))
end

local function acquire(kind)
  used[kind] = used[kind] + 1
  local pool = (kind == "header" and headerPool) or (kind == "quest" and questPool) or objPool
  local row = pool[used[kind]]
  if row then row:Show() return row end

  if kind == "header" then
    row = CreateFrame("Button", nil, content)
    row:SetHeight(HEADER_H)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", 2, 0)
    row:SetScript("OnClick", function(self)
      if self.groupKey then
        ns.cdb.collapsed[self.groupKey] = not ns.cdb.collapsed[self.groupKey]
        T:Rebuild()
      end
    end)
  elseif kind == "quest" then
    row = CreateFrame("Button", nil, content)
    row:SetHeight(TITLE_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.08)
    row.flash = row:CreateTexture(nil, "BACKGROUND")
    row.flash:SetAllPoints()
    row.flash:SetColorTexture(1, 0.9, 0.3, 0.35)
    row.flash:Hide()
    row.target = row:CreateTexture(nil, "BACKGROUND")
    row.target:SetPoint("TOPLEFT") row.target:SetPoint("BOTTOMLEFT") row.target:SetWidth(2)
    row.target:SetColorTexture(0.3, 0.9, 1, 0.9)
    row.target:Hide()
    row.swatch = row:CreateTexture(nil, "ARTWORK")
    row.swatch:SetSize(3, TITLE_H - 4)
    row.swatch:SetPoint("LEFT", 4, 0)
    row.order = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.order:SetPoint("LEFT", 10, 0)
    row.order:SetWidth(16)
    row.order:SetJustifyH("RIGHT")
    row.dir = row:CreateTexture(nil, "ARTWORK")
    row.dir:SetSize(11, 11)
    row.dir:SetPoint("RIGHT", -2, 0)
    row.dir:SetTexture(MEDIA .. "arrow")
    row.dist = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.dist:SetPoint("RIGHT", row.dir, "LEFT", -3, 0)
    row.dist:SetJustifyH("RIGHT")
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.title:SetPoint("LEFT", row.order, "RIGHT", 3, 0)
    row.title:SetPoint("RIGHT", row.dist, "LEFT", -4, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row:SetScript("OnClick", function(self, button)
      if not self.quest then return end
      if button == "RightButton" then
        contextMenu(self)
      elseif IsShiftKeyDown and IsShiftKeyDown() then
        C.InsertChatLink(C.GetQuestLink(self.quest.questID))
      elseif ns:IsModuleEnabled("Navigator") then
        ns.Navigator:SetQuest(self.quest.questID)
      end
    end)
    row:SetScript("OnEnter", questTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  else
    row = CreateFrame("Frame", nil, content)
    row:SetHeight(OBJ_H)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 32, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
  end
  pool[used[kind]] = row
  return row
end

local function releaseAll()
  for kind, pool in pairs({ header = headerPool, quest = questPool, obj = objPool }) do
    for i = 1, #pool do pool[i]:Hide() pool[i].quest = nil end
    used[kind] = 0
  end
  wipe(shownQuestRows)
end

local function setDistance(row, q)
  local d = ns:IsModuleEnabled("Navigator") and ns.Navigator:GetQuestDistance(q)
  if d then
    row.dist:SetText(string.format(L["YARDS_SHORT_FMT"], d))
    local bearing = ns.Navigator:GetQuestBearing(q.questID)
    local facing = C.GetPlayerFacing()
    if bearing and facing then
      row.dir:SetRotation(ns.Geo.RelativeAngle(bearing, facing))
      row.dir:Show()
    else
      row.dir:Hide()
    end
  else
    local p = ns:IsModuleEnabled("Navigator") and ns.Navigator:ResolveQuest(q.questID)
    row.dist:SetText(p and L["OTHER_ZONE_SHORT"] or L["UNKNOWN_SHORT"])
    row.dir:Hide()
  end
end

local function markers(q)
  local s = ""
  if q.suggestedGroup and q.suggestedGroup > 1 then s = s .. " |cffff8040+" .. q.suggestedGroup .. "|r" end
  if q.isElite then s = s .. " " .. ICON_SKULL end
  if q.tagName == "Dungeon" or q.tagName == "Raid" or q.tagName == "Heroic" then s = s .. " " .. ICON_LOCK end
  if q.hasTimer then s = s .. " " .. ICON_CLOCK end
  return s
end

local function addQuest(q, y, width, planOrder, hideDone, targetID)
  local row = acquire("quest")
  row.quest = q
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", 0, -y)
  row:SetWidth(width)
  local col = U.DifficultyColor(q.difficulty)
  local title = string.format("[%d] %s", q.level, q.title)
  if q.isFailed then title = title .. " |cffff3030(" .. L["FAILED"] .. ")|r"
  elseif q.isComplete then title = title .. " |cff40ff40(" .. L["DONE"] .. ")|r" end
  row.title:SetText(title .. markers(q))
  row.title:SetTextColor(col.r, col.g, col.b)
  local c = q.color or U.PALETTE[1]
  row.swatch:SetColorTexture(c[1], c[2], c[3], 1)
  local n = planOrder and planOrder[q.questID]
  row.order:SetText(n and tostring(n) or "")
  row.target:SetShown(targetID == q.questID)
  row.flash:SetShown((flashUntil[q.questID] or 0) > C.GetTime())
  setDistance(row, q)
  shownQuestRows[#shownQuestRows + 1] = row
  y = y + TITLE_H
  local rows = 1
  if not q.isComplete then
    for _, o in ipairs(q.objectives) do
      if not (hideDone and o.finished) then
        local orow = acquire("obj")
        orow:ClearAllPoints()
        orow:SetPoint("TOPLEFT", 0, -y)
        orow:SetWidth(width)
        local text = o.text
        if o.need > 1 and not text:find("%d+/%d+") then
          text = string.format("%s %d/%d", text, o.done, o.need)
        end
        orow.text:SetText(text)
        if o.finished then orow.text:SetTextColor(0.5, 0.5, 0.5) else orow.text:SetTextColor(0.85, 0.85, 0.85) end
        y = y + OBJ_H
        rows = rows + 1
      end
    end
  end
  return y, rows
end

local function addHeader(text, groupKey, y, width)
  local row = acquire("header")
  row.groupKey = groupKey
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", 0, -y)
  row:SetWidth(width)
  local mark = groupKey and (ns.cdb.collapsed[groupKey] and "[+] " or "[-] ") or ""
  row.text:SetText(mark .. text)
  return y + HEADER_H
end

local function footerText()
  local parts = { T.CountText(ns.QuestData:Count(), C.GetMaxQuests()) }
  if ns:IsModuleEnabled("Stats") then
    local xph = ns.Stats:XPPerHour()
    if xph and xph > 0 then parts[#parts + 1] = string.format(L["XP_PER_HOUR_FMT"], U.FormatShort(xph)) end
    local n = ns.Stats:QuestsToLevel()
    if n then parts[#parts + 1] = string.format(L["QUESTS_TO_LEVEL_FMT"], n) end
  end
  return table.concat(parts, "  |  ")
end

function T:Rebuild()
  if not frame or not frame:IsShown() then return end
  if C.InCombat() then self.dirty = true return end
  local start = debugprofilestop and debugprofilestop()
  self.dirty = false
  releaseAll()
  local width = ns:GetSetting("tracker", "width") or 260
  local maxRows = ns:GetSetting("tracker", "maxRows") or 30
  local hideDone = ns:GetSetting("tracker", "hideDone")
  frame:SetWidth(width)
  local inner = width - 2 * PAD

  local list = ns.QuestData:GetList()
  local navOn = ns:IsModuleEnabled("Navigator")
  local mapID = C.GetPlayerMapID()
  local zoneName = C.GetMapName(mapID)
  if navOn then
    for _, q in ipairs(list) do
      local p = ns.Navigator:ResolveQuest(q.questID)
      q.isHere = p ~= nil and mapID ~= nil and p.mapID == mapID
    end
  end
  local sorted = T.SortQuests(list, ns:GetSetting("tracker", "sort"),
    navOn and function(q) return ns.Navigator:GetQuestDistance(q) end or nil, ns.cdb.manualOrder)
  local ready, here, other = T.Group(sorted, zoneName, mapID)
  local planOrder = ns:IsModuleEnabled("Planner") and ns.Planner:GetOrderMap() or nil
  local targetID = navOn and ns.Navigator:GetTargetQuestID() or nil

  local y, rows, cut = 0, 0, 0
  local function section(title, key, quests, collapsedDefault)
    if #quests == 0 then return end
    local collapsed = ns.cdb.collapsed[key]
    if collapsed == nil then collapsed = collapsedDefault end
    ns.cdb.collapsed[key] = collapsed
    y = addHeader(string.format("%s (%d)", title, #quests), key, y, inner)
    if collapsed then return end
    for _, q in ipairs(quests) do
      if rows >= maxRows then cut = cut + 1 else
        local used_
        y, used_ = addQuest(q, y, inner, planOrder, hideDone, targetID)
        rows = rows + used_
      end
    end
  end
  section(L["GROUP_READY"], "ready", ready, false)
  section(zoneName or L["GROUP_HERE"], "here", here, false)
  section(L["GROUP_OTHER"], "other", other, true)
  if #list == 0 then
    y = addHeader(L["NO_QUESTS"], nil, y, inner)
  end
  if cut > 0 then
    y = addHeader(string.format(L["MORE_FMT"], cut), nil, y, inner)
  end

  content:SetHeight(math.max(y, 1))
  local showFooter = ns:GetSetting("tracker", "showFooter")
  footer:SetShown(showFooter)
  if showFooter then footer:SetText(footerText()) end
  nextBtn:SetShown(ns:IsModuleEnabled("Planner") and ns:IsModuleEnabled("Navigator"))
  frame:SetHeight(y + 22 + (showFooter and 16 or 0) + PAD)
  if start then
    self.lastBuildMs = debugprofilestop() - start
    ns.Debug:Trace(string.format("tracker rebuild %.2f ms (%d quests)", self.lastBuildMs, #list))
  end
end

function T:RequestRebuild()
  ns:Throttle("Tracker.rebuild", 0.5, function() T:Rebuild() end)
end

-- Every second: distances and direction icons only; resort when needed.
local lastOrder = ""
local function tick()
  if not frame or not frame:IsShown() or C.InCombat() then return end
  ns.QuestData:RefreshDistances()
  if ns:GetSetting("tracker", "sort") == "distance" and ns:IsModuleEnabled("Navigator") then
    local sorted = T.SortQuests(ns.QuestData:GetList(), "distance",
      function(q) return ns.Navigator:GetQuestDistance(q) end)
    local ids = {}
    for i, q in ipairs(sorted) do ids[i] = q.questID end
    local key = table.concat(ids, ",")
    if key ~= lastOrder then
      lastOrder = key
      T:RequestRebuild()
      return
    end
  end
  for _, row in ipairs(shownQuestRows) do
    if row.quest then
      setDistance(row, row.quest)
      if row.flash:IsShown() and (flashUntil[row.quest.questID] or 0) <= C.GetTime() then row.flash:Hide() end
    end
  end
end

local function applyLook()
  local scale = U.Clamp(ns:GetSetting("tracker", "scale") or 1, 0.7, 1.5)
  frame:SetScale(scale)
  U.SkinFrame(frame, ns:GetSetting("tracker", "bgAlpha") or 0.6)
  local locked = ns:GetSetting("tracker", "locked")
  frame.lockIcon:SetText(locked and L["LOCKED"] or "")
end

local function createFrame()
  frame = CreateFrame("Frame", nil, UIParent)
  frame:SetSize(260, 100)
  frame:SetFrameStrata("LOW")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if not ns:GetSetting("tracker", "locked") and not C.InCombat() then self:StartMoving() end
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
  end)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", PAD, -5)
  title:SetText("QuestKompas")
  frame.lockIcon = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.lockIcon:SetPoint("LEFT", title, "RIGHT", 6, 0)

  nextBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  nextBtn:SetSize(64, 16)
  nextBtn:SetPoint("TOPRIGHT", -PAD, -3)
  nextBtn:SetText(L["NEXT"])
  nextBtn:SetScript("OnClick", function() ns.Navigator:Next(ns.Navigator:GetTargetQuestID()) end)

  content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", PAD, -22)
  content:SetPoint("TOPRIGHT", -PAD, -22)
  content:SetHeight(1)

  footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", PAD, 5)
  footer:SetPoint("BOTTOMRIGHT", -PAD, 5)
  footer:SetJustifyH("LEFT")

  applyPosition()
  applyLook()
end

----------------------------------------------------------------------------
-- Blizzard tracker (optional, off by default).
-- TODO(verify): SetAlpha(0) out of combat is the least invasive route; check
-- taint.log in game before relying on it.
----------------------------------------------------------------------------
local blizzHidden = false
function T:ApplyBlizzardTracker()
  ns:RunOutOfCombat(function()
    local otf = ObjectiveTrackerFrame
    if not otf then return end
    if ns:GetSetting("tracker", "hideBlizzard") then
      otf:SetAlpha(0)
      blizzHidden = true
    elseif blizzHidden then
      otf:SetAlpha(1)
      blizzHidden = false
    end
  end, "Tracker.blizz")
end

----------------------------------------------------------------------------
-- Public
----------------------------------------------------------------------------
function T:SetShown(show)
  ns:SetSetting("tracker", "shown", show)
  if frame then frame:SetShown(show) end
  if show then self:Rebuild() end
end

function T:Toggle()
  self:SetShown(not (frame and frame:IsShown()))
end

function T:ToggleLock()
  ns:SetSetting("tracker", "locked", not ns:GetSetting("tracker", "locked"))
  if frame then applyLook() end
  return ns:GetSetting("tracker", "locked")
end

function T:ResetPosition()
  ns.cdb.positions.tracker = nil
  if frame then applyPosition() end
end

function T:Flash(questID)
  flashUntil[questID] = C.GetTime() + 0.3
end

function T:GetFrame()
  return frame
end

local ticker
function T:OnEnable()
  if not frame then createFrame() end
  frame:SetShown(ns:GetSetting("tracker", "shown") ~= false)
  self:ApplyBlizzardTracker()
  local function rebuild() T:RequestRebuild() end
  ns:On("QK_QUESTS_UPDATED", "Tracker", rebuild)
  ns:On("QK_NAV_CHANGED", "Tracker", rebuild)
  ns:On("QK_PLAN_UPDATED", "Tracker", rebuild)
  ns:On("ZONE_CHANGED_NEW_AREA", "Tracker", rebuild)
  ns:On("PLAYER_XP_UPDATE", "Tracker", function()
    ns:Debounce("Tracker.footer", 1, rebuild)
  end)
  ns:On("QK_OBJECTIVE_PROGRESS", "Tracker", function(_, questID) T:Flash(questID) end)
  ns:On("QK_SETTING_CHANGED", "Tracker", function(_, section, key)
    if section == "tracker" or section == nil then
      applyLook()
      if key == "hideBlizzard" or section == nil then T:ApplyBlizzardTracker() end
      if key == "shown" then return end
      T:RequestRebuild()
    elseif section == "modules" then
      T:RequestRebuild()
    end
  end)
  if ticker then ticker:Cancel() end
  ticker = C_Timer.NewTicker(1, tick)
  self:Rebuild()
end

function T:OnDisable()
  if ticker then ticker:Cancel() ticker = nil end
  if frame then frame:Hide() end
  if blizzHidden and ObjectiveTrackerFrame then
    ns:RunOutOfCombat(function() ObjectiveTrackerFrame:SetAlpha(1) blizzHidden = false end, "Tracker.blizz")
  end
end

function T:OnCombatStart()
  if frame and ns:GetSetting("tracker", "fadeInCombat") then
    frame:SetAlpha(0.3)
    frame:EnableMouse(false)
    for i = 1, used.quest do questPool[i]:EnableMouse(false) end
    for i = 1, used.header do headerPool[i]:EnableMouse(false) end
    nextBtn:EnableMouse(false)
  end
end

function T:OnCombatEnd()
  if frame then
    frame:SetAlpha(1)
    frame:EnableMouse(true)
    for i = 1, #questPool do questPool[i]:EnableMouse(true) end
    for i = 1, #headerPool do headerPool[i]:EnableMouse(true) end
    nextBtn:EnableMouse(true)
    if self.dirty then self:Rebuild() end
  end
end
