# Testing Plan: op-ssh-addhost.sh

**Date:** October 22, 2025  
**Status:** 🟡 In Progress  
**Current Coverage:** 8 tests (3 BATS unit + 5 shell integration)

---

## Test Coverage Goals

| Category | Current | Target | Priority |
|----------|---------|--------|----------|
| **Helper Functions** | 0/6 | 6/6 | 🔴 High |
| **Error Conditions** | 2/10 | 10/10 | 🔴 High |
| **Edge Cases** | 3/8 | 8/8 | 🟡 Medium |
| **Integration** | 5/7 | 7/7 | 🟡 Medium |
| **Total** | **8/31** | **31/31** | |

---

## Phase 1: Unit Tests for Helper Functions (High Priority)

### Test Suite: `test_helpers.bats`

Create new file: `tests/test_helpers.bats`

#### Test 1.1: `fp_from_pub()` - Valid Ed25519 Key

```bash
@test "fp_from_pub extracts fingerprint from valid ed25519 key" {
  export OPSSH_TEST_MODE=1
  source "$SCRIPT_DIR/op-ssh-addhost.sh"
  
  local pubkey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBfakekeyfortesting user@example.com"
  local result
  result="$(echo "$pubkey" | fp_from_pub)"
  
  # Should return a fingerprint starting with SHA256:
  [[ "$result" =~ ^SHA256: ]]
  [ -n "$result" ]
}
```

#### Test 1.2: `fp_from_pub()` - Valid RSA Key

```bash
@test "fp_from_pub extracts fingerprint from valid rsa key" {
  export OPSSH_TEST_MODE=1
  source "$SCRIPT_DIR/op-ssh-addhost.sh"
  
  # Use a real RSA public key for testing
  local pubkey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... user@example.com"
  local result
  result="$(echo "$pubkey" | fp_from_pub)"
  
  [[ "$result" =~ ^SHA256: ]]
  [ -n "$result" ]
}
```

#### Test 1.3: `fp_from_pub()` - Invalid Key Format

```bash
@test "fp_from_pub returns empty string for invalid key" {
  export OPSSH_TEST_MODE=1
  source "$SCRIPT_DIR/op-ssh-addhost.sh"
  
  local invalid_key="not-a-valid-ssh-key"
  local result
  result="$(echo "$invalid_key" | fp_from_pub)"
  
  [ -z "$result" ]
}
```

#### Test 1.4: `fp_from_pub()` - Empty Input

```bash
@test "fp_from_pub handles empty input gracefully" {
  export OPSSH_TEST_MODE=1
  source "$SCRIPT_DIR/op-ssh-addhost.sh"
  
  local result
  result="$(echo "" | fp_from_pub)"
  
  [ -z "$result" ]
}
```

#### Test 1.5: `fp_from_file()` - Valid File

```bash
@test "fp_from_file extracts fingerprint from valid pub file" {
  export OPSSH_TEST_MODE=1
  source "$SCRIPT_DIR/op-ssh-addhost.sh"
  
  TMPDIR=$(mktemp -d)
  local pubfile="$TMPDIR/test.pub"
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBfakekeyfortesting user@example.com" > "$pubfile"
  
  local result
  result="$(fp_from_file "$pubfile")"
  
  [[ "$result" =~ ^SHA256: ]]
  [ -n "$result" ]
  
  rm -rf "$TMPDIR"
}
```

#### Test 1.6: `fp_from_file()` - Missing File

```bash
@test "fp_from_file returns empty for non-existent file" {
  export OPSSH_TEST_MODE=1
  source "$SCRIPT_DIR/op-ssh-addhost.sh"
  
  local result
  result="$(fp_from_file "/nonexistent/file.pub")"
  
  [ -z "$result" ]
}
```

#### Test 1.7: `fp_from_file()` - Malformed File

