-- QuestKompas: every client API call that can be missing or behave
-- differently goes through here (spec 13.3). Modules never call C_QuestLog,
-- C_Map, C_GossipInfo etc. directly.
--
-- Verified against the exported interface code of WoW Forever 1.60.1 (70888),
-- Gethe/wow-ui-source branch "forever", Blizzard_APIDocumentationGenerated.
-- Items still marked TODO(verify) exist in the export but their runtime
-- behaviour on Forever (for example: does it return data for vanilla quests)
-- can only be checked in game.
local _, ns = ...

local C = {}
ns.Compat = C

local function has(tbl, key)
  return type(tbl) == "table" and type(tbl[key]) == "function"
end
C.has = has

local function global(name)
  local fn = _G[name]
  if type(fn) == "function" then return fn end
  return nil
end

----------------------------------------------------------------------------
-- Secret values (spec 2.3)
----------------------------------------------------------------------------
local issecret = global("issecretvalue")

function ns.IsSafe(v)
  if v == nil then return false end
  if issecret and issecret(v) then return false end
  return true
end

----------------------------------------------------------------------------
-- Generic
----------------------------------------------------------------------------
function C.GetTime()
  return GetTime and GetTime() or 0
end

function C.InCombat()
  return InCombatLockdown and InCombatLockdown() or false
end

function C.GetClientInterface()
  if not GetBuildInfo then return nil end
  return (select(4, GetBuildInfo()))
end

function C.GetClientBuild()
  if not GetBuildInfo then return nil end
  local version, build = GetBuildInfo()
  return version, build
end

function C.IsAddOnLoaded(name)
  if has(C_AddOns, "IsAddOnLoaded") then
    local loaded = C_AddOns.IsAddOnLoaded(name)
    return loaded and true or false
  end
  return false
end

function C.IsInInstance()
  if not IsInInstance then return false end
  local inInstance, instanceType = IsInInstance()
  return inInstance and true or false, instanceType
end

function C.IsInGroup()
  return IsInGroup and IsInGroup() or false
end

function C.GetNumGroupMembers()
  return GetNumGroupMembers and GetNumGroupMembers() or 0
end

function C.IsModifierDown(which)
  if which == "SHIFT" then return IsShiftKeyDown and IsShiftKeyDown() or false end
  if which == "CTRL" then return IsControlKeyDown and IsControlKeyDown() or false end
  if which == "ALT" then return IsAltKeyDown and IsAltKeyDown() or false end
  return false
end

function C.PlaySound(kitName)
  if not PlaySound or type(SOUNDKIT) ~= "table" then return end
  local id = SOUNDKIT[kitName]
  if id then PlaySound(id, "SFX") end
end

function C.ShowCenterMessage(text)
  local f = UIErrorsFrame
  if f and f.AddMessage then
    f:AddMessage(text, 1.0, 0.82, 0.0, 1.0)
  else
    ns:Print(text)
  end
end

----------------------------------------------------------------------------
-- Player
----------------------------------------------------------------------------
function C.UnitLevel(unit)
  local lvl = UnitLevel and UnitLevel(unit or "player")
  if ns.IsSafe(lvl) then return lvl end
  return nil
end

function C.UnitEffectiveLevel()
  local fn = global("UnitEffectiveLevel")
  local lvl = fn and fn("player")
  if ns.IsSafe(lvl) and lvl > 0 then return lvl end
  return C.UnitLevel("player") or 1
end

function C.UnitQuestTrivialLevelRange()
  local fn = global("UnitQuestTrivialLevelRange")
  local v = fn and fn("player")
  if ns.IsSafe(v) then return v end
  return 5 -- TODO(verify): fallback guess when the API is missing
end

function C.UnitXP()
  local xp = UnitXP and UnitXP("player") or 0
  local max = UnitXPMax and UnitXPMax("player") or 0
  return xp, max
end

function C.GetXPExhaustion()
  return GetXPExhaustion and GetXPExhaustion() or nil
end

function C.GetMaxPlayerLevel()
  local fn = global("GetMaxPlayerLevel")
  return fn and fn() or 60
end

function C.GetMoney()
  return GetMoney and GetMoney() or 0
end

