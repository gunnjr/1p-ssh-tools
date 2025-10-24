#!/usr/bin/env bash
set -euo pipefail

# Functional tests for op-ssh-show-pubkey.sh
# Uses real 1Password data (discovers SSH keys dynamically)

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/op-ssh-show-pubkey.sh"

PASS=0
FAIL=0

ok() { printf "[ OK ] %s\n" "$1"; PASS=$((PASS+1)); }
no() { printf "[FAIL] %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "[start] op-ssh-show-pubkey functional tests"
if [[ "${DEBUG:-0}" = "1" ]]; then set -x; fi

# Verify op CLI is available and signed in
if ! command -v op >/dev/null 2>&1; then
  echo "[FAIL-SETUP] op CLI not found. Install 1Password CLI first." >&2
  exit 2
fi

whoami_status=0
if ! whoami_out="$(op whoami 2>&1)"; then
  whoami_status=$?
fi
if [[ $whoami_status -ne 0 ]]; then
  echo "[FAIL-SETUP] Not signed in to 1Password (op whoami failed)." >&2
  printf "%s\n" "$whoami_out" | sed 's/^/[op whoami] /' >&2 || true
  echo "[action] Run: op signin" >&2
  exit 2
fi

echo "[info] Using 1Password vault: Private"

# Discover available SSH keys in vault
echo "[run] Discovering SSH keys in vault..."
available_keys=$(op item list --vault Private --categories "SSH Key" --format json 2>/dev/null | jq -r '.[].title' 2>/dev/null || echo "")

if [ -z "$available_keys" ]; then
  echo "[SKIP] No SSH keys found in Private vault. Cannot run tests."
  exit 0
fi

# Pick first key for testing
first_key=$(echo "$available_keys" | head -1)
first_key_pattern=$(echo "$first_key" | cut -c1-5)  # First 5 chars as pattern
echo "[info] Found SSH key: $first_key"
echo ""

# Test 1: List all SSH keys in vault
TEST1="List all SSH keys in vault"
if output=$("$SCRIPT" "." --list-only 2>&1 || true); then
  if echo "$output" | grep -q "Matches in vault"; then
    ok "$TEST1"
  else
    no "$TEST1"
  fi
else
  no "$TEST1"
fi

# Test 2: Pattern matching finds discovered key
TEST2="Pattern matching finds real SSH key"
if output=$("$SCRIPT" "$first_key_pattern" --list-only 2>&1 || true); then
  if echo "$output" | grep -q "$first_key"; then
    ok "$TEST2"
  else
    no "$TEST2"
  fi
else
  no "$TEST2"
fi

# Test 3: Case-insensitive pattern matching
TEST3="Pattern matching is case-insensitive"
upper_pattern=$(echo "$first_key_pattern" | tr '[:lower:]' '[:upper:]')
if output=$("$SCRIPT" "$upper_pattern" --list-only 2>&1 || true); then
  if echo "$output" | grep -q "$first_key"; then
    ok "$TEST3"
  else
    no "$TEST3"
  fi
else
  no "$TEST3"
fi

# Test 4: Help flag works
TEST4="Help flag shows usage"
if output=$("$SCRIPT" --help 2>&1 || true); then
  if echo "$output" | grep -q "Usage:"; then
    ok "$TEST4"
  else
    no "$TEST4"
  fi
else
  no "$TEST4"
fi

# Test 5: Missing pattern returns error
TEST5="Missing pattern returns error"
output=$("$SCRIPT" 2>&1 || true)
if echo "$output" | grep -q "Usage:"; then
  ok "$TEST5"
else
  no "$TEST5"
fi

# Test 6: Invalid option returns error
TEST6="Invalid option returns error"
output=$("$SCRIPT" "test" --invalid-flag 2>&1 || true)
if echo "$output" | grep -q "Unknown option"; then
  ok "$TEST6"
else
  no "$TEST6"
fi

# Test 7: --no-copy flag works with real key
TEST7="--no-copy flag works with real key"
if output=$("$SCRIPT" "$first_key_pattern" --list-only --no-copy 2>&1 || true); then
  if echo "$output" | grep -q "Matches in vault"; then
    ok "$TEST7"
  else
    no "$TEST7"
  fi
else
  no "$TEST7"
fi

# Test 8: Non-existent pattern returns error
TEST8="Non-existent pattern returns error"
output=$("$SCRIPT" "NONEXISTENT_KEY_12345_XYZ" --list-only 2>&1 || true)
if echo "$output" | grep -q "No SSH items found"; then
  ok "$TEST8"
else
  no "$TEST8"
fi

echo ""
echo "========================================"
printf "Passed: %d  Failed: %d\n" "$PASS" "$FAIL"
echo "========================================"

if [ "$FAIL" -eq 0 ]; then
  echo "✅ All functional tests passed!"
  if [[ "${SHOW_OUTPUT:-0}" = "1" ]]; then
    echo ""
    echo "----- BEGIN op-ssh-show-pubkey output -----"
    printf "%s\n" "$output"
    echo "----- END op-ssh-show-pubkey output -----"
  fi
  exit 0
else
  echo ""
  echo "----- BEGIN op-ssh-show-pubkey output (on failure) -----"
  printf "%s\n" "$output"
  echo "----- END op-ssh-show-pubkey output -----"
  echo "❌ Some tests failed."
  exit 1
fi
