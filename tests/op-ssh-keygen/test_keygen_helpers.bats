#!/usr/bin/env bats

# Helper function tests for scripts/op-ssh-keygen.sh
# Focused: fingerprint extraction (agent.toml behavior removed)

TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
ROOT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts"

# Test harness
setup() {
  TMPROOT=$(mktemp -d)
  export HOME="$TMPROOT/home"
  mkdir -p "$HOME"
}

teardown() {
  rm -rf "$TMPROOT"
}

# Utility: generate a real SSH ed25519 keypair for fingerprint tests
_gen_keypair() {
  local keydir="$TMPROOT/key"
  mkdir -p "$keydir"
  local keyfile="$keydir/id_ed25519"
  ssh-keygen -t ed25519 -f "$keyfile" -N "" -C "bats@test" >/dev/null 2>&1
  PUBFILE="$keyfile.pub"
  FP_FILE="$(ssh-keygen -lf "$PUBFILE" -E sha256 2>/dev/null | awk '{print $2 " " $1}')"
}

## agent.toml-related tests removed: script no longer reads or writes agent.toml

@test "fingerprint extraction from public key is valid" {
  _gen_keypair

  # Extract fingerprint like the script does
  fp="$(ssh-keygen -lf "$PUBFILE" -E sha256 2>/dev/null | awk '{print $2 " " $1}')"

  [ -n "$fp" ]
  [[ "$fp" =~ ^SHA256: ]]
}

@test "fingerprint matches across multiple extractions" {
  _gen_keypair

  fp1="$(ssh-keygen -lf "$PUBFILE" -E sha256 2>/dev/null | awk '{print $2 " " $1}')"
  fp2="$(ssh-keygen -lf "$PUBFILE" -E sha256 2>/dev/null | awk '{print $2 " " $1}')"

  [ "$fp1" = "$fp2" ]
}
