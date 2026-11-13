-- Core: loading, event isolation, combat queue, timers, DB.
local S = {}

S["addon loads and enables modules without errors"] = function()
  local ns = stub.LoadAddon()
  T.clean(ns)
  T.ok(ns.loggedIn, "PLAYER_LOGIN handled")
  for _, name in ipairs({ "QuestData", "Tracker", "Navigator", "Planner", "Learn", "AutoQuest", "RewardHelper",
                          "MapPins", "ItemBar", "LogTools", "Stats", "Bridges" }) do
    T.ok(ns:IsModuleEnabled(name), name .. " enabled")
  end
  T.eq(ns:IsModuleEnabled("Party"), false, "Party off by default")
  T.ok(SlashCmdList.QUESTKOMPAS, "slash registered")
  T.eq(SLASH_QUESTKOMPAS1, "/qk")
end

S["settings panel registers with verified signatures"] = function()
  local ns = stub.LoadAddon()
  T.ok(stub.settings["QuestKompas_tracker_scale"], "scale slider registered")
  T.ok(stub.settings["QuestKompas_module_Party"], "module toggle registered")
  for _, line in ipairs(ns.Debug.lines) do
    T.ok(not line:find("instellingenpaneel fout", 1, true), line)
  end
  -- Proxy setter writes through to the settings table.
  stub.settings["QuestKompas_tracker_scale"].set(1.2)
  T.eq(ns:GetSetting("tracker", "scale"), 1.2)
end

S["settings panel: subpages, new options and a real tooltip on every control"] = function()
  local ns = stub.LoadAddon()
  T.eq(#stub.subcategories, 4, "four subpages")
  T.ok(stub.settings["QuestKompas_nav_scale"], "arrow scale registered")
  T.ok(stub.settings["QuestKompas_general_minimap"], "minimap toggle registered")
  local active = ns.L:GetActive()
  local known, n = {}, 0
  for _, text in pairs(active) do known[text] = true end
  for name, tip in pairs(stub.tooltips) do
    n = n + 1
    T.ok(type(tip) == "string" and known[tip], "tooltip missing for: " .. name)
  end
  T.ok(n >= 50, "controls with a tooltip: " .. n)
end

S["a failing module in OnEnable is disabled, others keep working"] = function()
  local ns = stub.LoadAddon({ login = false })
  local broken = ns:RegisterModule("Broken", { OnEnable = function() error("boom") end })
  ns.DB.defaults.modules.Broken = true
  stub.FireEvent("ADDON_LOADED", "QuestKompas")
  stub.FireEvent("PLAYER_LOGIN")
  T.eq(broken.enabled, false)
  T.ok(broken.brokenUntilReload)
  T.ok(ns:IsModuleEnabled("Tracker"))
  local found = false
  for _, msg in ipairs(stub.chat) do if msg:find("Broken", 1, true) then found = true end end
  T.ok(found, "one chat line about the broken module")
  ns.DB.defaults.modules.Broken = nil
end

S["handler errors are isolated and 3 failures in 10 s disable the module"] = function()
  local ns = stub.LoadAddon()
  local mod = ns:RegisterModule("Flaky", {})
  mod.enabled = true
  local otherRan = 0
  ns:On("QK_TEST", "Flaky", function() error("bad") end)
  ns:On("QK_TEST", "Other", function() otherRan = otherRan + 1 end)
  ns:Fire("QK_TEST")
  ns:Fire("QK_TEST")
  T.eq(mod.enabled, true, "still on after 2 failures")
  ns:Fire("QK_TEST")
  T.eq(mod.enabled, false, "off after 3 failures")
  T.eq(otherRan, 3, "other handler kept running")
  ns:Fire("QK_TEST")
  T.eq(otherRan, 4)
end

S["unknown client events do not break registration"] = function()
  stub.unknownEvents.DOES_NOT_EXIST = true
  local ns = stub.LoadAddon()
  ns:On("DOES_NOT_EXIST", "X", function() end)
  T.clean(ns)
end

S["RunOutOfCombat queues until PLAYER_REGEN_ENABLED, keyed entries dedupe"] = function()
  local ns = stub.LoadAddon()
  local ran = {}
  stub.combat = true
  ns:RunOutOfCombat(function() ran[#ran + 1] = "a" end)
  ns:RunOutOfCombat(function() ran[#ran + 1] = "k1" end, "k")
  ns:RunOutOfCombat(function() ran[#ran + 1] = "k2" end, "k")
  T.eq(#ran, 0)
  stub.combat = false
  stub.FireEvent("PLAYER_REGEN_ENABLED")
  T.same(ran, { "a", "k2" })
  ns:RunOutOfCombat(function() ran[#ran + 1] = "now" end)
  T.eq(ran[3], "now")
end

S["Debounce runs once after the last call; Throttle limits rate"] = function()
  local ns = stub.LoadAddon()
  local n = 0
  for _ = 1, 5 do ns:Debounce("t", 0.3, function() n = n + 1 end) stub.Advance(0.1) end
  T.eq(n, 0)
  stub.Advance(0.3)
  T.eq(n, 1)
  local m = 0
  for _ = 1, 10 do ns:Throttle("th", 0.5, function() m = m + 1 end) stub.Advance(0.05) end
  T.eq(m, 1, "first call runs immediately")
  stub.Advance(1)
  T.eq(m, 2, "one trailing run")
end

S["DB defaults merge without overwriting, migrations run once"] = function()
  local ns = stub.LoadAddon({ login = false })
  local db = { settings = { tracker = { scale = 1.3 } } }
  local cdb = {}
  ns.DB.Prepare(db, cdb)
  T.eq(db.schema, 1)
  T.eq(db.settings.tracker.scale, 1.3, "existing value kept")
  T.eq(db.settings.tracker.width, 260, "default filled")
  T.ok(db.learned.quests)
  T.ok(cdb.positions and cdb.history and cdb.colors)
  local calls = 0
  ns.DB.migrations[2] = function(d) calls = calls + 1 d.extra = true end
  ns.DB.Migrate(db, ns.DB.migrations, 2)
  ns.DB.Migrate(db, ns.DB.migrations, 2)
  T.eq(calls, 1)
  T.eq(db.schema, 2)
  ns.DB.migrations[2] = nil
end

S["per-character overrides win and reset restores defaults"] = function()
  local ns = stub.LoadAddon()
  ns.cdb.perChar = true
  ns:SetSetting("tracker", "width", 300)
  T.eq(ns:GetSetting("tracker", "width"), 300)
  T.eq(ns.db.settings.tracker.width, 260, "account value untouched")
  T.eq(ns.cfg.tracker.width, 300, "cfg proxy reads effective value")
  ns:ResetSection("tracker")
  T.eq(ns:GetSetting("tracker", "width"), 260)
end

S["slash commands run without errors"] = function()
  local ns = stub.LoadAddon()
  for _, cmd in ipairs({ "version", "help", "toggle", "toggle", "lock", "lock", "reset", "dump", "plan debug",
                         "grey", "find wolf", "stats", "stats reset", "auto", "auto", "clear", "next",
                         "debug", "debug", "debug profile", "debug profile", "export alles", "import", "",
                         "onzin" }) do
    SlashCmdList.QUESTKOMPAS(cmd)
  end
  stub.Advance(1)
  T.clean(ns)
end

return S
