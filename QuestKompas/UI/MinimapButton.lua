-- QuestKompas: small button at the minimap (spec 4.15). Own frame, no
-- library: click toggles the tracker, right-click opens the settings, drag
-- moves it around the minimap edge.
local _, ns = ...

local MB = {}
ns.MinimapButton = MB
local L, Style = ns.L, ns.Style
local COL = Style.color

local DEFAULT_ANGLE = 215
local SIZE = 28
local button

-- Offset from the minimap centre for an angle in degrees (0 = east,
-- counter-clockwise) on a round minimap.
function MB.Offset(angle, radius)
  local a = math.rad(angle or DEFAULT_ANGLE)
  return math.cos(a) * radius, math.sin(a) * radius
end

-- Angle in degrees (0 to 360) from the minimap centre to the cursor.
function MB.AngleTo(centerX, centerY, cursorX, cursorY)
  local dx, dy = cursorX - centerX, cursorY - centerY
  if dx == 0 and dy == 0 then return DEFAULT_ANGLE end
  local a = math.deg(math.atan2(dy, dx))
  if a < 0 then a = a + 360 end
  return a
end

local function place()
  local angle = ns.cdb.positions.minimap
  if type(angle) ~= "number" then angle = DEFAULT_ANGLE end
  local x, y = MB.Offset(angle, (Minimap:GetWidth() or 140) / 2 + 6)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function dragUpdate()
  local cx, cy = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  if not (cx and px and scale and scale > 0) then return end
  ns.cdb.positions.minimap = MB.AngleTo(cx, cy, px / scale, py / scale)
  place()
end

local function tooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("QuestKompas", 1, 1, 1)
  if ns.QuestData and ns.Tracker then
    local count = ns.Tracker.CountText(ns.QuestData:Count(), ns.Compat.GetMaxQuests())
    GameTooltip:AddLine(string.format(L["MINIMAP_QUESTS_FMT"], count), 1, 0.82, 0)
  end
  GameTooltip:AddLine(L["MINIMAP_HINT"], COL.dim[1], COL.dim[2], COL.dim[3], true)
  GameTooltip:Show()
end

local function create()
  button = CreateFrame("Button", nil, Minimap)
  button:SetSize(SIZE, SIZE)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  local disc = button:CreateTexture(nil, "BACKGROUND")
  disc:SetAllPoints()
  disc:SetTexture(Style.MEDIA .. "dot")
  disc:SetVertexColor(COL.panel[1], COL.panel[2], COL.panel[3], 0.9)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(SIZE - 8, SIZE - 8)
  icon:SetPoint("CENTER")
  icon:SetTexture(Style.MEDIA .. "icon")
  local glow = button:CreateTexture(nil, "HIGHLIGHT")
  glow:SetAllPoints()
  glow:SetTexture(Style.MEDIA .. "ring")
  glow:SetVertexColor(COL.accent[1], COL.accent[2], COL.accent[3], 0.9)

  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then
      ns.Options:Open()
    elseif ns:IsModuleEnabled("Tracker") then
      ns.Tracker:Toggle()
    else
      ns:Print(string.format(L["MODULE_OFF"], L["MOD_TRACKER"]))
    end
  end)
  button:SetScript("OnDragStart", function(self)
    if ns:GetSetting("tracker", "locked") then return end
    GameTooltip:Hide()
    self:SetScript("OnUpdate", dragUpdate)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", tooltip)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place()
end

function MB:Apply()
  ns:RunOutOfCombat(function()
    local show = ns:GetSetting("general", "minimap") ~= false
    if show and not button then
      if not Minimap then return end
      create()
    end
    if button then button:SetShown(show) end
  end, "MinimapButton.apply")
end

function MB:ResetPosition()
  ns.cdb.positions.minimap = nil
  if button then ns:RunOutOfCombat(place, "MinimapButton.pos") end
end

function MB:GetButton()
  return button
end

ns:On("QK_READY", "MinimapButton", function() MB:Apply() end)
ns:On("QK_SETTING_CHANGED", "MinimapButton", function(_, section, key)
  if section == nil or (section == "general" and key == "minimap") then MB:Apply() end
end)
