# fspi - Fedora Sway Post-Install

Idempotent shell script framework for setting up a Fedora Sway desktop environment.

## Structure

```
fspi/
├── install.sh          # Main entry point - runs all steps in order
├── lib/
│   ├── logging.sh      # log_info, log_warn, log_error, log_debug
│   └── utils.sh        # Helper functions (see below)
├── steps/              # Numbered scripts executed sequentially (00-99)
├── config/             # Dotfiles copied to ~/.config/
├── scripts/            # User scripts copied to ~/scripts/
└── files/              # Other files to be installed
```

## Running

```bash
DEBUG=1 ./install.sh    # Run with debug output
./install.sh            # Run normally
```

## Adding packages

Add to the `PACKAGES` array in `steps/02_packages.sh`.

## Adding a new step

Create `steps/XX_name.sh` where XX determines execution order:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step description"

# ... your code ...

log_info "Step complete"
```

## Key utility functions (lib/utils.sh)

- `ensure_package "pkg"` - Install package if not present
- `ensure_repo "name" "url"` - Add dnf repo if not present
- `ensure_symlink "target" "dest"` - Create symlink idempotently
- `ensure_file_copy "src" "dest"` - Copy file if changed
- `ensure_user_in_group "user" "group"` - Add user to group
- `run_sudo "cmd"` - Run command with sudo if not root
- `check_command "cmd"` - Check if command exists (returns bool)

## Notes

- All steps must be idempotent (safe to run multiple times)
- Use `log_debug` for verbose output (shown when DEBUG=1)
- Config files in `config/X/` are typically symlinked to `~/.config/X/`