function C.UnitFaction()
  if not UnitFactionGroup then return nil end
  local f = UnitFactionGroup("player")
  if f == "Alliance" then return "A" end
  if f == "Horde" then return "H" end
  return nil
end

function C.UnitClassRace()
  local class = UnitClass and select(2, UnitClass("player"))
  local race = UnitRace and select(2, UnitRace("player"))
  return class, race
end

-- GUID and name of an NPC-like unit token. Returns nil for secret values.
function C.UnitGUIDAndName(unit)
  if not UnitGUID then return nil end
  local guid = UnitGUID(unit)
  if not ns.IsSafe(guid) then return nil end
  local name = UnitName and UnitName(unit)
  if not ns.IsSafe(name) then name = nil end
  return guid, name
end

-- Abbreviated key text for a binding action, or nil when unbound. Both are
-- plain globals; FrameXML calls GetBindingText(GetBindingKey(action), true).
function C.GetBindingKeyText(action)
  local getKey, getText = global("GetBindingKey"), global("GetBindingText")
  local key = getKey and getKey(action)
  if not key or key == "" then return nil end
  return getText and getText(key, true) or key
end

function C.GetPlayerFacing()
  local fn = global("GetPlayerFacing")
  if not fn then return nil end
  local facing = fn()
  if ns.IsSafe(facing) then return facing end
  return nil
end

----------------------------------------------------------------------------
-- Quest log
----------------------------------------------------------------------------
function C.GetNumQuestLogEntries()
  if has(C_QuestLog, "GetNumQuestLogEntries") then
    local entries, quests = C_QuestLog.GetNumQuestLogEntries()
    return entries or 0, quests or 0
  end
  return 0, 0
end

function C.GetMaxQuests()
  if has(C_QuestLog, "GetMaxNumQuestsCanAccept") then
    local n = C_QuestLog.GetMaxNumQuestsCanAccept()
    if n and n > 0 then return n end
  end
  if has(C_QuestLog, "GetMaxNumQuests") then
    local n = C_QuestLog.GetMaxNumQuests()
    if n and n > 0 then return n end
  end
  return 25
end

function C.GetQuestInfo(logIndex)
  if has(C_QuestLog, "GetInfo") then return C_QuestLog.GetInfo(logIndex) end
  return nil
end

function C.GetQuestObjectives(questID)
  if has(C_QuestLog, "GetQuestObjectives") then
    return C_QuestLog.GetQuestObjectives(questID) or {}
  end
  return {}
end

function C.IsQuestComplete(questID)
  if has(C_QuestLog, "ReadyForTurnIn") and C_QuestLog.ReadyForTurnIn(questID) then return true end
  if has(C_QuestLog, "IsComplete") and C_QuestLog.IsComplete(questID) then return true end
  return false
end

function C.IsQuestFailed(questID)
  return has(C_QuestLog, "IsFailed") and C_QuestLog.IsFailed(questID) and true or false
end

function C.GetQuestTagInfo(questID)
  if has(C_QuestLog, "GetQuestTagInfo") then return C_QuestLog.GetQuestTagInfo(questID) end
  return nil
end

function C.GetSuggestedGroupSize(questID)
  if has(C_QuestLog, "GetSuggestedGroupSize") then
    return C_QuestLog.GetSuggestedGroupSize(questID) or 0
  end
  return 0
end

function C.GetQuestDifficultyLevel(questID)
  if has(C_QuestLog, "GetQuestDifficultyLevel") then
    local lvl = C_QuestLog.GetQuestDifficultyLevel(questID)
    if lvl and lvl > 0 then return lvl end
  end
  return nil
end

-- distanceSq in yards squared, nil when unknown or not on this continent.
function C.GetDistanceSqToQuest(questID)
  if has(C_QuestLog, "GetDistanceSqToQuest") then
    local d, onContinent = C_QuestLog.GetDistanceSqToQuest(questID)
    if d and onContinent and d > 0 then return d end
  end
  return nil
end

function C.GetLogIndexForQuestID(questID)
  if has(C_QuestLog, "GetLogIndexForQuestID") then return C_QuestLog.GetLogIndexForQuestID(questID) end
  return nil
end

