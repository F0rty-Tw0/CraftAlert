#!/usr/bin/env python3
"""Run a single Lua test file under lupa's Lua 5.1 runtime (WoW is Lua 5.1).

Usage:  python scripts/run_test.py tests/core/test_flavor_compat.lua
        python scripts/run_test.py --jit tests/model/test_matcher_perf.lua   # lupa.luajit21
"""

import importlib
import os
import sys


def main():
    args = [a for a in sys.argv[1:] if a != "--jit"]
    jit = "--jit" in sys.argv[1:]
    if not args:
        print("Usage: python scripts/run_test.py [--jit] <test-file.lua>", file=sys.stderr)
        sys.exit(1)

    runtime = "lupa.luajit21" if jit else "lupa.lua51"
    try:
        LuaRuntime = importlib.import_module(runtime).LuaRuntime
    except ImportError:
        print(f"ERROR: {runtime} is not available. Run: pip install lupa", file=sys.stderr)
        sys.exit(1)

    test_path = args[0].replace("\\", "/")
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")
    # Tests read repo files (CraftAlert.toc, ...) with paths relative to the root.
    os.chdir(project_root)

    lua = LuaRuntime(unpack_returned_tuples=True)

    # Mirror tests/run.lua: strip the "CraftAlert." prefix so
    # require("CraftAlert.Core.X") resolves to <root>/Core/X.lua.
    lua.execute(f"""
        package.path = "{project_root}/?.lua;{project_root}/?/init.lua;" .. package.path

        local rawRequire = require
        require = function(name)
            if type(name) == "string" and name:find("CraftAlert.", 1, true) == 1 then
                name = name:sub(#"CraftAlert." + 1)
            end
            return rawRequire(name)
        end
        _G.require = require
    """)

    abs_test_path = os.path.join(project_root, test_path).replace("\\", "/")
    if not os.path.isfile(abs_test_path):
        print(f"ERROR: test file not found: {abs_test_path}", file=sys.stderr)
        sys.exit(1)

    try:
        test_fn = lua.execute(f'return dofile("{abs_test_path}")')
        if callable(test_fn):
            test_fn()
        print(f"PASS {test_path}")
    except Exception as e:
        print(f"FAIL {test_path}", file=sys.stderr)
        print(str(e), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
