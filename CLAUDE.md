# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` is the long-form coding-agent reference (style, naming, idempotency
patterns, helper inventory, step skeleton). Read it for anything not covered
here. README.md is the user-facing overview. The lowercase `claude.md` is an
older redundant stub — prefer AGENTS.md.

## Commands

```bash
./install.sh            # run every steps/*.sh in glob order
DEBUG=1 ./install.sh    # also surface log_debug ("already done, skipping") lines
bash steps/02_packages.sh   # run a single step in isolation; safe to repeat

./diff-check.sh         # list deployed configs/scripts that drift from the repo
./diff-check.sh -d      # also print unified diffs for changed files
DEBUG=1 ./diff-check.sh # also list files that already match

shellcheck steps/*.sh lib/*.sh install.sh diff-check.sh   # no CI runs this; do it manually
```

There are no tests, no linters, and no CI. Validation is "run it on a Fedora
Sway box." `install.sh` aborts on the first failing step (`bash "$step" || exit 1`).

`logging.sh` always appends to `~/.local/share/fedora-setup/install.log` in
addition to stdout — useful when a step fails silently or far up the
scrollback.

## Architecture

Linear pipeline. `install.sh` glob-sorts `steps/*.sh` and runs each as a
standalone bash process. There is no shared state between steps beyond what
they read from disk (`rpm -q`, `dnf repolist`, `~/.config/...`). Each step
re-bootstraps the same way:

```bash
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"   # must come first — utils.sh asserts log_info exists
source "$SCRIPT_DIR/lib/utils.sh"
```

Three layers stacked top-down:

1. **`lib/`** — primitives. `logging.sh` provides `log_info/warn/error/debug`
   (debug only fires when `DEBUG=1`). `utils.sh` provides the `ensure_*`
   check-then-act helpers — `ensure_package`, `ensure_repo`, `ensure_symlink`,
   `ensure_file_copy`, `ensure_user_in_group`, `run_sudo`, `check_command`.
   These are the unit of work; new steps should compose them rather than
   reinvent the check-then-act pattern.
2. **`steps/`** — orchestration. The two-digit prefix is the architecture, not
   just sorting:
   - `00–09` base system (sudoers, upgrade, env, repos, packages, SELinux,
     flatpaks, aliases, sysrq, swap, earlyoom, timezone, VS Code, fonts)
   - `10–19` tools fetched/built out of band (LazyVim, gsettings, Docker,
     vpn-slice, wayfreeze, Satty, yazi)
   - `20–29` config deployment, color schemes, desktop entries, zsh, calendar
     sync
   - `30+` user scripts and finishing touches
3. **`config/`, `scripts/`, `files/`** — payload. Mostly inert; deployed by a
   couple of dispatcher steps.

### Two coupled dispatcher steps

`steps/20_config.sh` and `steps/30_scripts.sh` are bulk-deploy steps that
copy the bulk of the payload. Specifically, `20_config.sh` defines a
`config_step_copy_collection` of source/target pairs; adding a new dotfile
means appending a pair there.

**`diff-check.sh` mirrors these lists.** Section 1 of `diff-check.sh`
(`CONFIG_PAIRS`) and Sections 2–4 (Scripts, Desktop entries, Calendar sync)
must be kept in sync with the matching steps. When you add a file to
`steps/20_config.sh` or `steps/30_scripts.sh`, also add it to
`diff-check.sh` or drift detection will silently miss it.

### Idempotency contract

Every step is expected to be re-runnable with no surprises. The standard
pattern is `if [[ already-done ]]; then log_debug "skip"; else log_info
"do"; ... fi`. Most of the time the `ensure_*` helpers already implement
this — reach for them first. `install.sh` calls every step on every run, so
"do nothing if already done" is the default branch, not the exception.

### Optional vs. core

`optional/` is **not** run by `install.sh`. Each subdirectory has its own
`setup.sh` and is opt-in. `diff-check.sh` checks optional/ files with a
`true` flag that silently skips when the optional component was never
installed.

## Repos and external dependencies

`steps/01_repos.sh` enables RPM Fusion (free + nonfree), Flathub, Vivaldi,
git-secret, and Terra (`fyralabs`). Several packages used elsewhere come
from these — when `dnf install` of a package fails, double-check
`01_repos.sh` ran first. `02_packages.sh` is a single big array iterated
through `ensure_package`; for anything that needs swap/`--allowerasing`
semantics (e.g. file-conflicting forks), it needs its own dedicated step,
not an array entry.

### Known dep-chain trap: swaylock

Fedora's `sway-config-fedora` package hard-requires the literal `swaylock`
package and ships infrastructure the user's sway session actually uses
(`/usr/libexec/sway/layered-include`, `/usr/share/sway/config.d/*.conf`,
`start-sway`, the sway `.desktop` session entry). Replacing `swaylock` with
any fork (Terra's `swaylock-effects`, COPR variants) currently fails because
none of those packages declare `Provides: swaylock`. Source-build to
`/usr/local/bin/<name>` or a locally-rebuilt RPM with `Provides: swaylock`
are the workable paths if a swap is ever needed.

## Conventions worth knowing up front

- Comments may be Czech or English; user-facing strings (logs, prompts) are
  English. Don't "translate" existing Czech comments — leave them.
- `set -euo pipefail` everywhere. Two-space indent. `[[ ]]` not `[ ]`. Quote
  expansions. `$( )` not backticks.
- Step numbering ranges are documented above and in AGENTS.md — pick a
  number in the right range when adding a new step.
- Recent commit message style is short, scoped, lowercase: `area/file: what
  changed` (e.g. `waybar/launchers: drop wezterm, …`). One-line is normal.
