#!/usr/bin/env bats

# Get the directory where the test file is located
TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SCRIPT_DIR="$TEST_DIR/../scripts"

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

@test "upsert handles Host lines with multiple tokens (example.com example)" {
  cat >"$CFG" <<'EOF'
Host first
  HostName first

Host example.com example
  HostName old-example

Host *
  IdentitiesOnly no
EOF

  cat >"$BLK" <<'EOF'
Host example.com
  HostName example.com
  User bob
  IdentityFile /home/bob/.ssh/id_example.pub
  IdentitiesOnly yes
EOF

  # Call the actual function from the script
  upsert_host_block "$CFG" "$OUT" "example.com"

  # There should be exactly one Host example.com (the new block)
  run grep -c "^Host example.com$" "$OUT"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # The old multi-token line should not remain
  run grep -q "Host example.com example" "$OUT"
  [ "$status" -ne 0 ]

  # Ensure first host still present
  run grep -q "Host first" "$OUT"
  [ "$status" -eq 0 ]
}

@test "upsert preserves comments and unrelated blocks" {
  cat >"$CFG" <<'EOF'
# Global comment
Host keepme
  HostName keepme.local

# Another comment
Host example.com
  HostName older.example

# Tail comment
EOF

  cat >"$BLK" <<'EOF'
Host example.com
  HostName example.com
  User carol
EOF

  # Call the actual function from the script
  upsert_host_block "$CFG" "$OUT" "example.com"

  # comments should be preserved
  run grep -q "# Global comment" "$OUT"
  [ "$status" -eq 0 ]
  run grep -q "# Another comment" "$OUT"
  [ "$status" -eq 0 ]
  run grep -q "# Tail comment" "$OUT"
  [ "$status" -eq 0 ]

  # keepme block should still be present
  run grep -q "Host keepme" "$OUT"
  [ "$status" -eq 0 ]

  # new block should contain User carol
  run grep -q "User carol" "$OUT"
  [ "$status" -eq 0 ]
}
