function fish_prompt
end # In case this file gets loaded non-interactively, e.g by conda
status is-interactive || exit

_tide_remove_unusable_items
_tide_cache_variables
_tide_parent_dirs
source (functions --details _tide_pwd)

set -l prompt_var _tide_prompt_$fish_pid
set -g $prompt_var
# global so `tide reload` reuses it instead of leaking one per reload; a
# private 0700 dir (rather than a bare mktemp file) keeps the per-render
# scratch files -- created via `>` redirection at umask perms -- from ever
# being exposed at a world-readable path
set -q _tide_prompt_tmpdir || set -g _tide_prompt_tmpdir (mktemp -d)
set -g _tide_prompt_tmpfile $_tide_prompt_tmpdir/prompt

# Bumped once per prompt cycle and stamped into $_tide_repaint every time a
# repaint is requested. Without it, a repaint requested while a command is
# still running -- a render landing, or a terminal resize, during a long
# command -- would be mistaken for a repaint of the prompt drawn next, whose
# render would then be skipped, leaving pre-command content on screen until
# something else redrew it.
set -q _tide_cycle || set -g _tide_cycle 0

function _tide_next_prompt_cycle --on-event fish_postexec
    set -g _tide_cycle (math $_tide_cycle + 1)
end

set_color normal | read -l color_normal
status fish-path | read -l fish_path

if string match -i homebrew/Cellar $fish_path
    set fish_path (string replace -r '/Cellar/[^/]+/[^/]+/bin/' '/bin/' $fish_path)
end

# The item check above reused an earlier answer instead of looking every tool
# up again, which can take over a second where PATH is slow. Check again in
# the background, so a tool installed or removed since then still shows up
# (or disappears) by a later prompt.
if set -q _tide_unusable_items_reused
    # PATH is set before the function loads, so its PATH handler doesn't fire
    $fish_path -c "set -gx PATH "(string escape -- $PATH)"; _tide_remove_unusable_items --refresh" </dev/null >/dev/null 2>&1 &
    builtin disown
end

# Stores a finished render for drawing. A last line starting with \x1f holds
# the versions of the jj segment its placeholder can be filled with (see
# _tide_1_line_prompt), so it's moved into $_tide_jj_variants instead.
function _tide_store_render --inherit-variable prompt_var
    set -g _tide_jj_variants
    if string match -q \x1f'*' -- "$argv[-1]"
        set _tide_jj_variants (string split -n \x1f -- $argv[-1])
        set -e argv[-1]
    end
    set -g $prompt_var $argv
end

# _tide_repaint prevents us from creating a second background job
function _tide_refresh_prompt --on-signal SIGUSR1 --inherit-variable prompt_var
    # Every job publishes under its own pid (see _tide_dispatch_render), so
    # only the newest job's file is ever read: a superseded job that finishes
    # late writes somewhere else entirely, where it can neither be read here
    # nor overwrite fresher content. Nothing there yet means this signal came
    # from such a straggler while the current job is still rendering -- drop
    # it and wait, the current job signals for itself once it finishes.
    #
    # The file is read with a builtin rather than `cat`: this handler runs in
    # the interactive shell, where a fork costs hundreds of ms on WSL2. A
    # builtin's failed redirect warns in a way `2>/dev/null` can't silence,
    # hence the `test -e` first. Only a job dispatched after this one deletes
    # this file, and only once that job has finished its own render, so in
    # practice it can't vanish in the moment between the check and the read.
    set -q _tide_last_pid || return
    test -e $_tide_prompt_tmpfile.$_tide_last_pid || return
    set -l rendered (string replace -r '' '' <$_tide_prompt_tmpfile.$_tide_last_pid)
    set -q rendered[1] || return
    # Marks this job as finished even if a tmp cleaner later deletes its file,
    # so it's never mistaken for one still running (see _tide_dispatch_render).
    set -g _tide_done_pid $_tide_last_pid
    _tide_store_render $rendered
    set -g _tide_repaint $_tide_cycle
    commandline -f repaint
end

# On resize, repaint with the last completed render but leave $prompt_var
# alone -- in synchronous-fallback mode the tmpfile is never written, so
# reading it here would blank the prompt.
function _tide_repaint_on_resize --on-variable COLUMNS
    set -g _tide_repaint $_tide_cycle
    commandline -f repaint
end

# Escape hatch: some sandboxes/containers block or silently swallow signal
# delivery. Self-signal once at init (on a signal SIGUSR1 never uses) so we
# know, before the first render, whether SIGUSR1 can actually reach us --
# if not, every render below falls back to rendering synchronously instead
# of spawning a background job that can never notify us it's done.
function _tide_signal_test --on-signal SIGUSR2
    set -g _tide_signal_confirmed true
    functions -e _tide_signal_test
