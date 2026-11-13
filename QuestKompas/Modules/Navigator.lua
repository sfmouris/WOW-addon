-- QuestKompas: arrow and distance to the active target (spec 4.4).
local _, ns = ...

local Nav = ns:RegisterModule("Navigator")
local C, Geo, L, Style = ns.Compat, ns.Geo, ns.L, ns.Style

local MEDIA, COL = Style.MEDIA, Style.color
local RESOLVE_TTL, POI_TTL = 2, 2

Nav.target = nil        -- { kind = "quest", questID } or { kind = "point", mapID, x, y, title }
Nav.point = nil         -- resolved { mapID, x, y, source, title }
local resolveCache = {} -- questID -> { t, point }
local poiCache = {}     -- mapID -> { t, byQuest }

----------------------------------------------------------------------------
-- Source layers (spec 3.2 / 4.4)
----------------------------------------------------------------------------
local function poisForMap(mapID)
  local now = C.GetTime()
  local entry = poiCache[mapID]
  if entry and now - entry.t < POI_TTL then return entry.byQuest end
  local byQuest = {}
  for _, info in ipairs(C.GetQuestPOIsOnMap(mapID)) do
    local id = info.questID or info.questId
    if id and info.x and info.y then
      byQuest[id] = { mapID = info.mapID or mapID, x = info.x, y = info.y }
    end
  end
  poiCache[mapID] = { t = now, byQuest = byQuest }
  return byQuest
end

-- Resolves where to go for a quest. Returns point table or nil.
function Nav:ResolveQuest(questID, noCache)
  local now = C.GetTime()
  local cached = resolveCache[questID]
  if cached and not noCache and now - cached.t < RESOLVE_TTL then return cached.point end
  local q = ns.QuestData:Get(questID)
  local title = q and q.title or C.GetQuestTitle(questID)
  local isComplete = q and q.isComplete or false
  local point

  local m, x, y = C.GetNextWaypoint(questID)
  if m then point = { mapID = m, x = x, y = y, source = "client" } end

  if not point then
    local pm = C.GetPlayerMapID()
    if pm then
      local p = poisForMap(pm)[questID]
      if p then point = { mapID = p.mapID, x = p.x, y = p.y, source = "poi" } end
    end
  end

  local pm, px, py = C.GetPlayerPosition()
  if not point and ns:IsModuleEnabled("Bridges") then
    local bm, bx, by = ns.Bridges:GetQuestPoint(questID, isComplete, pm, px, py)
    if bm then point = { mapID = bm, x = bx, y = by, source = "questie" } end
  end

  if not point and ns:IsModuleEnabled("Learn") then
    local lm, lx, ly = ns.Learn:GetQuestPoint(questID, isComplete, pm, px, py)
    if lm then point = { mapID = lm, x = lx, y = ly, source = "learned" } end
  end

  if point then point.title = title end
  resolveCache[questID] = { t = now, point = point }
  return point
end

function Nav:InvalidateCache(questID)
  if questID then resolveCache[questID] = nil else resolveCache = {} end
  poiCache = {}
end

-- Distance in yards for a quest: client distance first, then resolved point.
function Nav:GetQuestDistance(q)
  if q.distanceSq then return math.sqrt(q.distanceSq) end
  local p = self:ResolveQuest(q.questID)
  if not p then return nil end
  local pm, px, py = C.GetPlayerPosition()
  if not pm then return nil end
  return (Geo.Distance(pm, px, py, p.mapID, p.x, p.y))
end

-- Bearing from player to a quest's point, for the tracker direction icon.
function Nav:GetQuestBearing(questID)
  local p = self:ResolveQuest(questID)
  if not p then return nil end
  local pm, px, py = C.GetPlayerPosition()
  if not pm then return nil end
  return Geo.Bearing(pm, px, py, p.mapID, p.x, p.y)
end

----------------------------------------------------------------------------
-- Arrow frame
----------------------------------------------------------------------------
local arrow, ticker
local speed = { lastD = nil, lastT = nil, yps = nil }

local function savePosition(frame)
  local point, _, relPoint, x, y = frame:GetPoint(1)
  ns.cdb.positions.arrow = { point, x, y, relPoint }
end

