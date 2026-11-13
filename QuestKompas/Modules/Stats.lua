-- QuestKompas: session and history statistics (spec 4.13).
local _, ns = ...

local ST = ns:RegisterModule("Stats")
local C, U, L = ns.Compat, ns.Util, ns.L

local HISTORY_MAX = 2000
local RESUME_SECONDS = 300 -- a /reload or quick relog continues the session

----------------------------------------------------------------------------
-- Pure helpers (tests/spec_stats.lua)
----------------------------------------------------------------------------
function ST.PerHour(amount, seconds)
  if not seconds or seconds < 60 then return nil end
  return amount * 3600 / seconds
end

-- Remaining XP divided by the average XP of the last n quest turn-ins.
function ST.CalcQuestsToLevel(remaining, history, n)
  n = n or 10
  local sum, count = 0, 0
  for i = #history, 1, -1 do
    local h = history[i]
    if h.xp and h.xp > 0 then
      sum, count = sum + h.xp, count + 1
      if count >= n then break end
    end
  end
  if count == 0 or remaining <= 0 then return nil end
  return math.ceil(remaining / (sum / count))
end

function ST.AddHistory(history, rec, max)
  history[#history + 1] = rec
  while #history > (max or HISTORY_MAX) do table.remove(history, 1) end
end

-- XP gained between two readings, across level-ups.
function ST.XPDelta(oldXP, oldMax, newXP, levelUps)
  if levelUps and levelUps > 0 then
    return (oldMax - oldXP) + newXP
  end
  return math.max(0, newXP - oldXP)
end

----------------------------------------------------------------------------
-- Session
----------------------------------------------------------------------------
local lastXP, lastMax, pendingLevelUps = 0, 0, 0

local function session()
  return ns.cdb.session
end

function ST:StartSession(force)
  local s = session()
  local now = time()
  if force or not s.start or not s.last or now - s.last > RESUME_SECONDS then
    s.start, s.xp, s.questXP, s.quests, s.money = now, 0, 0, 0, 0
  end
  s.last = now
  lastXP, lastMax = C.UnitXP()
end

function ST:Elapsed()
  local s = session()
  return s.start and (time() - s.start) or 0
end

function ST:XPPerHour()
  return ST.PerHour(session().xp or 0, self:Elapsed())
end

function ST:QuestsToLevel()
  local xp, max = C.UnitXP()
  if max <= 0 then return nil end
  return ST.CalcQuestsToLevel(max - xp, ns.cdb.history, 10)
end

function ST:TimeToLevel()
  local xph = self:XPPerHour()
  local xp, max = C.UnitXP()
  if not xph or xph <= 0 or max <= 0 then return nil end
  return (max - xp) / xph * 3600
end

function ST:Lines()
  local s = session()
  local elapsed = self:Elapsed()
  local out = {
    string.format(L["STATS_SESSION_FMT"], U.FormatDuration(elapsed)),
    string.format(L["STATS_XP_FMT"], U.FormatShort(s.xp or 0), U.FormatShort(self:XPPerHour() or 0)),
    string.format(L["STATS_QUESTXP_FMT"], U.FormatShort(s.questXP or 0),
      U.FormatShort(ST.PerHour(s.questXP or 0, elapsed) or 0)),
    string.format(L["STATS_QUESTS_FMT"], s.quests or 0, string.format("%.1f", ST.PerHour(s.quests or 0, elapsed) or 0)),
    string.format(L["STATS_MONEY_FMT"], U.FormatMoney(s.money or 0)),
  }
  local ttl = self:TimeToLevel()
  out[#out + 1] = string.format(L["STATS_TTL_FMT"], ttl and U.FormatDuration(ttl) or "?")
  local qtl = self:QuestsToLevel()
  out[#out + 1] = string.format(L["STATS_QTL_FMT"], qtl and tostring(qtl) or "?")
  out[#out + 1] = ""
  out[#out + 1] = L["STATS_HISTORY"]
  local h = ns.cdb.history
  for i = #h, math.max(1, #h - 9), -1 do
    local r = h[i]
    out[#out + 1] = string.format("  %s  [%s] %s  %s xp  %s", date("%d-%m %H:%M", r.ts), tostring(r.l or "?"),
      r.t or tostring(r.id), U.FormatShort(r.xp or 0), U.FormatMoney(r.c or 0))
  end
  return out
end

local window
function ST:ShowWindow()
  window = window or ns.UI:CreateTextWindow(L["STATS_TITLE"], 380, 300)
  window:SetLines(self:Lines())
  window:Show()
end

function ST:Reset()
  self:StartSession(true)
  ns:Print(L["STATS_RESET"])
end

function ST:OnEnable()
  self:StartSession(false)
  ns:On("PLAYER_LEVEL_UP", "Stats", function() pendingLevelUps = pendingLevelUps + 1 end)
  ns:On("PLAYER_XP_UPDATE", "Stats", function()
    local xp, max = C.UnitXP()
    local s = session()
    s.xp = (s.xp or 0) + ST.XPDelta(lastXP, lastMax, xp, pendingLevelUps)
    pendingLevelUps = 0
    lastXP, lastMax = xp, max
    s.last = time()
  end)
  ns:On("QK_QUEST_TURNED_IN", "Stats", function(_, questID, xp, money)
    local s = session()
    s.questXP = (s.questXP or 0) + (xp or 0)
    s.quests = (s.quests or 0) + 1
    s.money = (s.money or 0) + (money or 0)
    s.last = time()
    local q = ns.QuestData:Get(questID)
    ST.AddHistory(ns.cdb.history, {
      id = questID, ts = time(), z = q and q.zoneHeader or C.GetMapName(C.GetPlayerMapID()),
      l = q and q.level, xp = xp, c = money, t = q and q.title,
    }, HISTORY_MAX)
  end)
  ns:On("PLAYER_LOGOUT", "Stats", function() session().last = time() end)
end