```bash
@test "fp_from_file handles malformed pub file" {
  export OPSSH_TEST_MODE=1
  source "$SCRIPT_DIR/op-ssh-addhost.sh"
  
  TMPDIR=$(mktemp -d)
  local pubfile="$TMPDIR/bad.pub"
  echo "garbage data not a key" > "$pubfile"
  
  local result
  result="$(fp_from_file "$pubfile")"
  
  [ -z "$result" ]
  
  rm -rf "$TMPDIR"
}
```

#### Test 1.8: `ensure_default_block()` - Missing Default Block

```bash
@test "ensure_default_block adds Host * when missing" {
  export OPSSH_TEST_MODE=1
  source "$SCRIPT_DIR/op-ssh-addhost.sh"
  
  TMPDIR=$(mktemp -d)
  local config="$TMPDIR/config"
  
  cat > "$config" <<'EOF'
Host example.com
  HostName example.com
EOF
  
  ensure_default_block "$config"
  
  run grep -q "^Host \*$" "$config"
  [ "$status" -eq 0 ]
  
  rm -rf "$TMPDIR"
}
```

#### Test 1.9: `ensure_default_block()` - Existing Default Block

```bash
@test "ensure_default_block skips when Host * exists" {
  export OPSSH_TEST_MODE=1
  source "$SCRIPT_DIR/op-ssh-addhost.sh"
  
  TMPDIR=$(mktemp -d)
  local config="$TMPDIR/config"
  
  cat > "$config" <<'EOF'
Host example.com
  HostName example.com

Host *
  IdentitiesOnly no
EOF
  
  ensure_default_block "$config"
  
  # Should have exactly one Host *
  run grep -c "^Host \*$" "$config"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
  
  rm -rf "$TMPDIR"
}
```

#### Test 1.10: `render_host_block()` - Full Parameters

```bash
@test "render_host_block creates complete block" {
  export OPSSH_TEST_MODE=1
  source "$SCRIPT_DIR/op-ssh-addhost.sh"
  
  TMPDIR=$(mktemp -d)
  TBLK="$TMPDIR/block"
  
  render_host_block "example.com" "example.com" "user" "/path/to/key.pub"
  
  run grep -q "^Host example.com$" "$TBLK"
  [ "$status" -eq 0 ]
  run grep -q "^  HostName example.com$" "$TBLK"
  [ "$status" -eq 0 ]
  run grep -q "^  User user$" "$TBLK"
  [ "$status" -eq 0 ]
  run grep -q "^  IdentityFile /path/to/key.pub$" "$TBLK"
  [ "$status" -eq 0 ]
  run grep -q "^  IdentitiesOnly yes$" "$TBLK"
  [ "$status" -eq 0 ]
  
  rm -rf "$TMPDIR"
}
```

#### Test 1.11: `render_host_block()` - Minimal Parameters

```bash
@test "render_host_block handles empty optional params" {
  export OPSSH_TEST_MODE=1
  source "$SCRIPT_DIR/op-ssh-addhost.sh"
  
  TMPDIR=$(mktemp -d)
  TBLK="$TMPDIR/block"
  
  render_host_block "example.com" "" "" ""
  
  run grep -q "^Host example.com$" "$TBLK"
  [ "$status" -eq 0 ]
  run grep -q "^  HostName" "$TBLK"
  [ "$status" -ne 0 ]
  
  rm -rf "$TMPDIR"
}
```

---

## Phase 2: Error Condition Tests (High Priority)

### Test Suite: `test_errors.bats`

Create new file: `tests/test_errors.bats`

#### Test 2.1: Invalid 1Password Response

```bash
@test "script handles empty 1Password response" {
  # Create mock op that returns empty JSON
  TMPDIR=$(mktemp -d)
  cat > "$TMPDIR/op" <<'EOF'
#!/usr/bin/env bash
echo '{}'
EOF
  chmod +x "$TMPDIR/op"
  
  PATH="$TMPDIR:$PATH"
  HOME="$TMPDIR/home"
  mkdir -p "$HOME/.ssh"
  
  # Should fail gracefully
  run "$SCRIPT" --host example.com --user test --pub-file "$HOME/.ssh/test.pub"
  [ "$status" -ne 0 ]
  
  rm -rf "$TMPDIR"
}
```

