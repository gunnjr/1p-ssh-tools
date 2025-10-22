<!-- markdownlint-disable -->
# TODO: Code Review and Testing Tasks

## Status: Ready for Fresh Code Review

### What We Just Completed (Oct 22, 2025)
- ✅ Successfully migrated test files to new location (`tests/` directory)
- ✅ Made `scripts/op-ssh-addhost.sh` testable by:
  - Adding `OPSSH_TEST_MODE` environment variable support
  - Extracted 6 functions to dedicated section (lines 76-193)
  - Wrapped main execution in test mode conditional
- ✅ Updated test paths to work from new location
- ✅ All tests passing: 3 BATS tests + 5 shell tests

### Next Session: Fresh Code Review

**Primary Goal:** Comprehensive review of `scripts/op-ssh-addhost.sh`

**Review Areas:**
1. **Code Quality & Structure**
   - Function organization and clarity
   - Variable naming and scope
   - Error handling completeness
   - Edge case handling

2. **Testing Coverage**
   - Review existing BATS tests (`test_upsert.bats`, `test_upsert_extra.bats`)
   - Review existing shell tests (`run_shell_tests.sh`)
   - Identify gaps in test coverage
   - Add tests for:
     - Individual helper functions (`fp_from_pub`, `fp_from_file`, `ensure_default_block`, `render_host_block`)
     - Error conditions and edge cases
     - 1Password integration scenarios
     - File permission handling
     - Config backup functionality

3. **Potential Improvements**
   - Documentation/comments
   - Error messages clarity
   - Dry-run mode coverage
   - Interactive prompts handling

**Test Files to Review:**
- `tests/test_upsert.bats` - Currently tests `upsert_host_block` only
- `tests/test_upsert_extra.bats` - Tests multi-token hosts and comment preservation
- `tests/run_shell_tests.sh` - Integration tests with mocked `op` command

**Questions to Address:**
- Are there untested code paths?
- Do we need unit tests for the helper functions?
- Should we test error conditions more thoroughly?
- Is the test mode implementation complete and safe?

---

## Other Scripts Requiring Code Review and Testing

### 1. `scripts/op-ssh-keygen.sh`
**Purpose:** Generates or retrieves SSH key pairs in 1Password and exports public keys locally

**Review Needs:**
- Code quality and structure review
- Error handling validation
- Edge case testing
- Add unit tests for key functions
- Integration testing with mocked `op` command
- Test key generation workflows
- Test key retrieval from existing items

### 2. `scripts/op-ssh-status.sh`
**Purpose:** Displays local SSH configuration, key fingerprints, and 1Password matches

**Review Needs:**
- Code quality and structure review
- Output formatting validation
- Test fingerprint comparison logic
- Test detection of missing/mismatched configurations
- Mock 1Password responses for testing
- Test various SSH config scenarios

### 3. `scripts/op-ssh-show-pubkey.sh`
**Purpose:** Retrieves and displays public keys from 1Password

**Review Needs:**
- Code quality and structure review
- Error handling for missing keys
- Test key retrieval and display
- Test clipboard functionality
- Mock 1Password responses
- Test various key formats (ed25519, RSA, etc.)

**Testing Strategy for All Scripts:**
- Create BATS test files for each script
- Add integration tests similar to `run_shell_tests.sh`
- Mock external dependencies (op, ssh-keygen, etc.)
- Test error conditions and edge cases
- Ensure all scripts support test mode if needed

---

## Current Test Status

```text
BATS Tests: 3/3 passing
Shell Tests: 5/5 passing
Total: 8/8 passing
```

**Scripts with tests:** `op-ssh-addhost.sh` only
**Scripts needing tests:** `op-ssh-keygen.sh`, `op-ssh-status.sh`, `op-ssh-show-pubkey.sh`

---

## Future: CI/CD and Automated Regression Testing

### Benefits of Current Test Setup
✅ **Automated test suites ready for CI/CD integration**
- All tests self-contained and reproducible
- Mock external dependencies (no 1Password account needed)
- Clear pass/fail exit codes
- Runs in isolated temporary directories

### Automation Options

#### 1. GitHub Actions (Recommended)
Create `.github/workflows/test.yml`:

```yaml
name: Test Suite

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest  # or ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install BATS
        run: |
          brew install bats-core
          # or: npm install -g bats
      
      - name: Run BATS tests
        run: bats tests/*.bats
      
      - name: Run shell integration tests
        run: bash tests/run_shell_tests.sh
      
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: tests/*.log
```

#### 2. Pre-commit Hook
Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash
echo "Running tests before commit..."

# Run BATS tests
if ! bats tests/*.bats; then
    echo "❌ BATS tests failed. Commit aborted."
    exit 1
fi

# Run shell tests
if ! bash tests/run_shell_tests.sh; then
    echo "❌ Shell tests failed. Commit aborted."
    exit 1
fi

echo "✅ All tests passed!"
exit 0
```

Make it executable: `chmod +x .git/hooks/pre-commit`

#### 3. Make Target for Easy Testing
Create `Makefile`:

```makefile
.PHONY: test test-bats test-shell test-all

test-bats:
	@echo "Running BATS tests..."
	@bats tests/*.bats

test-shell:
	@echo "Running shell integration tests..."
	@bash tests/run_shell_tests.sh

test: test-bats test-shell

test-all: test
	@echo "✅ All tests passed!"

watch:
	@echo "Watching for changes..."
	@while true; do \
		inotifywait -q -e modify scripts/*.sh tests/*.bats tests/*.sh 2>/dev/null && \
		make test; \
	done
```

Usage: `make test` or `make watch` (requires `inotifywait`)

#### 4. Simple Test Runner Script
Create `tests/run_all_tests.sh`:

```bash
#!/bin/bash
set -e

echo "=========================================="
echo "Running All Tests"
echo "=========================================="

echo ""
echo "→ Running BATS tests..."
bats tests/*.bats

echo ""
echo "→ Running shell integration tests..."
bash tests/run_shell_tests.sh

echo ""
echo "=========================================="
echo "✅ All tests passed!"
echo "=========================================="
```

### Implementation Priority
1. **Now:** Add `tests/run_all_tests.sh` for easy local testing
2. **Soon:** Set up GitHub Actions for automated CI/CD
3. **Optional:** Add pre-commit hooks for local validation
4. **Optional:** Create Makefile for convenience

### Regression Testing Benefits
- 🔒 **Prevent breaking changes** - Tests fail immediately if functionality breaks
- 🚀 **Refactor with confidence** - Improve code knowing tests will catch issues
- 📝 **Living documentation** - Tests show how the code should work
- 🐛 **Bug prevention** - Add test for each bug fix to prevent recurrence
- ⚡ **Fast feedback** - Know within seconds if changes break anything
