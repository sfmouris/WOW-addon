-- QuestKompas: quest pins on world map and minimap (spec 4.9).
-- Uses HereBeDragons-Pins so the Blizzard map is never modified.
local ADDON, ns = ...

local MP = ns:RegisterModule("MapPins")
local C, L = ns.Compat, ns.L

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\UI\\Media\\"
local TEX_TURNIN = "Interface\\GossipFrame\\ActiveQuestIcon"
local TEX_GIVER = "Interface\\GossipFrame\\AvailableQuestIcon"
local REF_WORLD, REF_MINI = "QuestKompas-world", "QuestKompas-mini"

local pins -- HereBeDragons-Pins-2.0
local pools = { world = {}, mini = {} }
local inUse = { world = 0, mini = 0 }

local function onEnter(self)
  local d = self.data
  if not d then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if d.level and d.level > 0 then
    GameTooltip:AddLine(string.format("[%d] %s", d.level, d.title or "?"), 1, 0.82, 0)
  else
    GameTooltip:AddLine(d.title or "?", 1, 0.82, 0)
  end
  if d.text then GameTooltip:AddLine(d.text, 1, 1, 1, true) end
  GameTooltip:AddLine(L["PIN_CLICK_HINT"], 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

local function onClick(self)
  local d = self.data
  if not d or not ns:IsModuleEnabled("Navigator") then return end
  if d.questID and ns.QuestData:Get(d.questID) then
    ns.Navigator:SetQuest(d.questID)
  else
    ns.Navigator:SetPoint(d.mapID, d.x, d.y, d.title)
  end
end

local function acquire(kind)
  inUse[kind] = inUse[kind] + 1
  local f = pools[kind][inUse[kind]]
  if not f then
    f = CreateFrame("Button", nil, UIParent)
    f:SetSize(14, 14)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    f:SetScript("OnEnter", onEnter)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnClick", onClick)
    pools[kind][inUse[kind]] = f
  end
  return f
end

local function style(f, kind, color, size)
  f:SetSize(size, size)
  if kind == "turnin" then
    f.tex:SetTexture(TEX_TURNIN) f.tex:SetVertexColor(1, 1, 1) f.tex:SetDesaturated(false)
  elseif kind == "giver" then
    f.tex:SetTexture(TEX_GIVER) f.tex:SetVertexColor(1, 1, 1)
  elseif kind == "ring" then
    f.tex:SetTexture(MEDIA .. "ring") f.tex:SetVertexColor(0.3, 0.9, 1) f.tex:SetDesaturated(false)
  else
    f.tex:SetTexture(MEDIA .. "dot") f.tex:SetDesaturated(false)
    f.tex:SetVertexColor(color[1], color[2], color[3])
  end
end

local function add(kind, data, color, size, minimapToo)
  local f = acquire("world")
  f.data = data
  style(f, kind, color, size)
  if kind == "giver" then f.tex:SetDesaturated(data.tooLow and true or false) end
  pins:AddWorldMapIconMap(REF_WORLD, f, data.mapID, data.x, data.y, HBD_PINS_WORLDMAP_SHOW_CONTINENT)
  if minimapToo and ns:GetSetting("pins", "minimap") then
    local m = acquire("mini")
    m.data = data
    style(m, kind, color, math.max(10, size - 2))
    if kind == "giver" then m.tex:SetDesaturated(data.tooLow and true or false) end
    pins:AddMinimapIconMap(REF_MINI, m, data.mapID, data.x, data.y, true, kind == "ring")
  end
end

local function clear()
  if not pins then return end
  pins:RemoveAllWorldMapIcons(REF_WORLD)
  pins:RemoveAllMinimapIcons(REF_MINI)
  for kind, pool in pairs(pools) do
    for i = 1, #pool do pool[i]:Hide() pool[i].data = nil end
    inUse[kind] = 0
  end
end

local function giverMapID()
  local wm = WorldMapFrame
  if wm and wm:IsShown() and wm.GetMapID then return wm:GetMapID() end
  return C.GetPlayerMapID()
end

function MP:Refresh()
  if not pins then return end
  clear()
  local learnOn = ns:IsModuleEnabled("Learn")
  local navOn = ns:IsModuleEnabled("Navigator")
  for _, q in ipairs(ns.QuestData:GetList()) do
    local color = q.color or ns.Util.PALETTE[1]
    if q.isComplete then
      if ns:GetSetting("pins", "turnin") then
        local p = navOn and ns.Navigator:ResolveQuest(q.questID)
        if p then
          add("turnin", { questID = q.questID, mapID = p.mapID, x = p.x, y = p.y, title = q.title,
                          level = q.level, text = L["PIN_TURNIN"] }, color, 16, true)
        end
      end
    elseif ns:GetSetting("pins", "hotspots") and learnOn then
      for _, h in ipairs(ns.Learn:GetHotspots(q.questID)) do
        add("dot", { questID = q.questID, mapID = h.m, x = h.x, y = h.y, title = q.title, level = q.level,
                     text = string.format(L["PIN_HOTSPOT_FMT"], h.c) }, color, 10, true)
      end
    end
  end
  if ns:GetSetting("pins", "givers") and learnOn then
    local mapID = giverMapID()
    if mapID then
      for _, g in ipairs(ns.Learn:GetGivers(mapID)) do
        add("giver", { questID = g.questID, mapID = mapID, x = g.x, y = g.y, title = g.title, level = g.level,
                       text = g.npc, tooLow = g.tooLow }, nil, 16, true)
      end
    end
  end
  if ns:GetSetting("pins", "nav") and navOn and ns.Navigator.point then
    local p = ns.Navigator.point
    add("ring", { mapID = p.mapID, x = p.x, y = p.y, title = p.title, text = L["PIN_NAV"] }, nil, 24, true)
  end
end

function MP:RequestRefresh()
  ns:Debounce("MapPins.refresh", 0.5, function()
    ns:RunOutOfCombat(function() MP:Refresh() end, "MapPins.refresh")
  end)
end

----------------------------------------------------------------------------
-- Coordinates under the world map (player and cursor)
----------------------------------------------------------------------------
local coords
local function createCoords()
  local wm = WorldMapFrame
  if not wm or coords then return end
  coords = CreateFrame("Frame", nil, wm)
  coords:SetSize(300, 16)
  local anchor = wm.ScrollContainer or wm
  coords:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 4)
  coords:SetFrameStrata("HIGH")
  coords.text = coords:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  coords.text:SetAllPoints()
  local elapsed = 0
  coords:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0
    if not ns:GetSetting("pins", "coords") then self.text:SetText("") return end
    local _, px, py = C.GetPlayerPosition()
    local playerText = px and string.format("%.1f, %.1f", px * 100, py * 100) or "-"
    local cursorText = "-"
    local sc = wm.ScrollContainer
    if sc and sc.GetNormalizedCursorPosition and sc:IsMouseOver() then
      local cx, cy = sc:GetNormalizedCursorPosition()
      if cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
        cursorText = string.format("%.1f, %.1f", cx * 100, cy * 100)
      end
    end
    self.text:SetText(string.format(L["COORDS_FMT"], playerText, cursorText))
  end)
end

----------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------
local mapHooked = false
function MP:OnEnable()
  pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
  if not pins then
    ns.Debug:Log("HereBeDragons-Pins ontbreekt, kaartpins uit")
    return
  end
  local function req() MP:RequestRefresh() end
  ns:On("QK_QUESTS_UPDATED", "MapPins", req)
  ns:On("QK_LEARN_UPDATED", "MapPins", req)
  ns:On("QK_NAV_CHANGED", "MapPins", req)
  ns:On("ZONE_CHANGED_NEW_AREA", "MapPins", req)
  ns:On("QK_SETTING_CHANGED", "MapPins", function(_, section)
    if section == "pins" or section == "modules" or section == nil then req() end
  end)
  createCoords()
  if not mapHooked and WorldMapFrame and WorldMapFrame.OnMapChanged and hooksecurefunc then
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
      if MP.enabled and ns:GetSetting("pins", "givers") then req() end
    end)
    mapHooked = true
  end
  req()
end

function MP:OnDisable()
  clear()
end
