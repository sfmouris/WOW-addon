-- QuestKompas: auto accept and turn in at NPCs (spec 4.7).
local _, ns = ...

local AQ = ns:RegisterModule("AutoQuest")
local C, L = ns.Compat, ns.L

local GUARD_SECONDS = 3
local GOSSIP_CHAT_ICON = 132053 -- Interface\GossipFrame\GossipGossipIcon. TODO(verify) fileID on Forever

local attempts = {}      -- "action:questID" -> time
local suppressed = false -- skip modifier was held for this interaction
local offered = {}       -- questID -> { level, repeatable } seen in gossip / greeting

----------------------------------------------------------------------------
-- Decision helpers (pure where possible, tests/spec_autoquest.lua)
----------------------------------------------------------------------------
function AQ.Guard(action, questID, now)
  local key = action .. ":" .. tostring(questID)
  local last = attempts[key]
  if last and now - last < GUARD_SECONDS then return false end
  attempts[key] = now
  return true
end

function AQ.ResetGuards()
  for k in pairs(attempts) do attempts[k] = nil end
end

-- Should an offered quest be accepted automatically?
-- info: { questID, questLevel, repeatable, frequency }. Returns ok, reason.
function AQ.ShouldAccept(info, ctx)
  if not ctx.accept then return false, "off" end
  if info.questID and ctx.blacklist[info.questID] then return false, "blacklist" end
  if info.isIgnored then return false, "ignored" end
  local repeatable = info.repeatable or (info.frequency and info.frequency > 0)
  if repeatable and not ctx.repeatable then return false, "repeatable" end
  if info.questLevel and info.questLevel > 0 and info.questLevel > ctx.playerLevel + ctx.maxLevelAbove then
    return false, "level"
  end
  if ctx.logFull then return false, "full" end
  return true
end

local function context()
  local _, numQuests = C.GetNumQuestLogEntries()
  return {
    accept = ns:GetSetting("auto", "accept"),
    turnin = ns:GetSetting("auto", "turnin"),
    repeatable = ns:GetSetting("auto", "repeatable"),
    maxLevelAbove = ns:GetSetting("auto", "maxLevelAbove") or 4,
    blacklist = ns.db.blacklist,
    playerLevel = C.UnitLevel("player") or 1,
    logFull = numQuests >= C.GetMaxQuests(),
  }
end

local function announce(fmt, level, title)
  if not ns:GetSetting("auto", "announce") then return end
  if level and level > 0 then
    ns:Print(string.format(fmt, string.format("[%d] %s", level, title or "?")))
  else
    ns:Print(string.format(fmt, title or "?"))
  end
end

local function checkSkip()
  if C.IsModifierDown(ns:GetSetting("auto", "skipModifier") or "SHIFT") then suppressed = true end
  return suppressed
end

local function active()
  if C.InCombat() then return false end
  if checkSkip() then return false end
  return true
end

-- Remembers level and repeatability of offered quests for QUEST_DETAIL.
local function remember(q)
  if q.questID then
    offered[q.questID] = { level = q.questLevel, repeatable = q.repeatable or (q.frequency or 0) > 0 }
  end
end

local fullWarned = 0
local function warnFull()
  local now = C.GetTime()
  if now - fullWarned > 5 then
    fullWarned = now
    C.ShowCenterMessage(L["LOG_FULL"])
  end
end

----------------------------------------------------------------------------
-- Gossip and greeting: one action per event; the NPC window refreshes after
-- each selection and the next event handles the rest.
----------------------------------------------------------------------------
function AQ:HandleGossip()
  if not active() then return end
  local ctx = context()
  if ctx.turnin then
    for _, q in ipairs(C.GossipActiveQuests()) do
      if q.isComplete and q.questID and AQ.Guard("select-active", q.questID, C.GetTime()) then
        C.GossipSelectActive(q.questID)
        return
      end
    end
  end
  local available = C.GossipAvailableQuests()
  for _, q in ipairs(available) do
    remember(q)
    local ok, reason = AQ.ShouldAccept(q, ctx)
    if ok and AQ.Guard("select-available", q.questID, C.GetTime()) then
      C.GossipSelectAvailable(q.questID)
      return
    elseif reason == "full" then
      warnFull()
    end
  end
  if ns:GetSetting("auto", "gossip") and #available == 0 and #C.GossipActiveQuests() == 0 then
    local options = C.GossipOptions()
    if #options == 1 then
      local o = options[1]
      if o.gossipOptionID and o.icon == GOSSIP_CHAT_ICON and AQ.Guard("gossip", o.gossipOptionID, C.GetTime()) then
        C.GossipSelectOption(o.gossipOptionID)
      end
    end
  end
end

function AQ:HandleGreeting()
  if not active() then return end
  local ctx = context()
  if ctx.turnin then
    for _, q in ipairs(C.GreetingActive()) do
      if q.isComplete and AQ.Guard("select-active", q.questID or ("g" .. q.index), C.GetTime()) then
        C.GreetingSelectActive(q.index)
        return
      end
    end
  end
  for _, q in ipairs(C.GreetingAvailable()) do
    remember(q)
    local ok, reason = AQ.ShouldAccept(q, ctx)
    if ok and AQ.Guard("select-available", q.questID or ("g" .. q.index), C.GetTime()) then
      C.GreetingSelectAvailable(q.index)
      return
    elseif reason == "full" then
      warnFull()
    end
  end
