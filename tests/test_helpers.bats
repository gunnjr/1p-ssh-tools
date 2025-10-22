#!/usr/bin/env bats

# Helper function tests for scripts/op-ssh-addhost.sh
# Focused and minimal: fingerprints, default block, and render block

# Test harness variables
TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SCRIPT_DIR="$TEST_DIR/../scripts"

# Prevent main execution when sourcing the script
export OPSSH_TEST_MODE=1

# Mock need() to avoid dependency checks while sourcing
need() { :; }
export -f need

# Source the script (temporarily relax -e -u if set by bats)
set +eu
source "$SCRIPT_DIR/op-ssh-addhost.sh"
set -eu

setup() {
  TMPROOT=$(mktemp -d)
  # Keep AGENT_SOCK empty for deterministic default block output
  AGENT_SOCK=""
}

teardown() {
  rm -rf "$TMPROOT"
}

# Utility: generate a real SSH ed25519 keypair for fingerprint tests
# Returns: sets PUBFILE path and FP_FILE fingerprint
_gen_keypair() {
  local keydir="$TMPROOT/key"
  mkdir -p "$keydir"
  local keyfile="$keydir/id_ed25519"
  ssh-keygen -t ed25519 -f "$keyfile" -N "" -C "bats@test" >/dev/null 2>&1
  PUBFILE="$keyfile.pub"
  FP_FILE="$(fp_from_file "$PUBFILE")"
}

@test "fp_from_file extracts fingerprint from a valid .pub file" {
  _gen_keypair
  [ -n "$FP_FILE" ]
  [[ "$FP_FILE" =~ ^SHA256: ]]
}

@test "fp_from_pub matches fp_from_file for same key" {
  _gen_keypair
  # Call the function in the same shell so it is in scope
  local out
  out="$(fp_from_pub < "$PUBFILE")"
  [ -n "$out" ]
  [ "$out" = "$FP_FILE" ]
}

@test "fp_from_pub returns empty for invalid input" {
  local out
  out="$(fp_from_pub <<< "not-a-valid-ssh-key")"
  [ -z "$out" ]
}

@test "ensure_default_block adds Host * and IdentitiesOnly no when missing" {
  local cfg="$TMPROOT/config"
  cat >"$cfg" <<'EOF'
Host example.com
  HostName example.com
EOF
  ensure_default_block "$cfg"

  run grep -q "^Host \*$" "$cfg"
  [ "$status" -eq 0 ]

  # Ensure IdentitiesOnly no is present under the default block
  run grep -q "^  IdentitiesOnly no$" "$cfg"
  [ "$status" -eq 0 ]
}

@test "ensure_default_block is idempotent (does not duplicate Host *)" {
  local cfg="$TMPROOT/config2"
  cat >"$cfg" <<'EOF'
Host example.com
  HostName example.com

Host *
  IdentitiesOnly no
EOF
  ensure_default_block "$cfg"

  run bash -c "grep -c '^Host \*$' '$cfg'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "render_host_block writes expected lines to TBLK" {
  local blk="$TMPROOT/block"
  TBLK="$blk"
  : >"$TBLK"
  render_host_block "example.com" "example.com" "alice" "/home/alice/.ssh/id_example.pub"

  run grep -q "^Host example.com$" "$TBLK"
  [ "$status" -eq 0 ]
  run grep -q "^  HostName example.com$" "$TBLK"
  [ "$status" -eq 0 ]
  run grep -q "^  User alice$" "$TBLK"
  [ "$status" -eq 0 ]
  run grep -q "^  IdentityFile /home/alice/.ssh/id_example.pub$" "$TBLK"
  [ "$status" -eq 0 ]
  run grep -q "^  IdentitiesOnly yes$" "$TBLK"
  [ "$status" -eq 0 ]
}
