-- RewardHelper, LogTools, Stats, Party, Bridges, Navigator, ItemBar.
local H = dofile("tests/helpers.lua")
local S = {}

S["reward: coin on highest sell price, arrow on upgrades only"] = function()
  local ns = stub.LoadAddon({ login = false })
  local best, up = ns.RewardHelper.Evaluate({
    { index = 1, price = 1240, ilvl = 18, usable = true, current = { 15 } },
    { index = 2, price = 3000, ilvl = 14, usable = true, current = { 15 } },
    { index = 3, price = 200, ilvl = 20, usable = false, current = { 15 } },
    { index = 4, price = 100, ilvl = 16, usable = true, current = { 20, false } },
  })
  T.eq(best, 2)
  T.eq(up[1], 15)
  T.eq(up[2], nil)
  T.eq(up[3], nil, "not wearable")
  T.eq(up[4], 0, "empty ring slot")
end

S["reward helper never picks unless the option is on"] = function()
  local ns = stub.LoadAddon()
  stub.npc.choices, stub.npc.questID = 3, 40
  stub.FireEvent("QUEST_COMPLETE", 40, true)
  stub.Advance(1)
  for _, c in ipairs(stub.calls) do T.ok(not c:find("GetQuestReward", 1, true), c) end
  T.clean(ns)
end

