-- QuestKompas: debug log window and a tiny profiler (spec 4.1, 10.1).
local _, ns = ...

local Debug = { lines = {}, max = 500, profiling = false, profile = {} }
ns.Debug = Debug

local window

local function stamp()
  local t = ns.Compat and ns.Compat.GetTime() or 0
  return string.format("%.1f", t)
end

function Debug:Log(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  local line = stamp() .. " " .. table.concat(parts, " ")
  local lines = self.lines
  lines[#lines + 1] = line
  if #lines > self.max then table.remove(lines, 1) end
  if window and window:IsShown() then window.messages:AddMessage(line) end
end

function Debug:IsEnabled()
  return ns.db ~= nil and ns:GetSetting("general", "debug") == true
end

-- Logs only when debug mode is on (for chatty messages).
function Debug:Trace(...)
  if self:IsEnabled() then self:Log(...) end
end

local function createWindow()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(560, 320)
  f:SetPoint("CENTER", 0, 120)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  ns.Util.SkinFrame(f, 0.85)
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetText("QuestKompas debug")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  local msgs = CreateFrame("ScrollingMessageFrame", nil, f)
  msgs:SetPoint("TOPLEFT", 10, -28)
  msgs:SetPoint("BOTTOMRIGHT", -10, 10)
  msgs:SetFontObject(GameFontHighlightSmall)
  msgs:SetJustifyH("LEFT")
  msgs:SetMaxLines(Debug.max)
  msgs:SetFading(false)
  msgs:EnableMouseWheel(true)
  msgs:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  f.messages = msgs
  return f
end

function Debug:ShowWindow()
  if not window then window = createWindow() end
  window.messages:Clear()
  for i = 1, #self.lines do window.messages:AddMessage(self.lines[i]) end
  window:Show()
end

function Debug:HideWindow()
  if window then window:Hide() end
end

function Debug:ToggleWindow()
  if window and window:IsShown() then self:HideWindow() else self:ShowWindow() end
end

-- Logs a block of lines and opens the window (used by /qk dump).
function Debug:Dump(lines)
  for i = 1, #lines do self:Log(lines[i]) end
  self:ShowWindow()
end

----------------------------------------------------------------------------
-- Profiler: Events.lua times each handler while profiling is on.
----------------------------------------------------------------------------
function Debug:AddProfile(owner, ms)
  local p = self.profile[owner]
  if not p then p = { ms = 0, calls = 0 } self.profile[owner] = p end
  p.ms = p.ms + ms
  p.calls = p.calls + 1
end

function Debug:StartProfile()
  self.profile = {}
  self.profileStart = ns.Compat.GetTime()
  self.profiling = true
end

function Debug:ProfileReport()
  local elapsed = math.max(0.001, ns.Compat.GetTime() - (self.profileStart or 0))
  local out = { string.format("Profiel over %.0f s:", elapsed) }
  local names = {}
  for owner in pairs(self.profile) do names[#names + 1] = owner end
  table.sort(names)
  for _, owner in ipairs(names) do
    local p = self.profile[owner]
    out[#out + 1] = string.format("  %-14s %7.3f ms/s  %5d calls", owner, p.ms / elapsed, p.calls)
  end
  return out
end

function Debug:StopProfile()
  self.profiling = false
  return self:ProfileReport()
end
