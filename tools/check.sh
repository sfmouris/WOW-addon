#!/usr/bin/env bash
# Runs luacheck and the test suite. On macOS: brew install luajit luarocks && luarocks install luacheck
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
LUA=""
for c in ${LUA_BIN:-} lua5.1 luajit lua-5.1; do if command -v "$c" >/dev/null 2>&1; then LUA="$c"; break; fi; done
if [ -z "$LUA" ]; then echo "Geen Lua 5.1 of LuaJIT gevonden (brew install luajit)." >&2; exit 1; fi
if command -v luacheck >/dev/null 2>&1; then luacheck . ; else echo "luacheck ontbreekt (luarocks install luacheck), overgeslagen." ; fi
"$LUA" tests/run.lua "$@"
