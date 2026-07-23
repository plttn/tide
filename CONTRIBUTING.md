# Contributing

🌊 Thank you for contributing to Tide! 🌊

If you have any questions that aren't addressed in this document, please don't hesitate to open an issue!

## Code Conventions

### Style Guide

- `test` > `[...]`
- `&&`/`||` > `and`/`or`
- Conditionals
  - For simple conditionals use `&&`/`||`
    - Ex: `test -n "$foo" && echo "foo is not empty"`
    - Ex: `foo || bar || baz`
  - For anything more complex use `if`, `else`, and `else if`
- Piping > command substitution (only when convenient, i.e no extra commands)

### Pull Requests

PRs are merged into `main` with a real merge commit, not squashed. Because of
that, every commit in the PR — not just the title — must follow
[Conventional Commits][]: `<type>[(scope)][!]: <description>`, e.g.
`fix: correct jj branch color` or `feat(vcs)!: unify git/jj into a single
item`. [release-please][] reads these commits directly off `main` to
generate the next release's changelog entry. A CI check (`commit-lint`)
enforces this on every commit in the PR.

- Allowed types: `feat`, `fix`, `build`, `chore`, `ci`, `docs`, `style`, `refactor`, `perf`, `test`, `revert`.
- Add `!` before the `:` (or a `BREAKING CHANGE:` footer) for breaking changes.

The PR title itself has no format requirement — write it as plain,
descriptive text for anyone skimming the PR list.

Each pull request should only impact a single `<type>(scope)`. In other words,
a PR with only `fix: correct branch color` commits or only
`feat(foobar): ...` commits is acceptable, but mixing `perf(docker): ...` and
`perf(kubectl): ...` commits in the same PR is not.

This is to keep the changelog generating cleanly off `main`'s commit history.

### Naming Conventions

- Everything should be in `snake_case`.
- Anything exposed to the user (variables, files, functions) should begin with `tide_`.
- If the user isn't meant to interact with it from the commandline, prepend an underscore.
- If the function only exists to be accessed by tide, it should begin with `_tide_internal_`

Examples:

- `set -l split_pwd`
- `set -U tide_right_prompt_items`
- `_tide_detect_os.fish`
- `_tide_print_item`
- `_tide_internal_jj_git.fish`

#### Specific Naming Conventions

- Items begin with `_tide_item_`
- Subcommands begin with `_tide_sub_`

## Mise Tasks

Primary development tasks will be `fmt`, `lint`, and `test`.

- `install`
  - Installs the current state of the directory using fisher to your real fish
    environment. This probably isn't what you intend to do.
- `fmt`
  - Formats files to meet fish standards. This is a must pass for PRs.
- `lint`
  - Validates that all files are valid fish files. This is also a must pass for PRs.
- `test`
  - Creates a local environment for testing and performs the tests. This will not
    impact your real environment.
- `test-clean`
  - Cleans up the test homedir used by `test`.

### Specifics

- [Littlecheck][] - Test driver for command line tools
- [Clownfish][] - Override the behavior of commands
- Code linting is done via [`fish --no-execute`][].
- Markdown and Yaml linting is done via the [Mega-Linter][] action.
- Code formatting is done via [`fish_indent`][].
- Markdown and Yaml formatting is done via [Prettier][].

## Documentation Conventions

All links should be in reference style, with references at the bottom of the document in alphabetical order.

### Images

- Gnome DE
- Blackbox terminal
  - Show Header Bar: off
  - Padding: 12
  - Default color scheme
- Stitches: Dont stack frames, output image quality 100

#### Specifics

- Header: 13pt, 55x16
- Configuration Wizard: 17pt, 70x21
  - Stitch delays:
  - | 80  | 10  | 10  | 10  | 10  | 14  | 10  | 30  |
    | --- | --- | --- | --- | --- | --- | --- | --- |
    | 80  | 110 | 110 | 110 | 110 | 110 | 110 | 110 |
    | 110 | 110 | 110 | 110 | 300 |     |     |     |
- Flexible: 13pt, 56x4
- Extendable: 13pt, 55x9
- PWD: 17pt, 42x14

## Releasing

Releases are automated by [release-please][]. It watches `main` and keeps an
open "release PR" containing the next version bump and a generated
`CHANGELOG.md` entry, derived from Conventional Commit messages on `main`
since the last release. Merge commits themselves carry GitHub's default
message ("Merge pull request #N from branch"), which never matches the
Conventional Commits pattern, so release-please skips them and reads only
the PR's individual commits.

- [ ] Before merging the release PR, hand-edit its `CHANGELOG.md` diff to
      clean up the generated bullets into prose, and add any narrative
      notes (e.g. security callouts, migration instructions, wiki links)
- [ ] Merge the release PR
- [ ] release-please tags the release, publishes it on GitHub, and updates
      `functions/tide.fish`'s version string automatically
- [ ] The floating `vN`/`vN.M` convenience tags (used by `fisher install
      plttn/tide@v7`) update automatically in a follow-up job

[`fish --no-execute`]: https://fishshell.com/docs/current/cmds/fish.html
[`fish_indent`]: https://fishshell.com/docs/current/cmds/fish_indent.html
[clownfish]: https://github.com/IlanCosman/clownfish
[conventional commits]: https://www.conventionalcommits.org/
[littlecheck]: https://github.com/ridiculousfish/littlecheck
[mega-linter]: https://github.com/nvuillam/mega-linter
[prettier]: https://github.com/prettier/prettier
[release-please]: https://github.com/googleapis/release-please
