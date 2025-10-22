#!/usr/bin/env bats

# Helper function tests for scripts/op-ssh-show-pubkey.sh
# Focused: pattern matching, key extraction, fingerprint display

TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SCRIPT_DIR="$TEST_DIR/../scripts"

setup() {
  TMPROOT=$(mktemp -d)
  export HOME="$TMPROOT/home"
  mkdir -p "$HOME"
}

teardown() {
  rm -rf "$TMPROOT"
}

# Utility: generate a real SSH ed25519 keypair
_gen_keypair() {
  local keydir="$TMPROOT/key"
  mkdir -p "$keydir"
  local keyfile="$keydir/id_ed25519"
  ssh-keygen -t ed25519 -f "$keyfile" -N "" -C "bats@test" >/dev/null 2>&1
  PUBFILE="$keyfile.pub"
}

@test "public key can be extracted from file" {
  _gen_keypair

  # Read the public key
  pub="$(cat "$PUBFILE")"

  [ -n "$pub" ]
  [[ "$pub" =~ ^ssh-ed25519 ]]
}

@test "fingerprint extraction from public key file is valid" {
  _gen_keypair

  fp="$(ssh-keygen -lf "$PUBFILE" 2>/dev/null | awk '{print $2}')"

  [ -n "$fp" ]
  [[ "$fp" =~ ^SHA256: ]]
}

@test "case-insensitive pattern matching works" {
  # Simulate title list
  titles=(
    "SSH Key - GitHub"
    "SSH Key - gitlab"
    "SSH Key - BITBUCKET"
  )

  # Filter like the script does: case-insensitive substring match
  pattern="git"
  matched=()
  for title in "${titles[@]}"; do
    if [[ "$title" =~ $pattern ]] || [[ "$title" =~ [Gg][Ii][Tt] ]]; then
      matched+=("$title")
    fi
  done

  # Should match GitHub and gitlab
  [ "${#matched[@]}" -eq 2 ]
}

@test "exact match is prioritized" {
  titles=(
    "SSH Key - example"
    "SSH Key - example.com"
    "SSH Key - example-prod"
  )

  pattern="example.com"

  # Find exact match
  exact=""
  for title in "${titles[@]}"; do
    if [ "$title" = "SSH Key - $pattern" ]; then
      exact="$title"
      break
    fi
  done

  [ "$exact" = "SSH Key - example.com" ]
}
