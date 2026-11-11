local H = dofile("tests/helpers.lua")
local S = {}

local function q(id, level, dist, zone, complete)
  return { questID = id, level = level, zoneHeader = zone, isComplete = complete, objectives = {}, d = dist }
end

S["sorting by distance, level, zone and manual"] = function()
  local ns = stub.LoadAddon({ login = false })
  local Tr = ns.Tracker
  local list = { q(1, 14, 300, "B"), q(2, 11, nil, "A"), q(3, 12, 100, "A"), q(4, 12, 200, "C") }
  local dist = function(x) return x.d end
  local function ids(l) local o = {} for i, x in ipairs(l) do o[i] = x.questID end return o end
  T.same(ids(Tr.SortQuests(list, "distance", dist)), { 3, 4, 1, 2 }, "unknown distance last")
  T.same(ids(Tr.SortQuests(list, "level")), { 2, 3, 4, 1 })
  T.same(ids(Tr.SortQuests(list, "zone")), { 2, 3, 1, 4 })
  T.same(ids(Tr.SortQuests(list, "manual", nil, { 4, 1 })), { 4, 1, 2, 3 })
end

S["grouping: ready first, then this zone, then the rest"] = function()
  local ns = stub.LoadAddon({ login = false })
  local ready, here, other = ns.Tracker.Group({ q(1, 1, 1, "Westfall", true), q(2, 1, 1, "Westfall"),
    q(3, 1, 1, "Duskwood") }, "Westfall", 52)
  T.eq(#ready, 1) T.eq(ready[1].questID, 1)
  T.eq(#here, 1) T.eq(here[1].questID, 2)
  T.eq(#other, 1) T.eq(other[1].questID, 3)
end

S["rebuild with 25 quests stays fast and error free"] = function()
  local quests = {}
  for i = 1, 25 do quests[i] = H.quest(300 + i, { dist = i * 10, objectives = {
    { text = "A", done = 1, need = 4 }, { text = "B", done = 0, need = 1 } } }) end
  stub.log = H.log("Westfall", quests)
  stub.pos = { 52, 0.5, 0.5 }
  local ns = stub.LoadAddon()
  ns.Tracker:Rebuild()
  T.ok(ns.Tracker.lastBuildMs ~= nil)
  T.ok(ns.Tracker.lastBuildMs < 50, "rebuild took " .. ns.Tracker.lastBuildMs .. " ms against the stub")
  -- every second the distance ticker runs; no errors over a minute
  stub.Advance(60)
  T.clean(ns)
end

S["combat: no rebuild while in combat, rebuild after"] = function()
  stub.log = H.log("Westfall", { H.quest(401) })
  local ns = stub.LoadAddon()
  stub.combat = true
  stub.FireEvent("PLAYER_REGEN_DISABLED")
  ns.Tracker.lastBuildMs = nil
  stub.log[2].objectives[1].done = 2
  stub.FireEvent("QUEST_LOG_UPDATE")
  stub.Advance(2)
  T.eq(ns.Tracker.lastBuildMs, nil, "no rebuild in combat")
  T.ok(ns.Tracker.dirty)
  stub.combat = false
  stub.FireEvent("PLAYER_REGEN_ENABLED")
  T.ok(ns.Tracker.lastBuildMs ~= nil, "rebuilt after combat")
  T.clean(ns)
end

return S
