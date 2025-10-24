#!/usr/bin/env bats

# Get the directory where the test file is located
TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SCRIPT_DIR="$TEST_DIR/../../scripts"

# Source the main script to get access to the upsert_host_block function
# We need to set OPSSH_TEST_MODE to prevent the script from executing
export OPSSH_TEST_MODE=1

# Mock the need() function to avoid dependency checks during testing
need() { :; }
export -f need

# Temporarily disable strict error handling to allow sourcing
set +eu
source "$SCRIPT_DIR/op-ssh-addhost.sh"
set -eu

setup() {
  TMPDIR=$(mktemp -d)
  CFG="$TMPDIR/ssh_config"
  BLK="$TMPDIR/block"
  OUT="$TMPDIR/out"
  # Set TBLK for the function to use
  TBLK="$BLK"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "upsert_host_block replaces existing Host block and appends new block" {
  cat >"$CFG" <<'EOF'
Host oldhost
  HostName oldhost.local

Host example.com
  HostName old-old.example.com

Host *
  IdentitiesOnly no
EOF

  cat >"$BLK" <<'EOF'
Host example.com
  HostName example.com
  User alice
  IdentityFile /home/alice/.ssh/id_example.pub
  IdentitiesOnly yes
EOF

  # Call the actual function from the script
  # Function signature: upsert_host_block inFile outFile host
  # It uses the global TBLK variable for the block content
  upsert_host_block "$CFG" "$OUT" "example.com"

  run grep -c "Host example.com" "$OUT"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  run grep -q "User alice" "$OUT"
  [ "$status" -eq 0 ]

  # Ensure oldhost preserved
  run grep -q "Host oldhost" "$OUT"
  [ "$status" -eq 0 ]
}
