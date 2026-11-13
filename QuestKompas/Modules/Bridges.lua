-- QuestKompas: optional Questie and TomTom integration (spec 4.12).
-- Questie has no stable public API: every call is wrapped in pcall and the
-- bridge switches itself off after repeated failures.
--
-- Structure checked against Questie v12.6.5 (Questie_Forever.toc,
-- Interface 16001): QuestieLoader:ImportModule("QuestieDB"),
-- QuestieDB.GetQuest(id) -> { Starts = { NPC, GameObject, Item },
-- Finisher = { NPC, GameObject }, ObjectiveData = { { Type, Id } } },
-- QuestieDB:GetNPC(id).spawns / QuestieDB:GetObject(id).spawns
-- = { [areaId] = { { x, y } } } in 0..100, ZoneDB:GetUiMapIdByAreaId(areaId).
local _, ns = ...

local BR = ns:RegisterModule("Bridges")
local C, L = ns.Compat, ns.L

local MAX_SPAWNS = 400
local questie = { state = "unknown", errors = 0 } -- unknown | ok | off
local tomtomUID

----------------------------------------------------------------------------
-- Pure: nearest spawn (tests/spec_bridges.lua)
-- spawns: { [areaId] = { {x, y}, ... } }, toMap(areaId) -> uiMapID
----------------------------------------------------------------------------
function BR.NearestSpawn(spawns, toMap, pm, px, py, dist, preferMap)
  local best, bestD, fallback
  local seen = 0
  for areaId, list in pairs(spawns or {}) do
    local mapID = toMap(areaId)
    if mapID and type(list) == "table" then
      for _, s in ipairs(list) do
        seen = seen + 1
        if seen > MAX_SPAWNS then break end
        local x, y = tonumber(s[1]), tonumber(s[2])
        if x and y and x >= 0 and y >= 0 then
          x, y = x / 100, y / 100
          local d = pm and dist(pm, px, py, mapID, x, y)
          if d and (not bestD or d < bestD) then
            best, bestD = { mapID, x, y }, d
          elseif not fallback or (preferMap and mapID == preferMap and fallback[1] ~= preferMap) then
            fallback = { mapID, x, y }
          end
        end
      end
    end
  end
  local p = best or fallback
  if p then return p[1], p[2], p[3] end
  return nil
end

----------------------------------------------------------------------------
-- Questie
----------------------------------------------------------------------------
local QDB, ZDB

local function questieFail(err)
  questie.errors = questie.errors + 1
  ns.Debug:Log("Questie-brug fout:", tostring(err))
  if questie.errors >= 3 then
    questie.state = "off"
    ns.Debug:Log("Questie-brug uitgeschakeld")
  end
end

local function setupQuestie()
  if questie.state ~= "unknown" then return questie.state == "ok" end
  if not C.IsAddOnLoaded("Questie") or type(QuestieLoader) ~= "table"
      or type(QuestieLoader.ImportModule) ~= "function" then
    questie.state = "off"
    return false
  end
  local ok, err = pcall(function()
    QDB = QuestieLoader:ImportModule("QuestieDB")
    ZDB = QuestieLoader:ImportModule("ZoneDB")
    assert(type(QDB.GetQuest) == "function", "QuestieDB.GetQuest ontbreekt")
    assert(type(QDB.GetNPC) == "function", "QuestieDB:GetNPC ontbreekt")
    assert(type(ZDB.GetUiMapIdByAreaId) == "function", "ZoneDB:GetUiMapIdByAreaId ontbreekt")
  end)
  if not ok then
    questie.state = "off"
    ns.Debug:Log("Questie-brug zelftest mislukt:", tostring(err))
    return false
  end
  questie.state = "ok"
  return true
end

local function toMap(areaId)
  return ZDB:GetUiMapIdByAreaId(areaId)
end

