# RUN: %fish %s
# The item editor behind `tide items` and the wizard's customize_items step,
# driven by piping keys into it
functions --query _tide_sub_configure # loads the editor and the preview it draws

for var in (set --names | string match -r '^tide_.*')
    set -g fake_$var $$var
end
set -g fake_columns 80
set -g fake_lines 30

function _edit -a keys
    set -g fake_tide_left_prompt_items pwd vcs newline character
    set -g fake_tide_right_prompt_items status node
    printf %s $keys | _tide_items_editor >/dev/null
    echo $status: $fake_tide_left_prompt_items '|' $fake_tide_right_prompt_items
end

# Columns are Left, Hidden, Right; lowercase keys move the cursor and
# uppercase keys move the item under it. Hidden is alphabetical (aws first).
_edit lLy
# CHECK: 0: pwd vcs newline character | status node aws
# New left items go before character, which stays last
_edit lHy
# CHECK: 0: pwd vcs newline aws character | status node
_edit LHy
# CHECK: 0: vcs newline pwd character | status node

# Reorder within a side
_edit llJy
# CHECK: 0: pwd vcs newline character | node status
_edit jJy
# CHECK: 0: pwd newline vcs character | status node

# character stays last on the left, and can't move up
_edit jjJy
# CHECK: 0: pwd vcs newline character | status node
_edit jjjKy
# CHECK: 0: pwd vcs newline character | status node

# newline and character only work on the left
_edit jjjLLy
# CHECK: 0: pwd vcs newline | status node
_edit jjLLy
# CHECK: 0: pwd vcs character | status node

# Moving character back in puts it last again
_edit jjjLHy
# CHECK: 0: pwd vcs newline character | status node

# r resets, and q (or running out of input) cancels
_edit lLry
# CHECK: 0: pwd vcs newline character | status node
_edit lLq
# CHECK: 1: pwd vcs newline character | status node
_edit lL
# CHECK: 1: pwd vcs newline character | status node

# Every item is offered, pwd and newline included
set -g fake_tide_left_prompt_items
set -g fake_tide_right_prompt_items
set -g _tide_items_all pwd newline (functions --all | string replace -rf '^_tide_item_(.+)$' '$1')
contains pwd (_tide_items_column 2) && contains newline (_tide_items_column 2) && contains node (_tide_items_column 2) && echo all-offered
# CHECK: all-offered
set -e _tide_items_all

# The editor leaves no state behind, and the preview stubs draw nothing again
set --names | string match -r '^_tide_items_' | count
# CHECK: 0
_fake_tide_item_node | count
# CHECK: 0

# tide items saves only on y, and a cancel leaves every universal alone
for var in (set --names | string match -r '^fake_.*')
    set -e $var
end
_tide_test_save_universals
set -l count_before (set -U --names | count)
printf q | COLUMNS=80 LINES=30 tide items >/dev/null
test (set -U --names | count) = $count_before && echo cancel-kept
# CHECK: cancel-kept
set -l right_before $tide_right_prompt_items
set -l first_hidden (for item in pwd newline (functions --all | string replace -rf '^_tide_item_(.+)$' '$1')
        contains $item $tide_left_prompt_items $tide_right_prompt_items || echo $item
    end | path sort -u)[1]
printf lLy | COLUMNS=80 LINES=30 tide items >/dev/null
test "$tide_right_prompt_items" = "$right_before $first_hidden" && echo saved
# CHECK: saved
set --names | string match -r '^fake_' | count
# CHECK: 0

# --auto command lines from before the customize_items step still finish
tide configure --auto --style=Lean --prompt_colors='True color' --show_time=No --lean_prompt_height='One line' --prompt_spacing=Compact --icons='Few icons' >/dev/null
echo $status: $tide_left_prompt_items
# CHECK: 0: pwd vcs character
_tide_test_restore_universals
