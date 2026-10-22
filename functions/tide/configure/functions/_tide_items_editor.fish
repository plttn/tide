# Interactive editor for which prompt items show, on which side and in what
# order. Edits fake_tide_left_prompt_items / fake_tide_right_prompt_items in
# place, with a live preview. Returns 0 to keep the edit and 1 to cancel it
# (the lists are then put back as they were).
#
# Three columns, in prompt order: Left, Hidden, Right. Lowercase keys move the
# cursor and uppercase keys move the item under it.
function _tide_items_editor
    set -l saved_left $fake_tide_left_prompt_items
    set -l saved_right $fake_tide_right_prompt_items

    # Every item there is: one per _tide_item_* function, plus pwd and newline,
    # which the line prompts handle themselves
    set -g _tide_items_all pwd newline (functions --all | string replace -rf '^_tide_item_(.+)$' '$1')
    set -g _tide_items_col 1
    set -g _tide_items_row 1
    set -g _tide_items_top 1
    set -g _tide_items_message
    set -g _tide_items_preview_all

    set -l result 1
    while true
        _tide_items_draw
        read --nchars 1 --prompt-str "$(set_color -o)Key: $(set_color normal)" key || break
        set _tide_items_message
        switch $key
            case j
                _tide_items_cursor_move 1
            case k
                _tide_items_cursor_move -1
            case h
                _tide_items_cursor_column -1
            case l
                _tide_items_cursor_column 1
            case J
                _tide_items_reorder 1
            case K
                _tide_items_reorder -1
            case H
                _tide_items_shift -1
            case L
                _tide_items_shift 1
            case r
                set fake_tide_left_prompt_items $saved_left
                set fake_tide_right_prompt_items $saved_right
                _tide_items_cursor_move 0
            case y
                set result 0
                break
            case q
                break
        end
    end

    if test $result -ne 0
        set fake_tide_left_prompt_items $saved_left
        set fake_tide_right_prompt_items $saved_right
    end
    set -e _tide_items_all _tide_items_col _tide_items_row _tide_items_top _tide_items_message _tide_items_preview_all
    return $result
end

# The items in column $argv[1]: 1 left, 2 hidden (alphabetical), 3 right
function _tide_items_column -a col
    switch $col
        case 1
            string join \n -- $fake_tide_left_prompt_items
        case 2
            for item in $_tide_items_all
                contains -- $item $fake_tide_left_prompt_items $fake_tide_right_prompt_items || echo $item
            end | path sort -u
        case 3
            string join \n -- $fake_tide_right_prompt_items
    end
end

# Move the cursor $argv[1] rows, keeping it on an item (0 just clamps it)
function _tide_items_cursor_move -a step
    set -l count (count (_tide_items_column $_tide_items_col))
    set -l row (math $_tide_items_row + $step)
    test $row -gt $count && set row $count
    test $row -lt 1 && set row 1
    set _tide_items_row $row
end

# Move the cursor to the next column in direction $argv[1]
function _tide_items_cursor_column -a step
    set -l col (math $_tide_items_col + $step)
    test $col -ge 1 -a $col -le 3 || return
    set _tide_items_col $col
    _tide_items_cursor_move 0
end

# Move the item under the cursor $argv[1] places up or down within its side
function _tide_items_reorder -a step
    set -l list
    switch $_tide_items_col
        case 1
            set list fake_tide_left_prompt_items
        case 3
            set list fake_tide_right_prompt_items
        case 2
            set _tide_items_message 'Hidden items are listed alphabetically'
            return
    end

    set -l from $_tide_items_row
    set -l to (math $from + $step)
    set -l items $$list
    set -q items[$from] || return
    test $to -ge 1 -a $to -le (count $items) || return
    if contains character $items[$from] $items[$to] && test $list = fake_tide_left_prompt_items
        set _tide_items_message 'character stays at the end of the left prompt'
        return
    end

    set -l item $items[$from]
    set items[$from] $items[$to]
    set items[$to] $item
    set $list $items
    set _tide_items_row $to