function C.GetQuestIDForLogIndex(logIndex)
  if has(C_QuestLog, "GetQuestIDForLogIndex") then return C_QuestLog.GetQuestIDForLogIndex(logIndex) end
  return nil
end

-- Returns link, texture(item), charges, showItemWhenComplete.
function C.GetQuestSpecialItem(logIndex)
  local fn = global("GetQuestLogSpecialItemInfo")
  if not fn or not logIndex then return nil end
  return fn(logIndex)
end

function C.GetQuestSpecialItemCooldown(logIndex)
  local fn = global("GetQuestLogSpecialItemCooldown")
  if not fn or not logIndex then return nil end
  return fn(logIndex)
end

function C.GetQuestRewardXP(questID)
  local fn = global("GetQuestLogRewardXP")
  return fn and fn(questID) or 0
end

function C.GetQuestRewardMoney(questID)
  local fn = global("GetQuestLogRewardMoney")
  return fn and fn(questID) or 0
end

function C.IsQuestFlaggedCompleted(questID)
  return has(C_QuestLog, "IsQuestFlaggedCompleted") and C_QuestLog.IsQuestFlaggedCompleted(questID) and true or false
end

function C.IsOnQuest(questID)
  return has(C_QuestLog, "IsOnQuest") and C_QuestLog.IsOnQuest(questID) and true or false
end

function C.RequestLoadQuest(questID)
  if has(C_QuestLog, "RequestLoadQuestByID") then C_QuestLog.RequestLoadQuestByID(questID) end
end

function C.GetQuestTitle(questID)
  if has(C_QuestLog, "GetTitleForQuestID") then
    local t = C_QuestLog.GetTitleForQuestID(questID)
    if t and t ~= "" then return t end
  end
  return nil
end

function C.IsRepeatableQuest(questID)
  return has(C_QuestLog, "IsRepeatableQuest") and C_QuestLog.IsRepeatableQuest(questID) and true or false
end

function C.GetTimeAllowed(questID)
  if has(C_QuestLog, "GetTimeAllowed") then
    local total, elapsed = C_QuestLog.GetTimeAllowed(questID)
    if total and total > 0 then return total, elapsed end
  end
  return nil
end

function C.IsQuestWatched(questID)
  if has(C_QuestLog, "GetQuestWatchType") then
    return C_QuestLog.GetQuestWatchType(questID) ~= nil
  end
  return false
end

function C.RemoveQuestWatch(questID)
  if has(C_QuestLog, "RemoveQuestWatch") then C_QuestLog.RemoveQuestWatch(questID) end
end

function C.AddQuestWatch(questID)
  if has(C_QuestLog, "AddQuestWatch") then C_QuestLog.AddQuestWatch(questID) end
end

function C.IsPushableQuest(questID)
  return has(C_QuestLog, "IsPushableQuest") and C_QuestLog.IsPushableQuest(questID) and true or false
end

-- Same call order as Blizzard's QuestMapQuestOptions_ShareQuest.
function C.ShareQuest(questID)
  local fn = global("QuestLogPushQuest")
  local logIndex = C.GetLogIndexForQuestID(questID)
  if fn and logIndex then fn(logIndex) return true end
  return false
end

-- Same sequence as QuestMapQuestOptions_AbandonQuest, minus Blizzard's
-- popup: we confirm ourselves before calling this.
function C.AbandonQuest(questID)
  if not (has(C_QuestLog, "SetSelectedQuest") and has(C_QuestLog, "SetAbandonQuest")
      and has(C_QuestLog, "AbandonQuest")) then
    return false
  end
  local old = has(C_QuestLog, "GetSelectedQuest") and C_QuestLog.GetSelectedQuest() or nil
  C_QuestLog.SetSelectedQuest(questID)
  C_QuestLog.SetAbandonQuest()
  C_QuestLog.AbandonQuest()
  if old and old ~= questID then C_QuestLog.SetSelectedQuest(old) end
  return true
end

function C.GetQuestLink(questID)
  local fn = global("GetQuestLink")
  return fn and fn(questID) or nil
end

