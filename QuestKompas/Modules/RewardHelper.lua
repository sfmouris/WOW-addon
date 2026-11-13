-- QuestKompas: help choosing a quest reward, without choosing (spec 4.8).
local _, ns = ...

local RH = ns:RegisterModule("RewardHelper")
local C, U, L = ns.Compat, ns.Util, ns.L

RH.SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
  INVTYPE_THROWN = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_RELIC = { 18 },
}

----------------------------------------------------------------------------
-- Pure evaluation (tests/spec_reward.lua).
-- choice: { index, price, ilvl, usable, current = { ilvl or false per slot } }
-- An empty slot (false) counts as ilvl 0. With several slots (rings,
-- trinkets, one-hand weapons) we compare against the weakest one.
----------------------------------------------------------------------------
function RH.Evaluate(choices)
  local bestIndex, bestPrice = nil, 0
  local upgrades = {}
  for _, c in ipairs(choices) do
    if (c.price or 0) > bestPrice then bestIndex, bestPrice = c.index, c.price end
    if c.usable and c.ilvl and c.current and #c.current > 0 then
      local weakest = math.huge
      for _, cur in ipairs(c.current) do
        local v = cur or 0
        if v < weakest then weakest = v end
      end
      if c.ilvl > weakest then upgrades[c.index] = weakest end
    end
  end
  return bestIndex, upgrades
end

----------------------------------------------------------------------------
-- Overlays on Blizzard's reward buttons. We never modify their frames: our
-- own frames are parented to UIParent and only anchored to them.
----------------------------------------------------------------------------
local overlays = {}
local info = {}       -- index -> { price, currentText }

local function getOverlay(i)
  local o = overlays[i]
  if o then return o end
  o = CreateFrame("Frame", nil, UIParent)
  o:SetSize(16, 16)
  o:SetFrameStrata("DIALOG")
  o.coin = o:CreateTexture(nil, "OVERLAY")
  o.coin:SetSize(14, 14)
  o.coin:SetPoint("TOPLEFT")
  o.coin:SetTexture("Interface\\AddOns\\" .. ns.name .. "\\UI\\Media\\coin")
  o.up = o:CreateTexture(nil, "OVERLAY")
  o.up:SetSize(14, 14)
  o.up:SetPoint("LEFT", o.coin, "RIGHT", 1, 0)
  o.up:SetTexture("Interface\\AddOns\\" .. ns.name .. "\\UI\\Media\\arrow")
  o.up:SetVertexColor(0.2, 1, 0.2)
  overlays[i] = o
  return o
end

local function hideOverlays()
  for _, o in pairs(overlays) do o:Hide() end
  wipe(info)
end

local function findButton(index)
  local frame = QuestInfoRewardsFrame
  local buttons = frame and frame.RewardButtons
  if not buttons then return nil end
  for _, b in ipairs(buttons) do
    if b.type == "choice" and b.GetID and b:GetID() == index and b:IsShown() then return b end
  end
  return nil
end

local function currentFor(equipLoc)
  local slots = RH.SLOTS[equipLoc]
  if not slots then return nil, nil end
  local current, names = {}, {}
  for i, slot in ipairs(slots) do
    local link = C.GetInventoryItemLink(slot)
    if link then
      current[i] = C.GetItemLevel(link) or 0
      names[#names + 1] = string.format("%s (ilvl %d)", C.GetItemName(link) or "?", current[i])
    else
      current[i] = false
    end
  end
  return current, names
end

function RH:Show(numChoices)
  hideOverlays()
  local choices, pending = {}, numChoices
  local pawn = C.IsAddOnLoaded("Pawn")
  local function finish()
    local best, upgrades = RH.Evaluate(choices)
    for _, c in ipairs(choices) do
      local button = findButton(c.index)
      if button then
        local o = getOverlay(c.index)
        o:ClearAllPoints()
        o:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        o.coin:SetShown(c.index == best)
        o.up:SetShown(not pawn and upgrades[c.index] ~= nil)
        o:Show()
      end
    end
    self.best, self.upgrades = best, upgrades
    if ns:GetSetting("auto", "autoReward") and best and next(upgrades) == nil
        and not C.InCombat() and ns.AutoQuest.Guard("reward-pick", C.GetOfferedQuestID(), C.GetTime()) then
      C.GetQuestReward(best)
    end
  end
  for i = 1, numChoices do
    local link = C.GetQuestItemLink("choice", i)
    C.OnItemLoaded(link, function()
      local usable = select(5, C.GetQuestItemInfo("choice", i))
      local equipLoc = link and select(4, C.GetItemInfoInstant(link))
      local current, names = currentFor(equipLoc)
      local c = { index = i, price = link and C.GetItemSellPrice(link) or 0,
                  ilvl = link and C.GetItemLevel(link), usable = usable, current = current }
      choices[#choices + 1] = c
      info[i] = { price = c.price, current = names and table.concat(names, ", ") or nil }
      pending = pending - 1
      if pending == 0 then finish() end
    end)
  end
end

-- Extra tooltip lines on reward items (sell price, currently equipped).
local function onTooltip(tooltip, kind, index)
  if kind ~= "choice" or not RH.enabled then return end
  local data = info[index]
  if not data then return end
  tooltip:AddLine(L["SELL_PRICE"] .. ": " .. U.FormatMoney(data.price), 1, 1, 1)
  if data.current then tooltip:AddLine(L["CURRENT"] .. ": " .. data.current, 0.8, 0.8, 0.8, true) end
  tooltip:Show()
end

local hooked = false
function RH:OnEnable()
  ns:On("QUEST_COMPLETE", "RewardHelper", function()
    local n = C.GetNumQuestChoices()
    if n > 1 then RH:Show(n) end
  end)
  ns:On("QUEST_FINISHED", "RewardHelper", hideOverlays)
  if not hooked and GameTooltip and GameTooltip.SetQuestItem and hooksecurefunc then
    hooksecurefunc(GameTooltip, "SetQuestItem", onTooltip)
    hooked = true
  end
end

function RH:OnDisable()
  hideOverlays()
end
