# RUN: %fish %s
set -U tide_left_prompt_items status jobs
set -U tide_right_prompt_items
set -U tide_prompt_add_newline_before false
set -U tide_left_prompt_frame_enabled false
set -U tide_right_prompt_frame_enabled false
set -U tide_prompt_min_cols 1
set -Ux tide_status_icon ✔
set -Ux tide_status_icon_failure ✘
set -Ux tide_jobs_icon JOBS
set -Ux tide_jobs_number_threshold 1000
set -gx COLUMNS 80
set -gx LINES 24

# Happy path: async render via SIGUSR1, then a resize event must repaint
# with the same content instead of blanking or recomputing.
fish -i -c '
    false
    fish_prompt >/dev/null
    for i in (seq 1 50)
        set -q _tide_repaint && break
        sleep 0.01
    end
    _tide_decolor (fish_prompt)
    _tide_repaint_on_resize
    true
    _tide_decolor (fish_prompt)
' </dev/null
# CHECK: {{.*}}✘ 1{{.*}}
# CHECK: {{.*}}✘ 1{{.*}}

# Signal-unavailable fallback: a fake `kill` that always fails simulates a
# sandbox that blocks signal delivery. `command kill` bypasses fish
# functions (by design, same as the real code), so this has to be a real
# executable ahead of the real one on PATH, not a mocked fish function.
# With a background job running, the jobs item must render in the
# synchronous path too, and a resize event must not blank the prompt (the
# tmpfile is never written in this mode).
set -l fake_bin (mktemp -d)
echo '#!/bin/sh
exit 1' >$fake_bin/kill
chmod +x $fake_bin/kill

env PATH="$fake_bin:$PATH" fish -i -c '
    sleep 2 &
    false
    _tide_decolor (fish_prompt)
    _tide_repaint_on_resize
    true
    _tide_decolor (fish_prompt)
    wait
' </dev/null
# CHECK: {{.*}}✘ 1{{.*}}JOBS{{.*}}
# CHECK: {{.*}}✘ 1{{.*}}JOBS{{.*}}

# Tmpfile hygiene: a fake `mktemp` redirects the prompt tmpdir into a watch
# dir whose path contains a space, proving the path survives the background
# job's command string unmangled. macOS mktemp ignores TMPDIR, so
# PATH-shadowing is the only reliable redirection. The tmpdir itself is
# created once and reused ($TIDE_TEST_TMPDIR always has exactly 1 entry --
# the tmpdir -- until exit), so hygiene is checked *inside* it: after a
# completed render the scratch file must be renamed away (1 file), `tide
# reload` must reuse the same tmpdir instead of minting new ones (still 1
# file), and exit must remove the whole tmpdir (0 entries at the watch root).
set -l watch_root (mktemp -d)
mkdir -p "$watch_root/tide tmp"
set -l fake_mktemp_bin (mktemp -d)
echo '#!/bin/sh
exec /usr/bin/mktemp -d "$TIDE_TEST_TMPDIR/tide.XXXXXX"' >$fake_mktemp_bin/mktemp
chmod +x $fake_mktemp_bin/mktemp

env TIDE_TEST_TMPDIR="$watch_root/tide tmp" PATH="$fake_mktemp_bin:$PATH" fish -i -c '
    false
    fish_prompt >/dev/null
    for i in (seq 1 50)
        set -q _tide_repaint && break
        sleep 0.01
    end
    _tide_decolor (fish_prompt)
    echo files-after-render (command ls $TIDE_TEST_TMPDIR/tide.*/ | count)
    tide reload
    tide reload
    echo files-after-reloads (command ls $TIDE_TEST_TMPDIR/tide.*/ | count)
' </dev/null
# CHECK: {{.*}}✘ 1{{.*}}
# CHECK: files-after-render 1
# CHECK: files-after-reloads 1
echo files-after-exit (command ls "$watch_root/tide tmp" | count)
# CHECK: files-after-exit 0

command rm -r $fake_bin $fake_mktemp_bin $watch_root
set -e tide_left_prompt_items tide_right_prompt_items tide_prompt_add_newline_before tide_left_prompt_frame_enabled tide_right_prompt_frame_enabled tide_prompt_min_cols tide_status_icon tide_status_icon_failure tide_jobs_icon tide_jobs_number_threshold
