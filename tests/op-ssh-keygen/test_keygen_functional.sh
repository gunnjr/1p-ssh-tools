#!/usr/bin/env bash
set -uo pipefail

# Functional tests for op-ssh-keygen.sh
# Tests interactive mode with real 1Password vault data

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/op-ssh-keygen.sh"

PASS=0
FAIL=0

ok() { printf "[ OK ] %s\n" "$1"; ((PASS++)); }
no() { printf "[FAIL] %s\n" "$1"; ((FAIL++)); }

# Always announce start so we see output even if preflight fails
echo "[start] op-ssh-keygen functional tests"

# Optional debug tracing: DEBUG=1 ./test_keygen_functional.sh
if [[ "${DEBUG:-0}" = "1" ]]; then
  set -x
fi

# Preflight: Verify op CLI is available and signed in
if ! command -v op >/dev/null 2>&1; then
  echo "[FAIL-SETUP] op CLI not found. Install 1Password CLI and ensure 'op' is on PATH." >&2
  echo "[hint] https://developer.1password.com/docs/cli/get-started" >&2
  exit 2
fi

whoami_out="$(op whoami 2>&1)"; whoami_status=$?
if [[ $whoami_status -ne 0 ]]; then
  echo "[FAIL-SETUP] Not signed in to 1Password (op whoami failed)." >&2
  printf "%s\n" "$whoami_out" | sed 's/^/[op whoami] /' >&2 || true
  echo "[action] Run: op signin" >&2
  exit 2
fi

echo "[info] Using 1Password vault: Private"
echo "[run] Starting interactive test for op-ssh-keygen.sh"
echo ""

# Test 1: Find and display existing SSH key
TEST1="Find existing SSH key and display it"
echo "[TEST] Invoking: $SCRIPT --title \"SSH Key - sdr-host - sdrpi\" --no-copy"
echo "[TEST] Providing input: 1 (select first key)"

output=$(printf "1\n" | "$SCRIPT" --title "SSH Key - sdr-host - sdrpi" --no-copy 2>&1 || true)

# Check that output contains expected elements
if echo "$output" | grep -q "Title"; then
  if echo "$output" | grep -q "Fingerprint"; then
    if echo "$output" | grep -q "ssh-rsa\|ssh-ed25519"; then
      ok "$TEST1"
    else
      no "$TEST1 (ERROR: No public key in output)"
    fi
  else
    no "$TEST1 (ERROR: Fingerprint not found in output)"
  fi
else
  no "$TEST1 (ERROR: Title not found in output)"
fi

# Optionally show the captured script output
if [[ "${SHOW_OUTPUT:-0}" = "1" ]]; then
  echo ""
  echo "----- BEGIN op-ssh-keygen output -----"
  printf "%s\n" "$output"
  echo "----- END op-ssh-keygen output -----"
fi

echo ""
echo "========================================"
printf "Passed: %d  Failed: %d\n" "$PASS" "$FAIL"
echo "========================================"

if [ "$FAIL" -eq 0 ]; then
  echo "✅ All functional tests passed!"
  exit 0
else
  # On failure, print captured output to aid debugging
  echo ""
  echo "----- BEGIN op-ssh-keygen output (on failure) -----"
  printf "%s\n" "$output"
  echo "----- END op-ssh-keygen output -----"
  echo "❌ Some tests failed."
  exit 1
fi