end

# Move the item under the cursor one column over, in direction $argv[1]
function _tide_items_shift -a step
    set -l items (_tide_items_column $_tide_items_col)
    set -q items[$_tide_items_row] || return
    set -l item $items[$_tide_items_row]
    set -l col (math $_tide_items_col + $step)
    test $col -ge 1 -a $col -le 3 || return

    if test $col = 3 && contains -- $item newline character
        set _tide_items_message "$item only works on the left prompt"
        return
    end

    _tide_find_and_remove $item fake_tide_left_prompt_items
    _tide_find_and_remove $item fake_tide_right_prompt_items
    switch $col
        case 1
            # New items go at the end, but before character, which stays last
            set -l index (contains --index character $fake_tide_left_prompt_items)
            if test -n "$index" && test $item != character
                set -l before
                test $index -gt 1 && set before $fake_tide_left_prompt_items[1..(math $index - 1)]
                set fake_tide_left_prompt_items $before $item $fake_tide_left_prompt_items[$index..]
            else
                set -a fake_tide_left_prompt_items $item
            end
        case 3
            set -a fake_tide_right_prompt_items $item
    end

    # Follow the item to its new place
    set _tide_items_col $col
    set -l row (contains --index -- $item (_tide_items_column $col))
    set _tide_items_row $row
end

function _tide_items_draw
    set -l preview
    for line in (_tide_display_prompt)
        set -l width (string length --visible -- $line)
        test $width -eq 0 && continue
        # With every item showing, a side can be wider than the screen
        test $width -gt $fake_columns && set line (string shorten --max $fake_columns -- $line)
        set -a preview $line
    end
    set -l left (_tide_items_column 1)
    set -l hidden (_tide_items_column 2)
    set -l right (_tide_items_column 3)
    set -l width (math --scale=0 $fake_columns / 3)

    # Rows left over once the title, preview, headings, scroll markers, help
    # and key prompt are drawn. Scroll to keep the cursor in view.
    set -l visible (math $fake_lines - (count $preview) - 10)
    test $visible -lt 3 && set visible 3
    set -l rows (math max (count $left), (count $hidden), (count $right), 1)
    test $_tide_items_row -lt $_tide_items_top && set _tide_items_top $_tide_items_row
    test $_tide_items_row -ge (math $_tide_items_top + $visible) &&
        set _tide_items_top (math $_tide_items_row - $visible + 1)
    set _tide_items_top (math min $_tide_items_top, max 1, $rows - $visible + 1)
    set -l last (math min $rows, $_tide_items_top + $visible - 1)

    _tide_title 'Prompt Items'
    echo
    printf '%s\n' $preview
    set_color normal
    echo

    set_color -o
    for heading in Left Hidden Right
        printf '%s' (string pad --right --width $width "  $heading")
    end
    set_color normal
    echo

    # A … above or below the rows when there are more that way
    test $_tide_items_top -gt 1 && echo '  …' || echo
    for row in (seq $_tide_items_top $last)
        set -l line
        for col in 1 2 3
            set -l items $left
            test $col = 2 && set items $hidden
            test $col = 3 && set items $right
            if not set -q items[$row]
                set -a line (string repeat --count $width ' ')
            else if test $col = $_tide_items_col -a $row = $_tide_items_row
                # Pad before colouring, so the escapes don't count as width
                set -a line (set_color -o brcyan)(string pad --right --width $width -- "› $items[$row]")(set_color normal)
            else
                set -a line (string pad --right --width $width -- "  $items[$row]")
            end
        end
        string join '' -- $line
    end
    test $last -lt $rows && echo '  …' || echo

    echo 'j/k up/down  h/l column  J/K reorder  H/L move item'
    echo 'y done  r reset  q cancel'
    if test -n "$_tide_items_message"
        set_color yellow
        echo $_tide_items_message
        set_color normal
    else
        echo
    end
end
