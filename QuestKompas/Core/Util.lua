-- QuestKompas: pure helpers (distance, colours, money, timers).
-- Most functions here are covered by tests/spec_util.lua.
local _, ns = ...

local U = {}
ns.Util = U

local floor, sqrt, atan2, pi = math.floor, math.sqrt, math.atan2, math.pi
local TWO_PI = 2 * pi

----------------------------------------------------------------------------
-- Timers
----------------------------------------------------------------------------
local debounceTimers = {}

-- Runs fn once, `seconds` after the last call with the same key.
function ns:Debounce(key, seconds, fn)
  local t = debounceTimers[key]
  if t then t:Cancel() end
  debounceTimers[key] = C_Timer.NewTimer(seconds, function()
    debounceTimers[key] = nil
    ns.SafeCall(fn)
  end)
end

function ns:CancelDebounce(key)
  local t = debounceTimers[key]
  if t then t:Cancel() debounceTimers[key] = nil end
end

-- Runs fn at most once per `seconds`; a call inside the window schedules one
-- trailing run at the end of the window.
local throttleState = {}
function ns:Throttle(key, seconds, fn)
  local now = ns.Compat.GetTime()
  local st = throttleState[key]
  if not st then st = { last = -math.huge } throttleState[key] = st end
  st.fn = fn
  if now - st.last >= seconds then
    st.last = now
    ns.SafeCall(fn)
    return true
  end
  if not st.pending then
    st.pending = true
    C_Timer.After(seconds - (now - st.last), function()
      st.pending = false
      st.last = ns.Compat.GetTime()
      ns.SafeCall(st.fn)
    end)
  end
  return false
end

----------------------------------------------------------------------------
-- Numbers and text
----------------------------------------------------------------------------
function U.Round(v, decimals)
  local m = 10 ^ (decimals or 0)
  return floor(v * m + 0.5) / m
end

