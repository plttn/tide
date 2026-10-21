# RUN: %fish %s
# Tool lookups are slow where PATH is (e.g. WSL's Windows directories), so the
# answer is reused while PATH and the prompt items stay the same.
_tide_test_save_universals
set -U tide_left_prompt_items node
set -U tide_right_prompt_items

# A PATH holding only a fake node, so what's installed on the machine running
# the tests doesn't matter
set -l bin (mktemp -d)
printf '#!/bin/sh\n' >$bin/node
chmod +x $bin/node
set -l saved_path $PATH
set -gx PATH $bin

function _items
    echo $argv[1]: $_tide_left_items (set -q _tide_unusable_items_reused && echo '(reused)')
end

_tide_remove_unusable_items --refresh
_items checked
# CHECK: checked: node

# Removed, but PATH and the items are unchanged, so the earlier answer stands
/bin/rm $bin/node
_tide_remove_unusable_items
_items unchanged
# CHECK: unchanged: node (reused)

# --refresh (run in the background by each new shell) catches the change
_tide_remove_unusable_items --refresh
_items refreshed
# CHECK: refreshed:

# Changing PATH checks again straight away
printf '#!/bin/sh\n' >$bin/node
/bin/chmod +x $bin/node
set -gx PATH $bin /nonexistent-tide-test-dir
_items path-changed
# CHECK: path-changed: node

# So does changing the prompt items
set -U tide_left_prompt_items node pwd
_tide_remove_unusable_items
_items items-changed
# CHECK: items-changed: node pwd

set -gx PATH $saved_path
command rm -r $bin
functions -e _items
_tide_test_restore_universals
_tide_remove_unusable_items --refresh