local function spawnsFor(kind, id)
  if kind == "npc" then
    local npc = QDB:GetNPC(id)
    return npc and npc.spawns
  elseif kind == "obj" and type(QDB.GetObject) == "function" then
    local obj = QDB:GetObject(id)
    return obj and obj.spawns
  end
  return nil
end

local function nearestOf(kind, ids, pm, px, py)
  local best, bestD
  for _, id in ipairs(ids or {}) do
    local m, x, y = BR.NearestSpawn(spawnsFor(kind, id), toMap, pm, px, py, ns.Geo.Distance, pm)
    if m then
      local d = pm and ns.Geo.Distance(pm, px, py, m, x, y) or math.huge
      if not bestD or d < bestD then best, bestD = { m, x, y }, d end
    end
  end
  if best then return best[1], best[2], best[3] end
  return nil
end

-- Navigator layer 3.
function BR:GetQuestPoint(questID, isComplete, pm, px, py)
  if not setupQuestie() then return nil end
  local ok, m, x, y = pcall(function()
    local quest = QDB.GetQuest(questID)
    if type(quest) ~= "table" then return nil end
    if isComplete then
      local f = quest.Finisher or {}
      local mm, xx, yy = nearestOf("npc", f.NPC, pm, px, py)
      if not mm then mm, xx, yy = nearestOf("obj", f.GameObject, pm, px, py) end
      return mm, xx, yy
    end
    local npcs, objs = {}, {}
    for _, o in ipairs(quest.ObjectiveData or {}) do
      if o.Type == "monster" and o.Id then npcs[#npcs + 1] = o.Id end
      if o.Type == "object" and o.Id then objs[#objs + 1] = o.Id end
    end
    local mm, xx, yy = nearestOf("npc", npcs, pm, px, py)
    if not mm then mm, xx, yy = nearestOf("obj", objs, pm, px, py) end
    return mm, xx, yy
  end)
  if not ok then questieFail(m) return nil end
  return m, x, y
end

function BR:QuestieState()
  return questie.state
end

----------------------------------------------------------------------------
-- TomTom
----------------------------------------------------------------------------
function BR:HasTomTom()
  return C.IsAddOnLoaded("TomTom") and type(TomTom) == "table" and type(TomTom.AddWaypoint) == "function"
end

function BR:TomTomClear()
  if tomtomUID and self:HasTomTom() and type(TomTom.RemoveWaypoint) == "function" then
    pcall(TomTom.RemoveWaypoint, TomTom, tomtomUID)
  end
  tomtomUID = nil
end

function BR:TomTomSet(point)
  if not self:HasTomTom() then return false end
  self:TomTomClear()
  if not point then return false end
  local ok, uid = pcall(TomTom.AddWaypoint, TomTom, point.mapID, point.x, point.y,
    { title = point.title or "QuestKompas", persistent = false, minimap = true, world = true })
  if ok then tomtomUID = uid return true end
  ns.Debug:Log("TomTom-brug fout:", tostring(uid))
  return false
end

----------------------------------------------------------------------------
-- Overlap with Forever Quest Pins (spec 1.4)
----------------------------------------------------------------------------
local QUEST_PIN_ADDONS = { "ForeverQuestPins", "Forever_Quest_Pins" } -- TODO(verify) folder name

function BR:CheckQuestPins()
  for _, name in ipairs(QUEST_PIN_ADDONS) do
    if C.IsAddOnLoaded(name) and not ns.db.warned[name] then
      ns.db.warned[name] = true
      ns:SetSetting("pins", "givers", false)
      ns:Print(string.format(L["OVERLAP_PINS"], name))
    end
  end
end

function BR:LoadedList()
  local out = {}
  if C.IsAddOnLoaded("Questie") then out[#out + 1] = "Questie (" .. questie.state .. ")" end
  if self:HasTomTom() then out[#out + 1] = "TomTom" end
  if C.IsAddOnLoaded("Pawn") then out[#out + 1] = "Pawn" end
  return out
end

function BR:OnEnable()
  self:CheckQuestPins()
end

function BR:OnDisable()
  self:TomTomClear()
end
