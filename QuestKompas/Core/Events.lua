-- QuestKompas: event dispatcher, internal callbacks and module lifecycle.
local ADDON, ns = ...

local frame = CreateFrame("Frame")
local handlers = {}      -- event -> { owner -> fn }
local registered = {}    -- client events registered on the frame
local failures = {}      -- owner -> { times }

local FAIL_LIMIT, FAIL_WINDOW = 3, 10

local function isInternal(event)
  return event:sub(1, 3) == "QK_"
end

-- Unknown events raise an error in RegisterEvent; never let that break us.
local function registerClientEvent(event)
  if registered[event] then return true end
  local ok = pcall(frame.RegisterEvent, frame, event)
  registered[event] = ok
  if not ok and ns.Debug then ns.Debug:Log("event bestaat niet:", event) end
  return ok
end

-- handlers[event] = { map = { owner -> fn }, order = { owners }, dirty }.
-- The order array is rebuilt lazily, so handlers may be added or removed
-- while an event is being dispatched without allocating per dispatch.
local function bucket(event)
  local b = handlers[event]
  if not b then
    b = { map = {}, order = {}, dirty = false }
    handlers[event] = b
  end
  return b
end

function ns:On(event, owner, fn)
  local b = bucket(event)
  if b.map[owner] == nil then b.dirty = true end
  b.map[owner] = fn
  if not isInternal(event) then registerClientEvent(event) end
end

function ns:Off(event, owner)
  local b = handlers[event]
  if b and b.map[owner] ~= nil then
    b.map[owner] = nil
    b.dirty = true
  end
end

function ns:OffAll(owner)
  for event in pairs(handlers) do self:Off(event, owner) end
end

local function recordFailure(owner, event, err)
  if ns.Debug then ns.Debug:Log("fout in", tostring(owner), event, tostring(err)) end
  local mod = ns.modules[owner]
  if not mod then return end
  local now = ns.Compat.GetTime()
  local list = failures[owner] or {}
  failures[owner] = list
  list[#list + 1] = now
  while list[1] and now - list[1] > FAIL_WINDOW do table.remove(list, 1) end
  if #list >= FAIL_LIMIT then
    failures[owner] = nil
    ns:DisableModule(owner, true)
    ns:Print(string.format(ns.L["MODULE_DISABLED_ERRORS"], owner))
  end
end

function ns:Fire(event, ...)
  local b = handlers[event]
  if not b then return end
  if b.dirty then
    local order = {}
    for owner in pairs(b.map) do order[#order + 1] = owner end
    table.sort(order, function(x, y) return tostring(x) < tostring(y) end)
    b.order, b.dirty = order, false
  end
  local order, map = b.order, b.map
  local profiling = ns.Debug and ns.Debug.profiling
  for i = 1, #order do
    local owner = order[i]
    local fn = map[owner]
    if fn then
      local start = profiling and debugprofilestop and debugprofilestop()
      local ok, err = ns.SafeCall(fn, owner, ...)
      if start then ns.Debug:AddProfile(owner, debugprofilestop() - start) end
      if not ok then recordFailure(owner, event, err) end
    end
  end
end

frame:SetScript("OnEvent", function(_, event, ...) ns:Fire(event, ...) end)

----------------------------------------------------------------------------
-- Error handler: log always, forward to the client error handler (BugSack)
-- only out of combat so we never throw at the player mid-fight (10.2).
----------------------------------------------------------------------------
local pendingErrors = {}
ns.errorHandler = function(err)
  local msg = tostring(err)
  if ns.Compat and ns.Compat.InCombat() then
    if #pendingErrors < 20 then pendingErrors[#pendingErrors + 1] = msg end
  elseif geterrorhandler then
    local handler = geterrorhandler()
    if handler then pcall(handler, msg) end
  end
  return msg
end

----------------------------------------------------------------------------
-- Module lifecycle
----------------------------------------------------------------------------
local function call(mod, hook, ...)
  local fn = mod[hook]
  if type(fn) ~= "function" then return true end
  local ok, err = ns.SafeCall(fn, mod, ...)
  if not ok and ns.Debug then ns.Debug:Log("fout in", mod.name, hook, tostring(err)) end
  return ok, err
end

function ns:EnableModule(name)
  local mod = self.modules[name]
  if not mod or mod.enabled or mod.brokenUntilReload then return false end
  mod.enabled = true
  local ok = call(mod, "OnEnable")
  if not ok then
    self:DisableModule(name, true)
    self:Print(string.format(ns.L["MODULE_DISABLED_ENABLE"], name))
    return false
  end
  return true
end

function ns:DisableModule(name, broken)
  local mod = self.modules[name]
  if not mod then return end
  if broken then mod.brokenUntilReload = true end
  if not mod.enabled then return end
  mod.enabled = false
  self:OffAll(name)
  call(mod, "OnDisable")
end

function ns:SetModuleEnabled(name, on)
  if on then
    local mod = self.modules[name]
    if mod then mod.brokenUntilReload = nil end
    return self:EnableModule(name)
  end
  self:DisableModule(name)
  return true
end

-- ADDON_LOADED: database first, then OnInit for every module.
ns:On("ADDON_LOADED", "Core", function(_, name)
  if name ~= ADDON then return end
  ns:Off("ADDON_LOADED", "Core")
  ns.DB:Init()
  ns.L:SetLanguage(ns.cfg.general.language)
  for _, modName in ipairs(ns.moduleOrder) do
    local mod = ns.modules[modName]
    local ok = call(mod, "OnInit")
    if not ok then mod.brokenUntilReload = true end
  end
end)

-- PLAYER_LOGIN: enable modules that are switched on in the settings.
ns:On("PLAYER_LOGIN", "Core", function()
  ns:Off("PLAYER_LOGIN", "Core")
  local enabledCfg = ns.db and ns.db.settings.modules or {}
  for _, modName in ipairs(ns.moduleOrder) do
    local mod = ns.modules[modName]
    local wanted = enabledCfg[modName]
    if mod.alwaysOn then wanted = true end
    if wanted ~= false and wanted ~= nil then ns:EnableModule(modName) end
  end
  ns.loggedIn = true
  ns:Fire("QK_READY")
end)

ns:On("PLAYER_REGEN_DISABLED", "Core", function()
  ns.inCombat = true
  for _, modName in ipairs(ns.moduleOrder) do
    local mod = ns.modules[modName]
    if mod.enabled then call(mod, "OnCombatStart") end
  end
end)

ns:On("PLAYER_REGEN_ENABLED", "Core", function()
  ns.inCombat = false
  for _, modName in ipairs(ns.moduleOrder) do
    local mod = ns.modules[modName]
    if mod.enabled then call(mod, "OnCombatEnd") end
  end
  if #pendingErrors > 0 and geterrorhandler then
    local list = pendingErrors
    pendingErrors = {}
    local handler = geterrorhandler()
    for i = 1, #list do pcall(handler, list[i]) end
  end
end)

-- Test hook: reset dispatcher state between test cases.
function ns._ResetEventsForTests()
  for k in pairs(failures) do failures[k] = nil end
end
