-- Test runner: lua5.1 tests/run.lua [filter]
-- Each spec file returns a table of name -> function. Specs call
-- stub.Reset() / stub.LoadAddon() themselves when they need the addon.
local root = arg[0]:match("^(.*)/tests/run%.lua$") or "."
package.path = root .. "/tests/?.lua;" .. package.path

require("wow_stub")

local T = {}
_G.T = T

local function fmt(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function T.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg and (msg .. ": ") or "") .. "expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
  end
end

function T.ok(v, msg)
  if not v then error(msg or "expected truthy value", 2) end
end

function T.near(actual, expected, eps, msg)
  if type(actual) ~= "number" or math.abs(actual - expected) > (eps or 1e-6) then
    error((msg and (msg .. ": ") or "") .. "expected ~" .. fmt(expected) .. ", got " .. fmt(actual), 2)
  end
end

local function deepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
T.deepEq = deepEq

function T.same(actual, expected, msg)
  if not deepEq(actual, expected) then error((msg or "tables differ"), 2) end
end

-- Fails when any Lua error was routed to the error handler or a module got
-- disabled.
function T.clean(ns)
  if #stub.errors > 0 then error("errors: " .. table.concat(stub.errors, " | "), 2) end
  for name, mod in pairs(ns.modules) do
    if mod.brokenUntilReload then error("module broken: " .. name, 2) end
  end
end

local filter = arg[1]
local files = {}
local p = io.popen('ls "' .. root .. '/tests"')
for f in p:lines() do
  if f:match("^spec_.*%.lua$") and (not filter or f:find(filter, 1, true)) then files[#files + 1] = f end
end
p:close()
table.sort(files)

local passed, failed = 0, 0
for _, file in ipairs(files) do
  local specs = dofile(root .. "/tests/" .. file)
  local names = {}
  for name in pairs(specs) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    stub.Reset()
    local ok, err = xpcall(specs[name], debug.traceback)
    if ok then
      passed = passed + 1
    else
      failed = failed + 1
      print("FAIL " .. file .. " :: " .. name .. "\n  " .. tostring(err):gsub("\n", "\n  "))
    end
  end
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
