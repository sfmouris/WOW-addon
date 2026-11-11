-- Static checks: TOC, locale keys, forbidden characters and APIs.
local S = {}
local root = stub.ADDON_DIR:gsub("/QuestKompas/$", "")

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function luaFiles(dir)
  local out = {}
  local p = io.popen('find "' .. dir .. '" -name "*.lua" -not -path "*/Libs/*"')
  for f in p:lines() do out[#out + 1] = f end
  p:close()
  return out
end

S["TOC: interface 16001, every file exists, every addon file is listed"] = function()
  local ns = stub.LoadAddon({ login = false })
  local toc = read(stub.ADDON_DIR .. "QuestKompas.toc")
  T.eq(tonumber(toc:match("## Interface: (%d+)")), ns.TOC_INTERFACE)
  local listed = {}
  for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^#") then
      local path = line:gsub("\\", "/")
      T.ok(io.open(stub.ADDON_DIR .. path), "missing file " .. path)
      listed[path] = true
    end
  end
  for _, f in ipairs(luaFiles(stub.ADDON_DIR)) do
    local rel = f:sub(#stub.ADDON_DIR + 1)
    T.ok(listed[rel], "not in TOC: " .. rel)
  end
end

S["every locale key used in code exists in English and Dutch with the same placeholders"] = function()
  local ns = stub.LoadAddon({ login = false })
  local en, nl = ns.Locales.enUS, ns.Locales.nlNL
  local dynamic = { SOURCE_ = true, MOD_ = true, OPT_SECTION_ = true }
  for _, f in ipairs(luaFiles(stub.ADDON_DIR)) do
    local src = read(f)
    for key in src:gmatch('L%["([%u%d_]+)"%]') do
      T.ok(en[key], "enUS missing " .. key .. " (" .. f .. ")")
      T.ok(nl[key], "nlNL missing " .. key .. " (" .. f .. ")")
    end
    for prefix in src:gmatch('L%["([%u_]+_)" %.%.') do T.ok(dynamic[prefix], "unexpected dynamic key " .. prefix) end
  end
  for _, suffix in ipairs({ "CLIENT", "POI", "QUESTIE", "LEARNED", "USER" }) do T.ok(nl["SOURCE_" .. suffix]) end
  for key, v in pairs(en) do
    T.ok(nl[key], "nlNL missing " .. key)
    local function specs(s) local o = {} for spec in s:gmatch("%%[%d%.]*[sdf]") do o[#o + 1] = spec end return table.concat(o, " ") end
    T.eq(specs(nl[key]), specs(v), "placeholders differ for " .. key)
  end
  for key in pairs(nl) do T.ok(en[key], "enUS missing " .. key) end
end

S["no em-dash anywhere in the repository text"] = function()
  local dash = "\226\128\148"
  local p = io.popen('cd "' .. root .. '" && git ls-files 2>/dev/null; find QuestKompas tests tools docs -type f 2>/dev/null; ls *.md 2>/dev/null')
  local checked = 0
  for f in p:lines() do
    if not f:find("/Libs/", 1, true) and not f:match("%.tga$") then
      local fh = io.open(root .. "/" .. f, "rb")
      if fh then
        local s = fh:read("*a")
        fh:close()
        T.ok(not s:find(dash, 1, true), "em-dash in " .. f)
        checked = checked + 1
      end
    end
  end
  p:close()
  T.ok(checked > 20, "checked " .. checked .. " files")
end

S["no forbidden APIs (combat log, loadstring, classic globals)"] = function()
  for _, f in ipairs(luaFiles(stub.ADDON_DIR)) do
    local src = read(f)
    for _, bad in ipairs({ "COMBAT_LOG_EVENT", "loadstring", "RunScript", "GetQuestLogTitle", "GetContainerItemInfo",
                           "CombatLogGetCurrentEventInfo" }) do
      T.ok(not src:find(bad, 1, true), bad .. " used in " .. f)
    end
  end
end

S["modules only reach client quest and map APIs through Compat"] = function()
  for _, f in ipairs(luaFiles(stub.ADDON_DIR .. "Modules")) do
    local src = read(f)
    for _, ns in ipairs({ "C_QuestLog%.", "C_GossipInfo%.", "C_Map%.", "C_SuperTrack%.", "C_TaskQuest%." }) do
      T.ok(not src:find(ns), ns .. " called directly in " .. f)
    end
  end
end

return S
