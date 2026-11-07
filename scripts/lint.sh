#!/usr/bin/env bash
# Lint and format-check CraftAlert Lua source
# Usage:
#   ./scripts/lint.sh          # check only (CI-safe)
#   ./scripts/lint.sh --fix    # auto-format in place
#
# Exit code reflects StyLua and luacheck only. LuaLS just prints LUALS_WARNINGS=<n>
# so the count can be tracked in the plan Log (it must not rise).

set -euo pipefail
cd "$(dirname "$0")/.."

FIX=false
if [[ "${1:-}" == "--fix" ]]; then
  FIX=true
fi

EXIT_CODE=0
ALL_TARGETS=(Bootstrap.lua Core Model Professions Persistence UI tests)
# Folders arrive task by task; skip the ones that do not exist yet.
TARGETS=()
for target in "${ALL_TARGETS[@]}"; do
  if [[ -e "$target" ]]; then
    TARGETS+=("$target")
  fi
done
# Folders searched for the tools, nearest first: this checkout, the main checkout
# (differs when this is a linked worktree, which has no .tools/ of its own), then
# the sibling WhisperMessenger checkout. Resolved from git's common dir, not the
# current folder, so a worktree finds the same tools as the main checkout.
MAIN_ROOT="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$PWD/.git")")"
FALLBACK_TOOLS="$MAIN_ROOT/../WhisperMessenger/.tools"
TOOL_DIRS=(.tools "$MAIN_ROOT/.tools" "$FALLBACK_TOOLS")

find_command() {
  local name="$1"
  local resolved=""

  if resolved="$(command -v "$name" 2>/dev/null)"; then
    printf '%s\n' "$resolved"
    return 0
  fi

  local old_ifs="$IFS"
  IFS=:
  for dir in $PATH; do
    IFS="$old_ifs"
    for candidate in "$dir/$name" "$dir/$name.exe" "$dir/$name.EXE"; do
      if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
    IFS=:
  done
  IFS="$old_ifs"

  return 1
}

# Echo the first executable among the arguments, or nothing.
first_executable() {
  for candidate in "$@"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Echo the first <tool dir>/<relative path> that is executable, or nothing.
find_tool() {
  for dir in "${TOOL_DIRS[@]}"; do
    if [[ -x "$dir/$1" ]]; then
      printf '%s\n' "$dir/$1"
      return 0
    fi
  done
  return 1
}

STYLUA_CMD=""
if STYLUA_CMD="$(find_tool stylua/stylua.exe)"; then
  :
elif STYLUA_CMD="$(find_command stylua)"; then
  :
elif STYLUA_CMD="$(first_executable "$HOME/.cargo/bin/stylua.exe" "$HOME/.cargo/bin/stylua")"; then
  :
else
  STYLUA_CMD=""
fi

LUACHECK_CMD=""
# Prefer the bare exe: the hererocks-generated luacheck.bat is a bash script
# with a .bat extension and does not run under cmd.exe on Windows.
if LUACHECK_CMD="$(find_tool luacheck.exe)"; then
  :
elif LUACHECK_CMD="$(find_command luacheck)"; then
  :
else
  LUACHECK_CMD=""
fi

LUALS_CMD=""
if LUALS_CMD="$(find_tool lua-language-server/bin/lua-language-server.exe)"; then
  :
elif LUALS_CMD="$(find_command lua-language-server)"; then
  :
else
  LUALS_CMD=""
fi

# Ketho's WoW API annotations (github.com/Ketho/vscode-wow-api, its Annotations/Core folder)
# type Blizzard's globals and widgets. Without them LuaLS checks the plain count, which flags
# the WoW type names the code uses. Get them once (core.longpaths for Windows):
#   git -c core.longpaths=true clone --depth 1 https://github.com/Ketho/vscode-wow-api .tools/vscode-wow-api
WOW_API=""
for dir in "${TOOL_DIRS[@]}"; do
  if [[ -d "$dir/vscode-wow-api/Annotations/Core" ]]; then
    WOW_API="$dir/vscode-wow-api/Annotations/Core"
    break
  fi
done

# --- StyLua (formatting) ---
if [[ -n "$STYLUA_CMD" ]]; then
  echo "=== StyLua ==="
  if $FIX; then
    if ! "$STYLUA_CMD" "${TARGETS[@]}" tools; then
      EXIT_CODE=1
    else
      echo "  Formatted OK"
    fi
  else
    if ! "$STYLUA_CMD" --check "${TARGETS[@]}" tools; then
      echo "  Run './scripts/lint.sh --fix' to auto-format"
      EXIT_CODE=1
    else
      echo "  OK"
    fi
  fi
else
  echo "FAIL: stylua not found (install it: cargo install stylua)"
  EXIT_CODE=1
fi

echo ""

# --- Luacheck (static analysis; .luacheckrc skips tools/) ---
if [[ -n "$LUACHECK_CMD" ]]; then
  echo "=== Luacheck ==="
  if ! "$LUACHECK_CMD" --no-color "${TARGETS[@]}"; then
    EXIT_CODE=1
  fi
else
  echo "FAIL: luacheck not found (looked in ${TOOL_DIRS[*]} and PATH)"
  EXIT_CODE=1
fi

echo ""

# --- Lua Language Server diagnostics: count only, never fails the script ---
if [[ -n "$LUALS_CMD" ]]; then
  echo "=== LuaLS Diagnostics (count only) ==="
  LUALS_LOG="$(mktemp)"
  LUALS_ARGS=(--check=. --check_format=pretty --checklevel=Warning --logpath=.tmp_luals)
  # The splice below needs .luarc.json's closing brace alone on its last line.
  if [[ -n "$WOW_API" && "$(tail -n 1 .luarc.json | tr -d '[:space:]')" != "}" ]]; then
    echo "  WoW API annotations skipped: .luarc.json must end with } on its own line"
    WOW_API=""
  fi
  if [[ -n "$WOW_API" ]]; then
    echo "  with WoW API annotations from $WOW_API"
    mkdir -p .tmp_luals
    # .luarc.json plus a workspace.library entry: drop its closing brace, then append the entry.
    {
      sed '$d' .luarc.json | sed '$s/$/,/'
      printf '  "workspace.library": ["%s"]\n}\n' "$WOW_API"
    } >.tmp_luals/luarc.json
    LUALS_ARGS+=(--configpath=.tmp_luals/luarc.json)
  fi
  "$LUALS_CMD" "${LUALS_ARGS[@]}" >"$LUALS_LOG" 2>&1 || true
  LUALS_COUNT="$(grep -Eo '[0-9]+ problems? found' "$LUALS_LOG" | grep -Eo '^[0-9]+' | tail -n 1 || true)"
  if grep -q 'no problems found' "$LUALS_LOG"; then
    LUALS_COUNT=0
  fi
  rm -f "$LUALS_LOG"
  echo "LUALS_WARNINGS=${LUALS_COUNT:-unknown}"
else
  echo "LUALS_WARNINGS=unknown (lua-language-server not found)"
fi
exit $EXIT_CODE
