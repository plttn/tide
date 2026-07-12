# RUN: %fish %s
set -U tide_left_prompt_items status
set -U tide_right_prompt_items
set -U tide_prompt_add_newline_before false
set -U tide_left_prompt_frame_enabled false
set -U tide_right_prompt_frame_enabled false
set -U tide_prompt_min_cols 1
set -Ux tide_status_icon ✔
set -Ux tide_status_icon_failure ✘
set -gx COLUMNS 80
set -gx LINES 24

fish -i -c '
    false
    fish_prompt >/dev/null
    for i in (seq 1 50)
        set -q _tide_repaint && break
        sleep 0.01
    end
    _tide_decolor (fish_prompt)
' </dev/null # CHECK: {{.*}}✘ 1{{.*}}

# Signal-unavailable fallback: a fake `kill` that always fails simulates a
# sandbox that blocks signal delivery. `command kill` bypasses fish
# functions (by design, same as the real code), so this has to be a real
# executable ahead of the real one on PATH, not a mocked fish function.
set -l fake_bin (mktemp -d)
echo '#!/bin/sh
exit 1' >$fake_bin/kill
chmod +x $fake_bin/kill

env PATH="$fake_bin:$PATH" fish -i -c '
    false
    _tide_decolor (fish_prompt)
' </dev/null # CHECK: {{.*}}✘ 1{{.*}}

command rm -r $fake_bin
set -e tide_left_prompt_items tide_right_prompt_items tide_prompt_add_newline_before tide_left_prompt_frame_enabled tide_right_prompt_frame_enabled tide_prompt_min_cols
