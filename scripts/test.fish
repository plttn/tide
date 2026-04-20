#!/usr/bin/env fish

set -l inner_cmd "
type -q fisher || begin
    curl -sL https://git.io/fisher | source #when running in CI like GHA, we'll have already installed Fisher so this is a no-op
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

if test "$GITHUB_ACTIONS" = true #we can just have it work normally in CI, since it runs in a clean environment
    fish -c $inner_cmd
else
    set -l test_home (mktemp -d)
    env HOME=$test_home XDG_CONFIG_HOME=$test_home/.config fish -c $inner_cmd
    command rm -rf $test_home
end
exit $status
