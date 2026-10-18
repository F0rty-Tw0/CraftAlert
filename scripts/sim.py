#!/usr/bin/env python3
"""Run tools/sim.lua under lupa's Lua 5.1 and print its output lines.

Usage:  python scripts/sim.py [--flavor tbc] [--db FILE] [--sender NAME] "LF plate belt" ...

The repo root comes from this file's own path, so a copy of the script inside a
base worktree runs that worktree's code (before/after proof pairs).
"""

import os
import sys

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    print("ERROR: lupa is not installed. Run: pip install lupa", file=sys.stderr)
    sys.exit(1)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")
    sim_path = f"{root}/tools/sim.lua"
    if not os.path.isfile(sim_path):
        print(f"ERROR: {sim_path} not found", file=sys.stderr)
        sys.exit(1)

    lua = LuaRuntime(unpack_returned_tuples=True)

    # Same shim as run_test.py: require("CraftAlert.Core.X") resolves to <root>/Core/X.lua,
    # and the "C" locale keeps string.lower ASCII-only as in WoW (see run_test.py).
    lua.execute(f"""
        os.setlocale("C")
        package.path = "{root}/?.lua;{root}/?/init.lua;" .. package.path

        local rawRequire = require
        require = function(name)
            if type(name) == "string" and name:find("CraftAlert.", 1, true) == 1 then
                name = name:sub(#"CraftAlert." + 1)
            end
            return rawRequire(name)
        end
        _G.require = require
    """)

    lua_globals = lua.globals()
    lua_globals.CRAFTALERT_ROOT = root
    lua_globals.arg = lua.table(*sys.argv[1:])

    try:
        lua.execute(f'dofile("{sim_path}")')
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