-- Arrow tint for the angle between facing and target (radians, any range):
-- green when heading straight at it, yellow sideways, red when it is behind.
function Nav.ArrowColor(relAngle)
  -- Deviation as a fraction of a half turn, 0 (ahead) to 1 (behind).
  local dev = math.acos(math.max(-1, math.min(1, math.cos(relAngle or 0)))) / math.pi
  local r = dev < 0.5 and dev * 2 or 1
  local g = dev < 0.5 and 1 or (1 - dev) * 2
  return 0.25 + 0.75 * r, 0.25 + 0.75 * g, 0.25
end

local function turnArrow(f, facing)
  if not (Nav.bearing and facing) then return end
  local rel = Geo.RelativeAngle(Nav.bearing, facing)
  f.arrow:SetRotation(rel)
  f.arrow:SetVertexColor(Nav.ArrowColor(rel))
end

local function createArrow()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(150, 96)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if not ns:GetSetting("tracker", "locked") then self:StartMoving() end
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition(self)
  end)
  f:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then Nav:Clear() end
  end)
  -- Every frame: only the facing changes; the bearing comes from the ticker.
  f:SetScript("OnUpdate", function(self)
    if self.arrow:IsShown() then turnArrow(self, C.GetPlayerFacing()) end
  end)

  local tex = f:CreateTexture(nil, "ARTWORK")
  tex:SetSize(44, 44)
  tex:SetPoint("TOP", 0, 0)
  tex:SetTexture(MEDIA .. "arrow")
  tex:SetVertexColor(COL.accent[1], COL.accent[2], COL.accent[3])
  f.arrow = tex

  local check = f:CreateTexture(nil, "ARTWORK")
  check:SetSize(38, 38)
  check:SetPoint("TOP", 0, -3)
  check:SetTexture(MEDIA .. "check")
  check:SetVertexColor(COL.good[1], COL.good[2], COL.good[3])
  check:Hide()
  f.check = check

  -- Text block on a small panel so it stays readable over any terrain.
  local info = CreateFrame("Frame", nil, f)
  info:SetPoint("TOPLEFT", 0, -48)
  info:SetPoint("BOTTOMRIGHT")
  Style.Panel(info, 0.55)
  local dist = info:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  dist:SetPoint("TOP", 0, -5)
  f.dist = dist
  local title = info:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOP", dist, "BOTTOM", 0, -2)
  title:SetWidth(140)
  title:SetWordWrap(false)
  f.title = title
  local eta = info:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  eta:SetPoint("TOP", title, "BOTTOM", 0, -2)
  f.eta = eta

  local pos = ns.cdb.positions.arrow
  if pos then
    f:SetPoint(pos[1], UIParent, pos[4] or pos[1], pos[2], pos[3])
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  end
  f:Hide()
  return f
end

function Nav:ResetPosition()
  ns.cdb.positions.arrow = nil
  if arrow then
    arrow:ClearAllPoints()
    arrow:SetPoint("TOP", UIParent, "TOP", 0, -120)
  end
end

local function stopTicker()
  if ticker then ticker:Cancel() ticker = nil end
end

local function useOwnArrow()
  if ns:GetSetting("nav", "mode") == "native" then return false end
  if ns:GetSetting("nav", "useTomTom") and ns:IsModuleEnabled("Bridges") and ns.Bridges:HasTomTom() then
    return false
  end
  return true
end