-- Description and objective text for the tooltip.
-- TODO(verify): Mainline GetQuestLogQuestText takes a log index; the Vanilla
-- UI calls it without arguments after selecting the quest.
function C.GetQuestDescription(questID)
  local fn = global("GetQuestLogQuestText")
  local logIndex = C.GetLogIndexForQuestID(questID)
  if not fn or not logIndex then return nil end
  local ok, desc = pcall(fn, logIndex)
  if ok and type(desc) == "string" and desc ~= "" then return desc end
  return nil
end

function C.OpenQuestDetails(questID)
  local fn = global("QuestMapFrame_OpenToQuestDetails")
  if fn then fn(questID) return true end
  return false
end

----------------------------------------------------------------------------
-- Quest locations from the client (Navigator source layers 1 and 2)
----------------------------------------------------------------------------
-- TODO(verify): exists on 1.60.1, but may be empty for most vanilla quests.
function C.GetNextWaypoint(questID)
  if has(C_QuestLog, "GetNextWaypoint") then
    local mapID, x, y = C_QuestLog.GetNextWaypoint(questID)
    if mapID and x and y and (x > 0 or y > 0) then return mapID, x, y end
  end
  return nil
end

-- Quest POIs for one map from both C_QuestLog and C_TaskQuest (Forever was
-- reported to use the latter). Both return QuestPOIMapInfo tables.
-- TODO(verify): which of the two yields data on Forever.
function C.GetQuestPOIsOnMap(mapID)
  local out = {}
  if has(C_QuestLog, "GetQuestsOnMap") then
    local list = C_QuestLog.GetQuestsOnMap(mapID)
    if type(list) == "table" then
      for _, info in ipairs(list) do out[#out + 1] = info end
    end
  end
  if has(C_TaskQuest, "GetQuestsOnMap") then
    local list = C_TaskQuest.GetQuestsOnMap(mapID)
    if type(list) == "table" then
      for _, info in ipairs(list) do out[#out + 1] = info end
    end
  end
  return out
end

----------------------------------------------------------------------------
-- Map and position
----------------------------------------------------------------------------
local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
C.HBD = HBD

-- Player position as uiMapID, x, y (0..1). nil in instances, on taxis without
-- a map position, or while loading.
function C.GetPlayerPosition()
  if HBD then
    local x, y, mapID = HBD:GetPlayerZonePosition()
    if x and y and mapID then return mapID, x, y end
  end
  if has(C_Map, "GetBestMapForUnit") and has(C_Map, "GetPlayerMapPosition") then
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
      local pos = C_Map.GetPlayerMapPosition(mapID, "player")
      if pos and pos.GetXY then
        local x, y = pos:GetXY()
        if x and y and (x > 0 or y > 0) then return mapID, x, y end
      end
    end
  end
  return nil
end

function C.GetPlayerMapID()
  if HBD then
    local mapID = HBD:GetPlayerZone()
    if mapID then return mapID end
  end
  if has(C_Map, "GetBestMapForUnit") then return C_Map.GetBestMapForUnit("player") end
  return nil
end

function C.GetMapInfo(mapID)
  if mapID and has(C_Map, "GetMapInfo") then return C_Map.GetMapInfo(mapID) end
  return nil
end

function C.GetMapName(mapID)
  local info = C.GetMapInfo(mapID)
  return info and info.name or nil
end

-- World position (instance, north, west) for a map coordinate.
function C.GetWorldPos(mapID, x, y)
  if not (has(C_Map, "GetWorldPosFromMapPos") and CreateVector2D) then return nil end
  local instance, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
  if instance and pos then
    local wx, wy = pos:GetXY()
    return instance, wx, wy
  end
  return nil
end

function C.GetAllMapIDs()
  if HBD then return HBD:GetAllMapIDs() end
  return {}
end

----------------------------------------------------------------------------
-- Native navigation (Navigator mode "native")
----------------------------------------------------------------------------
function C.SetUserWaypoint(mapID, x, y)
  if not (has(C_Map, "SetUserWaypoint") and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
  if has(C_Map, "CanSetUserWaypointOnMap") and not C_Map.CanSetUserWaypointOnMap(mapID) then return false end
  C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
  if has(C_SuperTrack, "SetSuperTrackedUserWaypoint") then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  return true
end

function C.ClearUserWaypoint()
  if has(C_Map, "ClearUserWaypoint") then C_Map.ClearUserWaypoint() end
end

function C.SuperTrackQuest(questID)
  if has(C_SuperTrack, "SetSuperTrackedQuestID") then
    C_SuperTrack.SetSuperTrackedQuestID(questID)
    return true
  end
  return false
end

function C.ClearSuperTrack()
  if has(C_SuperTrack, "ClearAllSuperTracked") then C_SuperTrack.ClearAllSuperTracked() end
end

----------------------------------------------------------------------------
-- NPC interaction (AutoQuest)
----------------------------------------------------------------------------
function C.GossipAvailableQuests()
  if has(C_GossipInfo, "GetAvailableQuests") then return C_GossipInfo.GetAvailableQuests() or {} end
  return {}
end

function C.GossipActiveQuests()
  if has(C_GossipInfo, "GetActiveQuests") then return C_GossipInfo.GetActiveQuests() or {} end
  return {}
end

function C.GossipSelectAvailable(questID)
  if has(C_GossipInfo, "SelectAvailableQuest") then C_GossipInfo.SelectAvailableQuest(questID) end
end

function C.GossipSelectActive(questID)
  if has(C_GossipInfo, "SelectActiveQuest") then C_GossipInfo.SelectActiveQuest(questID) end
end

function C.GossipOptions()
  if has(C_GossipInfo, "GetOptions") then return C_GossipInfo.GetOptions() or {} end
  return {}
end

function C.GossipSelectOption(optionID)
  if has(C_GossipInfo, "SelectOption") then C_GossipInfo.SelectOption(optionID) end
end

-- Quest greeting panel (NPCs with only quests, no gossip).
function C.GreetingActive()
  local out = {}
  local num = global("GetNumActiveQuests")
  local title, idfn = global("GetActiveTitle"), global("GetActiveQuestID")
  if not (num and title) then return out end
  for i = 1, num() do
    local t, isComplete = title(i)
    out[#out + 1] = { index = i, title = t, isComplete = isComplete, questID = idfn and idfn(i) or nil }
  end
  return out
end

function C.GreetingAvailable()
  local out = {}
  local num = global("GetNumAvailableQuests")
  local info, title = global("GetAvailableQuestInfo"), global("GetAvailableTitle")
  local level = global("GetAvailableLevel")
  if not num then return out end
  for i = 1, num() do
    local isTrivial, frequency, isRepeatable, _, questID
    if info then isTrivial, frequency, isRepeatable, _, questID = info(i) end
    out[#out + 1] = {
      index = i, title = title and title(i) or nil, isTrivial = isTrivial,
      frequency = frequency, repeatable = isRepeatable, questID = questID,
      questLevel = level and level(i) or nil, -- TODO(verify): GetAvailableLevel not in export
    }
  end
  return out
end

function C.GreetingSelectActive(index)
  local fn = global("SelectActiveQuest")
  if fn then fn(index) end
end

function C.GreetingSelectAvailable(index)
  local fn = global("SelectAvailableQuest")
  if fn then fn(index) end
end

function C.GetOfferedQuestID()
  local fn = global("GetQuestID")
  local id = fn and fn()
  if id and id > 0 then return id end
  return nil
end

function C.GetOfferedTitle()
  local fn = global("GetTitleText")
  return fn and fn() or nil
end

function C.QuestIsAutoAccept()
  local fn = global("QuestGetAutoAccept")
  return fn and fn() and true or false
end

function C.QuestIsPvP()
  local fn = global("QuestFlagsPVP")
  return fn and fn() and true or false
end

function C.AcceptOfferedQuest()
  if C.QuestIsAutoAccept() then
    local ack = global("AcknowledgeAutoAcceptQuest")
    if ack then ack() return true end
  end
  local fn = global("AcceptQuest")
  if fn then fn() return true end
  return false
end

function C.IsQuestCompletable()
  local fn = global("IsQuestCompletable")
  return fn and fn() and true or false
end

function C.CompleteQuest()
  local fn = global("CompleteQuest")
  if fn then fn() end
end

function C.GetQuestMoneyToGet()
  local fn = global("GetQuestMoneyToGet")
  return fn and fn() or 0
end

function C.GetNumQuestChoices()
  local fn = global("GetNumQuestChoices")
  return fn and fn() or 0
end

function C.GetNumRequiredCurrencies()
  local fn = global("GetNumQuestCurrencies")
  return fn and fn() or 0
end

-- Required items for the progress panel: list of { itemID, name, count }.
function C.GetRequiredItems()
  local out = {}
  local num, info = global("GetNumQuestItems"), global("GetQuestItemInfo")
  if not (num and info) then return out end
  for i = 1, num() do
    local name, _, count, _, _, itemID = info("required", i)
    out[#out + 1] = { itemID = itemID, name = name, count = count }
  end
  return out
end

-- Returns name, texture, count, quality, isUsable, itemID.
function C.GetQuestItemInfo(kind, index)
  local fn = global("GetQuestItemInfo")
  if not fn then return nil end
  return fn(kind, index)
end

function C.GetQuestItemLink(kind, index)
  local fn = global("GetQuestItemLink")
  return fn and fn(kind, index) or nil
end

function C.GetQuestReward(choice)
  local fn = global("GetQuestReward")
  if fn then fn(choice) end
end

----------------------------------------------------------------------------
-- Items
----------------------------------------------------------------------------
-- Returns itemID, itemType, itemSubType, equipLoc, icon, classID, subclassID.
function C.GetItemInfoInstant(item)
  if has(C_Item, "GetItemInfoInstant") then return C_Item.GetItemInfoInstant(item) end
  return nil
end

function C.GetItemSellPrice(item)
  if has(C_Item, "GetItemInfo") then
    local price = select(11, C_Item.GetItemInfo(item))
    return price
  end
  return nil
end

function C.GetItemName(item)
  if has(C_Item, "GetItemInfo") then return (C_Item.GetItemInfo(item)) end
  return nil
end

function C.GetItemLevel(item)
  if has(C_Item, "GetDetailedItemLevelInfo") then
    local lvl = C_Item.GetDetailedItemLevelInfo(item)
    return lvl
  end
  return nil
end

function C.GetItemCount(item)
  if has(C_Item, "GetItemCount") then return C_Item.GetItemCount(item) or 0 end
  return 0
end

function C.IsEquippableItem(item)
  return has(C_Item, "IsEquippableItem") and C_Item.IsEquippableItem(item) and true or false
end

function C.GetInventoryItemLink(slot)
  return GetInventoryItemLink and GetInventoryItemLink("player", slot) or nil
end

-- Calls fn when the item behind link is cached.
function C.OnItemLoaded(link, fn)
  if Item and Item.CreateFromItemLink and link then
    local item = Item:CreateFromItemLink(link)
    if item and item.ContinueOnItemLoad and not item:IsItemEmpty() then
      item:ContinueOnItemLoad(fn)
      return
    end
  end
  fn()
end

----------------------------------------------------------------------------
-- Chat
----------------------------------------------------------------------------
function C.InsertChatLink(link)
  if not link then return false end
  if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
  local fn = global("ChatEdit_InsertLink")
  return fn and fn(link) or false
end

-- Puts text in the chat input. The player presses Enter (spec 2.5).
function C.OpenChatWithText(text)
  if ChatFrameUtil and ChatFrameUtil.OpenChat then ChatFrameUtil.OpenChat(text) return end
  local fn = global("ChatFrame_OpenChat")
  if fn then fn(text) end
end

function C.RegisterAddonPrefix(prefix)
  if has(C_ChatInfo, "RegisterAddonMessagePrefix") then return C_ChatInfo.RegisterAddonMessagePrefix(prefix) end
  return false
end

function C.SendAddonMessage(prefix, msg, channel)
  if has(C_ChatInfo, "SendAddonMessage") then return C_ChatInfo.SendAddonMessage(prefix, msg, channel) end
  return false
end

----------------------------------------------------------------------------
-- Settings panel
----------------------------------------------------------------------------
function C.OpenSettings(category)
  if category and Settings and Settings.OpenToCategory and category.GetID then
    Settings.OpenToCategory(category:GetID())
    return true
  end
  return false
end
