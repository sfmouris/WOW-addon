-- QuestKompas: buttons for usable quest items (spec 4.10).
-- Buttons are SecureActionButtonTemplate; everything that touches them runs
-- out of combat only.
local _, ns = ...

local IB = ns:RegisterModule("ItemBar")
local C, L = ns.Compat, ns.L

local SIZE, GAP = 32, 4
-- Button 1 needs a global name for CLICK bindings (Bindings.xml and
-- SetOverrideBindingClick). Documented exception to spec 13.6.
local BUTTON1_NAME = "QuestKompasItemButton1"

local bar
local buttons = {}
local currentKey = ""

local function savePosition()
  local point, _, relPoint, x, y = bar:GetPoint(1)
  ns.cdb.positions.itembar = { point, x, y, relPoint }
end

local function applyPosition()
  bar:ClearAllPoints()
  local pos = ns.cdb.positions.itembar
  if pos then
    bar:SetPoint(pos[1], UIParent, pos[4] or pos[1], pos[2], pos[3])
  else
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
  end
end

local function createBar()
  bar = CreateFrame("Frame", nil, UIParent)
  bar:SetSize(SIZE, SIZE + 12)
  bar:SetClampedToScreen(true)
  bar:SetMovable(true)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function(self)
    if not C.InCombat() and not ns:GetSetting("tracker", "locked") then self:StartMoving() end
  end)
  bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
  end)
  local handle = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  handle:SetPoint("TOPLEFT", 0, 0)
  handle:SetText(L["ITEMBAR"])
  applyPosition()
  bar:Hide()
end

local function createButton(i)
  local b = CreateFrame("Button", i == 1 and BUTTON1_NAME or nil, bar, "SecureActionButtonTemplate")
  b:SetSize(SIZE, SIZE)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "item")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", -2, 2)
  b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cooldown:SetAllPoints()
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 1, 1, 0.2)
  b:SetScript("OnEnter", function(self)
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.link)
    if self.questTitle then GameTooltip:AddLine(self.questTitle, 1, 0.82, 0) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  buttons[i] = b
  return b
end

-- Usable items of active quests, nearest quest first, at most max.
function IB.Collect(list, distFn, max)
  local items = {}
  for _, q in ipairs(list) do
    if q.hasUsableItem and q.itemLink then
      items[#items + 1] = { q = q, d = distFn and distFn(q) or nil }
    end
  end
  table.sort(items, function(a, b)
    if a.d and b.d then return a.d < b.d end
    if a.d then return true end
    if b.d then return false end
    return a.q.logIndex < b.q.logIndex
  end)
  local out = {}
  for i = 1, math.min(#items, max) do out[i] = items[i].q end
  return out
end

local function itemString(link)
  local id = link and link:match("item:(%d+)")
  return id and ("item:" .. id) or link
end

function IB:Update()
  if C.InCombat() then self.dirty = true return end
  if not bar then createBar() end
  self.dirty = false
  local max = math.min(ns:GetSetting("itembar", "max") or 6, 12)
  local navOn = ns:IsModuleEnabled("Navigator")
  local quests = IB.Collect(ns.QuestData:GetList(),
    navOn and function(q) return ns.Navigator:GetQuestDistance(q) end or nil, max)
  local keyParts = {}
  for i, q in ipairs(quests) do keyParts[i] = q.questID .. "=" .. tostring(q.itemLink) end
  local key = table.concat(keyParts, ";")
  if key ~= currentKey then
    currentKey = key
    for i, q in ipairs(quests) do
      local b = buttons[i] or createButton(i)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", bar, "TOPLEFT", (i - 1) * (SIZE + GAP), -12)
      b:SetAttribute("item", itemString(q.itemLink))
      b.link, b.questTitle, b.logIndex = q.itemLink, q.title, q.logIndex
      b.icon:SetTexture(q.itemTexture or select(5, C.GetItemInfoInstant(q.itemLink)))
      b:Show()
    end
    for i = #quests + 1, #buttons do
      buttons[i]:Hide()
      buttons[i]:SetAttribute("item", nil)
      buttons[i].link = nil
    end
    bar:SetWidth(math.max(SIZE, #quests * (SIZE + GAP) - GAP))
    bar:SetShown(#quests > 0)
  end
  self:UpdateCounts()
  self:ApplyKey()
end

-- Counts and cooldowns are plain (non-secure) regions: safe in combat.
function IB:UpdateCounts()
  for _, b in ipairs(buttons) do
    if b:IsShown() and b.link then
      local n = C.GetItemCount(b.link)
      b.count:SetText(n > 1 and n or "")
      local start, duration, enable = C.GetQuestSpecialItemCooldown(b.logIndex)
      if start and duration and duration > 0 and enable ~= 0 then
        b.cooldown:SetCooldown(start, duration)
      else
        b.cooldown:Clear()
      end
    end
  end
end

local boundKey
function IB:ApplyKey()
  if C.InCombat() or not bar then return end
  local key = ns:GetSetting("itembar", "key")
  if key == boundKey then return end
  ClearOverrideBindings(bar)
  if key and key ~= "" then SetOverrideBindingClick(bar, true, key, BUTTON1_NAME, "LeftButton") end
  boundKey = key
end

function IB:ResetPosition()
  ns.cdb.positions.itembar = nil
  if bar then ns:RunOutOfCombat(applyPosition, "ItemBar.pos") end
end

function IB:OnEnable()
  local function req() ns:Debounce("ItemBar.update", 0.3, function() IB:Update() end) end
  ns:On("QK_QUESTS_UPDATED", "ItemBar", req)
  ns:On("ZONE_CHANGED_NEW_AREA", "ItemBar", req)
  ns:On("BAG_UPDATE_DELAYED", "ItemBar", function() IB:UpdateCounts() end)
  ns:On("BAG_UPDATE_COOLDOWN", "ItemBar", function() IB:UpdateCounts() end)
  ns:On("QK_SETTING_CHANGED", "ItemBar", function(_, section)
    if section == "itembar" or section == nil then currentKey = "" req() end
  end)
  req()
end

function IB:OnDisable()
  ns:RunOutOfCombat(function()
    if bar then
      ClearOverrideBindings(bar)
      boundKey = nil
      bar:Hide()
    end
    currentKey = ""
  end, "ItemBar.disable")
end

function IB:OnCombatEnd()
  if self.dirty then self:Update() end
end
