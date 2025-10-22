#!/usr/bin/env bash
set -euo pipefail

# Simple dependency-free tests for op-ssh-addhost.sh
# Usage: ./run_shell_tests.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/op-ssh-addhost.sh"
# Create a portable temporary test directory. On macOS TMPDIR may point to a
# per-user tmp path that no longer exists (stale). Try a TMPDIR-based mktemp
# first, then fall back to the -t form which uses /tmp.
if ! TESTDIR="$(mktemp -d "${TMPDIR:-/tmp}/opssh-test.XXXXXX" 2>/dev/null)"; then
  TESTDIR="$(mktemp -d -t opssh-test)"
fi
cleanup(){ rm -rf "$TESTDIR"; }
trap cleanup EXIT
LOGDIR="$TESTDIR/logs"
mkdir -p "$LOGDIR"

PASS=0
FAIL=0

ok(){ printf "[ OK ] %s\n" "$1"; PASS=$((PASS+1)); }
no(){ printf "[FAIL] %s\n" "$1"; FAIL=$((FAIL+1)); }

# Helper to run script with isolated HOME and PATH
run_cmd(){
  local name="$1"; shift
  local desc="$1"; shift
  echo "---> $name : $desc"
  HOME="$TESTDIR/$name-home"; mkdir -p "$HOME"
  PATH="$TESTDIR/$name-bin:$PATH"
  mkdir -p "$HOME/.ssh"
  mkdir -p "$TESTDIR/$name-bin"
  # Install the op mock into the test bin as `op` so the script finds it via PATH
  if [ -x "$TESTDIR/op-mock" ]; then
    cp "$TESTDIR/op-mock" "$TESTDIR/$name-bin/op"
    chmod +x "$TESTDIR/$name-bin/op"
  fi
  # Run the command with HOME and PATH set for the child process only.
  # Capture stdout/stderr to a per-test log so outputs don't intermix.
  local log="$LOGDIR/$name.log"
  echo "[debug] HOME=$HOME" >"$log"
  echo "[debug] PATH=$PATH" >>"$log"
  echo "[info] desc=$desc" >>"$log"
  if ! env HOME="$HOME" PATH="$PATH" "$@" >>"$log" 2>&1; then
    echo "[debug] Command failed; listing $HOME/.ssh:" >>"$log"
    ls -la "$HOME/.ssh" >>"$log" 2>&1 || true
    # Print a clear separator and the log so maintainers can see what happened
    echo ""; echo "===== BEGIN TEST OUTPUT: $name - $desc (FAILED) ====="; cat "$log"; echo "===== END TEST OUTPUT: $name ====="; echo ""
    return 1
  fi
  # On success, print a clear separator and the test log
  echo ""; echo "===== BEGIN TEST OUTPUT: $name - $desc (OK) ====="; cat "$log"; echo "===== END TEST OUTPUT: $name ====="; echo ""
  return 0
}