S["logtools: grey list, candidates and search"] = function()
  local ns = stub.LoadAddon({ login = false })
  local LT = ns.LogTools
  local list = {
    { questID = 1, title = "Grey Wolves", difficulty = "grey", xpReward = 50, objectives = {} },
    { questID = 2, title = "Far Away", difficulty = "yellow", xpReward = 900, objectives = {} },
    { questID = 3, title = "Near", difficulty = "yellow", xpReward = 100,
      objectives = { { text = "Gnoll Paw" } } },
    { questID = 4, title = "Done", difficulty = "grey", isComplete = true, objectives = {} },
  }
  local grey = LT.GreyQuests(list)
  T.eq(#grey, 1) T.eq(grey[1].questID, 1)
  local d = { [1] = 10, [2] = 900, [3] = 20 }
  local c = LT.AbandonCandidates(list, function(q) return d[q.questID] end, 3)
  T.eq(c[1].questID, 1) T.eq(c[2].questID, 2) T.eq(c[3].questID, 3)
  local hits = LT.Search("gnoll", list, { [99] = { t = "Gnoll Hunt", l = 12 } })
  T.eq(#hits, 2)
  T.eq(hits[1].questID, 3, "active quest first")
end

S["bulk abandon needs two confirmations and only touches the shown list"] = function()
  stub.level = 30
  stub.log = H.log("Westfall", { H.quest(1, { level = 10 }), H.quest(2, { level = 11 }), H.quest(3, { level = 30 }) })
  local ns = stub.LoadAddon()
  local confirms = {}
  ns.UI.Confirm = function(_, _, fn) confirms[#confirms + 1] = fn end
  ns.LogTools:ShowGrey()
  -- footer button
  local win
  for _, f in ipairs(stub.frames) do if f.footer then win = f end end
  T.ok(win, "grey window built")
  -- a new grey quest appears after the list was shown: must not be abandoned
  stub.log[#stub.log + 1] = H.quest(4, { level = 5 })
  stub.FireEvent("QUEST_LOG_UPDATE")
  stub.Advance(1)
  win.footer:GetScript("OnClick")()
  T.eq(#stub.abandoned, 0, "nothing after the button")
  confirms[1]()
  T.eq(#stub.abandoned, 0, "nothing after one confirmation")
  confirms[2]()
  stub.Advance(2)
  T.same(stub.abandoned, { 1, 2 })
  T.clean(ns)
end

S["stats helpers"] = function()
  local ns = stub.LoadAddon({ login = false })
  local ST = ns.Stats
  T.eq(ST.PerHour(100, 30), nil, "too short")
  T.near(ST.PerHour(1000, 1800), 2000)
  local hist = {}
  for i = 1, 12 do hist[i] = { xp = (i <= 2) and 99999 or 500 } end
  T.eq(ST.CalcQuestsToLevel(2600, hist, 10), 6, "average of the last 10 is 500")
  T.eq(ST.XPDelta(900, 1000, 50, 1), 150)
  T.eq(ST.XPDelta(100, 1000, 180, 0), 80)
  local h = {}
  for i = 1, 2005 do ST.AddHistory(h, { id = i }, 2000) end
  T.eq(#h, 2000) T.eq(h[1].id, 6)
end

S["stats records quest turn-ins in game flow"] = function()
  stub.log = H.log("Westfall", { H.quest(12, { title = "Militia", level = 12 }) })
  local ns = stub.LoadAddon()
  stub.FireEvent("QUEST_TURNED_IN", 12, 850, 1200)
  stub.xp = 950
  stub.FireEvent("PLAYER_XP_UPDATE", "player")
  T.eq(ns.cdb.session.questXP, 850)
  T.eq(ns.cdb.session.money, 1200)
  T.eq(ns.cdb.session.xp, 850)
  T.eq(ns.cdb.history[1].id, 12)
  T.eq(ns.cdb.history[1].t, "Militia")
  T.clean(ns)
end

S["party wire format: roundtrip and hostile input"] = function()
  local ns = stub.LoadAddon({ login = false })
  local PT = ns.Party
  local msg = PT.Encode({ { questID = 12, objectives = { { done = 3, need = 10 }, { done = 1, need = 1 } } },
                          { questID = 13, objectives = {} } })
  T.eq(msg, "P1|12:3/10,1/1;13:")
  local d = PT.Decode(msg)
  T.same(d[12], { { 3, 10 }, { 1, 1 } })
  T.same(d[13], {})
  T.eq(PT.Decode("P1|12:3/10;loadstring(x)"), nil)
  T.eq(PT.Decode("X1|12:3/10"), nil)
  T.eq(PT.Decode(string.rep("1", 300)), nil)
  T.eq(PT.Decode(nil), nil)
  local big = {}
  for i = 1, 60 do big[i] = { questID = 10000 + i, objectives = { { done = 1, need = 2 } } } end
  T.ok(#PT.Encode(big) <= 200, "payload under 200 characters")
end

S["bridges: nearest spawn and silent fallback without Questie"] = function()
  local ns = stub.LoadAddon()
  local m, x, y = ns.Bridges.NearestSpawn({ [40] = { { 50, 50 }, { 10, 10 } } }, function() return 52 end,
    52, 0.12, 0.12, function(_, ax, ay, _, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end)
  T.eq(m, 52) T.near(x, 0.1) T.near(y, 0.1)
  T.eq(ns.Bridges:GetQuestPoint(1, false), nil)
  T.eq(ns.Bridges:QuestieState(), "off")
  T.clean(ns)
end

S["bridges: a broken Questie structure switches the bridge off"] = function()
  stub.loadedAddons.Questie = true
  _G.QuestieLoader = { ImportModule = function() return { GetQuest = function() error("changed") end,
    GetNPC = function() end, GetUiMapIdByAreaId = function() end } end }
  local ns = stub.LoadAddon()
  for _ = 1, 4 do T.eq(ns.Bridges:GetQuestPoint(5, false), nil) end
  T.eq(ns.Bridges:QuestieState(), "off")
  T.clean(ns)
  _G.QuestieLoader = nil
end

S["bridges: Questie data is used when it is there"] = function()
  stub.loadedAddons.Questie = true
  local QDB = {
    GetQuest = function(id) return { Finisher = { NPC = { 234 } }, ObjectiveData = { { Type = "monster", Id = 99 } } } end,
    GetNPC = function(_, id)
      if id == 234 then return { spawns = { [40] = { { 56.3, 47.6 } } } } end
      return { spawns = { [40] = { { 48.1, 36.5 } } } }
    end,
  }
  local ZDB = { GetUiMapIdByAreaId = function() return 52 end }
  _G.QuestieLoader = { ImportModule = function(_, name) return name == "QuestieDB" and QDB or ZDB end }
  local ns = stub.LoadAddon()
  local m, x = ns.Bridges:GetQuestPoint(5, true)
  T.eq(m, 52) T.near(x, 0.563)
  m, x = ns.Bridges:GetQuestPoint(5, false)
  T.near(x, 0.481)
  T.eq(ns.Bridges:QuestieState(), "ok")
  _G.QuestieLoader = nil
end

S["navigator: source layers and arrow without errors"] = function()
  stub.pos = { 52, 0.5, 0.5 }
  stub.log = H.log("Westfall", { H.quest(1, { waypoint = { 52, 0.5, 0.6 } }), H.quest(2), H.quest(3) })
  local ns = stub.LoadAddon()
  ns.db.learned.quests[2] = { o = { [1] = { h = { { m = 52, x = 0.4, y = 0.5, c = 1 } } } } }
  ns:Fire("QK_LEARN_UPDATED", 2)
  local p1 = ns.Navigator:ResolveQuest(1)
  T.eq(p1.source, "client")
  local p2 = ns.Navigator:ResolveQuest(2)
  T.eq(p2.source, "learned")
  T.eq(ns.Navigator:ResolveQuest(3), nil, "unknown")
  T.near(ns.Navigator:GetQuestDistance(ns.QuestData:Get(1)), 100, 1e-6)
  ns.Navigator:SetQuest(1)
  stub.Advance(1)
  T.eq(ns.Navigator:GetTargetQuestID(), 1)
  T.eq(ns.cdb.nav.questID, 1)
  -- in an instance: no position, arrow hides, no errors
  stub.pos = nil
  stub.facing = nil
  stub.Advance(1)
  -- walk to the point: arrival
  stub.pos = { 52, 0.5, 0.595 }
  stub.facing = 0
  stub.Advance(0.5)
  T.ok(ns.Navigator.arrived, "within 10 yards")
  T.clean(ns)
end

S["navigator: /qk way parses coordinates and zones"] = function()
  stub.pos = { 52, 0.5, 0.5 }
  local ns = stub.LoadAddon()
  T.ok(ns.Navigator:Way("45.2 67.8"))
  stub.Advance(0.5)
  T.eq(ns.Navigator.target.mapID, 52)
  T.near(ns.Navigator.target.x, 0.452)
  T.eq(ns.Navigator:Way("abc"), false)
  T.eq(ns.Navigator:Way("101 5"), false)
  T.clean(ns)
end

S["navigator: auto advance after completion, combat queues the change"] = function()
  stub.pos = { 52, 0.5, 0.5 }
  stub.log = H.log("Westfall", { H.quest(1, { waypoint = { 52, 0.5, 0.6 } }), H.quest(2, { waypoint = { 52, 0.9, 0.9 } }) })
  local ns = stub.LoadAddon()
  ns.Navigator:SetQuest(2)
  stub.Advance(1)
  stub.combat = true
  ns.Navigator:SetQuest(1)
  T.eq(ns.Navigator:GetTargetQuestID(), 2, "unchanged in combat")
  stub.combat = false
  stub.FireEvent("PLAYER_REGEN_ENABLED")
  T.eq(ns.Navigator:GetTargetQuestID(), 1, "applied after combat")
  table.remove(stub.log, 2)
  stub.FireEvent("QUEST_REMOVED", 1)
  stub.Advance(3)
  T.eq(ns.Navigator:GetTargetQuestID(), 2, "advanced to the remaining quest")
  T.clean(ns)
end

S["itembar: nearest quest first, max buttons, no changes in combat"] = function()
  local ns = stub.LoadAddon({ login = false })
  local list = {
    { questID = 1, logIndex = 1, hasUsableItem = true, itemLink = "item:1", d = 300 },
    { questID = 2, logIndex = 2, hasUsableItem = false },
    { questID = 3, logIndex = 3, hasUsableItem = true, itemLink = "item:3", d = 100 },
    { questID = 4, logIndex = 4, hasUsableItem = true, itemLink = "item:4" },
  }
  local out = ns.ItemBar.Collect(list, function(q) return q.d end, 2)
  T.eq(#out, 2) T.eq(out[1].questID, 3) T.eq(out[2].questID, 1)

  stub.log = H.log("Westfall", { H.quest(7, { item = "|Hitem:5060|h" }) })
  ns = stub.LoadAddon()
  stub.Advance(1)
  local btn = _G.QuestKompasItemButton1
  T.ok(btn, "button 1 exists")
  T.eq(btn:GetAttribute("type"), "item")
  T.eq(btn:GetAttribute("item"), "item:5060")
  stub.combat = true
  stub.log[#stub.log + 1] = H.quest(8, { item = "|Hitem:6000|h" })
  stub.FireEvent("QUEST_LOG_UPDATE")
  stub.Advance(1)
  T.ok(ns.ItemBar.dirty, "change deferred")
  stub.combat = false
  stub.FireEvent("PLAYER_REGEN_ENABLED")
  T.eq(ns.ItemBar.dirty, false)
  T.clean(ns)
end

return S