end
command kill -s USR2 $fish_pid 2>/dev/null || set -g _tide_signal_unavailable true

# Renders in the background (or synchronously, if signals are confirmed
# unavailable) and repaints when ready. $argv[1] is the render function to
# call for this session (_tide_1_line_prompt or _tide_2_line_prompt).
function _tide_dispatch_render --inherit-variable prompt_var --inherit-variable fish_path
    jobs -q && jobs -p | count | read -lx _tide_jobs

    if test "$_tide_signal_unavailable" = true
        _tide_store_render ($argv[1])
        return
    end

    # Stopping the previous job and removing its files is left to the job
    # below, so those forks land in the background instead of on the
    # interactive path, where one fork can cost hundreds of ms on WSL2.
    #
    # The new job kills every earlier job that may still be running before it
    # renders, so a burst of prompts (vi mode switches, repaints from other
    # plugins) leaves one live render instead of one per prompt. Killing only
    # the job just before it isn't enough: jobs start up at uneven speeds, so
    # a job can be killed before it gets to kill its own predecessor.
    #
    # $_tide_render_pids lists the jobs that may still be running or still
    # have files, oldest first. Walking it newest first, using only builtins:
    # - A job that has published (or whose render the handler already read)
    #   has finished, and so has already killed every job before it and will
    #   remove their files after its render. The walk stops there.
    # - A job whose `.part` file exists has started, so it has already killed
    #   every job before it. Those older jobs are left off the kill list,
    #   which keeps the chance of killing a reused pid small.
    #
    # The files go after the new job's own render. If a kill missed (that job
    # published in between), unlinking a file a process still has open is
    # silent, and that job's `mv -f` then fails into `2>/dev/null`. Anything
    # still left behind is removed with the tmpdir on exit.
    set -l kill_pids
    set -l stale_files
    set -l tracked
    set -l started false
    for pid in $_tide_render_pids[-1..1]
        set -l file $_tide_prompt_tmpfile.$pid
        set -a stale_files (string escape -- $file $file.part)
        set -p tracked $pid
        if test "$pid" = "$_tide_done_pid" || test -e $file
            break
        end
        test $started = false && set -a kill_pids $pid
        test -e $file.part && set started true
    end
    # Bound the list if renders keep hanging without ever publishing.
    set -q tracked[33] && set tracked $tracked[-32..-1]

    set -l stop_stale
    set -q kill_pids[1] && set stop_stale "command kill $kill_pids 2>/dev/null"
    set -l rm_stale
    set -q stale_files[1] && set rm_stale "command rm -f $stale_files 2>/dev/null"

    # The job renders into a private scratch file and atomically renames it to
    # a path named after its own pid, so the SIGUSR1 handler can never read a
    # partial write, and a superseded job can never overwrite the result of a
    # job dispatched after it. Paths cross into the job string-escaped -- and
    # the tmpfile is expanded there as a variable, never re-parsed as syntax
    # -- so any TMPDIR is safe.
    $fish_path -c "$stop_stale
set _tide_pipestatus $_tide_pipestatus
set _tide_parent_dirs $_tide_parent_dirs
set _tide_prompt_tmpfile "(string escape -- $_tide_prompt_tmpfile)"
PATH="(string escape "$PATH")" CMD_DURATION=$CMD_DURATION fish_key_bindings=$fish_key_bindings fish_bind_mode=$fish_bind_mode $argv[1] >\$_tide_prompt_tmpfile.\$fish_pid.part
command mv -f \$_tide_prompt_tmpfile.\$fish_pid.part \$_tide_prompt_tmpfile.\$fish_pid 2>/dev/null
command kill -s USR1 $fish_pid 2>/dev/null
$rm_stale" &
    builtin disown

    set -g _tide_last_pid $last_pid
    set -g _tide_render_pids $tracked $last_pid

    if not set -q _tide_signal_confirmed
        for _tide_i in (seq 1 10)
            set -q _tide_signal_confirmed && break
            sleep 0.01
        end
        set -q _tide_signal_confirmed || set -g _tide_signal_unavailable true
    end
end

