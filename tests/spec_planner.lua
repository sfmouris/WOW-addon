local H = dofile("tests/helpers.lua")
local S = {}

local function flat(a, b)
  if a.mapID ~= b.mapID then return nil end
  local dx, dy = (a.x - b.x) * 1000, (a.y - b.y) * 1000
  return math.sqrt(dx * dx + dy * dy)
end

local function pt(id, x, y, factor) return { mapID = 52, x = x, y = y, questID = id, factor = factor or 1 } end

S["clustering merges points within the radius"] = function()
  local ns = stub.LoadAddon({ login = false })
  local stops = ns.Planner.Cluster({ pt(1, 0.10, 0.10), pt(2, 0.15, 0.10), pt(3, 0.60, 0.60) }, 150, flat)
  T.eq(#stops, 2)
  T.eq(#stops[1].items, 2, "50 yards apart: one stop")
end

S["nearest neighbour visits closest first, unknown last"] = function()
  local ns = stub.LoadAddon({ login = false })
  local P = ns.Planner
  local a, b, c = { mapID = 52, x = 0.9, y = 0.9 }, { mapID = 52, x = 0.2, y = 0.2 }, { mapID = 99, x = 0, y = 0 }
  local route = P.NearestNeighbour({ mapID = 52, x = 0.1, y = 0.1 }, { a, c, b }, flat)
  T.eq(route[1], b) T.eq(route[2], a) T.eq(route[3], c)
end

S["six quests: plan is shorter than log order"] = function()
  local ns = stub.LoadAddon({ login = false })
  local P = ns.Planner
  -- log order zig-zags across the zone
  local coords = { { 0.9, 0.9 }, { 0.1, 0.1 }, { 0.8, 0.8 }, { 0.2, 0.2 }, { 0.7, 0.7 }, { 0.3, 0.3 } }
  local quests, points = {}, {}
  for i, c in ipairs(coords) do
    quests[i] = { questID = i, isComplete = false, difficulty = "yellow", suggestedGroup = 0, objectives = {} }
    points[i] = { mapID = 52, x = c[1], y = c[2] }
  end
  local start = { mapID = 52, x = 0.05, y = 0.05 }
  local stops = P.Plan(quests, { start = start, mapID = 52, dist = flat, clusterYards = 50,
    resolve = function(q) return points[q.questID] end, progress = function() return 0 end })
  T.eq(#stops, 6)
  local logRoute = {}
  for i = 1, 6 do logRoute[i] = points[i] end
  local planned, logLen = P.PathLength(start, stops, flat), P.PathLength(start, logRoute, flat)
  T.ok(planned < logLen, string.format("planned %.0f < log %.0f", planned, logLen))
end

S["ready-to-turn-in first, grey last, other zones counted"] = function()
  local ns = stub.LoadAddon({ login = false })
  local quests = {
    { questID = 1, difficulty = "yellow", objectives = {}, suggestedGroup = 0 },
    { questID = 2, difficulty = "grey", objectives = {}, suggestedGroup = 0 },
    { questID = 3, difficulty = "yellow", isComplete = true, objectives = {}, suggestedGroup = 0 },
    { questID = 4, difficulty = "yellow", objectives = {}, zoneHeader = "Duskwood" },
    { questID = 5, difficulty = "yellow", objectives = {}, zoneHeader = "Westfall" },
  }
  local points = { [1] = pt(1, 0.2, 0.2), [2] = pt(2, 0.21, 0.21), [3] = pt(3, 0.9, 0.9),
                   [4] = { mapID = 47, x = 0.5, y = 0.5 } }
  local stops, unknown, other = ns.Planner.Plan(quests, { start = pt(0, 0.2, 0.2), mapID = 52, zoneName = "Westfall",
    dist = flat, clusterYards = 5, resolve = function(q) return points[q.questID] end,
    progress = function() return 0 end })
  T.eq(stops[1].questIDs[1], 3, "turn-in first even though it is far")
  T.eq(stops[#stops].questIDs[1], 2, "grey last")
  T.same(unknown, { 5 })
  T.eq(other.Duskwood, 1)
end

S["penalties: red and group quests when solo"] = function()
  local ns = stub.LoadAddon({ login = false })
  local F = ns.Planner.Factor
  T.eq(F({ difficulty = "yellow", suggestedGroup = 0 }, {}), 1)
  T.eq(F({ difficulty = "red", suggestedGroup = 0 }, {}), 1.5)
  T.eq(F({ difficulty = "yellow", suggestedGroup = 3 }, { solo = true, penalizeGroup = true }), 1.5)
  T.near(F({ difficulty = "yellow" }, { preferNearDone = true, progress = function() return 0.8 end }), 0.7)
end

S["planner module runs in game flow without errors"] = function()
  stub.log = H.log("Westfall", { H.quest(1, { waypoint = { 52, 0.3, 0.3 } }), H.quest(2, { waypoint = { 52, 0.6, 0.6 } }) })
  stub.pos = { 52, 0.5, 0.5 }
  local ns = stub.LoadAddon()
  stub.Advance(3)
  T.ok(ns.Planner:GetNextQuestID(), "a next quest")
  local lines = ns.Planner:DebugLines()
  T.ok(#lines >= 3)
  T.clean(ns)
end

return S
