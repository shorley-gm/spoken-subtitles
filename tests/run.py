"""Run the SpokenSubtitles Lua tests under real Lua 5.1 (via Lupa).

Each test file gets a fresh runtime: the WoW/Spoken mock, then the addon's files in TOC
order with the (addonName, namespace) varargs the client passes, then the test.

    python tests/run.py            # uses the Lupa copy on PYTHONPATH
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "SpokenSubtitles"
TESTS = ROOT / "tests"
FALLBACK_LUPA = pathlib.Path.home() / "AppData/Local/Temp/opencode/spoken-verification-runtime"

try:
    import lupa.lua51 as lupa
except ImportError:
    sys.path.insert(0, str(FALLBACK_LUPA))
    import lupa.lua51 as lupa


def toc_files():
    files = []
    for line in (ADDON / "SpokenSubtitles.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(ADDON / line.replace("\\", "/"))
    return files


def lua_path(path):
    return str(path).replace("\\", "/")


def run(test):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'dofile("{lua_path(TESTS / "wow_mock.lua")}")')
    lua.execute("ns = {}")
    for path in toc_files():
        lua.execute(f'assert(loadfile("{lua_path(path)}"))("SpokenSubtitles", ns)')
    lua.execute(f'dofile("{lua_path(test)}")')
    return lua.eval("Tests.passed")


def main():
    failures = 0
    for test in sorted(TESTS.glob("*_test.lua")):
        try:
            passed = run(test)
            print(f"ok   {test.name}: {passed} assertions")
        except Exception as error:  # a Lua error surfaces as LuaError
            failures += 1
            print(f"FAIL {test.name}: {error}")
    # Lua 5.1 compile check of every addon file on its own, too.
    lua = lupa.LuaRuntime()
    for path in toc_files():
        ok, message = lua.eval(f'function() local f, e = loadfile("{lua_path(path)}") return f ~= nil, e end')()
        if not ok:
            failures += 1
            print(f"FAIL compile {path.name}: {message}")
    print("all passed" if failures == 0 else f"{failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
