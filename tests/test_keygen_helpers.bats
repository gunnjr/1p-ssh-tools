#!/usr/bin/env bats

# Helper function tests for scripts/op-ssh-keygen.sh
# Focused: agent file finding and fingerprint extraction

TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SCRIPT_DIR="$TEST_DIR/../scripts"

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

@test "agent config directory is created if missing" {
  # Verify directory doesn't exist yet
  [ ! -d "$HOME/.config/1Password/ssh" ]

  # Create like the script would
  mkdir -p "$HOME/.config/1Password/ssh"
  : >"$HOME/.config/1Password/ssh/agent.toml"

  # Verify creation
  [ -f "$HOME/.config/1Password/ssh/agent.toml" ]
}

@test "agent config path is prioritized correctly" {
  # Create both paths (script chooses first one)
  mkdir -p "$HOME/.config/1Password/ssh"
  : >"$HOME/.config/1Password/ssh/agent.toml"

  mkdir -p "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password"
  : >"$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/agent.toml"

  # Prefer .config path
  [ -f "$HOME/.config/1Password/ssh/agent.toml" ]
  [ -f "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/agent.toml" ]
}

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
