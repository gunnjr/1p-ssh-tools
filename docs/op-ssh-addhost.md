op-ssh-addhost — Usage, testing, and notes

Purpose
-------
This document describes the `op-ssh-addhost` helper script: what it does, how to run it, and how to test it locally without touching your real 1Password data.

Location
--------
Note: in your environment the production script lives at a local path outside the repo (for example: `/Users/John.Gunn/Library/CloudStorage/OneDrive-Personal/dev/bin/op-ssh-addhost.sh`). The repo copy (if you want one) can be placed under `dev/bin/` in this repository.

Quick usage
-----------
Preview changes, no writes:

```bash
/path/to/op-ssh-addhost.sh --host example.com --user me --pub-file ~/.ssh/id_example.pub --dry-run
```

Write changes (be careful):

```bash
/path/to/op-ssh-addhost.sh --host example.com --user me --pub-file ~/.ssh/id_example.pub
```

Testing locally (safe, mock `op`)
---------------------------------
A dependency-free test harness is available at `dev/bin/tests/run_shell_tests.sh` in the repo (or in your workspace). It uses a mock `op` that returns a deterministic public key and verifies:

- dry-run produces no file writes
- creating the .pub file from 1Password data
- upserting the Host block into `~/.ssh/config`

To run it (from repo root):

```bash
dev/bin/tests/run_shell_tests.sh
```

Note: The test harness runs the current production script referenced by `SCRIPT` inside it. If you want tests to target the repo copy, either copy the script into `dev/bin/` or modify the `SCRIPT` variable inside the test harness.

CI and pytest (optional next steps)
-----------------------------------
If you'd like CI or pytest based tests I can scaffold:

- `tests/test_op_ssh_addhost.py` — pytest tests using a temporary directory and a mocked `op` command
- `.github/workflows/ci.yml` — run shellcheck, bash -n, and pytest on push/PR

If you want those in the repo, tell me and I'll add them under the repo root.

Notes & caveats
---------------
- The script expects the 1Password CLI (`op`) and `jq`. For tests we use a mock `op` to avoid contacting real 1Password.
- The script now expands `~` and literal `$HOME` in `--pub-file` values, making it more robust when callers pass those forms.

Contact
-------
If you tell me where you'd like the production script stored in the repo, I can copy it there and update tests/CI to target the repo copy instead of the local production path.
