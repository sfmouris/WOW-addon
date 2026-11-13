-- QuestKompas: self-learning location database (spec 4.6, 6.1).
local _, ns = ...

local Learn = ns:RegisterModule("Learn")
local C, U, L = ns.Compat, ns.Util, ns.L

local CHAIN_WINDOW, NPC_WINDOW = 10, 60
local EXPORT_PREFIX = "QK1:"
local MAX_STR = 200

local function round4(v) return U.Round(v, 4) end
Learn.Round4 = round4

----------------------------------------------------------------------------
-- Pure helpers (tests/spec_learn.lua)
----------------------------------------------------------------------------
-- Adds point p = { m, x, y, c } to hotspot list h. Points within
-- mergeYards of an existing hotspot on the same map are merged with a
-- count-weighted average. The least used hotspot drops when over maxN.
function Learn.MergeHotspot(h, p, mergeYards, maxN, dist)
  local c = p.c or 1
  for _, s in ipairs(h) do
    if s.m == p.m then
      local d = dist(s.m, s.x, s.y, p.m, p.x, p.y)
      if d and d <= mergeYards then
        local total = s.c + c
        s.x = round4((s.x * s.c + p.x * c) / total)
        s.y = round4((s.y * s.c + p.y * c) / total)
        s.c = total
        return h
      end
    end
  end
  h[#h + 1] = { m = p.m, x = round4(p.x), y = round4(p.y), c = c }
  while #h > maxN do
    local minI, minC = 1, math.huge
    for i, s in ipairs(h) do
      if s.c < minC then minI, minC = i, s.c end
    end
    table.remove(h, minI)
  end
  return h
end

local function isNum(v, lo, hi)
  return type(v) == "number" and v == v and v >= lo and v <= hi
end

local function cleanStr(v)
  if type(v) ~= "string" then return nil end
  if #v > MAX_STR then v = v:sub(1, MAX_STR) end
  return v
end

local KINDS = { npc = true, obj = true, item = true, unknown = true }

local function cleanPoint(p)
  if type(p) ~= "table" then return nil end
  if not (isNum(p.m, 1, 1e6) and isNum(p.x, 0, 1) and isNum(p.y, 0, 1)) then return nil end
  local out = { m = math.floor(p.m), x = round4(p.x), y = round4(p.y) }
  out.n = cleanStr(p.n)
  if isNum(p.id, 1, 1e8) then out.id = math.floor(p.id) end
  out.k = (type(p.k) == "string" and KINDS[p.k]) and p.k or nil
  return out
end

local function cleanSet(v)
  if type(v) ~= "table" then return nil end
  local out, n = {}, 0
  for k, flag in pairs(v) do
    if type(k) == "string" and #k <= 20 and flag == true and n < 20 then
      out[k] = true
      n = n + 1
    end
  end
  return n > 0 and out or nil
end

-- Validates untrusted data (import). Returns a clean quests table and the
-- number of accepted quests. Never executes anything.
function Learn.Validate(quests, maxHotspots)
  maxHotspots = maxHotspots or 12
  local out, n = {}, 0
  if type(quests) ~= "table" then return out, 0 end
  for id, q in pairs(quests) do
    if isNum(id, 1, 1e7) and id == math.floor(id) and type(q) == "table" then
      local c = {}
      c.t = cleanStr(q.t)
      if isNum(q.l, 0, 200) then c.l = math.floor(q.l) end
      if isNum(q.ml, 0, 200) then c.ml = math.floor(q.ml) end
      if q.f == "A" or q.f == "H" or q.f == "B" then c.f = q.f end
      c.s = cleanPoint(q.s)
      c.e = cleanPoint(q.e)
      if isNum(q.prev, 1, 1e7) then c.prev = math.floor(q.prev) end
      if isNum(q.seen, 0, 4e9) then c.seen = math.floor(q.seen) end
      c.cl = cleanSet(q.cl)
      c.ra = cleanSet(q.ra)
      if type(q.o) == "table" then
        c.o = {}
        for idx, o in pairs(q.o) do
          if isNum(idx, 1, 50) and idx == math.floor(idx) and type(o) == "table" then
            local co = { txt = cleanStr(o.txt), h = {} }
            if type(o.h) == "table" then
              for _, h in ipairs(o.h) do
                local p = cleanPoint(h)
                if p and #co.h < maxHotspots then
                  co.h[#co.h + 1] = { m = p.m, x = p.x, y = p.y, c = isNum(h.c, 1, 1e6) and math.floor(h.c) or 1 }
                end
              end
            end
            c.o[idx] = co
          end
        end
      end
      out[id] = c
      n = n + 1
    end
  end
  return out, n
end

-- Merges src into dst (both validated quest tables). Hotspot counts add up;
-- the newest quest giver wins on conflict. Returns total, new.
function Learn.MergeInto(dst, src, mergeYards, maxN, dist)
  local total, new = 0, 0
  for id, s in pairs(src) do
    total = total + 1
    local d = dst[id]
    if not d then
      dst[id] = ns.DB.Copy(s)
      new = new + 1
    else
      d.t = d.t or s.t
      d.l = d.l or s.l
      if s.ml and (not d.ml or s.ml < d.ml) then d.ml = s.ml end
      if s.f and d.f and s.f ~= d.f then d.f = "B" else d.f = d.f or s.f end
      local srcNewer = (s.seen or 0) > (d.seen or 0)
      if s.s and (srcNewer or not d.s) then d.s = ns.DB.Copy(s.s) end
      if s.e and (srcNewer or not d.e) then d.e = ns.DB.Copy(s.e) end
      d.prev = d.prev or s.prev
      if s.seen and (not d.seen or s.seen > d.seen) then d.seen = s.seen end
      for _, key in ipairs({ "cl", "ra" }) do
        if s[key] then
          d[key] = d[key] or {}
          for k in pairs(s[key]) do d[key][k] = true end
        end
      end
      if s.o then
        d.o = d.o or {}
        for idx, so in pairs(s.o) do
          local dob = d.o[idx]
          if not dob then
            d.o[idx] = ns.DB.Copy(so)
          else
            dob.txt = dob.txt or so.txt
            dob.h = dob.h or {}
            for _, h in ipairs(so.h or {}) do Learn.MergeHotspot(dob.h, h, mergeYards, maxN, dist) end
          end
        end
      end
    end
  end
  return total, new
end

-- Keeps quests that have any point on mapID.
function Learn.FilterZone(quests, mapID)
  local out = {}
  for id, q in pairs(quests) do
    local keep = (q.s and q.s.m == mapID) or (q.e and q.e.m == mapID)
    if not keep and q.o then
      for _, o in pairs(q.o) do
        for _, h in ipairs(o.h or {}) do
          if h.m == mapID then keep = true break end
        end
        if keep then break end
      end
    end
    if keep then out[id] = q end
  end
  return out
end

----------------------------------------------------------------------------
-- Serialisation (LibSerialize + LibDeflate, printable)
----------------------------------------------------------------------------
local function libs()
  local LS = LibStub and LibStub("LibSerialize", true)
  local LD = LibStub and LibStub("LibDeflate", true)
  return LS, LD
end

function Learn.Encode(quests)
  local LS, LD = libs()
  if not (LS and LD) then return nil, "libs" end
  local raw = LS:Serialize({ v = 1, quests = quests })
  local packed = LD:CompressDeflate(raw, { level = 9 })
  return EXPORT_PREFIX .. LD:EncodeForPrint(packed)
end

function Learn.Decode(str)
  local LS, LD = libs()
  if not (LS and LD) then return nil, "libs" end
  if type(str) ~= "string" then return nil, "type" end
  str = str:gsub("%s+", "")
  if str:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then return nil, "prefix" end
  if #str > 4 * 1024 * 1024 then return nil, "size" end
  local packed = LD:DecodeForPrint(str:sub(#EXPORT_PREFIX + 1))
  if not packed then return nil, "decode" end
  local raw = LD:DecompressDeflate(packed)
  if not raw then return nil, "decompress" end
  local ok, payload = LS:Deserialize(raw)
  if not ok or type(payload) ~= "table" or payload.v ~= 1 then return nil, "payload" end
  return payload.quests
end

----------------------------------------------------------------------------
-- Recording
----------------------------------------------------------------------------
local lastNPC      -- { guid info, t }
local lastTurnIn   -- { questID, id, t }

local function db()
  return ns.db.learned.quests
end

local function mayLearn()
  if not ns:GetSetting("learn", "enabled") then return false end
  if C.IsInInstance() then return false end
  return true
end

-- Player position, skipped when the client hands out secret values (2.3).
local function playerPoint()
  local m, x, y = C.GetPlayerPosition()
  if not m or not (ns.IsSafe(m) and ns.IsSafe(x) and ns.IsSafe(y)) then return nil end
  return { m = m, x = round4(x), y = round4(y) }
end

-- Remember who the player is talking to (quest frames use "questnpc",
-- gossip uses "npc").
local function captureNPC(kind)
  local guid, name = C.UnitGUIDAndName("questnpc")
  if not guid then guid, name = C.UnitGUIDAndName("npc") end
  if kind == "item" then
    lastNPC = { k = "item", t = C.GetTime() }
    return
  end
  if not guid then lastNPC = nil return end
  local gk, id = U.ParseGUID(guid)
  lastNPC = { k = gk or "unknown", id = id, n = name, t = C.GetTime() }
end

local function recentNPC()
  if lastNPC and C.GetTime() - lastNPC.t <= NPC_WINDOW then return lastNPC end
  return nil
end

local function entry(questID)
  local q = db()[questID]
  if not q then q = {} db()[questID] = q end
  q.seen = time and time() or 0
  return q
end

local function markFaction(q)
  local f = C.UnitFaction()
  if not f then return end
  if q.f and q.f ~= f then q.f = "B" else q.f = q.f or f end
end

local function markClassRace(q)
  local class, race = C.UnitClassRace()
  if class then q.cl = q.cl or {} q.cl[class] = true end
  if race then q.ra = q.ra or {} q.ra[race] = true end
end

function Learn:RecordAccept(questID)
  if not mayLearn() then return end
  local npc = recentNPC()
  if npc and npc.k == "player" then return end -- shared by a party member
  local pt = playerPoint()
  local q = entry(questID)
  q.t = C.GetQuestTitle(questID) or q.t
  local lvl = C.UnitLevel("player")
  if lvl and (not q.ml or lvl < q.ml) then q.ml = lvl end
  local logIndex = C.GetLogIndexForQuestID(questID)
  local info = logIndex and C.GetQuestInfo(logIndex)
  if info and info.level and info.level > 0 then q.l = info.level end
  markFaction(q)
  markClassRace(q)
  if pt then
    pt.n, pt.id, pt.k = npc and npc.n, npc and npc.id, npc and npc.k or "unknown"
    q.s = pt
  end
  if lastTurnIn and C.GetTime() - lastTurnIn.t <= CHAIN_WINDOW and npc and npc.id
      and lastTurnIn.id == npc.id and lastTurnIn.questID ~= questID then
    q.prev = lastTurnIn.questID
  end
  ns:Fire("QK_LEARN_UPDATED", questID)
end

function Learn:RecordTurnIn(questID)
  if not mayLearn() then return end
  local npc = recentNPC()
  local pt = playerPoint()
  local q = entry(questID)
  local snap = ns.QuestData:Get(questID)
  if snap then
    q.t = q.t or snap.title
    q.l = q.l or snap.level
  end
  if pt then
    pt.n, pt.id, pt.k = npc and npc.n, npc and npc.id, npc and npc.k or "unknown"
    q.e = pt
  end
  lastTurnIn = { questID = questID, id = npc and npc.id, t = C.GetTime() }
  ns:Fire("QK_LEARN_UPDATED", questID)
end

function Learn:RecordProgress(questID, objIndex)
  if not mayLearn() then return end
  local pt = playerPoint()
  if not pt then return end
  local q = entry(questID)
  q.o = q.o or {}
  local o = q.o[objIndex]
  if not o then o = { h = {} } q.o[objIndex] = o end
  local snap = ns.QuestData:Get(questID)
  local so = snap and snap.objectives[objIndex]
  if so then o.txt = cleanStr(so.text) end
  if snap then q.t = q.t or snap.title q.l = q.l or snap.level end
  pt.c = 1
  Learn.MergeHotspot(o.h, pt, ns:GetSetting("learn", "mergeYards") or 40,
    ns:GetSetting("learn", "maxHotspots") or 12, ns.Geo.Distance)
  ns:Fire("QK_LEARN_UPDATED", questID)
end

----------------------------------------------------------------------------
-- Queries
----------------------------------------------------------------------------
function Learn:Get(questID)
  return db()[questID]
end

-- Navigator layer 4: turn-in point when complete, else the nearest hotspot
-- of an unfinished objective.
function Learn:GetQuestPoint(questID, isComplete, pm, px, py)
  local q = db()[questID]
  if not q then return nil end
  if isComplete then
    if q.e then return q.e.m, q.e.x, q.e.y end
    if q.s then return q.s.m, q.s.x, q.s.y end -- most quests end where they start
    return nil
  end
  if not q.o then return nil end
  local snap = ns.QuestData:Get(questID)
  local best, bestD, bestC
  for idx, o in pairs(q.o) do
    local so = snap and snap.objectives[idx]
    if not (so and so.finished) then
      for _, h in ipairs(o.h or {}) do
        local d = pm and ns.Geo.Distance(pm, px, py, h.m, h.x, h.y)
        if d then
          if not bestD or d < bestD then best, bestD = h, d end
        elseif not bestD and (not bestC or h.c > bestC) then
          best, bestC = h, h.c
        end
      end
    end
  end
  if best then return best.m, best.x, best.y end
  return nil
end

function Learn:GetHotspots(questID)
  local q = db()[questID]
  local out = {}
  if not (q and q.o) then return out end
  for _, o in pairs(q.o) do
    for _, h in ipairs(o.h or {}) do out[#out + 1] = h end
  end
  return out
end

-- Quest givers on mapID for quests this character has not done.
function Learn:GetGivers(mapID)
  local out = {}
  local faction = C.UnitFaction()
  local level = C.UnitLevel("player") or 1
  for id, q in pairs(db()) do
    local s = q.s
    if s and s.m == mapID and (not q.f or q.f == "B" or q.f == faction)
        and not ns.QuestData:Get(id) and not C.IsQuestFlaggedCompleted(id) then
      out[#out + 1] = { questID = id, x = s.x, y = s.y, title = q.t, level = q.l, npc = s.n,
                        tooLow = (q.ml or q.l or 0) > level }
    end
  end
  return out
end

function Learn:Describe(questID)
  local q = db()[questID]
  if not q then return nil end
  local n = #self:GetHotspots(questID)
  local giver = q.s and q.s.n
  if giver then return string.format(L["LEARN_DESCRIBE_GIVER"], n, giver) end
  return string.format(L["LEARN_DESCRIBE"], n)
end

function Learn:Count()
  local n = 0
  for _ in pairs(db()) do n = n + 1 end
  return n
end

----------------------------------------------------------------------------
-- Export / import
----------------------------------------------------------------------------
function Learn:Export(scope)
  local quests = db()
  if scope ~= "all" then
    local mapID = C.GetPlayerMapID()
    if not mapID then return nil, L["WAY_NO_POSITION"] end
    quests = Learn.FilterZone(quests, mapID)
  end
  local n = 0
  for _ in pairs(quests) do n = n + 1 end
  local str, err = Learn.Encode(quests)
  return str, err, n
end

-- Returns a prepared import (validated) and a summary; nothing is merged
-- until Commit is called after the player confirms.
function Learn:PrepareImport(str)
  local quests, err = Learn.Decode(str)
  if not quests then return nil, err end
  local clean, n = Learn.Validate(quests, ns:GetSetting("learn", "maxHotspots"))
  local new = 0
  for id in pairs(clean) do if not db()[id] then new = new + 1 end end
  return { quests = clean, total = n, new = new }
end

function Learn:CommitImport(prepared)
  local total, new = Learn.MergeInto(db(), prepared.quests, ns:GetSetting("learn", "mergeYards") or 40,
    ns:GetSetting("learn", "maxHotspots") or 12, ns.Geo.Distance)
  ns:Fire("QK_LEARN_UPDATED")
  return total, new
end

----------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------
function Learn:OnEnable()
  ns:On("QUEST_DETAIL", "Learn", function(_, startItemID)
    captureNPC(startItemID and startItemID ~= 0 and "item" or nil)
  end)
  ns:On("QUEST_PROGRESS", "Learn", function() captureNPC() end)
  ns:On("QUEST_COMPLETE", "Learn", function() captureNPC() end)
  ns:On("QUEST_GREETING", "Learn", function() captureNPC() end)
  ns:On("GOSSIP_SHOW", "Learn", function() captureNPC() end)
  ns:On("QUEST_ACCEPTED", "Learn", function(_, questID) Learn:RecordAccept(questID) end)
  ns:On("QK_QUEST_TURNED_IN", "Learn", function(_, questID) Learn:RecordTurnIn(questID) end)
  ns:On("QK_OBJECTIVE_PROGRESS", "Learn", function(_, questID, idx) Learn:RecordProgress(questID, idx) end)
  ns:On("QK_QUEST_ADDED", "Learn", function(_, questID)
    local q = db()[questID]
    local snap = ns.QuestData:Get(questID)
    if q and snap then
      q.t = q.t or snap.title
      if not q.l or q.l == 0 then q.l = snap.level end
    end
  end)
end
