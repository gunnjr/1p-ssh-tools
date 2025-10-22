#!/usr/bin/env bash
set -euo pipefail

# Functional tests for op-ssh-show-pubkey.sh
# Uses real 1Password data (discovers SSH keys dynamically)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/op-ssh-show-pubkey.sh"

PASS=0
FAIL=0

ok() { printf "[ OK ] %s\n" "$1"; ((PASS++)); }
no() { printf "[FAIL] %s\n" "$1"; ((FAIL++)); }

# Verify op CLI is available and signed in
if ! command -v op >/dev/null 2>&1; then
  echo "[ERROR] op CLI not found. Install 1Password CLI first." >&2
  exit 2
fi

if ! op whoami >/dev/null 2>&1; then
  echo "[ERROR] Not signed in to 1Password. Run: op signin" >&2
  exit 2
fi

echo "Running op-ssh-show-pubkey functional tests..."
echo "Using 1Password vault: Private"
echo ""

# Discover available SSH keys in vault
echo "Discovering SSH keys in vault..."
available_keys=$(op item list --vault Private --categories "SSH Key" --format json 2>/dev/null | jq -r '.[].title' 2>/dev/null || echo "")

if [ -z "$available_keys" ]; then
  echo "[SKIP] No SSH keys found in Private vault. Cannot run tests."
  exit 0
fi

# Pick first key for testing
first_key=$(echo "$available_keys" | head -1)
first_key_pattern=$(echo "$first_key" | cut -c1-5)  # First 5 chars as pattern
echo "Found SSH keys. Testing with: $first_key"
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
if "$SCRIPT" 2>&1 | grep -q "Usage:"; then
  ok "$TEST5"
else
  no "$TEST5"
fi

# Test 6: Invalid option returns error
TEST6="Invalid option returns error"
if "$SCRIPT" "test" --invalid-flag 2>&1 | grep -q "Unknown option"; then
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
if "$SCRIPT" "NONEXISTENT_KEY_12345_XYZ" --list-only 2>&1 | grep -q "No SSH items found"; then
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
  exit 0
else
  echo "❌ Some tests failed."
  exit 1
fi
