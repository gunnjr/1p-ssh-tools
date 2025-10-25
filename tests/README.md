# 1Password SSH Tools – Test Suite

This directory contains automated and helper tests for the 1Password SSH Tools project. Tests are organized by tool, and use a mix of Bash and [Bats](https://github.com/bats-core/bats-core) for functional and unit-style testing.

## Structure

- `op-ssh-addhost/` – Tests for `op-ssh-addhost.sh`
- `op-ssh-keygen/` – Tests for `op-ssh-keygen.sh`
- `op-ssh-show-pubkey/` – Tests for `op-ssh-show-pubkey.sh`
- `op-ssh-status/` – Tests for `op-ssh-status.sh`

Each subdirectory may contain:
- `*_functional.sh` – End-to-end or integration tests (Bash)
- `*_helpers.bats` – Unit or helper tests (Bats)
- `*_upsert.bats` – Specific logic/unit tests (Bats)

## Running Tests

### Bats Tests

To run all Bats tests:

```bash
bats tests/**/*.bats
```

Or run a specific test file:

```bash
bats tests/op-ssh-addhost/test_addhost_helpers.bats
```

### Bash Functional Tests

To run a functional test script:

```bash
bash tests/op-ssh-addhost/test_addhost_functional.sh
```

Some tests may require 1Password CLI sign-in and/or may modify files in a test environment. Review scripts before running.

## Test Dependencies

- [Bats](https://github.com/bats-core/bats-core) (for `.bats` files)
- 1Password CLI, jq, ssh-keygen, and other project dependencies

## Notes

- Tests are designed to be safe, but always review before running in sensitive environments.
- Contributions of new or improved tests are welcome!
