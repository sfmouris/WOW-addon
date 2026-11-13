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

S["progress: average over objectives, nil without objectives"] = function()
  local ns = stub.LoadAddon({ login = false })
  local P = ns.Tracker.Progress
  T.eq(P({ objectives = {} }), nil)
  T.eq(P({ isComplete = true, objectives = {} }), 1)
  T.eq(P({ objectives = { { done = 5, need = 10 } } }), 0.5)
  T.eq(P({ objectives = { { done = 5, need = 10 }, { done = 0, need = 1, finished = true } } }), 0.75)
  T.eq(P({ objectives = { { done = 99, need = 4 }, { done = -1, need = 2 } } }), 0.5, "clamped per objective")
  T.eq(P({ objectives = { { done = 0, need = 0 } } }), 0, "need 0 does not divide by zero")
end

S["view height: content beyond maxRows scrolls"] = function()
  local ns = stub.LoadAddon({ login = false })
  local view, range = ns.Tracker.ViewHeight(100, 30)
  T.eq(view, 100) T.eq(range, 0)
  view, range = ns.Tracker.ViewHeight(1000, 30)
  T.eq(view, 420) T.eq(range, 580)
end

S["title bar: minimize, lock and flash work without errors"] = function()
  stub.log = H.log("Westfall", { H.quest(501), H.quest(502, { complete = true }) })
  local ns = stub.LoadAddon()
  local Tr = ns.Tracker
  local frame = Tr:GetFrame()
  T.ok(frame.minBtn and frame.lockBtn and frame.gearBtn, "title bar buttons exist")
  frame.minBtn:GetScript("OnClick")(frame.minBtn, "LeftButton")
  T.eq(ns.cdb.collapsed.all, true)
  T.eq(frame:GetHeight(), 22, "collapsed to the title bar")
  stub.Advance(3)
  frame.minBtn:GetScript("OnClick")(frame.minBtn, "LeftButton")
  T.eq(ns.cdb.collapsed.all, nil)
  T.ok(frame:GetHeight() > 22)
  frame.lockBtn:GetScript("OnClick")(frame.lockBtn, "LeftButton")
  T.eq(ns:GetSetting("tracker", "locked"), true)
  for _, b in ipairs(frame.buttons) do
    b:GetScript("OnEnter")(b)
    b:GetScript("OnLeave")(b)
  end
  Tr:Flash(501)
  stub.Advance(2)
  frame:GetScript("OnUpdate")(frame, 0.2)
  T.clean(ns)
end

return S
