# Linting and Code Style

This project uses a simple linting script, `lint.sh`, to enforce shell script style and catch common errors.

- **shellcheck**: Lints all scripts in the `scripts/` directory for best practices and common mistakes.
- **shfmt** (optional): Auto-formats scripts for consistent style if installed.

## Usage

From the project root, run:

```bash
./scripts/lint.sh
```

Or to lint a specific file:

```bash
./scripts/lint.sh scripts/op-ssh-addhost.sh
```

Install `shellcheck` and `shfmt` via Homebrew (macOS) or your package manager:

```bash
brew install shellcheck shfmt
```

All contributors are encouraged to run the linter before submitting changes.
