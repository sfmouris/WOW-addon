-- QuestKompas: own quest window (spec 4.3).
local _, ns = ...

local T = ns:RegisterModule("Tracker")
local C, U, L, Style = ns.Compat, ns.Util, ns.L, ns.Style

local MEDIA, COL, BAR_H = Style.MEDIA, Style.color, Style.BAR_H
local ICON_SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:12:12|t"
local ICON_LOCK = "|TInterface\\LFGFrame\\UI-LFG-ICON-LOCK:12:12|t"
local ICON_CLOCK = "|TInterface\\Icons\\INV_Misc_PocketWatch_01:12:12|t"
local ICON_DONE = Style.Icon("check", 11, COL.good)
local TITLE_H, OBJ_H, HEADER_H, PAD = 18, 13, 18, 6
local PROG_H, QUEST_GAP, HEADER_GAP = 4, 3, 4
-- One "row" of the maxRows setting, in pixels of visible height.
local ROW_UNIT = 14

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

-- Overall progress of a quest, 0 to 1: the average over its objectives, so
-- a "talk to" step weighs as much as "kill 10". nil without objectives.
function T.Progress(q)
  if q.isComplete then return 1 end
  local n, sum = 0, 0
  for _, o in ipairs(q.objectives or {}) do
    local need = math.max(o.need or 1, 1)
    local done = o.finished and need or math.min(math.max(o.done or 0, 0), need)
    n = n + 1
    sum = sum + done / need
  end
  if n == 0 then return nil end
  return sum / n
end

-- Visible height and scroll range for a content height and the row limit.
function T.ViewHeight(contentHeight, maxRows)
  local view = math.min(contentHeight, math.max(maxRows, 1) * ROW_UNIT)
  return view, math.max(0, contentHeight - view)
end

----------------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------------
local frame, scroll, content, footer, footerLine, thumb, nextBtn
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
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.05)
    row.chev = row:CreateTexture(nil, "ARTWORK")
    row.chev:SetSize(10, 10)
    row.chev:SetPoint("LEFT", 2, 0)
    row.chev:SetTexture(MEDIA .. "chevron")
    row.chev:SetVertexColor(COL.dim[1], COL.dim[2], COL.dim[3])
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.count:SetPoint("RIGHT", -4, 0)
    row.count:SetJustifyH("RIGHT")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", 16, 0)
    row.text:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.line = row:CreateTexture(nil, "BORDER")
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.line:SetColorTexture(COL.edge[1], COL.edge[2], COL.edge[3], 0.6)
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
    row.flash = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.flash:SetAllPoints()
    row.flash:SetColorTexture(1, 0.9, 0.3, 0.35)
    row.flash:Hide()
    row.targetBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.targetBg:SetAllPoints()
    row.targetBg:SetColorTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.10)
    row.targetBg:Hide()
    row.target = row:CreateTexture(nil, "BORDER")
    row.target:SetPoint("TOPLEFT") row.target:SetPoint("BOTTOMLEFT") row.target:SetWidth(2)
    row.target:SetColorTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.9)
    row.target:Hide()
    row.swatch = row:CreateTexture(nil, "ARTWORK")
    row.swatch:SetSize(3, TITLE_H - 6)
    row.swatch:SetPoint("LEFT", 5, 0)
    row.order = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.order:SetPoint("LEFT", 10, 0)
    row.order:SetWidth(16)
    row.order:SetJustifyH("RIGHT")
    row.dir = row:CreateTexture(nil, "ARTWORK")
    row.dir:SetSize(11, 11)
    row.dir:SetPoint("RIGHT", -3, 0)
    row.dir:SetTexture(MEDIA .. "arrow")
    row.dist = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.dist:SetPoint("RIGHT", row.dir, "LEFT", -3, 0)
    row.dist:SetJustifyH("RIGHT")
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.title:SetPoint("LEFT", row.order, "RIGHT", 4, 0)
    row.title:SetPoint("RIGHT", row.dist, "LEFT", -4, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.prog = Style.ProgressBar(row, 2)
    row.prog:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 30, -1)
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
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(5, 5)
    row.dot:SetPoint("LEFT", 33, 0)
    row.dot:SetTexture(MEDIA .. "dot")
    row.dot:SetVertexColor(COL.dim[1], COL.dim[2], COL.dim[3])
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(9, 9)
    row.check:SetPoint("LEFT", 31, 0)
    row.check:SetTexture(MEDIA .. "check")
    row.check:SetVertexColor(COL.faint[1], COL.faint[2], COL.faint[3])
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 43, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
  end
  pool[used[kind]] = row
  return row
