-- QuestKompas: questing together (spec 4.14). Off by default.
local _, ns = ...

local PT = ns:RegisterModule("Party")
local C, L = ns.Compat, ns.L

local PREFIX = "QKOMPAS"
local SEND_INTERVAL, MAX_LEN = 2, 200

PT.progress = {} -- sender -> { [questID] = { {done, need}, ... }, t }

----------------------------------------------------------------------------
-- Wire format (pure, tests/spec_party.lua)
-- "P1|questID:d/n,d/n;questID:d/n"   Only digits, ':', '/', ',', ';', '|'.
----------------------------------------------------------------------------
function PT.Encode(quests, maxLen)
  maxLen = maxLen or MAX_LEN
  local out = "P1|"
  for _, q in ipairs(quests) do
    local objs = {}
    for i, o in ipairs(q.objectives) do objs[i] = string.format("%d/%d", o.done, o.need) end
    local part = q.questID .. ":" .. table.concat(objs, ",")
    local candidate = (out == "P1|") and (out .. part) or (out .. ";" .. part)
    if #candidate > maxLen then break end
    out = candidate
  end
  return out
end

function PT.Decode(msg)
  if type(msg) ~= "string" or #msg > MAX_LEN or msg:sub(1, 3) ~= "P1|" then return nil end
  local body = msg:sub(4)
  if body:find("[^%d:/,;]") then return nil end
  local out = {}
  local n = 0
  for part in body:gmatch("[^;]+") do
    local id, objs = part:match("^(%d+):([%d/,]*)$")
    id = tonumber(id)
    if not id or id > 1e7 then return nil end
    local list = {}
    for d, need in objs:gmatch("(%d+)/(%d+)") do
      d, need = tonumber(d), tonumber(need)
      if d > 10000 or need > 10000 or #list >= 20 then return nil end
      list[#list + 1] = { d, need }
    end
    out[id] = list
    n = n + 1
    if n > 25 then return nil end
  end
  return out
end

----------------------------------------------------------------------------
-- Sharing and group finder
----------------------------------------------------------------------------
function PT:ShareAll()
  if not C.IsInGroup() then ns:Print(L["PARTY_NOT_IN_GROUP"]) return end
  local ids = {}
  for _, q in ipairs(ns.QuestData:GetList()) do
    if C.IsPushableQuest(q.questID) then ids[#ids + 1] = q.questID end
  end
  local i = 0
  local function step()
    i = i + 1
    if not ids[i] then ns:Print(string.format(L["PARTY_SHARED_FMT"], #ids)) return end
    C.ShareQuest(ids[i])
    C_Timer.After(0.5, step)
  end
  ns:RunOutOfCombat(step)
end

----------------------------------------------------------------------------
-- Progress sync (out of combat, outside instances, max 1 msg / 2 s)
----------------------------------------------------------------------------
local lastSend = 0
function PT:Broadcast()
  if not C.IsInGroup() or C.InCombat() or C.IsInInstance() then return end
  local now = C.GetTime()
  if now - lastSend < SEND_INTERVAL then
    ns:Debounce("Party.send", SEND_INTERVAL, function() PT:Broadcast() end)
    return
  end
  lastSend = now
  C.SendAddonMessage(PREFIX, PT.Encode(ns.QuestData:GetList()), "PARTY")
end

function PT:DescribeProgress(questID)
  local out = {}
  for sender, data in pairs(self.progress) do
    local objs = data.quests[questID]
    if objs then
      local parts = {}
      for i, o in ipairs(objs) do parts[i] = o[1] .. "/" .. o[2] end
      out[#out + 1] = string.format("%s: %s", sender, #parts > 0 and table.concat(parts, ", ") or L["DONE"])
    end
  end
  return out
end

function PT:OnEnable()
  C.RegisterAddonPrefix(PREFIX)
  ns:On("CHAT_MSG_ADDON", "Party", function(_, prefix, text, channel, sender)
    if prefix ~= PREFIX or channel ~= "PARTY" then return end
    if not ns.IsSafe(sender) or not ns.IsSafe(text) then return end
    local me = UnitName and UnitName("player")
    if type(sender) ~= "string" or #sender > 64 then return end
    local short = sender:match("^([^%-]+)") or sender
    if short == me then return end
    local data = PT.Decode(text)
    if data then PT.progress[short] = { quests = data, t = C.GetTime() } end
  end)
  ns:On("QK_OBJECTIVE_PROGRESS", "Party", function() PT:Broadcast() end)
  ns:On("QK_QUEST_ADDED", "Party", function() PT:Broadcast() end)
  ns:On("GROUP_ROSTER_UPDATE", "Party", function()
    if not C.IsInGroup() then wipe(PT.progress) else PT:Broadcast() end
  end)
end

function PT:OnDisable()
  wipe(self.progress)
end