function U.Clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function U.Trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 1234567 copper -> "123g 45s 67c". Zero parts are left out.
function U.FormatMoney(copper)
  copper = floor(tonumber(copper) or 0)
  if copper <= 0 then return "0c" end
  local g = floor(copper / 10000)
  local s = floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 then parts[#parts + 1] = c .. "c" end
  return table.concat(parts, " ")
end

-- 12345 -> "12.3k", 999 -> "999".
function U.FormatShort(n)
  n = tonumber(n) or 0
  if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
  if n >= 10000 then return string.format("%.0fk", n / 1000) end
  if n >= 1000 then return string.format("%.1fk", n / 1000) end
  return tostring(floor(n + 0.5))
end

function U.FormatDuration(seconds)
  seconds = floor(tonumber(seconds) or 0)
  if seconds < 60 then return seconds .. "s" end
  if seconds < 3600 then return string.format("%dm %02ds", floor(seconds / 60), seconds % 60) end
  return string.format("%du %02dm", floor(seconds / 3600), floor((seconds % 3600) / 60))
end

function U.ColorHex(r, g, b)
  return string.format("ff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

function U.Colorize(text, r, g, b)
  return "|c" .. U.ColorHex(r, g, b) .. text .. "|r"
end

----------------------------------------------------------------------------
-- Quest difficulty (mirrors DifficultyUtil.GetRelativeDifficultyColor in the
-- Forever 1.60.1 export).
----------------------------------------------------------------------------
function U.Difficulty(questLevel, playerLevel, trivialRange)
  local diff = (questLevel or playerLevel) - playerLevel
  if diff >= 5 then return "red" end
  if diff >= 3 then return "orange" end
  if diff >= -4 then return "yellow" end
  if -diff <= (trivialRange or 5) then return "green" end
  return "grey"
end

U.DIFF_KEY = { red = "impossible", orange = "verydifficult", yellow = "difficult",
               green = "standard", grey = "trivial" }
U.DIFF_FALLBACK = {
  red = { r = 1.0, g = 0.1, b = 0.1 }, orange = { r = 1.0, g = 0.5, b = 0.25 },
  yellow = { r = 1.0, g = 0.82, b = 0.0 }, green = { r = 0.25, g = 0.75, b = 0.25 },
  grey = { r = 0.5, g = 0.5, b = 0.5 },
}

function U.DifficultyColor(difficulty)
  local blizz = QuestDifficultyColors and QuestDifficultyColors[U.DIFF_KEY[difficulty] or "difficult"]
  return blizz or U.DIFF_FALLBACK[difficulty] or U.DIFF_FALLBACK.yellow
end

-- Eight distinguishable colours, used for tracker and map pins (8.1).
U.PALETTE = {
  { 0.35, 0.70, 1.00 }, { 1.00, 0.55, 0.20 }, { 0.45, 0.90, 0.35 }, { 0.95, 0.35, 0.75 },
  { 1.00, 0.90, 0.30 }, { 0.30, 0.90, 0.85 }, { 0.70, 0.50, 1.00 }, { 0.95, 0.30, 0.30 },
}

-- Picks the palette index used least by the current assignments.
function U.PickColor(assigned)
  local used = {}
  for i = 1, #U.PALETTE do used[i] = 0 end
  for _, idx in pairs(assigned) do
    if used[idx] then used[idx] = used[idx] + 1 end
  end
  local best, bestN = 1, math.huge
  for i = 1, #U.PALETTE do
    if used[i] < bestN then best, bestN = i, used[i] end
  end
  return best
end

----------------------------------------------------------------------------
-- GUIDs: "Creature-0-1-2-3-<npcID>-<spawn>"
----------------------------------------------------------------------------
local GUID_KIND = { Creature = "npc", Vehicle = "npc", Pet = "npc", GameObject = "obj", Item = "item",
                    Player = "player" }

function U.ParseGUID(guid)
  if type(guid) ~= "string" then return nil end
  local parts = {}
  for p in guid:gmatch("[^%-]+") do parts[#parts + 1] = p end
  local kind = GUID_KIND[parts[1]]
  if not kind then return nil end
  local id
  if kind == "npc" or kind == "obj" then id = tonumber(parts[6]) end
  return kind, id
end

----------------------------------------------------------------------------
-- Geometry. Positions are (mapID, x, y) with x, y in 0..1.
----------------------------------------------------------------------------
local Geo = {}
ns.Geo = Geo

-- Distance in yards between two map points, plus delta vector; nil when the
-- points are on different continents or the map is unknown.
function Geo.Distance(m1, x1, y1, m2, x2, y2)
  if not (m1 and x1 and y1 and m2 and x2 and y2) then return nil end
  local HBD = ns.Compat.HBD
  if HBD then
    local d, dx, dy = HBD:GetZoneDistance(m1, x1, y1, m2, x2, y2)
    if d then return d, dx, dy end
  end
  local i1, n1, w1 = ns.Compat.GetWorldPos(m1, x1, y1)
  local i2, n2, w2 = ns.Compat.GetWorldPos(m2, x2, y2)
  if not i1 or i1 ~= i2 then return nil end
  local dn, dw = n2 - n1, w2 - w1
  return sqrt(dn * dn + dw * dw), dn, dw
end

-- Normalises an angle to [0, 2*pi).
function Geo.NormAngle(a)
  a = a % TWO_PI
  if a < 0 then a = a + TWO_PI end
  return a
end

-- Angle (radians, counter-clockwise from north, same convention as
-- GetPlayerFacing) from point 1 to point 2.
function Geo.Bearing(m1, x1, y1, m2, x2, y2)
  local HBD = ns.Compat.HBD
  if HBD then
    local wx1, wy1, inst1 = HBD:GetWorldCoordinatesFromZone(x1, y1, m1)
    local wx2, wy2, inst2 = HBD:GetWorldCoordinatesFromZone(x2, y2, m2)
    if wx1 and wx2 and inst1 == inst2 then
      local angle = HBD:GetWorldVector(inst1, wx1, wy1, wx2, wy2)
      return angle
    end
  end
  -- TODO(verify): fallback assumes GetWorldPosFromMapPos returns
  -- (north, west), as UnitPosition does.
  local i1, n1, w1 = ns.Compat.GetWorldPos(m1, x1, y1)
  local i2, n2, w2 = ns.Compat.GetWorldPos(m2, x2, y2)
  if not i1 or i1 ~= i2 then return nil end
  return Geo.NormAngle(atan2(w2 - w1, n2 - n1))
end

-- Arrow rotation relative to the player's facing.
function Geo.RelativeAngle(bearing, facing)
  return Geo.NormAngle(bearing - facing)
end

-- Flat distance for points on the same map (no conversion), in map units.
function Geo.MapDistSq(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return dx * dx + dy * dy
end

----------------------------------------------------------------------------
-- Frame skin: solid background plus 1px border, built from colour textures
-- so no texture file is needed (8.1: dark, 60% opacity by default).
----------------------------------------------------------------------------
function U.SkinFrame(frame, alpha)
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
  frame.qkBg:SetColorTexture(0, 0, 0, alpha or 0.6)
  for _, e in ipairs(frame.qkEdges) do e:SetColorTexture(0.4, 0.4, 0.4, math.min(1, (alpha or 0.6) + 0.2)) end
end