if contains newline $_tide_left_items # two line prompt initialization
    test "$tide_prompt_add_newline_before" = true && set -l add_newline '\n'

    set_color $tide_prompt_color_frame_and_connection -b normal | read -l prompt_and_frame_color

    set -l column_offset 5
    test "$tide_left_prompt_frame_enabled" = true &&
        set -l top_left_frame "$prompt_and_frame_color╭─" &&
        set -l bot_left_frame "$prompt_and_frame_color╰─" &&
        set column_offset 3
    test "$tide_right_prompt_frame_enabled" = true &&
        set -l top_right_frame "$prompt_and_frame_color─╮" &&
        set -l bot_right_frame "$prompt_and_frame_color─╯" &&
        set column_offset (math $column_offset-2)
    # Columns the top line keeps for the frames, for _tide_fit_jj
    math 5 - $column_offset | read -l fit_reserved

    eval "
function fish_prompt
    set -lx _tide_status \$status
    _tide_pipestatus=\$pipestatus if test \"\$_tide_repaint\" = \"\$_tide_cycle\"
        set -e _tide_repaint
    else if not contains -- --final-rendering \$argv
        _tide_dispatch_render _tide_2_line_prompt
    end



    if not contains -- --final-rendering \$argv
        set -l top_left \"\$$prompt_var[1][1]\"
        set -q _tide_jj_variants[1] && set top_left (_tide_fit_jj $fit_reserved \"\$top_left\" \"\$$prompt_var[1][3]\" \$_tide_jj_variants)
        math \$COLUMNS-(string length -V \"\$top_left\$$prompt_var[1][3]\")+$column_offset | read -lx dist_btwn_sides

        echo -n $add_newline'$top_left_frame'(string replace @PWD@ (_tide_pwd) \"\$top_left\")'$prompt_and_frame_color'
        string repeat -Nm(math max 0, \$dist_btwn_sides-\$_tide_pwd_len) '$tide_prompt_icon_connection'

        echo \"\$$prompt_var[1][3]$top_right_frame\"
    end
    echo -n \e\[0J
    if contains -- --final-rendering \$argv
        add_prefix= _tide_item_character
        echo -n '$color_normal '
    else
        echo -n \"$bot_left_frame\$$prompt_var[1][2]$color_normal \"
    end
end

function fish_right_prompt
    if not contains -- --final-rendering \$argv
        string unescape \"\$$prompt_var[1][4]$bot_right_frame$color_normal\"
    end
end"

else # one line prompt initialization
    test "$tide_prompt_add_newline_before" = true && set -l add_newline '\0'
    math 5 -$tide_prompt_min_cols | read -l column_offset
    test $column_offset -ge 0 && set column_offset "+$column_offset"

    eval "
function fish_prompt
    set -lx _tide_status \$status
    _tide_pipestatus=\$pipestatus if test \"\$_tide_repaint\" = \"\$_tide_cycle\"
        set -e _tide_repaint
    else if not contains -- --final-rendering \$argv
        _tide_dispatch_render _tide_1_line_prompt
    end

    if contains -- --final-rendering \$argv
        echo -n \e\[0J
        add_prefix= _tide_item_character
        echo -n '$color_normal '
    else
        set -l top_left \$$prompt_var[1][1]
        set -q _tide_jj_variants[1] && set top_left (_tide_fit_jj $tide_prompt_min_cols \"\$top_left\" \"\$$prompt_var[1][2]\" \$_tide_jj_variants)
        math \$COLUMNS-(string length -V \"\$top_left\$$prompt_var[1][2]\")$column_offset | read -lx dist_btwn_sides
        printf '%s' (string replace @PWD@ (_tide_pwd) $add_newline \$top_left'$color_normal ')
    end
end

function fish_right_prompt
    if not contains -- --final-rendering \$argv
        string unescape \"\$$prompt_var[1][2]$color_normal\"
    end
end"

end

function _tide_on_fish_exit --on-event fish_exit
    # Render jobs are disowned, so nothing else waits for them -- kill any
    # that may still be running and confirm they're dead before removing the
    # tmpdir they write into, or a job that's still starting up (e.g. a
    # nested shell exited right after launch) can fail its redirect into a
    # dir we just deleted and print a spurious warning.
    set -l live
    # $_tide_last_pid is always the last entry already; listing it again just
    # makes sure the newest job is covered even if the list was never set.
    for pid in $_tide_render_pids $_tide_last_pid
        test "$pid" = "$_tide_done_pid" || test -e $_tide_prompt_tmpfile.$pid || set -a live $pid
    end
    if set -q live[1]
        command kill $live 2>/dev/null
        for _tide_i in (seq 1 10)
            set -l alive
            for pid in $live
                command kill -0 $pid 2>/dev/null && set -a alive $pid
            end
            set -q alive[1] || break
            set live $alive
            sleep 0.01
        end
    end
    set -q _tide_prompt_tmpdir && command rm -rf $_tide_prompt_tmpdir
end