end

local function releaseAll()
  for kind, pool in pairs({ header = headerPool, quest = questPool, obj = objPool }) do
    for i = 1, #pool do pool[i]:Hide() pool[i].quest = nil pool[i].bearing = nil end
    used[kind] = 0
  end
  wipe(shownQuestRows)
end

local function setDistance(row, q)
  local d = ns:IsModuleEnabled("Navigator") and ns.Navigator:GetQuestDistance(q)
  row.bearing = nil
  if d then
    row.dist:SetText(string.format(L["YARDS_SHORT_FMT"], d))
    local bearing = ns.Navigator:GetQuestBearing(q.questID)
    local facing = C.GetPlayerFacing()
    if bearing and facing then
      row.bearing = bearing
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
  elseif q.isComplete then title = ICON_DONE .. " " .. title end
  row.title:SetText(title .. markers(q))
  row.title:SetTextColor(col.r, col.g, col.b)
  local c = q.color or U.PALETTE[1]
  row.swatch:SetColorTexture(c[1], c[2], c[3], 1)
  local n = planOrder and planOrder[q.questID]
  row.order:SetText(n and tostring(n) or "")
  row.target:SetShown(targetID == q.questID)
  row.targetBg:SetShown(targetID == q.questID)
  -- A pending flash plays once on the fresh row; anything else is reset, so
  -- a reused row never keeps a half-played flash.
  if (flashUntil[q.questID] or 0) > C.GetTime() then
    flashUntil[q.questID] = nil
    Style.Flash(row.flash, 0.3)
  else
    Style.StopFlash(row.flash)
  end
  setDistance(row, q)
  shownQuestRows[#shownQuestRows + 1] = row
  y = y + TITLE_H
  local rows = 1
  local frac = (not q.isComplete) and T.Progress(q) or nil
  if frac then
    row.prog:SetProgress(frac, width - 34, c[1], c[2], c[3])
    row.prog:Show()
    y = y + PROG_H
  else
    row.prog:Hide()
  end
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
        orow.dot:SetShown(not o.finished)
        orow.check:SetShown(o.finished and true or false)
        if o.finished then
          orow.text:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        else
          orow.text:SetTextColor(0.85, 0.85, 0.85)
        end
        y = y + OBJ_H
        rows = rows + 1
      end
    end
  end
  return y + QUEST_GAP, rows
end

-- groupKey nil: plain info line (no chevron, not clickable).
local function addHeader(text, groupKey, y, width, count, col)
  if y > 0 then y = y + HEADER_GAP end
  local row = acquire("header")
  row.groupKey = groupKey
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", 0, -y)
  row:SetWidth(width)
  col = col or COL.dim
  row.text:SetTextColor(col[1], col[2], col[3])
  row.count:SetText(count and tostring(count) or "")
  if groupKey then
    row.text:SetText(text:upper())
    row.chev:SetRotation(ns.cdb.collapsed[groupKey] and math.pi / 2 or 0)
    row.chev:Show()
    row.line:Show()
  else
    row.text:SetText(text)
    row.chev:Hide()
    row.line:Hide()
  end
  return y + HEADER_H + 2
end

local function footerText()
  local parts = { T.CountText(ns.QuestData:Count(), C.GetMaxQuests()) }
  if ns:IsModuleEnabled("Stats") then
    local xph = ns.Stats:XPPerHour()
    if xph and xph > 0 then parts[#parts + 1] = string.format(L["XP_PER_HOUR_FMT"], U.FormatShort(xph)) end
    local n = ns.Stats:QuestsToLevel()
    if n then parts[#parts + 1] = string.format(L["QUESTS_TO_LEVEL_FMT"], n) end
  end
  return table.concat(parts, "  |cff6b7380·|r  ")
end

local function setScroll(value)
  local max = T.scrollMax or 0
  value = U.Clamp(value or 0, 0, max)
  T.scrollPos = value
  scroll:SetVerticalScroll(value)
  if max <= 0 then thumb:Hide() return end
  local view = T.viewHeight or 1
  local size = math.max(12, view * view / (view + max))
  thumb:ClearAllPoints()
  thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 4, -(view - size) * value / max)
  thumb:SetHeight(size)
  thumb:Show()
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
  nextBtn:SetShown(navOn and ns:IsModuleEnabled("Planner"))

  local minimized = ns.cdb.collapsed.all == true
  frame.minBtn:SetIcon(minimized and "chevron" or "minimize")
  if minimized then
    frame.count:SetText(T.CountText(ns.QuestData:Count(), C.GetMaxQuests()))
    scroll:Hide() footer:Hide() footerLine:Hide() thumb:Hide()
    frame:SetHeight(BAR_H)
    return
  end
  frame.count:SetText("")
  scroll:Show()

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

  local y = 0
  local function section(title, key, quests, collapsedDefault, col)
    if #quests == 0 then return end
    local collapsed = ns.cdb.collapsed[key]
    if collapsed == nil then collapsed = collapsedDefault end
    ns.cdb.collapsed[key] = collapsed
    y = addHeader(title, key, y, inner, #quests, col)
    if collapsed then return end
    for _, q in ipairs(quests) do
      y = addQuest(q, y, inner, planOrder, hideDone, targetID)
    end
  end
  section(L["GROUP_READY"], "ready", ready, false, COL.good)
  section(zoneName or L["GROUP_HERE"], "here", here, false, COL.text)
  section(L["GROUP_OTHER"], "other", other, true)
  if #list == 0 then
    y = addHeader(L["NO_QUESTS"], nil, y, inner)
  end

  -- Everything is built; more than maxRows worth of height scrolls.
  local view, range = T.ViewHeight(y, maxRows)
  content:SetSize(inner, math.max(y, 1))
  scroll:SetHeight(math.max(view, 1))
  scroll:EnableMouseWheel(range > 0)
  self.viewHeight, self.scrollMax = view, range
  setScroll(self.scrollPos)

  local showFooter = ns:GetSetting("tracker", "showFooter")
  footer:SetShown(showFooter)
  footerLine:SetShown(showFooter)
  if showFooter then footer:SetText(footerText()) end
  frame:SetHeight(BAR_H + 4 + view + 2 + (showFooter and 20 or 0))
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
  if not frame or not frame:IsShown() or C.InCombat() or ns.cdb.collapsed.all then return end
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
    if row.quest then setDistance(row, row.quest) end
  end
end

-- Ten times a second: turn the visible direction icons with the player.
-- Pure display on cached bearings, so it also runs in combat.
local turnAcc = 0
local function onUpdate(_, elapsed)
  turnAcc = turnAcc + elapsed
  if turnAcc < 0.1 then return end
  turnAcc = 0
  if #shownQuestRows == 0 then return end
  local facing = C.GetPlayerFacing()
  if not facing then return end
  for _, row in ipairs(shownQuestRows) do
    if row.bearing then row.dir:SetRotation(ns.Geo.RelativeAngle(row.bearing, facing)) end
  end
end

local function applyLook()
  local scale = U.Clamp(ns:GetSetting("tracker", "scale") or 1, 0.7, 1.5)
  frame:SetScale(scale)
  Style.Panel(frame, ns:GetSetting("tracker", "bgAlpha") or 0.6)
  frame.lockBtn:SetIcon(ns:GetSetting("tracker", "locked") and "lock" or "unlock")
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
  frame:SetScript("OnUpdate", onUpdate)

  local title = Style.TitleBar(frame, "QuestKompas", "icon")
  frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.count:SetPoint("LEFT", title, "RIGHT", 8, 0)

  -- Title bar buttons, right to left.
  frame.minBtn = Style.IconButton(frame, "minimize", function()
    return ns.cdb.collapsed.all and L["TIP_EXPAND"] or L["TIP_MINIMIZE"]
  end, function() T:ToggleMinimized() end)
  frame.minBtn:SetPoint("TOPRIGHT", -4, -3)
  frame.lockBtn = Style.IconButton(frame, "unlock", function()
    return ns:GetSetting("tracker", "locked") and L["TIP_UNLOCK"] or L["TIP_LOCK"]
  end, function() T:ToggleLock() end)
  frame.lockBtn:SetPoint("RIGHT", frame.minBtn, "LEFT", -2, 0)
  frame.gearBtn = Style.IconButton(frame, "gear", L["TIP_OPTIONS"], function() ns.Options:Open() end)
  frame.gearBtn:SetPoint("RIGHT", frame.lockBtn, "LEFT", -2, 0)
  nextBtn = Style.IconButton(frame, "next", L["TIP_NEXT"], function()
    ns.Navigator:Next(ns.Navigator:GetTargetQuestID())
  end)
  nextBtn:SetPoint("RIGHT", frame.gearBtn, "LEFT", -2, 0)
  frame.buttons = { frame.minBtn, frame.lockBtn, frame.gearBtn, nextBtn }

  scroll = CreateFrame("ScrollFrame", nil, frame)
  scroll:SetPoint("TOPLEFT", PAD, -(BAR_H + 4))
  scroll:SetPoint("TOPRIGHT", -PAD, -(BAR_H + 4))
  scroll:SetHeight(1)
  scroll:SetScript("OnMouseWheel", function(_, delta)
    setScroll((T.scrollPos or 0) - delta * 3 * ROW_UNIT)
  end)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(260 - 2 * PAD, 1)
  scroll:SetScrollChild(content)

  thumb = frame:CreateTexture(nil, "OVERLAY")
  thumb:SetWidth(2)
  thumb:SetColorTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.7)
  thumb:Hide()

  footerLine = frame:CreateTexture(nil, "BORDER")
  footerLine:SetPoint("BOTTOMLEFT", PAD, 20)
  footerLine:SetPoint("BOTTOMRIGHT", -PAD, 20)
  footerLine:SetHeight(1)
  footerLine:SetColorTexture(COL.edge[1], COL.edge[2], COL.edge[3], 0.6)
  footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", PAD, 6)
  footer:SetPoint("BOTTOMRIGHT", -PAD, 6)
  footer:SetJustifyH("LEFT")
  footer:SetWordWrap(false)

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

function T:ToggleMinimized()
  ns.cdb.collapsed.all = not ns.cdb.collapsed.all or nil
  self:Rebuild()
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

-- Marks the quest; the next rebuild plays the flash on its row.
function T:Flash(questID)
  flashUntil[questID] = C.GetTime() + 1.5
  self:RequestRebuild()
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
    for _, b in ipairs(frame.buttons) do b:EnableMouse(false) end
    scroll:EnableMouseWheel(false)
  end
end

function T:OnCombatEnd()
  if frame then
    frame:SetAlpha(1)
    frame:EnableMouse(true)
    for i = 1, #questPool do questPool[i]:EnableMouse(true) end
    for i = 1, #headerPool do headerPool[i]:EnableMouse(true) end
    for _, b in ipairs(frame.buttons) do b:EnableMouse(true) end
    scroll:EnableMouseWheel((self.scrollMax or 0) > 0)
    if self.dirty then self:Rebuild() end
  end
end
