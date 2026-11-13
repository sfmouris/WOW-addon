-- QuestKompas: shared look (spec 8.1). Colours, sizes and small building
-- blocks so the tracker, arrow, item bar and dialogs match.
local ADDON, ns = ...

local Style = {}
ns.Style = Style

Style.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\UI\\Media\\"

Style.color = {
  panel  = { 0.04, 0.05, 0.07 },
  bar    = { 0.09, 0.11, 0.15 },
  edge   = { 0.24, 0.28, 0.34 },
  accent = { 0.30, 0.90, 1.00 },
  text   = { 0.90, 0.90, 0.90 },
  dim    = { 0.58, 0.62, 0.68 },
  faint  = { 0.42, 0.45, 0.50 },
  good   = { 0.35, 1.00, 0.45 },
  bad    = { 1.00, 0.30, 0.25 },
}
local COL = Style.color

Style.BAR_H = 22

-- Inline texture escape for one of our white icons, tinted.
function Style.Icon(name, size, col)
  col = col or COL.text
  return string.format("|T%s%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t", Style.MEDIA, name, size, size,
    math.floor(col[1] * 255), math.floor(col[2] * 255), math.floor(col[3] * 255))
end

-- Dark panel with a one pixel edge. Safe to call again to change alpha.
function Style.Panel(frame, alpha)
  alpha = alpha or 0.6
  if not frame.qkBg then
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    frame.qkBg = bg
    local edges = {}
    for i = 1, 4 do edges[i] = frame:CreateTexture(nil, "BORDER") end
    edges[1]:SetPoint("TOPLEFT") edges[1]:SetPoint("TOPRIGHT") edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT") edges[2]:SetPoint("BOTTOMRIGHT") edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT") edges[3]:SetPoint("BOTTOMLEFT") edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT") edges[4]:SetPoint("BOTTOMRIGHT") edges[4]:SetWidth(1)
    frame.qkEdges = edges
  end
  frame.qkBg:SetColorTexture(COL.panel[1], COL.panel[2], COL.panel[3], alpha)
  local edgeAlpha = math.min(1, alpha + 0.2)
  for _, e in ipairs(frame.qkEdges) do e:SetColorTexture(COL.edge[1], COL.edge[2], COL.edge[3], edgeAlpha) end
  if frame.qkBar then
    frame.qkBar:SetColorTexture(COL.bar[1], COL.bar[2], COL.bar[3], math.min(1, alpha + 0.3))
    frame.qkBarLine:SetColorTexture(COL.accent[1], COL.accent[2], COL.accent[3], math.min(1, alpha + 0.1) * 0.7)
  end
end

-- Title strip with an accent line and a title text. Call before Panel so
-- Panel colours it. Returns the title font string.
function Style.TitleBar(frame, text, icon)
  local bar = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(Style.BAR_H - 1)
  frame.qkBar = bar
  local line = frame:CreateTexture(nil, "BORDER")
  line:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
  line:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT")
  line:SetHeight(1)
  frame.qkBarLine = line
  local left = 8
  if icon then
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetSize(14, 14)
    tex:SetPoint("TOPLEFT", 6, -4)
    tex:SetTexture(Style.MEDIA .. icon)
    left = 24
  end
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", left, -6)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)
  title:SetText(text or "")
  title:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
  return title
end

-- Small tintable icon button with a tooltip. tooltip may be a function.
function Style.IconButton(parent, icon, tooltip, onClick, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size or 16, size or 16)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetPoint("TOPLEFT", 2, -2)
  b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
  b.tex:SetVertexColor(COL.dim[1], COL.dim[2], COL.dim[3])
  b.tooltip = tooltip
  function b:SetIcon(name) self.tex:SetTexture(Style.MEDIA .. name) end
  b:SetIcon(icon)
  b:SetScript("OnEnter", function(self)
    self.tex:SetVertexColor(COL.accent[1], COL.accent[2], COL.accent[3])
    local tip = self.tooltip
    if type(tip) == "function" then tip = tip() end
    if tip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(tip, 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    self.tex:SetVertexColor(COL.dim[1], COL.dim[2], COL.dim[3])
    GameTooltip:Hide()
  end)
  b:SetScript("OnClick", function(self, button) ns.SafeCall(onClick, self, button) end)
  return b
end

-- Flat text button for dialogs.
function Style.Button(parent, text, width)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width or 90, 22)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(COL.bar[1], COL.bar[2], COL.bar[3], 1)
  local line = b:CreateTexture(nil, "BORDER")
  line:SetPoint("BOTTOMLEFT") line:SetPoint("BOTTOMRIGHT") line:SetHeight(1)
  line:SetColorTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.7)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.18)
  b:SetNormalFontObject("GameFontHighlightSmall")
  b:SetHighlightFontObject("GameFontHighlightSmall")
  b:SetDisabledFontObject("GameFontDisableSmall")
  b:SetText(text or "")
  return b
end

-- Thin progress bar. bar:SetProgress(fraction, width, r, g, b).
function Style.ProgressBar(parent, height)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(height or 2)
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints()
  bar.bg:SetColorTexture(1, 1, 1, 0.10)
  bar.fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill:SetPoint("TOPLEFT")
  bar.fill:SetPoint("BOTTOMLEFT")
  function bar:SetProgress(fraction, width, r, g, b)
    fraction = ns.Util.Clamp(fraction or 0, 0, 1)
    self:SetWidth(width)
    self.fill:SetWidth(math.max(0.01, width * fraction))
    self.fill:SetShown(fraction > 0)
    self.fill:SetColorTexture(r or COL.accent[1], g or COL.accent[2], b or COL.accent[3], 0.9)
  end
  return bar
end

-- Short fade-out flash on a texture (the only animation, spec 8.1).
function Style.Flash(tex, seconds)
  if not tex.qkFlash then
    local group = tex:CreateAnimationGroup()
    local anim = group:CreateAnimation("Alpha")
    anim:SetFromAlpha(1)
    anim:SetToAlpha(0)
    anim:SetSmoothing("OUT")
    group:SetScript("OnFinished", function() tex:Hide() end)
    tex.qkFlash, tex.qkFlashAnim = group, anim
  end
  tex.qkFlashAnim:SetDuration(seconds or 0.3)
  tex.qkFlash:Stop()
  tex:Show()
  tex.qkFlash:Play()
end

function Style.StopFlash(tex)
  if tex.qkFlash then tex.qkFlash:Stop() end
  tex:Hide()
end
