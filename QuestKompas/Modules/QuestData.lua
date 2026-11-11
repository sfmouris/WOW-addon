-- QuestKompas: one normalised view of the quest log (spec 4.2).
-- No other module calls the quest log API directly.
local _, ns = ...

local QD = ns:RegisterModule("QuestData", { alwaysOn = true })
local C, U = ns.Compat, ns.Util

QD.list = {}      -- quests in log order
QD.byID = {}      -- questID -> quest
QD.ready = false  -- first snapshot done
QD.pendingLoad = {}

----------------------------------------------------------------------------
-- Snapshot building
----------------------------------------------------------------------------
local TAG = { [1] = "Group", [41] = "PvP", [62] = "Raid", [81] = "Dungeon", [83] = "Legendary", [85] = "Heroic" }

local function tagName(questID)
  local info = C.GetQuestTagInfo(questID)
  if not info then return nil, false end
  local elite = info.isElite and true or false
  local name = TAG[info.tagID]
  if name == "Group" and elite then name = "Elite" end
  if not name and elite then name = "Elite" end
  return name, elite
end

local function buildObjectives(questID)
  local out = {}
  local list = C.GetQuestObjectives(questID)
  for i, o in ipairs(list) do
    out[i] = {
      text = o.text or "", type = o.type, done = o.numFulfilled or 0,
      need = o.numRequired or 0, finished = o.finished and true or false,
    }
  end
  return out
end

