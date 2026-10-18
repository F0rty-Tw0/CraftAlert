#!/usr/bin/env bash
# Run every tests/**/test_*.lua through scripts/run_test.py (lupa, Lua 5.1).
# Usage: bash scripts/test.sh
# Prints "N passed, M failed"; exits 1 on any failure.

set -uo pipefail
cd "$(dirname "$0")/.."

PYTHON="${PYTHON:-python}"
passed=0
failed=0

while IFS= read -r test_file; do
  if output="$("$PYTHON" scripts/run_test.py "$test_file" 2>&1)"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf '%s\n' "$output"
  fi
done < <(find tests -type f -name 'test_*.lua' | sort)

echo "${passed} passed, ${failed} failed"
if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