-- Throttled arrow update (ticker at 0.15 s). Pure display: uses the cached
-- target point, so it is safe in combat.
function Nav:UpdateArrow()
  if not arrow or not self.point then return end
  local p = self.point
  local pm, px, py = C.GetPlayerPosition()
  local facing = C.GetPlayerFacing()
  if not pm or not facing then
    arrow:Hide()
    return
  end
  arrow:Show()
  arrow.title:SetText(p.title or "")
  self.bearing = nil
  local d = Geo.Distance(pm, px, py, p.mapID, p.x, p.y)
  if not d then
    arrow.arrow:Hide()
    arrow.check:Hide()
    arrow.dist:SetText(L["OTHER_ZONE"])
    arrow.eta:SetText(C.GetMapName(p.mapID) or "")
    return
  end
  local arriveYards = ns:GetSetting("nav", "arriveYards") or 10
  if d <= arriveYards then
    if not self.arrived then
      self.arrived = true
      if ns:GetSetting("nav", "sound") then C.PlaySound("MAP_PING") end
    end
    arrow.arrow:Hide()
    arrow.check:Show()
    arrow.dist:SetText(string.format(L["YARDS_FMT"], d))
    arrow.eta:SetText("")
    return
  elseif d > arriveYards * 2 then
    self.arrived = false
  end
  arrow.check:Hide()
  arrow.arrow:Show()
  self.bearing = Geo.Bearing(pm, px, py, p.mapID, p.x, p.y)
  turnArrow(arrow, facing)
  arrow.dist:SetText(string.format(L["YARDS_FMT"], d))

  -- ETA from a smoothed approach speed.
  local now = C.GetTime()
  if speed.lastD and speed.lastT and now > speed.lastT then
    local v = (speed.lastD - d) / (now - speed.lastT)
    speed.yps = speed.yps and (speed.yps * 0.85 + v * 0.15) or v
  end
  speed.lastD, speed.lastT = d, now
  if speed.yps and speed.yps > 0.5 then
    arrow.eta:SetText(ns.Util.FormatDuration(d / speed.yps))
  else
    arrow.eta:SetText("")
  end
end

local function startTicker()
  stopTicker()
  speed.lastD, speed.lastT, speed.yps = nil, nil, nil
  ticker = C_Timer.NewTicker(0.15, function() Nav:UpdateArrow() end)
end

----------------------------------------------------------------------------
-- Target handling
----------------------------------------------------------------------------
local function applyNative(target, point)
  if ns:GetSetting("nav", "mode") ~= "native" then return end
  if target.kind == "quest" then C.SuperTrackQuest(target.questID) end
  if point and (target.kind == "point" or point.source ~= "client") then
    C.SetUserWaypoint(point.mapID, point.x, point.y)
  end
end

local function applyTomTom(point)
  if not (ns:GetSetting("nav", "useTomTom") and ns:IsModuleEnabled("Bridges")) then return end
  ns.Bridges:TomTomSet(point)
end

-- Re-resolves the current target and refreshes all displays.
function Nav:Apply()
  local t = self.target
  if not t then
    self.point = nil
    stopTicker()
    if arrow then arrow:Hide() end
    ns:Fire("QK_NAV_CHANGED")
    return
  end
  local point
  if t.kind == "quest" then
    point = self:ResolveQuest(t.questID, true)
  else
    point = { mapID = t.mapID, x = t.x, y = t.y, title = t.title, source = "user" }
  end
  self.point = point
  self.arrived = false
  applyNative(t, point)
  applyTomTom(point)
  if point and useOwnArrow() then
    if not arrow then arrow = createArrow() end
    arrow:SetScale(ns.Util.Clamp(ns:GetSetting("nav", "scale") or 1, 0.7, 1.5))
    local q = t.kind == "quest" and ns.QuestData:Get(t.questID)
    local c = q and q.color or COL.accent
    arrow.title:SetTextColor(c[1], c[2], c[3])
    arrow:Show()
    startTicker()
    self:UpdateArrow()
  else
    stopTicker()
    if arrow then arrow:Hide() end
  end
  ns:Fire("QK_NAV_CHANGED")
end

function Nav:SetQuest(questID)
  ns:RunOutOfCombat(function()
    self.target = { kind = "quest", questID = questID }
    ns.cdb.nav = { kind = "quest", questID = questID }
    self:Apply()
    if not self.point then
      local q = ns.QuestData:Get(questID)
      ns:Print(string.format(L["NAV_UNKNOWN"], q and q.title or tostring(questID)))
    end
  end, "nav")
end

function Nav:SetPoint(mapID, x, y, title)
  ns:RunOutOfCombat(function()
    self.target = { kind = "point", mapID = mapID, x = x, y = y, title = title }
    ns.cdb.nav = { kind = "point", mapID = mapID, x = x, y = y, title = title }
    self:Apply()
  end, "nav")
end

