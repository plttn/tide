#!/usr/bin/env fish

set -l inner_cmd "
type -q fisher || begin
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source #when running in CI like GHA, we'll have already installed Fisher so this is a no-op
    fisher install jorgebucaran/fisher
end
fisher install . >/dev/null
type -q mock || fisher install IlanCosman/clownfish
fish tests/test_cleanup.fish
fish tests/test_setup.fish
_tide_remove_unusable_items
_tide_cache_variables
python3 littlecheck.py --progress tests/**.test.fish
set -l test_status \$status
fish tests/test_cleanup.fish
exit \$test_status
"

# Always run against an isolated HOME so tests can never write into the real
# fish config -- even if GITHUB_ACTIONS happens to be set in a local shell
# (this previously ran the "normal" branch below unguarded and clobbered a
# real ~/.config/fish/fish_variables).
if test "$GITHUB_ACTIONS" = true
    # CI runners are already fresh/ephemeral, so there's nothing worth
    # caching across runs -- a throwaway dir is enough.
    set -l test_home (mktemp -d)
    env HOME=$test_home XDG_CONFIG_HOME=$test_home/.config fish -c $inner_cmd
else
    # Reuse a persistent HOME across local runs (shared across worktrees) so
    # fisher/clownfish aren't reinstalled over the network every time. `fisher
    # install .` still runs unconditionally, so local edits are always synced.
    # Run `mise run test-clean` to wipe it if it ever gets into a bad state.
    set -l cache_home $XDG_CACHE_HOME
    test -n "$cache_home" || set cache_home $HOME/.cache
    set -l test_home $cache_home/tide-test-home
    mkdir -p $test_home
    env HOME=$test_home XDG_CONFIG_HOME=$test_home/.config fish -c $inner_cmd
end
exit $status
