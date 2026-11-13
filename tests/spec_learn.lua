local H = dofile("tests/helpers.lua")
local S = {}

local function flatDist(m1, x1, y1, m2, x2, y2)
  if m1 ~= m2 then return nil end
  local dx, dy = (x1 - x2) * 1000, (y1 - y2) * 1000
  return math.sqrt(dx * dx + dy * dy)
end

S["hotspots merge within 40 yards and cap at 12"] = function()
  local ns = stub.LoadAddon({ login = false })
  local M = ns.Learn.MergeHotspot
  local h = {}
  M(h, { m = 52, x = 0.5, y = 0.5 }, 40, 12, flatDist)
  M(h, { m = 52, x = 0.52, y = 0.5 }, 40, 12, flatDist) -- 20 yards
  T.eq(#h, 1)
  T.eq(h[1].c, 2)
  T.near(h[1].x, 0.51, 1e-9)
  M(h, { m = 52, x = 0.6, y = 0.5 }, 40, 12, flatDist) -- 90 yards
  T.eq(#h, 2)
  for i = 1, 20 do M(h, { m = 52, x = i * 0.045, y = 0.9 }, 40, 12, flatDist) end
  T.eq(#h, 12)
  local kept = false
  for _, s in ipairs(h) do if s.c == 2 then kept = true end end
  T.ok(kept, "most used hotspot survives")
end

S["validation rejects bad types and ranges"] = function()
  local ns = stub.LoadAddon({ login = false })
  local data = {
    [100] = { t = string.rep("x", 500), l = 12, s = { m = 52, x = 0.5, y = 0.4, n = "Gryan", id = 234, k = "npc" },
              o = { [1] = { txt = "ok", h = { { m = 52, x = 0.1, y = 0.2, c = 3 }, { m = 52, x = 5, y = 0.2 } } } } },
    [101] = { s = { m = 52, x = -1, y = 0.4 } },
    ["bad"] = { t = "x" },
    [102.5] = { t = "x" },
    [103] = "not a table",
    [104] = { f = "Z", cl = { WARRIOR = true, [5] = true }, s = { m = "52", x = 0.1, y = 0.1 } },
  }
  local clean, n = ns.Learn.Validate(data, 12)
  T.eq(n, 3)
  T.eq(#clean[100].t, 200, "string capped")
  T.eq(clean[100].s.n, "Gryan")
  T.eq(#clean[100].o[1].h, 1, "out-of-range hotspot dropped")
  T.eq(clean[101].s, nil, "negative coordinate dropped")
  T.eq(clean[104].f, nil)
  T.same(clean[104].cl, { WARRIOR = true })
  T.eq(clean[104].s, nil, "string map id dropped")
  T.eq(clean.bad, nil)
end

S["export then import into an empty profile gives identical data"] = function()
  local ns = stub.LoadAddon()
  local quests = ns.db.learned.quests
  local r = ns.Learn.Round4 -- stored coordinates are always rounded
  for i = 1, 30 do
    quests[1000 + i] = { t = "Quest " .. i, l = 10 + (i % 5), ml = 9, f = "A", seen = 1794268800 + i,
      s = { m = 52, x = r(0.1 + i / 100), y = 0.2, n = "NPC " .. i, id = 200 + i, k = "npc" },
      e = { m = 52, x = 0.3, y = r(0.4 + i / 100), n = "NPC", id = 300, k = "npc" },
      o = { [1] = { txt = "Thing slain", h = { { m = 52, x = 0.5, y = 0.5, c = i } } } }, prev = i > 1 and 999 + i or nil }
  end
  local str = ns.Learn.Encode(quests)
  T.ok(str:sub(1, 4) == "QK1:")
  local decoded = assert(ns.Learn.Decode(str))
  local clean = ns.Learn.Validate(decoded, 12)
  local fresh = {}
  local total, new = ns.Learn.MergeInto(fresh, clean, 40, 12, flatDist)
  T.eq(total, 30) T.eq(new, 30)
  T.same(fresh, quests, "roundtrip identical")
end

S["decode refuses garbage"] = function()
  local ns = stub.LoadAddon({ login = false })
  T.eq((ns.Learn.Decode("hello")), nil)
  T.eq((ns.Learn.Decode("QK1:!!!!")), nil)
  T.eq((ns.Learn.Decode(42)), nil)
end

S["merge: hotspot counts add up, newest giver wins"] = function()
  local ns = stub.LoadAddon({ login = false })
  local dst = { [5] = { t = "A", seen = 10, s = { m = 52, x = 0.1, y = 0.1, n = "Old" },
                        o = { [1] = { h = { { m = 52, x = 0.5, y = 0.5, c = 2 } } } } } }
  local src = { [5] = { t = "A", seen = 20, s = { m = 52, x = 0.2, y = 0.2, n = "New" },
                        o = { [1] = { h = { { m = 52, x = 0.5, y = 0.5, c = 3 } } } } },
                [6] = { t = "B" } }
  local total, new = ns.Learn.MergeInto(dst, src, 40, 12, flatDist)
  T.eq(total, 2) T.eq(new, 1)
  T.eq(dst[5].s.n, "New")
  T.eq(dst[5].o[1].h[1].c, 5)
end

S["records start, progress, turn-in and chain in game flow"] = function()
  stub.pos = { 52, 0.5632, 0.4763 }
  stub.log = H.log("Westfall", { })
  local ns = stub.LoadAddon()
  -- talk to Gryan, accept 12
  stub.unitGUIDs.questnpc = "Creature-0-1-2-3-234-0000AAAA"
  stub.unitNames.questnpc = "Gryan Stoutmantle"
  stub.FireEvent("QUEST_DETAIL")
  stub.log = H.log("Westfall", { H.quest(12, { title = "The People's Militia", level = 12 }) })
  stub.FireEvent("QUEST_ACCEPTED", 12)
  stub.Advance(1)
  local q = ns.db.learned.quests[12]
  T.eq(q.s.n, "Gryan Stoutmantle") T.eq(q.s.id, 234) T.eq(q.s.k, "npc") T.eq(q.s.m, 52)
  T.eq(q.ml, 12) T.eq(q.f, "A") T.eq(q.l, 12)
  -- progress at a camp
  stub.pos = { 52, 0.4812, 0.3655 }
  stub.log[2].objectives[1].done = 1
  stub.FireEvent("QUEST_LOG_UPDATE")
  stub.Advance(1)
  T.eq(#q.o[1].h, 1)
  T.eq(q.o[1].txt, "Wolf slain")
  -- turn in and pick up the follow-up from the same NPC within 10 s
  stub.pos = { 52, 0.5632, 0.4763 }
  stub.FireEvent("QUEST_COMPLETE", 12, true)
  stub.FireEvent("QUEST_TURNED_IN", 12, 850, 1200)
  stub.log = H.log("Westfall", { })
  stub.FireEvent("QUEST_REMOVED", 12)
  stub.Advance(2)
  stub.FireEvent("QUEST_DETAIL")
  stub.log = H.log("Westfall", { H.quest(13) })
  stub.FireEvent("QUEST_ACCEPTED", 13)
  stub.Advance(1)
  T.eq(q.e.n, "Gryan Stoutmantle")
  T.eq(ns.db.learned.quests[13].prev, 12)
  -- navigator layer 4 uses it
  local m, x, y = ns.Learn:GetQuestPoint(12, true)
  T.eq(m, 52) T.near(x, 0.5632) T.near(y, 0.4763)
  T.ok(ns.Learn:Describe(12):find("Gryan", 1, true))
  T.clean(ns)
end

S["nothing is learned in instances"] = function()
  stub.pos = { 52, 0.5, 0.5 }
  stub.inInstance = true
  local ns = stub.LoadAddon()
  stub.FireEvent("QUEST_ACCEPTED", 50)
  T.eq(ns.db.learned.quests[50], nil)
end

S["givers for an alt: not done, not in log, right faction"] = function()
  local ns = stub.LoadAddon()
  local db = ns.db.learned.quests
  db[1] = { t = "A", l = 10, f = "A", s = { m = 52, x = 0.1, y = 0.1, n = "X" } }
  db[2] = { t = "B", l = 10, f = "H", s = { m = 52, x = 0.1, y = 0.1 } }
  db[3] = { t = "C", l = 20, ml = 18, f = "A", s = { m = 52, x = 0.1, y = 0.1 } }
  db[4] = { t = "D", l = 10, f = "B", s = { m = 37, x = 0.1, y = 0.1 } }
  db[5] = { t = "E", l = 10, f = "A", s = { m = 52, x = 0.1, y = 0.1 } }
  stub.completed[5] = true
  local givers = ns.Learn:GetGivers(52)
  table.sort(givers, function(a, b) return a.questID < b.questID end)
  T.eq(#givers, 2)
  T.eq(givers[1].questID, 1) T.eq(givers[1].tooLow, false)
  T.eq(givers[2].questID, 3) T.eq(givers[2].tooLow, true)
end

S["1500 quests stay well under 2 MB serialised"] = function()
  local ns = stub.LoadAddon({ login = false })
  local quests = {}
  for i = 1, 1500 do
    local o = {}
    for k = 1, 2 do
      local h = {}
      for j = 1, 6 do h[j] = { m = 52, x = 0.1234, y = 0.5678, c = j } end
      o[k] = { txt = "Some objective text slain", h = h }
    end
    quests[i] = { t = "A reasonably long quest title", l = 30, ml = 28, f = "A", seen = 1794268800,
      s = { m = 52, x = 0.5632, y = 0.4763, n = "Gryan Stoutmantle", id = 234, k = "npc" },
      e = { m = 52, x = 0.5632, y = 0.4763, n = "Gryan Stoutmantle", id = 234, k = "npc" }, o = o, prev = i - 1 }
  end
  -- SavedVariables text is roughly the size of a Lua table literal.
  local function size(v)
    if type(v) == "table" then
      local n = 2
      for k, sub in pairs(v) do n = n + size(k) + size(sub) + 4 end
      return n
    end
    return #tostring(v)
  end
  local bytes = size(quests)
  T.ok(bytes < 2 * 1024 * 1024, "estimated " .. bytes .. " bytes")
end

return S