function Nav:Clear()
  ns:RunOutOfCombat(function()
    self.target = nil
    ns.cdb.nav = nil
    if ns:GetSetting("nav", "mode") == "native" then
      C.ClearUserWaypoint()
      C.ClearSuperTrack()
    end
    if ns:IsModuleEnabled("Bridges") then ns.Bridges:TomTomClear() end
    self:Apply()
  end, "nav")
end

function Nav:GetTargetQuestID()
  return self.target and self.target.kind == "quest" and self.target.questID or nil
end

-- Chooses the next target: planner first, nearest known quest otherwise.
function Nav:Next(excludeID)
  local nextID
  if ns:IsModuleEnabled("Planner") then nextID = ns.Planner:GetNextQuestID(excludeID) end
  if not nextID then
    local best, bestD
    for _, q in ipairs(ns.QuestData:GetList()) do
      if q.questID ~= excludeID then
        local d = self:GetQuestDistance(q)
        if d and (not bestD or d < bestD) then best, bestD = q.questID, d end
      end
    end
    nextID = best
  end
  if nextID then self:SetQuest(nextID) else self:Clear() end
  return nextID
end

-- /qk way 45.2 67.8 [zone]
function Nav:FindMapByName(name)
  name = name:lower()
  local best
  for _, mapID in ipairs(C.GetAllMapIDs()) do
    local info = C.GetMapInfo(mapID)
    if info and info.name and info.name:lower() == name then
      if info.mapType == 3 then return mapID end -- Enum.UIMapType.Zone
      best = best or mapID
    end
  end
  return best
end

function Nav:Way(args)
  local xs, ys, zone = args:match("^%s*([%d%.]+)[,%s]+([%d%.]+)%s*(.-)%s*$")
  local x, y = tonumber(xs), tonumber(ys)
  if not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then
    ns:Print(L["WAY_USAGE"])
    return false
  end
  local mapID
  if zone and zone ~= "" then
    mapID = self:FindMapByName(zone)
    if not mapID then ns:Print(string.format(L["WAY_NO_ZONE"], zone)) return false end
  else
    mapID = C.GetPlayerMapID()
    if not mapID then ns:Print(L["WAY_NO_POSITION"]) return false end
  end
  local title = string.format("%s %.1f, %.1f", C.GetMapName(mapID) or "", x, y)
  self:SetPoint(mapID, x / 100, y / 100, title)
  return true
end

----------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------
function Nav:OnEnable()
  ns:On("QK_QUEST_COMPLETED", "Navigator", function(_, questID)
    Nav:InvalidateCache(questID)
    if Nav:GetTargetQuestID() == questID then
      if ns:GetSetting("nav", "autoAdvance") then Nav:Next() else Nav:Apply() end
    end
  end)
  ns:On("QK_QUEST_REMOVED", "Navigator", function(_, questID)
    Nav:InvalidateCache(questID)
    if Nav:GetTargetQuestID() == questID then
      if ns:GetSetting("nav", "autoAdvance") then Nav:Next(questID) else Nav:Clear() end
    end
  end)
  ns:On("QUEST_POI_UPDATE", "Navigator", function() Nav:InvalidateCache() end)
  ns:On("QK_LEARN_UPDATED", "Navigator", function(_, questID) Nav:InvalidateCache(questID) end)
  ns:On("ZONE_CHANGED_NEW_AREA", "Navigator", function()
    Nav:InvalidateCache()
    if Nav.target then ns:Debounce("Navigator.zone", 1, function() Nav:Apply() end) end
  end)
  ns:On("QK_SETTING_CHANGED", "Navigator", function(_, section)
    if section == "nav" or section == nil then Nav:Apply() end
  end)
  ns:On("QK_QUESTS_UPDATED", "Navigator", function(_, first)
    if first and not Nav.target and ns.cdb.nav then
      local saved = ns.cdb.nav
      if saved.kind == "quest" and ns.QuestData:Get(saved.questID) then
        Nav.target = { kind = "quest", questID = saved.questID }
        Nav:Apply()
      elseif saved.kind == "point" and saved.mapID then
        Nav.target = { kind = "point", mapID = saved.mapID, x = saved.x, y = saved.y, title = saved.title }
        Nav:Apply()
      end
    end
  end)
end

function Nav:OnDisable()
  stopTicker()
  if arrow then arrow:Hide() end
end