# Create a fake `op` that returns a public key line for the Title requested
cat > "$TESTDIR/op-mock" <<'OP'
#!/usr/bin/env bash
# simple mock: echo a JSON with fields containing a public key when asked
if [ "$1" = "item" ] && [ "$2" = "get" ]; then
  # return a JSON with a field labeled Public
  cat <<JSON
{ "fields": [ {"label": "Public Key", "value": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBfakekeyfor-testing user@example.com"} ] }
JSON
  exit 0
fi
# fallback: behave like `op` for whoami
if [ "$1" = "whoami" ]; then
  echo "you@example.com"
  exit 0
fi
# other commands: noop
exit 0
OP
chmod +x "$TESTDIR/op-mock"

# Test 1: Dry-run should not write files
TEST1="dry-run does not write files"
if run_cmd "test1" "$TEST1" "$SCRIPT" --host example.com --user testuser --pub-file "$TESTDIR/test1-home/.ssh/id_test.pub" --dry-run; then
  if [ ! -f "$TESTDIR/test1-home/.ssh/id_test.pub" ]; then
    ok "$TEST1"
  else
    no "$TEST1"
  fi
else
  no "$TEST1"
fi

# Test 2: Create pub file from 1Password
TEST2="create pub file from 1Password"
if run_cmd "test2" "$TEST2" "$SCRIPT" --host example.com --user testuser --pub-file "$TESTDIR/test2-home/.ssh/id_test.pub"; then
  if [ -f "$TESTDIR/test2-home/.ssh/id_test.pub" ]; then
    grep -q "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBfakekeyfor-testing" "$TESTDIR/test2-home/.ssh/id_test.pub" && ok "$TEST2" || no "$TEST2"
  else
    no "$TEST2"
  fi
else
  no "$TEST2"
fi

# Test 3: Upsert host block into config
TEST3="upsert host block into config"
if run_cmd "test3" "$TEST3" "$SCRIPT" --host example.com --user testuser --pub-file "$TESTDIR/test3-home/.ssh/id_test.pub"; then
  if grep -q "Host example.com" "$TESTDIR/test3-home/.ssh/config" ; then
    ok "$TEST3"
  else
    no "$TEST3"
  fi
else
  no "$TEST3"
fi

# Test 4: --force should backup and overwrite a mismatched local .pub
TEST4="force overwrite mismatched pub file"
# prepare a differing local pub file
mkdir -p "$TESTDIR/test4-home/.ssh"
cat > "$TESTDIR/test4-home/.ssh/id_test.pub" <<'OLD'
ssh-ed25519 AAAAoldkey old@example.com
OLD
chmod 644 "$TESTDIR/test4-home/.ssh/id_test.pub"
if run_cmd "test4" "$TEST4" "$SCRIPT" --host example.com --user testuser --pub-file "$TESTDIR/test4-home/.ssh/id_test.pub" --force; then
  # check the file was overwritten with the mock key and a backup exists
  if grep -q "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBfakekeyfor-testing" "$TESTDIR/test4-home/.ssh/id_test.pub" && ls "$TESTDIR/test4-home/.ssh/id_test.pub.bak."* >/dev/null 2>&1; then
    ok "$TEST4"
  else
    no "$TEST4"
  fi
else
  no "$TEST4"
fi

# Test 5: --auto-alias should add an IPv4 Host block when ping returns an address
TEST5="auto-alias adds IPv4 host block"
# create a small fake ping in the test workspace that prints the PING header line
cat > "$TESTDIR/ping-mock" <<'PING'
#!/usr/bin/env bash
printf 'PING example.com (1.2.3.4): 56 data bytes\n'
exit 0
PING
chmod +x "$TESTDIR/ping-mock"

# ensure the per-test bin exists and copy the ping mock there so it's found via PATH
mkdir -p "$TESTDIR/test5-bin"
cp "$TESTDIR/ping-mock" "$TESTDIR/test5-bin/ping"
chmod +x "$TESTDIR/test5-bin/ping"

# also add a simple dig mock that prints the A record
cat > "$TESTDIR/test5-bin/dig" <<'DIG'
#!/usr/bin/env bash
if [ "$1" = "+short" ] && [ "$2" = "example.com" ]; then
  echo "1.2.3.4"
  exit 0
fi
exit 1
DIG
chmod +x "$TESTDIR/test5-bin/dig"

if run_cmd "test5" "$TEST5" "$SCRIPT" --host example.com --user testuser --pub-file "$TESTDIR/test5-home/.ssh/id_test.pub" --auto-alias; then
  if grep -q "Host 1.2.3.4" "$TESTDIR/test5-home/.ssh/config" ; then
    ok "$TEST5"
  else
    no "$TEST5"
  fi
else
  no "$TEST5"
fi

# Summary
echo
echo "Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "All shell tests passed."
  exit 0
else
  echo "Some tests failed."
  exit 2
fi
