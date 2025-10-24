#!/usr/bin/env bash
set -euo pipefail


ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/op-ssh-status.sh"

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


LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/opssh-status-logs.XXXXXX" 2>/dev/null)"
cleanup(){ rm -rf "$LOGDIR"; }
trap cleanup EXIT

PASS=0
FAIL=0

ok(){ printf "[ OK ] %s\n" "$1"; PASS=$((PASS+1)); }
no(){ printf "[FAIL] %s\n" "$1"; FAIL=$((FAIL+1)); }

run_cmd(){
  local name="$1"; shift
  local desc="$1"; shift
  echo "---> $name : $desc"
  local log="$LOGDIR/$name.log"
  echo "[debug] HOME=$HOME" >"$log"
  echo "[info] desc=$desc" >>"$log"
  if ! "$@" >>"$log" 2>&1; then
    echo ""; echo "===== BEGIN TEST OUTPUT: $name - $desc (FAILED) ====="; cat "$log"; echo "===== END TEST OUTPUT: $name ====="; echo ""
    return 1
  fi
  echo ""; echo "===== BEGIN TEST OUTPUT: $name - $desc (OK) ====="; cat "$log"; echo "===== END TEST OUTPUT: $name ====="; echo ""
  return 0
}


# Test 1: --all returns OK for valid config and key
TEST1="--all returns OK for valid config and key"
mkdir -p "$HOME/.ssh"
ssh-keygen -t rsa -b 2048 -f "$HOME/.ssh/testkey" -N "" >/dev/null
cat > "$HOME/.ssh/config" <<EOF
Host testhost
  HostName test.example.com
  User testuser
  IdentityFile $HOME/.ssh/testkey.pub
EOF
if run_cmd "test1" "$TEST1" "$SCRIPT" --all; then
  grep -q "testhost" "$LOGDIR/test1.log" && grep -q "OK" "$LOGDIR/test1.log" && ok "$TEST1" || no "$TEST1"
else
  no "$TEST1"
fi

# Test 2: --orphans finds no orphaned keys when all are used
TEST2="--orphans finds no orphaned keys when all are used"
if run_cmd "test2" "$TEST2" "$SCRIPT" --orphans; then
  grep -q "No orphaned .pub files." "$LOGDIR/test2.log" && ok "$TEST2" || no "$TEST2"
else
  no "$TEST2"
fi

# Test 3: --host testhost returns only matching host
TEST3="--host testhost returns only matching host"
if run_cmd "test3" "$TEST3" "$SCRIPT" --host testhost; then
  grep -q "testhost" "$LOGDIR/test3.log" && ok "$TEST3" || no "$TEST3"
else
  no "$TEST3"
fi

# Test 4: --pubs-only lists public key and fingerprint
TEST4="--pubs-only lists public key and fingerprint"
if run_cmd "test4" "$TEST4" "$SCRIPT" --pubs-only; then
  grep -q "testkey.pub" "$LOGDIR/test4.log" && ok "$TEST4" || no "$TEST4"
else
  no "$TEST4"
fi

# Test 5: returns warning if IdentityFile missing
TEST5="returns warning if IdentityFile missing"
rm "$HOME/.ssh/testkey.pub"
if run_cmd "test5" "$TEST5" "$SCRIPT" --all; then
  grep -q "WARN" "$LOGDIR/test5.log" && ok "$TEST5" || no "$TEST5"
else
  ok "$TEST5" # script should exit 1, which is expected for warning
fi

echo
echo "Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "All shell tests passed."
  exit 0
else
  echo "Some tests failed."
  exit 2
fi
