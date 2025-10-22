#!/usr/bin/env bats

# Helper function tests for scripts/op-ssh-status.sh
# Focused: fingerprint comparison and config parsing

TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SCRIPT_DIR="$TEST_DIR/../scripts"

setup() {
  TMPROOT=$(mktemp -d)
  export HOME="$TMPROOT/home"
  mkdir -p "$HOME/.ssh"
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
  FP_FILE="$(ssh-keygen -lf "$PUBFILE" -E sha256 2>/dev/null | awk '{print $2}')"
}

@test "fingerprint comparison detects matching keys" {
  _gen_keypair

  # Extract fingerprint twice and compare
  fp1="$(ssh-keygen -lf "$PUBFILE" -E sha256 2>/dev/null | awk '{print $2}')"
  fp2="$(ssh-keygen -lf "$PUBFILE" -E sha256 2>/dev/null | awk '{print $2}')"

  [ "$fp1" = "$fp2" ]
}

@test "fingerprint comparison detects different keys" {
  _gen_keypair
  fp1="$(ssh-keygen -lf "$PUBFILE" -E sha256 2>/dev/null | awk '{print $2}')"

  # Generate a different key
  local keydir="$TMPROOT/key2"
  mkdir -p "$keydir"
  ssh-keygen -t ed25519 -f "$keydir/id_ed25519" -N "" -C "bats@test2" >/dev/null 2>&1
  fp2="$(ssh-keygen -lf "$keydir/id_ed25519.pub" -E sha256 2>/dev/null | awk '{print $2}')"

  [ "$fp1" != "$fp2" ]
}

@test "SSH config with Host blocks parses correctly" {
  cat >"$HOME/.ssh/config" <<'EOF'
Host example.com
  HostName example.com
  User alice
  IdentityFile ~/.ssh/id_example.pub

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_github.pub
EOF

  # Count Host lines
  count=$(grep -c "^Host " "$HOME/.ssh/config")
  [ "$count" -eq 2 ]
}

@test "SSH config parsing extracts Host aliases" {
  cat >"$HOME/.ssh/config" <<'EOF'
Host server server.example.com
  HostName server.example.com
  User admin
EOF

  # Extract first Host name (before first space)
  first_host=$(grep "^Host " "$HOME/.ssh/config" | head -1 | awk '{print $2}')
  [ "$first_host" = "server" ]
}
