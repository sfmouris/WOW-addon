-- QuestKompas: SavedVariables, defaults, migrations and settings access.
local _, ns = ...

local DB = {}
ns.DB = DB

DB.SCHEMA = 1
DB.CHAR_SCHEMA = 1

-- Spec 6.3. Language defaults to Dutch for this personal build.
DB.defaults = {
  modules = { Tracker = true, Navigator = true, Planner = true, Learn = true, AutoQuest = true,
              RewardHelper = true, MapPins = true, ItemBar = true, LogTools = true, Stats = true,
              Party = false, Bridges = true },
  tracker = { scale = 1.0, width = 260, locked = false, sort = "distance", hideDone = true,
              fadeInCombat = true, hideBlizzard = false, showFooter = true, maxRows = 30,
              bgAlpha = 0.6, shown = true },
  nav = { mode = "own", useTomTom = false, autoAdvance = true, arriveYards = 10, sound = true, scale = 1.0 },
  auto = { accept = true, turnin = true, skipModifier = "SHIFT", repeatable = false,
           maxLevelAbove = 4, gossip = false, announce = true, autoReward = false },
  pins = { turnin = true, hotspots = true, givers = true, coords = true, minimap = true, nav = true },
  learn = { enabled = true, maxHotspots = 12, mergeYards = 40 },
  planner = { clusterYards = 150, preferNearDone = true, penalizeGroup = true },
  itembar = { enabled = true, max = 6, key = nil },
  general = { language = "nl", debug = false, minimap = true },
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, sub in pairs(v) do out[k] = copy(sub) end
  return out
end
DB.Copy = copy

-- Fills missing keys from defaults, recursively. Never overwrites existing
-- values (spec 6.4).
function DB.DeepMerge(dst, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      DB.DeepMerge(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

-- migrations[n] upgrades a db from schema n-1 to n.
DB.migrations = {}
DB.charMigrations = {}

function DB.Migrate(db, migrations, target)
  db.schema = db.schema or 0
  for n = db.schema + 1, target do
    local fn = migrations[n]
    if fn then fn(db) end
    db.schema = n
  end
  return db
end

-- Schema 1: initial layout. Also used to normalise an empty table.
DB.migrations[1] = function(db)
  db.settings = db.settings or {}
  db.learned = db.learned or { quests = {} }
  db.notes = db.notes or {}
  db.blacklist = db.blacklist or {}
  db.warned = db.warned or {}
end

DB.charMigrations[1] = function(cdb)
  cdb.overrides = cdb.overrides or {}
  cdb.positions = cdb.positions or {}
  cdb.history = cdb.history or {}
  cdb.session = cdb.session or {}
  cdb.colors = cdb.colors or {}
  cdb.collapsed = cdb.collapsed or {}
  cdb.manualOrder = cdb.manualOrder or {}
end

function DB.Prepare(db, cdb)
  DB.Migrate(db, DB.migrations, DB.SCHEMA)
  db.settings = db.settings or {}
  DB.DeepMerge(db.settings, DB.defaults)
  db.learned = db.learned or {}
  db.learned.quests = db.learned.quests or {}
  DB.Migrate(cdb, DB.charMigrations, DB.CHAR_SCHEMA)
  return db, cdb
end

function DB:Init()
  if type(QuestKompasDB) ~= "table" then QuestKompasDB = {} end
  if type(QuestKompasCharDB) ~= "table" then QuestKompasCharDB = {} end
  DB.Prepare(QuestKompasDB, QuestKompasCharDB)
  ns.db, ns.cdb = QuestKompasDB, QuestKompasCharDB
end

----------------------------------------------------------------------------
-- Settings: account values with optional per-character overrides.
-- ns.cfg.tracker.scale reads the effective value; assigning writes it.
----------------------------------------------------------------------------
function ns:GetSetting(section, key)
  local cdb = self.cdb
  if cdb and cdb.overrides then
    local o = cdb.overrides[section]
    if o and o[key] ~= nil then return o[key] end
  end
  local s = self.db and self.db.settings[section]
  if s then
    local v = s[key]
    if v ~= nil then return v end
  end
  local d = DB.defaults[section]
  return d and d[key]
end

function ns:SetSetting(section, key, value)
  local cdb = self.cdb
  if cdb and cdb.perChar then
    cdb.overrides[section] = cdb.overrides[section] or {}
    cdb.overrides[section][key] = value
  else
    self.db.settings[section] = self.db.settings[section] or {}
    self.db.settings[section][key] = value
  end
  self:Fire("QK_SETTING_CHANGED", section, key, value)
end

function ns:ResetSection(section)
  if not DB.defaults[section] then return end
  self.db.settings[section] = copy(DB.defaults[section])
  if self.cdb and self.cdb.overrides then self.cdb.overrides[section] = nil end
  self:Fire("QK_SETTING_CHANGED", section, nil, nil)
end

function ns:ResetAllSettings()
  self.db.settings = copy(DB.defaults)
  if self.cdb then self.cdb.overrides = {} end
  self:Fire("QK_SETTING_CHANGED", nil, nil, nil)
end

ns.cfg = setmetatable({}, {
  __index = function(t, section)
    local proxy = setmetatable({}, {
      __index = function(_, key) return ns:GetSetting(section, key) end,
      __newindex = function(_, key, value) ns:SetSetting(section, key, value) end,
    })
    rawset(t, section, proxy)
    return proxy
  end,
})
