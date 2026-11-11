-- QuestKompas: out-of-combat queue (spec 2.3, 2.4).
local _, ns = ...

local queue = {}
local keyed = {}

-- Runs fn now, or after PLAYER_REGEN_ENABLED when in combat lockdown.
-- With a key, only the last queued fn for that key runs.
function ns:RunOutOfCombat(fn, key)
  if not ns.Compat.InCombat() then
    return fn()
  end
  if key then
    if not keyed[key] then queue[#queue + 1] = key end
    keyed[key] = fn
  else
    queue[#queue + 1] = fn
  end
end

function ns:PendingCombatTasks()
  return #queue
end

local function flush()
  local pending = queue
  queue = {}
  for i = 1, #pending do
    local item = pending[i]
    local fn = item
    if type(item) == "string" then
      fn = keyed[item]
      keyed[item] = nil
    end
    if fn then ns.SafeCall(fn) end
  end
end

ns:On("PLAYER_REGEN_ENABLED", "Combat", function()
  flush()
end)

ns._FlushCombatQueue = flush
