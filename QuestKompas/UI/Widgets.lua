-- QuestKompas: reusable dialogs and windows. Own frames instead of
-- StaticPopup so we never touch Blizzard's popup tables.
local _, ns = ...

local UI = {}
ns.UI = UI
local L, U = ns.L, ns.Util

local function baseWindow(title, width, height)
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(width, height)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  U.SkinFrame(f, 0.9)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 10, -8)
  f.title:SetPoint("TOPRIGHT", -30, -8)
  f.title:SetJustifyH("LEFT")
  f.title:SetText(title or "")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  f:Hide()
  return f
end
UI.BaseWindow = baseWindow

local function button(parent, text, width)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 90, 22)
  b:SetText(text)
  return b
end

----------------------------------------------------------------------------
-- Confirm(text, onAccept)
----------------------------------------------------------------------------
local confirm
function UI:Confirm(text, onAccept)
  if not confirm then
    confirm = baseWindow("QuestKompas", 340, 120)
    confirm.text = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    confirm.text:SetPoint("TOPLEFT", 12, -30)
    confirm.text:SetPoint("TOPRIGHT", -12, -30)
    confirm.text:SetJustifyH("LEFT")
    confirm.yes = button(confirm, L["YES"])
    confirm.yes:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -4, 10)
    confirm.no = button(confirm, L["NO"])
    confirm.no:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 4, 10)
    confirm.no:SetScript("OnClick", function() confirm:Hide() end)
  end
  confirm.text:SetText(text)
  confirm:SetHeight(math.max(110, confirm.text:GetStringHeight() + 74))
  confirm.yes:SetScript("OnClick", function()
    confirm:Hide()
    ns.SafeCall(onAccept)
  end)
  confirm:Show()
  confirm:Raise()
end

----------------------------------------------------------------------------
-- Input(text, default, maxLen, onAccept)
----------------------------------------------------------------------------
local input
function UI:Input(text, default, maxLen, onAccept)
  if not input then
    input = baseWindow("QuestKompas", 360, 130)
    input.text = input:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    input.text:SetPoint("TOPLEFT", 12, -30)
    input.text:SetPoint("TOPRIGHT", -12, -30)
    input.text:SetJustifyH("LEFT")
    input.box = CreateFrame("EditBox", nil, input, "InputBoxTemplate")
    input.box:SetHeight(20)
    input.box:SetPoint("BOTTOMLEFT", 18, 42)
    input.box:SetPoint("BOTTOMRIGHT", -14, 42)
    input.box:SetAutoFocus(true)
    input.box:SetScript("OnEscapePressed", function() input:Hide() end)
    input.ok = button(input, L["OK"])
    input.ok:SetPoint("BOTTOMRIGHT", input, "BOTTOM", -4, 10)
    input.cancel = button(input, L["CANCEL"])
    input.cancel:SetPoint("BOTTOMLEFT", input, "BOTTOM", 4, 10)
    input.cancel:SetScript("OnClick", function() input:Hide() end)
  end
  input.text:SetText(text)
  input.box:SetMaxLetters(maxLen or 300)
  input.box:SetText(default or "")
  local function accept()
    local value = input.box:GetText()
    input:Hide()
    ns.SafeCall(onAccept, value)
  end
  input.ok:SetScript("OnClick", accept)
  input.box:SetScript("OnEnterPressed", accept)
  input:Show()
  input:Raise()
  input.box:SetFocus()
end

----------------------------------------------------------------------------
-- Multi-line text window, optionally editable (export / import / stats).
----------------------------------------------------------------------------
function UI:CreateTextWindow(title, width, height, editable)
  local f = baseWindow(title, width or 480, height or 320)
  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -30)
  scroll:SetPoint("BOTTOMRIGHT", -30, editable and 40 or 10)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject(GameFontHighlightSmall)
  box:SetWidth((width or 480) - 50)
  box:SetScript("OnEscapePressed", function() f:Hide() end)
  if not editable then
    -- Read-only: restore the text when the player types.
    box:SetScript("OnTextChanged", function(self, userInput)
      if userInput and f.text then self:SetText(f.text) self:HighlightText() end
    end)
  end
  scroll:SetScrollChild(box)
  f.box = box
  if editable then
    f.ok = button(f, L["IMPORT"])
    f.ok:SetPoint("BOTTOMRIGHT", -10, 10)
  end
  function f:SetLines(lines)
    self:SetText(table.concat(lines, "\n"))
  end
  function f:SetText(text)
    self.text = text
    self.box:SetText(text or "")
    self.box:SetCursorPosition(0)
  end
  function f:SelectAll()
    self.box:SetFocus()
    self.box:HighlightText()
  end
  return f
end

----------------------------------------------------------------------------
-- List window with a button per row and an optional footer button.
----------------------------------------------------------------------------
function UI:CreateListWindow(title)
  local f = baseWindow(title, 380, 120)
  f.rows = {}
  function f:SetRows(items, fill)
    for _, r in ipairs(self.rows) do r:Hide() end
    for i, item in ipairs(items) do
      local row = self.rows[i]
      if not row then
        row = CreateFrame("Frame", nil, self)
        row:SetHeight(24)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetPoint("RIGHT", -96, 0)
        row.text:SetJustifyH("LEFT")
        row.button = button(row, "", 88)
        row.button:SetPoint("RIGHT", -2, 0)
        self.rows[i] = row
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 24)
      row:SetPoint("TOPRIGHT", -10, -28 - (i - 1) * 24)
      fill(row, item)
      row:Show()
    end
    self:SetHeight(28 + #items * 24 + 40)
  end
  function f:SetFooterButton(text, onClick)
    if not self.footer then
      self.footer = button(self, text, 200)
      self.footer:SetPoint("BOTTOM", 0, 10)
    end
    self.footer:SetText(text)
    self.footer:SetScript("OnClick", onClick)
  end
  return f
end
