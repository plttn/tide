# RUN: %fish %s
# Two-line prompt with the frame enabled, exercising fish's transient-prompt
# entry point (`--final-rendering`). Per
# https://github.com/plttn/tide/issues/42, the transient render must
# collapse down to `_tide_item_character` only -- dropping the frame's
# bottom-left connector and whatever else is configured on the prompt's
# second line -- matching the one-line prompt's existing behavior.
set -U tide_left_prompt_items newline character
set -U tide_right_prompt_items
set -U tide_prompt_add_newline_before false
set -U tide_left_prompt_frame_enabled true
set -U tide_right_prompt_frame_enabled true
set -U tide_prompt_min_cols 1
set -Ux tide_character_icon ❯
set -Ux tide_character_color 00FF00
set -Ux tide_character_color_failure FF0000
set -Ux tide_prompt_color_frame_and_connection 6C6C6C
set -Ux tide_prompt_icon_connection ·
set -gx COLUMNS 80
set -gx LINES 24

set -l stderr_log (mktemp)
fish -i -c '
    false
    fish_prompt >/dev/null
    for i in (seq 1 50)
        set -q _tide_repaint && break
        sleep 0.01
    end
    echo normal:
    for l in (fish_prompt)
        _tide_decolor $l
    end
    echo transient-left:
    _tide_decolor (fish_prompt --final-rendering)
    echo transient-right:
    _tide_decolor (fish_right_prompt --final-rendering)
    echo transient-right-end
' </dev/null 2>$stderr_log
# CHECK: normal:
# CHECK: {{.*}}╭─{{.*}}─╮{{.*}}
# CHECK: {{\x1b\[0J}}╰─❯
# CHECK: transient-left:
# CHECK: {{\x1b\[0J}}❯
# CHECK: transient-right:
# CHECK: transient-right-end

echo stderr-lines (count <$stderr_log)
# CHECK: stderr-lines 0
command rm -f $stderr_log

set -e tide_left_prompt_items tide_right_prompt_items tide_prompt_add_newline_before tide_left_prompt_frame_enabled tide_right_prompt_frame_enabled tide_prompt_min_cols tide_character_icon tide_character_color tide_character_color_failure tide_prompt_color_frame_and_connection tide_prompt_icon_connection