#### Test 2.2: Read-Only Config File

```bash
@test "script handles read-only config file" {
  TMPDIR=$(mktemp -d)
  HOME="$TMPDIR/home"
  mkdir -p "$HOME/.ssh"
  
  # Create read-only config
  touch "$HOME/.ssh/config"
  chmod 444 "$HOME/.ssh/config"
  
  # Should fail or warn
  run "$SCRIPT" --host example.com --user test --pub-file "$HOME/.ssh/test.pub"
  [ "$status" -ne 0 ]
  
  chmod 644 "$HOME/.ssh/config" || true
  rm -rf "$TMPDIR"
}
```

#### Test 2.3: Missing Parent Directory

```bash
@test "script creates missing directories for pub file" {
  TMPDIR=$(mktemp -d)
  HOME="$TMPDIR/home"
  
  # Don't create ~/.ssh directory
  run "$SCRIPT" --host example.com --user test --pub-file "$HOME/.ssh/keys/test.pub"
  
  # Should create the directory structure
  [ -d "$HOME/.ssh/keys" ]
  
  rm -rf "$TMPDIR"
}
```

#### Test 2.4: Invalid Key Type

```bash
@test "script rejects invalid --type argument" {
  run "$SCRIPT" --host example.com --user test --pub-file "$HOME/.ssh/test.pub" --type invalid
  
  # Current behavior: silently defaults to ed25519
  # Recommended: fail with error message
  # TODO: Add validation and update this test
}
```

#### Test 2.5: Special Characters in Hostname

```bash
@test "script handles special characters in hostname" {
  TMPDIR=$(mktemp -d)
  HOME="$TMPDIR/home"
  mkdir -p "$HOME/.ssh"
  
  # Test with hostname containing spaces (should fail)
  run "$SCRIPT" --host "example with spaces" --user test --pub-file "$HOME/.ssh/test.pub"
  
  # TODO: Should fail with validation error once validation is added
  
  rm -rf "$TMPDIR"
}
```

---

## Phase 3: Edge Case Tests (Medium Priority)

### Test Suite: `test_edge_cases.bats`

Create new file: `tests/test_edge_cases.bats`

#### Test 3.1: Empty Config File

```bash
@test "script handles empty config file" {
  TMPDIR=$(mktemp -d)
  HOME="$TMPDIR/home"
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/config"
  
  run "$SCRIPT" --host example.com --user test --pub-file "$HOME/.ssh/test.pub"
  [ "$status" -eq 0 ]
  
  # Should create default block
  grep -q "^Host \*$" "$HOME/.ssh/config"
  
  rm -rf "$TMPDIR"
}
```

#### Test 3.2: Very Long Hostname

```bash
@test "script handles very long hostname" {
  TMPDIR=$(mktemp -d)
  HOME="$TMPDIR/home"
  mkdir -p "$HOME/.ssh"
  
  # 255 character hostname (DNS max)
  local long_host=$(printf 'a%.0s' {1..255})
  
  run "$SCRIPT" --host "$long_host" --user test --pub-file "$HOME/.ssh/test.pub"
  
  # Should handle without truncation
  grep -q "^Host $long_host$" "$HOME/.ssh/config"
  
  rm -rf "$TMPDIR"
}
```

#### Test 3.3: Multiple Sequential Runs (Idempotency)

```bash
@test "script is idempotent when run multiple times" {
  TMPDIR=$(mktemp -d)
  HOME="$TMPDIR/home"
  mkdir -p "$HOME/.ssh"
  
  # Run three times
  "$SCRIPT" --host example.com --user test --pub-file "$HOME/.ssh/test.pub"
  "$SCRIPT" --host example.com --user test --pub-file "$HOME/.ssh/test.pub"
  "$SCRIPT" --host example.com --user test --pub-file "$HOME/.ssh/test.pub"
  
  # Should have exactly one Host example.com block
  count=$(grep -c "^Host example.com$" "$HOME/.ssh/config")
  [ "$count" -eq 1 ]
  
  rm -rf "$TMPDIR"
}
```

#### Test 3.4: Config with Many Blocks

