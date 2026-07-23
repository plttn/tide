# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## What this is

Tide is an asynchronous prompt for the [Fish shell][fish], installed as a Fisher plugin. This is `plttn/tide`, a fork of `IlanCosman/tide`. All work here targets `plttn/tide` — never open PRs against upstream `IlanCosman/tide`.

Everything is written in Fish script (`.fish`); there is no build step or compiled artifact.

## Commands

All tasks are run via [mise][mise] (use `mise`, not `make`):

- `mise run all` — fmt, lint, install, test (the standard pre-PR check)
- `mise run fmt` — format all `.fish` files with `fish_indent`
- `mise run lint` — syntax-check all `.fish` files via `fish --no-execute`
- `mise run install` — install Tide + test deps (fisher, clownfish) into the current Fish config
- `mise run test` — run the full littlecheck suite (`scripts/test.fish`)
- `mise run test-clean` — wipe the cached local test `HOME` (`scripts/test_clean.fish`) if the test env gets into a bad state

### Running a single test

Tests are [littlecheck][littlecheck] `.fish` files under `tests/`, each a self-contained script with `# CHECK:` comments asserting stdout. Run one directly:

```fish
python3 littlecheck.py tests/_tide_item_node.test.fish
```

(`littlecheck.py` is fetched by `mise run littlecheck`, a dependency of `mise run test`.) A local run reuses a persistent `HOME` (`$XDG_CACHE_HOME/tide-test-home` or `~/.cache/tide-test-home`) so `fisher`/`clownfish` aren't reinstalled every run; `mise run install` still resyncs local edits into it. In CI (`GITHUB_ACTIONS=true`) this caching is skipped and everything runs in a clean environment.

Test files mock external commands (e.g. `node`, `git`) via [clownfish][clownfish]'s `mock` function — see `tests/_tide_item_node.test.fish` for the pattern. `tests/test_setup.fish` defines `_tide_decolor` (strips ANSI codes for assertions) and sets `_tide_side` for right-prompt items.

## Architecture

### Item-based prompt composition

The prompt is built from **items** — one function per prompt segment, named `_tide_item_<name>.fish` in `functions/`. Each item function:

- Reads config from user-exposed `tide_<item>_*` variables (colors, icons, thresholds)
- Detects whether it's relevant (e.g. `_tide_item_node` checks `$_tide_parent_dirs` for `package.json` and that `node` is on PATH) and prints nothing if not
- Calls `_tide_print_item <name> <content...>` (`functions/_tide_print_item.fish`) to emit its segment, which handles background/foreground coloring and separators between adjacent items based on `tide_<side>_prompt_items`

Which items appear and in what order is controlled by the universal variables `tide_left_prompt_items` / `tide_right_prompt_items`, set by the configuration wizard or by hand.

### Rendering pipeline

`functions/fish_prompt.fish` is the entry point Fish calls to render a prompt. On each render it:

1. Kicks off a **background job** (a second `fish -c ...` subprocess) that computes the actual prompt content by calling `_tide_1_line_prompt` or `_tide_2_line_prompt` (chosen at load time based on whether `newline` is in `$_tide_left_items`), and stores the result in a per-PID universal variable `_tide_prompt_$fish_pid`
2. Immediately returns a (possibly stale) previous render so the shell never blocks
3. When the background job writes the uvar, `_tide_refresh_prompt` (an `--on-variable` handler) triggers `commandline -f repaint`, which re-renders `fish_prompt`/`fish_right_prompt` with the fresh content

This async design is why Tide can afford expensive checks (e.g. full git status with untracked/modified/deleted counts) that would make a synchronous prompt feel slow. `fish_prompt.fish` itself is built with a large `eval "..."` block assembled once at shell-init time (varies by one-line vs two-line, frame-enabled vs not) rather than branching on every render, since load time matters more than per-render branching cost here.

`_tide_1_line_prompt.fish` / `_tide_2_line_prompt.fish` iterate the configured items and concatenate their `_tide_print_item` output per side.

### VCS item internals

`_tide_item_vcs.fish` dispatches between git and [jj (Jujutsu)][jj] backends:

- `_tide_internal_jj_git.fish` walks up from `$PWD` looking for a `.jj` directory to decide if this is a jj repo (and whether `.disable-jj-prompt` opts back out)
- If in a jj repo and the `jj` binary is available, `_tide_internal_vcs_jj.fish` renders; otherwise `_tide_internal_vcs_git.fish` handles git (and jj-repos-backed-by-git without the jj CLI)

The git backend minimizes subprocess spawns (currently 3 git invocations) since each is a real fork/exec cost inside an already-forked background job.

### Configuration wizard

`tide configure` (`functions/_tide_sub_configure.fish`) is a self-contained interactive TUI, not part of the render path. It walks a decision tree defined by `.fish` files under `functions/tide/configure/choices/{all,lean,classic,powerline,rainbow}/**` and `functions/tide/configure/functions/`, previewing changes live using `fake_columns`/`fake_lines` and no-op stand-ins for every `_tide_item_*` function. See `ARCHITECTURE.md` for the full choice flowchart. Chosen values are written out via `functions/tide/configure/configs/`.

### Subcommands

`tide` (`functions/tide.fish`) dispatches to `_tide_sub_<name>` functions (`configure`, `reload`, `bug-report`) — adding a subcommand means adding a new `_tide_sub_<name>.fish`.

### Init / lifecycle hooks

`conf.d/_tide_init.fish` wires up Fisher's `_tide_init_install` / `_tide_init_update` / `_tide_init_uninstall` events — first-install onboarding, version-migration shims (e.g. `_tide_migrate_vcs_prompt_items`), and cleanup of all `tide_*`/`_tide_*` functions and universal variables on uninstall.

## Conventions

(Full detail in `CONTRIBUTING.md` — key points below.)

- Style: prefer `test` over `[ ]`; prefer `&&`/`||` over `and`/`or` for simple conditionals, `if`/`else`/`else if` for anything more complex; prefer piping over command substitution when it doesn't require extra commands.
- Naming: everything `snake_case`. User-facing names (variables, functions, files) are prefixed `tide_`; internal-only names are prefixed `_tide_`. Items live in `_tide_item_<name>.fish`; subcommands in `_tide_sub_<name>.fish`.
- PRs merge via a real merge commit (not squash), so every commit — not the PR title — must follow [Conventional Commits][conventional-commits] (`<type>[(scope)][!]: <description>`); [release-please][release-please] reads commits directly off `main` to generate the changelog. This is CI-enforced per-commit.
- Releases are fully automated by release-please; don't hand-edit `functions/tide.fish`'s version string or the floating `vN`/`vN.M` tags.

[clownfish]: https://github.com/IlanCosman/clownfish
[conventional-commits]: https://www.conventionalcommits.org/
[fish]: https://fishshell.com/
[jj]: https://jj-vcs.github.io/jj/latest/
[littlecheck]: https://github.com/ridiculousfish/littlecheck
[mise]: https://mise.jdx.dev/
[release-please]: https://github.com/googleapis/release-please
