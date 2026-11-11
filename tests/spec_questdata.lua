local H = dofile("tests/helpers.lua")
local S = {}

local function setup()
  stub.log = H.log("Westfall", {
    H.quest(101, { title = "The People's Militia", level = 15, dist = 120 }),
    H.quest(102, { title = "Westfall Stew", level = 11, objectives = {
      { text = "Goretusk Liver", done = 2, need = 8 }, { text = "Okra", done = 3, need = 3 } } }),
    H.quest(103, { title = "Red Leather Bandanas", level = 15, group = 3, tagID = 1, elite = true }),
  })
  local ns = stub.LoadAddon()
  return ns
end

S["snapshot matches the log"] = function()
  local ns = setup()
  local qd = ns.QuestData
  T.eq(qd:Count(), 3)
  local q = qd:Get(101)
  T.eq(q.title, "The People's Militia")
  T.eq(q.level, 15)
  T.eq(q.zoneHeader, "Westfall")
  T.eq(q.difficulty, "orange")
  T.near(q.distanceSq, 14400)
  T.eq(q.objectives[1].need, 5)
  local stew = qd:Get(102)
  T.eq(stew.objectives[2].finished, true)
  local band = qd:Get(103)
  T.eq(band.suggestedGroup, 3)
  T.eq(band.tagName, "Elite")
  T.ok(q.color, "colour assigned")
  T.clean(ns)
end

S["killing a quest mob fires exactly one progress event"] = function()
  local ns = setup()
  local got = H.capture(ns, { "QK_OBJECTIVE_PROGRESS", "QK_QUEST_COMPLETED" })
  stub.log[2].objectives[1].done = 1
  -- the client fires QUEST_LOG_UPDATE several times; the debounce merges them
  stub.FireEvent("QUEST_LOG_UPDATE")
  stub.FireEvent("QUEST_LOG_UPDATE")
  stub.FireEvent("UNIT_QUEST_LOG_CHANGED", "player")
  stub.FireEvent("QUEST_LOG_UPDATE")
  stub.Advance(1)
  T.eq(#got, 1)
  T.same(got[1], { "QK_OBJECTIVE_PROGRESS", 101, 1, 0, 1 })
end

S["completion, add and remove events"] = function()
  local ns = setup()
  local got = H.capture(ns, { "QK_QUEST_COMPLETED", "QK_QUEST_ADDED", "QK_QUEST_REMOVED", "QK_QUEST_TURNED_IN" })
  stub.log[3].objectives[1].done = 8
  stub.log[3].complete = true
  stub.log[#stub.log + 1] = H.quest(104)
  stub.FireEvent("QUEST_LOG_UPDATE")
  stub.Advance(1)
  table.remove(stub.log, 3) -- 102 turned in
  stub.FireEvent("QUEST_TURNED_IN", 102, 850, 1200)
  stub.FireEvent("QUEST_REMOVED", 102)
  stub.Advance(1)
  local names = {}
  for _, e in ipairs(got) do names[#names + 1] = e[1] .. ":" .. tostring(e[2]) end
  T.same(names, { "QK_QUEST_COMPLETED:102", "QK_QUEST_ADDED:104", "QK_QUEST_TURNED_IN:102",
                  "QK_QUEST_REMOVED:102" })
  T.same(got[3], { "QK_QUEST_TURNED_IN", 102, 850, 1200 })
end

S["missing titles at login are requested and filled in later"] = function()
  stub.log = H.log("Elwynn Forest", { H.quest(201) })
  stub.log[2].title = nil
  local ns = stub.LoadAddon()
  local q = ns.QuestData:Get(201)
  T.ok(q, "quest present without title")
  T.eq(q.titleMissing, true)
  T.eq(stub.loadRequests[1], 201)
  stub.log[2].title = "Wolves Across the Border"
  stub.FireEvent("QUEST_DATA_LOAD_RESULT", 201, true)
  stub.Advance(1)
  T.eq(ns.QuestData:Get(201).title, "Wolves Across the Border")
  T.clean(ns)
end

S["Progress fraction"] = function()
  local ns = setup()
  T.near(ns.QuestData.Progress(ns.QuestData:Get(102)), 5 / 11, 1e-9)
end

return S
