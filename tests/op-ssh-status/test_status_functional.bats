#!/usr/bin/env bats

setup() {
  export HOME="$BATS_TMPDIR"
  mkdir -p "$HOME/.ssh"
  echo "Host testhost
    HostName test.example.com
    User testuser
    IdentityFile $HOME/.ssh/testkey.pub
  " > "$HOME/.ssh/config"
  ssh-keygen -t rsa -b 2048 -f "$HOME/.ssh/testkey" -N "" >/dev/null
}

teardown() {
  rm -rf "$HOME/.ssh"
}

@test "op-ssh-status.sh --all returns OK for valid config and key" {
  run "$BATS_TEST_DIRNAME/../../scripts/op-ssh-status.sh" --all
  [ "$status" -eq 0 ]
  [[ "$output" =~ "testhost" ]]
  [[ "$output" =~ "OK" ]]
}

@test "op-ssh-status.sh --orphans finds no orphaned keys when all are used" {
  run "$BATS_TEST_DIRNAME/../../scripts/op-ssh-status.sh" --orphans
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No orphaned .pub files." ]]
}

@test "op-ssh-status.sh --host testhost returns only matching host" {
  run "$BATS_TEST_DIRNAME/../../scripts/op-ssh-status.sh" --host testhost
  [ "$status" -eq 0 ]
  [[ "$output" =~ "testhost" ]]
}

@test "op-ssh-status.sh --pubs-only lists public key and fingerprint" {
  run "$BATS_TEST_DIRNAME/../../scripts/op-ssh-status.sh" --pubs-only
  [ "$status" -eq 0 ]
  [[ "$output" =~ "testkey.pub" ]]
}

@test "op-ssh-status.sh returns warning if IdentityFile missing" {
  rm "$HOME/.ssh/testkey.pub"
  run "$BATS_TEST_DIRNAME/../../scripts/op-ssh-status.sh" --all
  [ "$status" -eq 1 ]
  [[ "$output" =~ "WARN" ]]
}
