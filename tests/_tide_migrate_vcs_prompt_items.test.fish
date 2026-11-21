# RUN: %fish %s
# Simulate a package-managed upgrade: the new Tide functions are installed,
# but Fisher's _tide_init_update event was never emitted.
_tide_test_save_universals

set -U tide_left_prompt_items pwd git jj status
set -U tide_right_prompt_items time jj

# Starting an interactive shell must migrate before the first prompt.
fish -i -c '
    fish_prompt >/dev/null
    echo left: (string join " " -- $tide_left_prompt_items)
    echo right: (string join " " -- $tide_right_prompt_items)
' </dev/null 2>/dev/null
# CHECK: left: pwd vcs status
# CHECK: right: time vcs

# The next shell must leave the migrated items unchanged.
fish -i -c '
    fish_prompt >/dev/null
    echo left: (string join " " -- $tide_left_prompt_items)
    echo right: (string join " " -- $tide_right_prompt_items)
' </dev/null 2>/dev/null
# CHECK: left: pwd vcs status
# CHECK: right: time vcs

_tide_test_restore_universals