```bash
@test "script handles config with 100+ host blocks" {
  TMPDIR=$(mktemp -d)
  HOME="$TMPDIR/home"
  mkdir -p "$HOME/.ssh"
  
  # Create config with 100 host blocks
  for i in {1..100}; do
    echo "Host host$i" >> "$HOME/.ssh/config"
    echo "  HostName host$i.example.com" >> "$HOME/.ssh/config"
    echo "" >> "$HOME/.ssh/config"
  done
  
  # Add new host
  "$SCRIPT" --host newhost --user test --pub-file "$HOME/.ssh/test.pub"
  
  # Should have 101 Host blocks
  count=$(grep -c "^Host " "$HOME/.ssh/config")
  [ "$count" -eq 101 ]
  
  rm -rf "$TMPDIR"
}
```

#### Test 3.5: Tilde Expansion in Paths

```bash
@test "script expands ~ in pub-file path" {
  HOME="$TMPDIR/home"
  mkdir -p "$HOME/.ssh"
  
  # Use ~ in path
  run "$SCRIPT" --host example.com --user test --pub-file "~/.ssh/test.pub"
  [ "$status" -eq 0 ]
  
  # Should create file at expanded path
  [ -f "$HOME/.ssh/test.pub" ]
}
```

#### Test 3.6: $HOME Expansion in Paths

```bash
@test "script expands \$HOME in pub-file path" {
  HOME="$TMPDIR/home"
  mkdir -p "$HOME/.ssh"
  
  # Use $HOME in path
  run "$SCRIPT" --host example.com --user test --pub-file "\$HOME/.ssh/test.pub"
  [ "$status" -eq 0 ]
  
  [ -f "$HOME/.ssh/test.pub" ]
}
```

---

## Phase 4: Integration Tests (Medium Priority)

### Enhance: `run_shell_tests.sh`

Add these tests to the existing `run_shell_tests.sh` file:

#### Test 4.1: Backup File Verification

```bash
TEST6="backup files are created with timestamps"
# Pre-create a config file
mkdir -p "$TESTDIR/test6-home/.ssh"
cat > "$TESTDIR/test6-home/.ssh/config" <<'EOF'
Host oldhost
  HostName old.example.com
EOF

if run_cmd "test6" "$TEST6" "$SCRIPT" --host example.com --user testuser --pub-file "$TESTDIR/test6-home/.ssh/id_test.pub"; then
  # Should have created a backup
  if ls "$TESTDIR/test6-home/.ssh/config.bak."* >/dev/null 2>&1; then
    ok "$TEST6"
  else
    no "$TEST6"
  fi
else
  no "$TEST6"
fi
```

#### Test 4.2: Config Permissions Verification

```bash
TEST7="config file has correct permissions (600)"
if run_cmd "test7" "$TEST7" "$SCRIPT" --host example.com --user testuser --pub-file "$TESTDIR/test7-home/.ssh/id_test.pub"; then
  # Check file permissions
  perms=$(stat -f %A "$TESTDIR/test7-home/.ssh/config" 2>/dev/null || stat -c %a "$TESTDIR/test7-home/.ssh/config" 2>/dev/null)
  if [ "$perms" = "600" ]; then
    ok "$TEST7"
  else
    no "$TEST7 (permissions: $perms)"
  fi
else
  no "$TEST7"
fi
```

---

## Phase 5: Performance Tests (Low Priority)

### Test Suite: `test_performance.bats`

Create new file: `tests/test_performance.bats` (optional)

#### Test 5.1: Large Config File Performance

```bash
@test "script handles large config file efficiently" {
  TMPDIR=$(mktemp -d)
  HOME="$TMPDIR/home"
  mkdir -p "$HOME/.ssh"
  
  # Create config with 1000 host blocks
  for i in {1..1000}; do
    echo "Host host$i" >> "$HOME/.ssh/config"
    echo "  HostName host$i.example.com" >> "$HOME/.ssh/config"
  done
  
  # Time the operation (should complete in reasonable time)
  start=$(date +%s)
  "$SCRIPT" --host newhost --user test --pub-file "$HOME/.ssh/test.pub"
  end=$(date +%s)
  
  duration=$((end - start))
  [ "$duration" -lt 5 ] # Should complete in under 5 seconds
  
  rm -rf "$TMPDIR"
}
```

