-- QuestKompas: suggested quest order within the current zone (spec 4.5).
local _, ns = ...

local P = ns:RegisterModule("Planner")
local C, L = ns.Compat, ns.L

P.stops = {}       -- ordered stops { mapID, x, y, questIDs, kind }
P.orderMap = {}    -- questID -> stop number
P.otherZones = {}  -- zoneHeader -> count
P.unknown = {}     -- questIDs here without a location

----------------------------------------------------------------------------
-- Pure algorithms (tests/spec_planner.lua). Points are tables with
-- mapID, x, y. dist(a, b) returns yards or nil.
----------------------------------------------------------------------------

-- Greedy clustering: a point joins the first stop whose anchor lies within
-- radius yards, otherwise it starts a new stop.
function P.Cluster(points, radius, dist)
  local stops = {}
  for _, p in ipairs(points) do
    local joined
    for _, s in ipairs(stops) do
      local d = dist(s, p)
      if d and d <= radius then joined = s break end
    end
    if joined then
      joined.items[#joined.items + 1] = p
      if p.factor < joined.factor then joined.factor = p.factor end
    else
      stops[#stops + 1] = { mapID = p.mapID, x = p.x, y = p.y, items = { p }, factor = p.factor or 1 }
    end
  end
  return stops
end

-- Nearest neighbour from start; cost = distance * stop.factor. Stops with
-- an unknown distance go last in their input order.
function P.NearestNeighbour(start, stops, dist)
  local remaining = {}
  for i = 1, #stops do remaining[i] = stops[i] end
  local route, cur, tail = {}, start, {}
  while #remaining > 0 do
    local bestI, bestCost
    for i, s in ipairs(remaining) do
      local d = cur and dist(cur, s)
      if d then
        local cost = d * (s.factor or 1)
        if not bestCost or cost < bestCost then bestI, bestCost = i, cost end
      end
    end
    if not bestI then
      for _, s in ipairs(remaining) do tail[#tail + 1] = s end
      break
    end
    local s = table.remove(remaining, bestI)
    route[#route + 1] = s
    cur = s
  end
  for _, s in ipairs(tail) do route[#route + 1] = s end
  return route
end

function P.PathLength(start, route, dist)
  local total, cur = 0, start
  for _, s in ipairs(route) do
    local d = cur and dist(cur, s)
    if d then total = total + d end
    cur = s
  end
  return total
end

-- Weight factor for an active quest: < 1 is preferred, > 1 penalised.
function P.Factor(q, opts)
  local f = 1
  if opts.preferNearDone and opts.progress and opts.progress(q) >= 0.75 then f = f * 0.7 end
  if q.difficulty == "red" then f = f * 1.5 end
  if opts.penalizeGroup and opts.solo and (q.suggestedGroup or 0) > 1 then f = f * 1.5 end
  return f
end

-- quests: snapshot list. ctx: { start = point, mapID, resolve(q) -> point,
-- dist(a, b), solo, clusterYards, preferNearDone, penalizeGroup, progress }
-- Returns stops (ordered), unknown (questIDs), otherZones (header -> n).
function P.Plan(quests, ctx)
  local ready, active, grey, unknown, other = {}, {}, {}, {}, {}
  for _, q in ipairs(quests) do
    local p = ctx.resolve(q)
    local here = p and ctx.mapID and p.mapID == ctx.mapID
    if here then
      local pt = { mapID = p.mapID, x = p.x, y = p.y, questID = q.questID, factor = 1 }
      if q.isComplete then
        ready[#ready + 1] = pt
      elseif q.difficulty == "grey" then
        grey[#grey + 1] = pt
      else
        pt.factor = P.Factor(q, ctx)
        active[#active + 1] = pt
      end
    elseif not p and ctx.zoneName and q.zoneHeader == ctx.zoneName then
      unknown[#unknown + 1] = q.questID
    else
      local key = q.zoneHeader or "?"
      other[key] = (other[key] or 0) + 1
    end
  end
  local radius = ctx.clusterYards or 150
  local route = {}
  local cur = ctx.start
  for _, group in ipairs({ { ready, "ready" }, { active, "active" }, { grey, "grey" } }) do
    local stops = P.Cluster(group[1], radius, ctx.dist)
    local ordered = P.NearestNeighbour(cur, stops, ctx.dist)
    for _, s in ipairs(ordered) do
      s.kind = group[2]
      s.questIDs = {}
      for i, item in ipairs(s.items) do s.questIDs[i] = item.questID end
      route[#route + 1] = s
      cur = s
    end
  end
  return route, unknown, other
end

----------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------
local function dist(a, b)
  return (ns.Geo.Distance(a.mapID, a.x, a.y, b.mapID, b.x, b.y))
end

local function context()
  local pm, px, py = C.GetPlayerPosition()
  return {
    start = pm and { mapID = pm, x = px, y = py } or nil,
    mapID = pm or C.GetPlayerMapID(),
    zoneName = C.GetMapName(pm or C.GetPlayerMapID()),
    resolve = function(q) return ns.Navigator:ResolveQuest(q.questID) end,
    dist = dist,
    solo = not C.IsInGroup(),
    clusterYards = ns:GetSetting("planner", "clusterYards"),
    preferNearDone = ns:GetSetting("planner", "preferNearDone"),
    penalizeGroup = ns:GetSetting("planner", "penalizeGroup"),
    progress = ns.QuestData.Progress,
  }
end

local lastKey = ""
function P:Compute()
  if C.InCombat() then self.dirty = true return end
  if not ns:IsModuleEnabled("Navigator") then return end
  self.dirty = false
  local stops, unknown, other = P.Plan(ns.QuestData:GetList(), context())
  self.stops, self.unknown, self.otherZones = stops, unknown, other
  local orderMap, keyParts = {}, {}
  for i, s in ipairs(stops) do
    for _, id in ipairs(s.questIDs) do
      orderMap[id] = i
      keyParts[#keyParts + 1] = id .. ":" .. i
    end
  end
  self.orderMap = orderMap
  local key = table.concat(keyParts, ",")
  if key ~= lastKey then
    lastKey = key
    ns:Fire("QK_PLAN_UPDATED")
  end
end

function P:RequestPlan()
  ns:Throttle("Planner.compute", 2, function() P:Compute() end)
end

function P:GetOrderMap()
  return self.orderMap
end

function P:GetNextQuestID(excludeID)
  for _, s in ipairs(self.stops) do
    for _, id in ipairs(s.questIDs) do
      if id ~= excludeID then return id end
    end
  end
  return nil
end

function P:DebugLines()
  self:Compute()
  local ctx = context()
  local out = { string.format("Plan: %d stops, %d onbekend", #self.stops, #self.unknown) }
  for i, s in ipairs(self.stops) do
    local names = {}
    for _, id in ipairs(s.questIDs) do
      local q = ns.QuestData:Get(id)
      names[#names + 1] = q and q.title or tostring(id)
    end
    out[#out + 1] = string.format("%2d. [%s] %.1f,%.1f  %s", i, s.kind, s.x * 100, s.y * 100,
      table.concat(names, " + "))
  end
  -- Compare with log order over the same points.
  local logRoute = {}
  for _, q in ipairs(ns.QuestData:GetList()) do
    local idx = self.orderMap[q.questID]
    if idx then logRoute[#logRoute + 1] = self.stops[idx] end
  end
  if ctx.start then
    out[#out + 1] = string.format(L["PLAN_LENGTH_FMT"], P.PathLength(ctx.start, self.stops, dist),
      P.PathLength(ctx.start, logRoute, dist))
  end
  for zone, n in pairs(self.otherZones) do out[#out + 1] = string.format("  %s: %d", zone, n) end
  return out
end

function P:OnEnable()
  local function req() P:RequestPlan() end
  ns:On("QK_QUESTS_UPDATED", "Planner", req)
  ns:On("QK_LEARN_UPDATED", "Planner", req)
  ns:On("ZONE_CHANGED_NEW_AREA", "Planner", req)
  ns:On("GROUP_ROSTER_UPDATE", "Planner", req)
  ns:On("QK_SETTING_CHANGED", "Planner", function(_, section)
    if section == "planner" or section == nil then req() end
  end)
  self.ticker = C_Timer.NewTicker(10, req)
  req()
end

function P:OnDisable()
  if self.ticker then self.ticker:Cancel() self.ticker = nil end
  self.stops, self.orderMap = {}, {}
  ns:Fire("QK_PLAN_UPDATED")
end

function P:OnCombatEnd()
  if self.dirty then self:RequestPlan() end
end
