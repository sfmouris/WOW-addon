-- QuestKompas: namespace, version, constants and module registry.
local ADDON, ns = ...

ns.name = ADDON
ns.Core = ns -- spec 4.1 uses ns.Core:RegisterModule; both spellings work.

-- Interface number this build targets. Must match "## Interface:" in the TOC
-- (checked by tests/spec_toc.lua).
ns.TOC_INTERFACE = 16001

do
  local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata
  ns.version = (getMeta and getMeta(ADDON, "Version")) or "dev"
end

ns.COLOR = "|cff33ccff"
ns.PREFIX = ns.COLOR .. "QuestKompas|r"

ns.modules, ns.moduleOrder = {}, {}

-- Registers a module table. Optional hooks: OnInit, OnEnable, OnDisable,
-- OnCombatStart, OnCombatEnd. The module is also reachable as ns[name].
function ns:RegisterModule(name, mod)
  mod = mod or {}
  mod.name = name
  mod.enabled = false
  self.modules[name] = mod
  self.moduleOrder[#self.moduleOrder + 1] = name
  self[name] = mod
  return mod
end

function ns:GetModule(name)
  return self.modules[name]
end

function ns:IsModuleEnabled(name)
  local mod = self.modules[name]
  return mod ~= nil and mod.enabled == true
end

-- Chat output: one line, addon prefix. Never used for debug output.
function ns:Print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring((select(i, ...)))
  end
  local msg = ns.PREFIX .. ": " .. table.concat(parts, " ")
  local frame = DEFAULT_CHAT_FRAME
  if frame and frame.AddMessage then
    frame:AddMessage(msg)
  elseif print then
    print(msg)
  end
end

-- Calls fn(...) through xpcall. WoW's xpcall forwards extra arguments, plain
-- Lua 5.1 (used by the tests) does not, so detect once and fall back to a
-- closure there.
local xpcallPassesArgs
do
  local _, v = xpcall(function(a) return a end, function() end, true)
  xpcallPassesArgs = (v == true)
end

local function defaultHandler(err)
  return err
end

function ns.SafeCall(fn, ...)
  local handler = ns.errorHandler or defaultHandler
  if xpcallPassesArgs then
    return xpcall(fn, handler, ...)
  end
  local n, args = select("#", ...), { ... }
  return xpcall(function() return fn(unpack(args, 1, n)) end, handler)
end