---

## Implementation Checklist

### Phase 1: Helper Functions (Week 1)

- [ ] Create `tests/test_helpers.bats`
- [ ] Implement tests 1.1-1.4 (fp_from_pub)
- [ ] Implement tests 1.5-1.7 (fp_from_file)
- [ ] Implement tests 1.8-1.9 (ensure_default_block)
- [ ] Implement tests 1.10-1.11 (render_host_block)
- [ ] Run: `bats tests/test_helpers.bats`
- [ ] Fix any failures

### Phase 2: Error Conditions (Week 1-2)

- [ ] Create `tests/test_errors.bats`
- [ ] Implement tests 2.1-2.5
- [ ] Add input validation to script (if tests reveal gaps)
- [ ] Run: `bats tests/test_errors.bats`
- [ ] Fix any failures

### Phase 3: Edge Cases (Week 2)

- [ ] Create `tests/test_edge_cases.bats`
- [ ] Implement tests 3.1-3.6
- [ ] Run: `bats tests/test_edge_cases.bats`
- [ ] Fix any edge case bugs discovered

### Phase 4: Integration (Week 2-3)

- [ ] Add tests 4.1-4.2 to `run_shell_tests.sh`
- [ ] Run: `bash tests/run_shell_tests.sh`
- [ ] Fix any integration issues

### Phase 5: Performance (Optional)

- [ ] Create `tests/test_performance.bats`
- [ ] Implement test 5.1
- [ ] Profile and optimize if needed

---

## Running All Tests

### Quick Test

```bash
# Run all BATS tests
bats tests/*.bats

# Run shell integration tests
bash tests/run_shell_tests.sh
```

### Comprehensive Test

```bash
# Create test runner script
cat > tests/run_all_tests.sh <<'EOF'
#!/bin/bash
set -e

echo "================================"
echo "Running All Test Suites"
echo "================================"
echo ""

echo "→ Helper Function Tests"
bats tests/test_helpers.bats

echo ""
echo "→ Upsert Function Tests"
bats tests/test_upsert.bats
bats tests/test_upsert_extra.bats

echo ""
echo "→ Error Condition Tests"
bats tests/test_errors.bats

echo ""
echo "→ Edge Case Tests"
bats tests/test_edge_cases.bats

echo ""
echo "→ Shell Integration Tests"
bash tests/run_shell_tests.sh

echo ""
echo "================================"
echo "✅ All tests passed!"
echo "================================"
EOF

chmod +x tests/run_all_tests.sh
./tests/run_all_tests.sh
```

---

## Success Criteria

**Phase 1 Complete:**

- ✅ All 6 helper functions have unit tests
- ✅ All tests passing
- ✅ Coverage: 14/31 tests

**Phase 2 Complete:**

- ✅ All error conditions tested
- ✅ Input validation added to script
- ✅ Coverage: 19/31 tests

**Phase 3 Complete:**

- ✅ All edge cases tested
- ✅ Idempotency verified
- ✅ Coverage: 25/31 tests

**Phase 4 Complete:**

- ✅ Integration workflow verified
- ✅ File permissions correct
- ✅ Backups working
- ✅ Coverage: 27/31 tests

**Final Goal:** 31/31 tests passing (100% coverage)

---

## Maintenance

After implementation:

1. **Update this document** when tests are added
2. **Run tests before commits** (add to pre-commit hook)
3. **Add CI/CD** to run tests on push (GitHub Actions)
4. **Monitor test execution time** and optimize if needed
5. **Add new tests** when bugs are discovered

---

## Notes

- All tests should be self-contained and use temporary directories
- Mock external dependencies (op, ssh-keygen, etc.)
- Tests should clean up after themselves
- Use descriptive test names that explain what is being tested
- Group related tests together
- Add comments for complex test logic