end

----------------------------------------------------------------------------
-- Quest frame panels
----------------------------------------------------------------------------
function AQ:HandleDetail(startItemID)
  if not active() then return end
  if startItemID and startItemID ~= 0 then return end -- Blizzard shows a popup and closes the frame
  local questID = C.GetOfferedQuestID()
  if not questID then return end
  if C.QuestIsPvP() then return end
  -- Timed quests ask for confirmation: the player clicks Accept.
  -- TODO(verify): GetTimeAllowed may only return data once the quest is in the log.
  if C.GetTimeAllowed(questID) then return end
  local ctx = context()
  local seen = offered[questID] or {}
  local level = seen.level or C.GetQuestDifficultyLevel(questID)
  local ok, reason = AQ.ShouldAccept({ questID = questID, questLevel = level, repeatable = seen.repeatable }, ctx)
  if not ok then
    if reason == "full" then warnFull() end
    return
  end
  if not AQ.Guard("accept", questID, C.GetTime()) then return end
  local title = C.GetOfferedTitle()
  if C.AcceptOfferedQuest() then announce(L["AUTO_ACCEPTED"], level, title) end
end

-- True when turning in costs something the player should decide on.
function AQ.TurnInNeedsPlayer(money, currencies, requiredItems, isQuestItem)
  if (money or 0) > 0 then return true end
  if (currencies or 0) > 0 then return true end
  for _, item in ipairs(requiredItems) do
    if not item.itemID or not isQuestItem(item.itemID) then return true end
  end
  return false
end

local function isQuestItem(itemID)
  local classID = select(6, C.GetItemInfoInstant(itemID))
  local questClass = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12
  return classID == questClass
end

function AQ:HandleProgress()
  if not active() or not ns:GetSetting("auto", "turnin") then return end
  if not C.IsQuestCompletable() then return end
  local questID = C.GetOfferedQuestID()
  if AQ.TurnInNeedsPlayer(C.GetQuestMoneyToGet(), C.GetNumRequiredCurrencies(), C.GetRequiredItems(), isQuestItem) then
    return
  end
  if not AQ.Guard("complete", questID, C.GetTime()) then return end
  C.CompleteQuest()
end

function AQ:HandleComplete()
  if not active() or not ns:GetSetting("auto", "turnin") then return end
  local questID = C.GetOfferedQuestID()
  if C.GetQuestMoneyToGet() > 0 then return end
  local choices = C.GetNumQuestChoices()
  if choices > 1 then
    ns:Fire("QK_REWARD_CHOICE", questID, choices)
    return
  end
  if not AQ.Guard("reward", questID, C.GetTime()) then return end
  local q = questID and ns.QuestData:Get(questID)
  C.GetQuestReward(choices == 1 and 1 or 0)
  announce(L["AUTO_TURNED_IN"], q and q.level, q and q.title or C.GetOfferedTitle())
end

----------------------------------------------------------------------------
-- Duplicate automation warning (spec 1.4)
----------------------------------------------------------------------------
local OVERLAP = { "Leatrix_Plus", "ForeverPlus" } -- TODO(verify) exact folder names

function AQ:CheckOverlap()
  for _, name in ipairs(OVERLAP) do
    if C.IsAddOnLoaded(name) and not ns.db.warned[name] then
      ns.db.warned[name] = true
      ns:Print(string.format(L["OVERLAP_WARNING"], name))
    end
  end
end

function AQ:Toggle()
  local on = not (ns:GetSetting("auto", "accept") or ns:GetSetting("auto", "turnin"))
  ns:SetSetting("auto", "accept", on)
  ns:SetSetting("auto", "turnin", on)
  return on
end

----------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------
local function endInteraction()
  C_Timer.After(0.5, function()
    local gossip = GossipFrame and GossipFrame:IsShown()
    local quest = QuestFrame and QuestFrame:IsShown()
    if not gossip and not quest then
      suppressed = false
      wipe(offered)
    end
  end)
end

function AQ:OnEnable()
  ns:On("GOSSIP_SHOW", "AutoQuest", function() AQ:HandleGossip() end)
  ns:On("QUEST_GREETING", "AutoQuest", function() AQ:HandleGreeting() end)
  ns:On("QUEST_DETAIL", "AutoQuest", function(_, startItemID) AQ:HandleDetail(startItemID) end)
  ns:On("QUEST_PROGRESS", "AutoQuest", function() AQ:HandleProgress() end)
  ns:On("QUEST_COMPLETE", "AutoQuest", function() AQ:HandleComplete() end)
  ns:On("GOSSIP_CLOSED", "AutoQuest", function(_, continuing)
    if not continuing then endInteraction() end
  end)
  ns:On("QUEST_FINISHED", "AutoQuest", endInteraction)
  self:CheckOverlap()
end

-- Test hook.
function AQ._SetSuppressed(v) suppressed = v end
