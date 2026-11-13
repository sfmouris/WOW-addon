local S = {}

local function npcWith(active, available)
  stub.npc.active, stub.npc.available = active, available
end

-- Simulates the NPC: each selection reopens the gossip without that quest.
local function talk(ns, rounds)
  for _ = 1, rounds do
    local before = #stub.calls
    stub.FireEvent("GOSSIP_SHOW")
    local call = stub.calls[#stub.calls]
    if #stub.calls == before then break end
    local kind, id = call:match("^(%a+):(%d+)$")
    id = tonumber(id)
    if kind == "SelectActive" then
      stub.npc.questID, stub.npc.completable, stub.npc.choices = id, true, 0
      stub.FireEvent("QUEST_PROGRESS")
      stub.FireEvent("QUEST_COMPLETE", id, true)
      for i, q in ipairs(stub.npc.active) do if q.questID == id then table.remove(stub.npc.active, i) break end end
    elseif kind == "SelectAvailable" then
      stub.npc.questID, stub.npc.title = id, "Quest " .. id
      stub.FireEvent("QUEST_DETAIL")
      for i, q in ipairs(stub.npc.available) do if q.questID == id then table.remove(stub.npc.available, i) break end end
    end
    stub.Advance(0.2)
  end
end

S["3 available and 2 ready quests: all handled without a click"] = function()
  local ns = stub.LoadAddon()
  npcWith({ { questID = 11, isComplete = true, title = "a" }, { questID = 12, isComplete = true, title = "b" },
            { questID = 13, isComplete = false, title = "c" } },
          { { questID = 21, questLevel = 12, title = "x" }, { questID = 22, questLevel = 10, title = "y" },
            { questID = 23, questLevel = 13, title = "z" } })
  talk(ns, 10)
  local counts = {}
  for _, c in ipairs(stub.calls) do local k = c:match("^(%a+)") counts[k] = (counts[k] or 0) + 1 end
  T.eq(counts.SelectActive, 2)
  T.eq(counts.CompleteQuest, 2)
  T.eq(counts.GetQuestReward, 2)
  T.eq(counts.SelectAvailable, 3)
  T.eq(counts.AcceptQuest, 3)
  T.clean(ns)
end

S["holding shift: nothing happens automatically"] = function()
  local ns = stub.LoadAddon()
  npcWith({ { questID = 11, isComplete = true } }, { { questID = 21, questLevel = 12 } })
  stub.shift = true
  stub.FireEvent("GOSSIP_SHOW")
  stub.shift = false -- released while the window is still open
  stub.npc.questID = 21
  stub.FireEvent("QUEST_DETAIL")
  T.eq(#stub.calls, 0)
  -- next interaction works again
  stub.FireEvent("GOSSIP_CLOSED", false)
  stub.Advance(1)
  stub.FireEvent("GOSSIP_SHOW")
  T.eq(#stub.calls, 1)
  T.clean(ns)
end

S["guard: at most one attempt per quest per 3 s"] = function()
  stub.LoadAddon()
  npcWith({}, { { questID = 21, questLevel = 12 } })
  for _ = 1, 5 do stub.FireEvent("GOSSIP_SHOW") end
  T.eq(#stub.calls, 1)
  stub.Advance(3.1)
  stub.FireEvent("GOSSIP_SHOW")
  T.eq(#stub.calls, 2)
end

S["exceptions: level, blacklist, repeatable, full log"] = function()
  local ns = stub.LoadAddon()
  local AQ = ns.AutoQuest
  local ctx = { accept = true, blacklist = { [5] = true }, playerLevel = 12, maxLevelAbove = 4, repeatable = false }
  T.eq((AQ.ShouldAccept({ questID = 1, questLevel = 16 }, ctx)), true)
  T.same({ AQ.ShouldAccept({ questID = 1, questLevel = 17 }, ctx) }, { false, "level" })
  T.same({ AQ.ShouldAccept({ questID = 5, questLevel = 12 }, ctx) }, { false, "blacklist" })
  T.same({ AQ.ShouldAccept({ questID = 6, repeatable = true }, ctx) }, { false, "repeatable" })
  ctx.logFull = true
  T.same({ AQ.ShouldAccept({ questID = 7 }, ctx) }, { false, "full" })
end

S["full log shows a centre message instead of accepting"] = function()
  stub.log = {}
  for i = 1, 25 do stub.log[i] = { questID = 500 + i, title = "q", level = 10, objectives = {} } end
  stub.LoadAddon()
  npcWith({}, { { questID = 21, questLevel = 12 } })
  stub.FireEvent("GOSSIP_SHOW")
  T.eq(#stub.calls, 0)
  T.eq(#stub.center, 1)
end

S["turn-in stops for money, non-quest items and reward choices"] = function()
  local ns = stub.LoadAddon()
  stub.npc.questID, stub.npc.completable = 30, true
  stub.npc.moneyToGet = 500
  stub.FireEvent("QUEST_PROGRESS")
  T.eq(#stub.calls, 0, "costs money")
  stub.npc.moneyToGet = 0
  stub.items[2589] = { 2589, "Trade Goods", "Cloth", "", 0, 7, 0 }
  stub.npc.required = { { itemID = 2589, name = "Linen Cloth", count = 10 } }
  stub.FireEvent("QUEST_PROGRESS")
  T.eq(#stub.calls, 0, "needs a normal item")
  stub.items[745] = { 745, "Quest", "Quest", "", 0, 12, 0 }
  stub.npc.required = { { itemID = 745, name = "Marshal Haggard's Badge", count = 1 } }
  stub.FireEvent("QUEST_PROGRESS")
  T.eq(stub.calls[1], "CompleteQuest", "quest items are fine")
  stub.npc.choices = 3
  stub.FireEvent("QUEST_COMPLETE", 30, true)
  T.eq(#stub.calls, 1, "three choices: no automatic reward")
  T.ok(ns.AutoQuest.TurnInNeedsPlayer(0, 1, {}, function() return true end), "currency cost")
end

S["single gossip option is only chosen for the plain chat icon"] = function()
  local ns = stub.LoadAddon()
  ns:SetSetting("auto", "gossip", true)
  stub.npc.options = { { gossipOptionID = 7, icon = 132060, name = "Browse goods" } }
  stub.FireEvent("GOSSIP_SHOW")
  T.eq(#stub.calls, 0, "vendor icon ignored")
  stub.npc.options = { { gossipOptionID = 8, icon = 132053, name = "Tell me more" } }
  stub.FireEvent("GOSSIP_SHOW")
  T.eq(stub.calls[1], "SelectOption:8")
end

S["no automation in combat"] = function()
  stub.LoadAddon()
  stub.combat = true
  npcWith({}, { { questID = 21, questLevel = 12 } })
  stub.FireEvent("GOSSIP_SHOW")
  T.eq(#stub.calls, 0)
end

return S