-- Builds a fresh snapshot from the client. Returns list, byID, missing
-- (questIDs whose data is not cached yet).
function QD.BuildSnapshot()
  local list, byID, missing = {}, {}, {}
  local playerLevel = C.UnitEffectiveLevel()
  local trivial = C.UnitQuestTrivialLevelRange()
  local numEntries = C.GetNumQuestLogEntries()
  local header
  for i = 1, numEntries do
    local info = C.GetQuestInfo(i)
    if info then
      if info.isHeader then
        header = info.title
      elseif not info.isHidden and info.questID and info.questID > 0 then
        local id = info.questID
        local title = info.title
        if not title or title == "" then
          missing[#missing + 1] = id
          title = C.GetQuestTitle(id)
        end
        local level = info.level or 0
        if level <= 0 then level = info.difficultyLevel or playerLevel end
        local tag, elite = tagName(id)
        local link, texture = C.GetQuestSpecialItem(i)
        local q = {
          questID = id, logIndex = i, title = title or ("Quest " .. id),
          titleMissing = (title == nil), level = level,
          difficulty = U.Difficulty(level, playerLevel, trivial),
          isComplete = C.IsQuestComplete(id), isFailed = C.IsQuestFailed(id),
          zoneHeader = header, suggestedGroup = info.suggestedGroup or 0,
          tagName = tag, isElite = elite, isTask = info.isTask,
          frequency = info.frequency, isRepeatable = (info.frequency or 0) > 0 or C.IsRepeatableQuest(id),
          objectives = buildObjectives(id),
          xpReward = C.GetQuestRewardXP(id), moneyReward = C.GetQuestRewardMoney(id),
          hasUsableItem = link ~= nil, itemLink = link, itemTexture = texture,
          isWatched = C.IsQuestWatched(id), hasTimer = C.GetTimeAllowed(id) ~= nil,
        }
        if q.suggestedGroup == 0 then q.suggestedGroup = C.GetSuggestedGroupSize(id) end
        local d = C.GetDistanceSqToQuest(id)
        if d then q.distanceSq = d end
        local mapID = C.GetNextWaypoint(id)
        if mapID then q.mapID = mapID end
        list[#list + 1] = q
        byID[id] = q
      end
    end
  end
  return list, byID, missing
end

----------------------------------------------------------------------------
-- Diff: compares two snapshots (byID maps) and returns a list of events
-- { name, args... } in a stable order. Pure, see tests/spec_questdata.lua.
----------------------------------------------------------------------------
function QD.Diff(old, new, newList)
  local events = {}
  for _, q in ipairs(newList) do
    local o = old[q.questID]
    if not o then
      events[#events + 1] = { "QK_QUEST_ADDED", q.questID }
    else
      for idx, obj in ipairs(q.objectives) do
        local prev = o.objectives[idx]
        if prev and obj.done ~= prev.done and obj.done > prev.done then
          events[#events + 1] = { "QK_OBJECTIVE_PROGRESS", q.questID, idx, prev.done, obj.done }
        end
      end
      if q.isComplete and not o.isComplete then
        events[#events + 1] = { "QK_QUEST_COMPLETED", q.questID }
      end
      if q.isFailed and not o.isFailed then
        events[#events + 1] = { "QK_QUEST_FAILED", q.questID }
      end
    end
  end
  local removed = {}
  for id in pairs(old) do
    if not new[id] then removed[#removed + 1] = id end
  end
  table.sort(removed)
  for _, id in ipairs(removed) do events[#events + 1] = { "QK_QUEST_REMOVED", id } end
  return events
end

----------------------------------------------------------------------------
-- Colours per quest, assigned in order of acceptance (8.1)
----------------------------------------------------------------------------
function QD:AssignColors(list)
  local colors = ns.cdb and ns.cdb.colors
  if not colors then return end
  local present = {}
  for _, q in ipairs(list) do present[q.questID] = true end
  for id in pairs(colors) do
    if not present[id] then colors[id] = nil end
  end
  for _, q in ipairs(list) do
    if not colors[q.questID] then colors[q.questID] = U.PickColor(colors) end
    q.colorIndex = colors[q.questID]
    q.color = U.PALETTE[q.colorIndex]
  end
end

----------------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------------
function QD:Refresh()
  local start = debugprofilestop and debugprofilestop()
  local list, byID, missing = QD.BuildSnapshot()
  self:AssignColors(list)
  for _, id in ipairs(missing) do
    if not self.pendingLoad[id] then
      self.pendingLoad[id] = true
      C.RequestLoadQuest(id)
    end
  end
  local old = self.byID
  local first = not self.ready
  self.list, self.byID, self.ready = list, byID, true
  if start then ns.Debug:Trace(string.format("snapshot %d quests in %.2f ms", #list, debugprofilestop() - start)) end
  if not first then
    for _, ev in ipairs(QD.Diff(old, byID, list)) do
      ns:Fire(unpack(ev))
    end
  end
  ns:Fire("QK_QUESTS_UPDATED", first)
end

function QD:RequestRefresh(delay)
  ns:Debounce("QuestData.refresh", delay or 0.3, function() QD:Refresh() end)
end

-- Distances change while walking; refresh them without a full snapshot.
function QD:RefreshDistances()
  for _, q in ipairs(self.list) do
    q.distanceSq = C.GetDistanceSqToQuest(q.questID)
  end
end

function QD:Get(questID)
  return self.byID[questID]
end

function QD:GetList()
  return self.list
end

function QD:Count()
  return #self.list
end

-- Progress fraction 0..1 over all objectives.
function QD.Progress(q)
  if q.isComplete then return 1 end
  local done, need = 0, 0
  for _, o in ipairs(q.objectives) do
    local n = math.max(o.need, 1)
    need = need + n
    done = done + math.min(o.finished and n or o.done, n)
  end
  if need == 0 then return 0 end
  return done / need
end

----------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------
function QD:OnEnable()
  ns:On("QUEST_LOG_UPDATE", "QuestData", function() QD:RequestRefresh(0.3) end)
  ns:On("QUEST_ACCEPTED", "QuestData", function() QD:RequestRefresh(0.1) end)
  ns:On("QUEST_REMOVED", "QuestData", function() QD:RequestRefresh(0.1) end)
  ns:On("PLAYER_ENTERING_WORLD", "QuestData", function() QD:RequestRefresh(0.5) end)
  ns:On("PLAYER_LEVEL_UP", "QuestData", function() QD:RequestRefresh(0.5) end)
  ns:On("QUEST_WATCH_LIST_CHANGED", "QuestData", function() QD:RequestRefresh(0.2) end)
  ns:On("QUEST_DATA_LOAD_RESULT", "QuestData", function(_, questID)
    if QD.pendingLoad[questID] then
      QD.pendingLoad[questID] = nil
      QD:RequestRefresh(0.3)
    end
  end)
  ns:On("QUEST_TURNED_IN", "QuestData", function(_, questID, xp, money)
    ns:Fire("QK_QUEST_TURNED_IN", questID, xp or 0, money or 0)
    QD:RequestRefresh(0.2)
  end)
  QD:RequestRefresh(0.5)
end

----------------------------------------------------------------------------
-- /qk dump
----------------------------------------------------------------------------
function QD:DumpLines()
  local out = { string.format("Snapshot: %d quests", #self.list) }
  for _, q in ipairs(self.list) do
    out[#out + 1] = string.format("[%d] %s (id %d) %s%s zone=%s group=%d tag=%s xp=%d money=%d dist=%s map=%s",
      q.level, q.title, q.questID, q.difficulty, q.isComplete and " KLAAR" or "",
      tostring(q.zoneHeader), q.suggestedGroup, tostring(q.tagName), q.xpReward or 0, q.moneyReward or 0,
      q.distanceSq and string.format("%.0f", math.sqrt(q.distanceSq)) or "?", tostring(q.mapID))
    for i, o in ipairs(q.objectives) do
      out[#out + 1] = string.format("    %d. %s [%s] %d/%d%s", i, o.text, tostring(o.type), o.done, o.need,
        o.finished and " ok" or "")
    end
  end
  return out
end
