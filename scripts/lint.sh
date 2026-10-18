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
# Sibling checkout whose .tools/ holds luacheck and lua-language-server
FALLBACK_TOOLS="../WhisperMessenger/.tools"

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

STYLUA_CMD=""
if STYLUA_CMD="$(first_executable .tools/stylua/stylua.exe)"; then
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
if LUACHECK_CMD="$(first_executable .tools/luacheck.exe "$FALLBACK_TOOLS/luacheck.exe")"; then
  :
elif LUACHECK_CMD="$(find_command luacheck)"; then
  :
else
  LUACHECK_CMD=""
fi

LUALS_CMD=""
if LUALS_CMD="$(first_executable .tools/lua-language-server/bin/lua-language-server.exe "$FALLBACK_TOOLS/lua-language-server/bin/lua-language-server.exe")"; then
  :
elif LUALS_CMD="$(find_command lua-language-server)"; then
  :
else
  LUALS_CMD=""
fi

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
  echo "FAIL: luacheck not found (looked in .tools/ and $FALLBACK_TOOLS)"
  EXIT_CODE=1
fi

echo ""

# --- Lua Language Server diagnostics: count only, never fails the script ---
if [[ -n "$LUALS_CMD" ]]; then
  echo "=== LuaLS Diagnostics (count only) ==="
  LUALS_LOG="$(mktemp)"
  "$LUALS_CMD" --check=. --check_format=pretty --checklevel=Warning \
    --logpath=.tmp_luals >"$LUALS_LOG" 2>&1 || true
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
