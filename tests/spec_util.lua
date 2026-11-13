local S = {}

S["FormatMoney and FormatShort"] = function()
  local ns = stub.LoadAddon({ login = false })
  local U = ns.Util
  T.eq(U.FormatMoney(0), "0c")
  T.eq(U.FormatMoney(1240), "12s 40c")
  T.eq(U.FormatMoney(1234567), "123g 45s 67c")
  T.eq(U.FormatMoney(10000), "1g")
  T.eq(U.FormatShort(999), "999")
  T.eq(U.FormatShort(1234), "1.2k")
  T.eq(U.FormatShort(12345), "12k")
end

S["Difficulty follows the Blizzard thresholds"] = function()
  local ns = stub.LoadAddon({ login = false })
  local D = ns.Util.Difficulty
  T.eq(D(17, 12, 5), "red")
  T.eq(D(15, 12, 5), "orange")
  T.eq(D(12, 12, 5), "yellow")
  T.eq(D(8, 12, 5), "yellow")
  T.eq(D(7, 12, 5), "green")
  T.eq(D(6, 12, 5), "grey")
end

S["ParseGUID extracts kind and id"] = function()
  local ns = stub.LoadAddon({ login = false })
  local kind, id = ns.Util.ParseGUID("Creature-0-1465-0-2105-234-000012ABCD")
  T.eq(kind, "npc") T.eq(id, 234)
  kind, id = ns.Util.ParseGUID("GameObject-0-1465-0-2105-1561-0000")
  T.eq(kind, "obj") T.eq(id, 1561)
  T.eq((ns.Util.ParseGUID("Player-1234-ABCDEF")), "player")
  T.eq(ns.Util.ParseGUID(nil), nil)
  T.eq(ns.Util.ParseGUID("Weird-1"), nil)
end

S["PickColor spreads palette indices"] = function()
  local ns = stub.LoadAddon({ login = false })
  local assigned = {}
  for i = 1, 8 do assigned[i] = ns.Util.PickColor(assigned) end
  local seen = {}
  for _, v in ipairs(assigned) do seen[v] = true end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  T.eq(n, 8, "8 quests get 8 different colours")
end

S["Geo distance and bearing via world positions"] = function()
  local ns = stub.LoadAddon({ login = false })
  local G = ns.Geo
  -- stub maps are 1000 yards wide
  T.near(G.Distance(52, 0.5, 0.5, 52, 0.5, 0.6), 100, 1e-6)
  T.near(G.Distance(52, 0.1, 0.1, 52, 0.4, 0.5), 500, 1e-6)
  T.near(G.Bearing(52, 0.5, 0.5, 52, 0.5, 0.4), 0, 1e-6, "north")
  T.near(G.Bearing(52, 0.5, 0.5, 52, 0.4, 0.5), math.pi / 2, 1e-6, "west")
  T.near(G.Bearing(52, 0.5, 0.5, 52, 0.6, 0.5), 3 * math.pi / 2, 1e-6, "east")
  T.near(G.RelativeAngle(0, math.pi / 2), 3 * math.pi / 2, 1e-6)
  T.eq(G.Distance(52, 0.5, 0.5, 999, 0.5, 0.5), nil, "unknown map")
end

S["Locale falls back to English and to the key"] = function()
  local ns = stub.LoadAddon({ login = false })
  local L = ns.L
  L:SetLanguage("en")
  T.eq(L["YES"], "Yes")
  L:SetLanguage("nl")
  T.eq(L["YES"], "Ja")
  T.eq(L["DOES_NOT_EXIST_KEY"], "DOES_NOT_EXIST_KEY")
end

return S
