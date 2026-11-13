-- QuestKompas: keep the quest log tidy (spec 4.11).
local _, ns = ...

local LT = ns:RegisterModule("LogTools")
local C, L = ns.Compat, ns.L

local NOTE_MAX = 300

----------------------------------------------------------------------------
-- Pure helpers (tests/spec_logtools.lua)
----------------------------------------------------------------------------
function LT.GreyQuests(list)
  local out = {}
  for _, q in ipairs(list) do
    if q.difficulty == "grey" and not q.isComplete then out[#out + 1] = q end
  end
  return out
end

-- Best candidates to abandon: grey first, then farthest, then lowest XP.
function LT.AbandonCandidates(list, distFn, n)
  local scored = {}
  for _, q in ipairs(list) do
    if not q.isComplete then
      scored[#scored + 1] = { q = q, grey = q.difficulty == "grey" and 1 or 0,
                              d = distFn and distFn(q) or 0, xp = q.xpReward or 0 }
    end
  end
  table.sort(scored, function(a, b)
    if a.grey ~= b.grey then return a.grey > b.grey end
    if a.d ~= b.d then return a.d > b.d end
    if a.xp ~= b.xp then return a.xp < b.xp end
    return a.q.questID < b.q.questID
  end)
  local out = {}
  for i = 1, math.min(n, #scored) do out[i] = scored[i].q end
  return out
end

function LT.Search(text, list, learned)
  text = text:lower()
  local hits = {}
  for _, q in ipairs(list) do
    local hit = q.title:lower():find(text, 1, true)
    if not hit then
      for _, o in ipairs(q.objectives) do
        if o.text:lower():find(text, 1, true) then hit = true break end
      end
    end
    if hit then hits[#hits + 1] = { questID = q.questID, title = q.title, level = q.level, active = true } end
  end
  for id, q in pairs(learned or {}) do
    if q.t and q.t:lower():find(text, 1, true) then
      local dup = false
      for _, h in ipairs(hits) do if h.questID == id then dup = true break end end
      if not dup then hits[#hits + 1] = { questID = id, title = q.t, level = q.l, learned = q } end
    end
  end
  table.sort(hits, function(a, b)
    if (a.active and 1 or 0) ~= (b.active and 1 or 0) then return a.active == true end
    return (a.title or "") < (b.title or "")
  end)
  return hits
end

----------------------------------------------------------------------------
-- Abandon (single, with confirmation)
----------------------------------------------------------------------------
function LT:ConfirmAbandon(questID)
  local q = ns.QuestData:Get(questID)
  if not q then return end
  ns.UI:Confirm(string.format(L["CONFIRM_ABANDON"], q.title), function()
    ns:RunOutOfCombat(function() C.AbandonQuest(questID) end)
  end)
end

----------------------------------------------------------------------------
-- Grey quest window (/qk grey). Bulk abandon needs two confirmations and
-- only touches quests that were shown in the list.
----------------------------------------------------------------------------
local greyFrame

local function abandonList(ids)
  local i = 0
  local function step()
    i = i + 1
    local id = ids[i]
    if not id then
      ns:Print(string.format(L["GREY_DONE_FMT"], i - 1))
      return
    end
    local q = ns.QuestData:Get(id)
    -- Still in the log and still grey: otherwise skip it.
    if q and q.difficulty == "grey" then C.AbandonQuest(id) end
    C_Timer.After(0.3, step)
  end
  ns:RunOutOfCombat(step)
end

function LT:ShowGrey()
  local grey = LT.GreyQuests(ns.QuestData:GetList())
  if #grey == 0 then ns:Print(L["GREY_NONE"]) return end
  local shownIDs = {}
  for i, q in ipairs(grey) do shownIDs[i] = q.questID end
  greyFrame = greyFrame or ns.UI:CreateListWindow(L["GREY_TITLE"])
  greyFrame:SetRows(grey, function(row, q)
    row.text:SetText(string.format("[%d] %s", q.level, q.title))
    row.button:SetText(L["ABANDON"])
    row.button:SetScript("OnClick", function()
      LT:ConfirmAbandon(q.questID)
      greyFrame:Hide()
    end)
  end)
  greyFrame:SetFooterButton(string.format(L["GREY_ALL_FMT"], #shownIDs), function()
    ns.UI:Confirm(string.format(L["GREY_CONFIRM1_FMT"], #shownIDs), function()
      ns.UI:Confirm(string.format(L["GREY_CONFIRM2_FMT"], #shownIDs), function()
        greyFrame:Hide()
        abandonList(shownIDs)
      end)
    end)
  end)
  greyFrame:Show()
end

----------------------------------------------------------------------------
-- Full log hint (once per session when two slots are left)
----------------------------------------------------------------------------
local hinted = false
function LT:CheckFull()
  if hinted then return end
  local n, max = ns.QuestData:Count(), C.GetMaxQuests()
  if n < max - 2 then return end
  hinted = true
  local navOn = ns:IsModuleEnabled("Navigator")
  local cands = LT.AbandonCandidates(ns.QuestData:GetList(),
    navOn and function(q) return ns.Navigator:GetQuestDistance(q) or 0 end or nil, 3)
  local names = {}
  for i, q in ipairs(cands) do names[i] = string.format("[%d] %s", q.level, q.title) end
  ns:Print(string.format(L["LOG_ALMOST_FULL_FMT"], n, max, table.concat(names, ", ")))
end

----------------------------------------------------------------------------
-- Notes
----------------------------------------------------------------------------
function LT:EditNote(questID)
  local q = ns.QuestData:Get(questID)
  local title = q and q.title or tostring(questID)
  ns.UI:Input(string.format(L["NOTE_PROMPT"], title), ns.db.notes[questID] or "", NOTE_MAX, function(text)
    text = ns.Util.Trim(text or "")
    if text == "" then ns.db.notes[questID] = nil else ns.db.notes[questID] = text:sub(1, NOTE_MAX) end
  end)
end

----------------------------------------------------------------------------
-- /qk find
----------------------------------------------------------------------------
function LT:Find(text)
  text = ns.Util.Trim(text or "")
  if text == "" then ns:Print(L["FIND_USAGE"]) return end
  local learned = ns:IsModuleEnabled("Learn") and ns.db.learned.quests or nil
  local hits = LT.Search(text, ns.QuestData:GetList(), learned)
  if #hits == 0 then ns:Print(string.format(L["FIND_NONE"], text)) return end
  ns:Print(string.format(L["FIND_RESULTS"], #hits, text))
  for i = 1, math.min(15, #hits) do
    local h = hits[i]
    local where = ""
    if h.learned and h.learned.s then
      where = string.format(" (%s %.1f, %.1f)", C.GetMapName(h.learned.s.m) or "?", h.learned.s.x * 100,
        h.learned.s.y * 100)
    end
    ns:Print(string.format("  %s[%s] %s%s", h.active and "* " or "", tostring(h.level or "?"), h.title or "?", where))
  end
end

function LT:OnEnable()
  ns:On("QK_QUEST_ADDED", "LogTools", function() LT:CheckFull() end)
  ns:On("QK_QUESTS_UPDATED", "LogTools", function(_, first) if first then LT:CheckFull() end end)
end
