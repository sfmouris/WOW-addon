-- Shared fixtures for the specs.
local H = {}

-- Builds a quest log entry for stub.log.
function H.quest(id, opts)
  opts = opts or {}
  local q = { questID = id, title = opts.title or ("Quest " .. id), level = opts.level or 12,
              objectives = opts.objectives or { { text = "Wolf slain", done = 0, need = 5 } },
              complete = opts.complete, group = opts.group, xp = opts.xp or 500, money = opts.money or 100,
              dist = opts.dist, waypoint = opts.waypoint, item = opts.item, tagID = opts.tagID,
              elite = opts.elite, watched = true, frequency = opts.frequency }
  return q
end

function H.log(header, quests)
  local log = { { header = header } }
  for _, q in ipairs(quests) do log[#log + 1] = q end
  return log
end

-- Collects internal events fired on ns.
function H.capture(ns, names)
  local got = {}
  for _, name in ipairs(names) do
    ns:On(name, "Capture", function(_, ...) got[#got + 1] = { name, ... } end)
  end
  return got
end

return H
