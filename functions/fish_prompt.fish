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

# Bumped on every dispatch and stamped into each job's output, so a job that
# finishes after a newer one has already been dispatched -- e.g. a slow
# in-repo render outliving a fast render for the directory `cd`ed into next
# -- can be recognized as superseded and dropped instead of overwriting
# fresher content.
set -q _tide_render_gen || set -g _tide_render_gen 0

set_color normal | read -l color_normal
status fish-path | read -l fish_path

if string match -i homebrew/Cellar $fish_path
    set fish_path (string replace -r '/Cellar/[^/]+/[^/]+/bin/' '/bin/' $fish_path)
end

# _tide_repaint prevents us from creating a second background job
function _tide_refresh_prompt --on-signal SIGUSR1 --inherit-variable prompt_var
    set -l rendered (cat $_tide_prompt_tmpfile 2>/dev/null)
    # First line is the generation this job was dispatched at (see
    # _tide_dispatch_render) -- a mismatch means a newer job has since been
    # dispatched, so this result is stale and superseded; drop it rather
    # than clobbering $prompt_var with old content. No repaint here is
    # correct: the newer job has either already applied its own result or
    # will signal on its own once it finishes.
    test "$rendered[1]" = "$_tide_render_gen" || return
    set -g $prompt_var $rendered[2..]
    set -g _tide_repaint
    commandline -f repaint
end

# On resize, repaint with the last completed render but leave $prompt_var
# alone -- in synchronous-fallback mode the tmpfile is never written, so
# reading it here would blank the prompt.
function _tide_repaint_on_resize --on-variable COLUMNS
    set -g _tide_repaint
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
        set -g $prompt_var ($argv[1])
        return
    end

    set -g _tide_render_gen (math $_tide_render_gen + 1)

    # The job renders into a private scratch file (suffixed with its own
    # pid) and atomically renames it over the shared tmpfile, so the
    # SIGUSR1 handler can never read a partial write from a newer job. Its
    # first line is stamped with the generation dispatched here (baked in
    # as a literal below, not read back from the variable, since the job
    # is a separate process) so _tide_refresh_prompt can recognize and
    # drop a result superseded by a since-dispatched job. The tmpfile path
    # crosses into the job string-escaped and is expanded as a variable
    # there, never re-parsed as syntax, so any TMPDIR is safe.
    $fish_path -c "set _tide_pipestatus $_tide_pipestatus
set _tide_parent_dirs $_tide_parent_dirs
set _tide_prompt_tmpfile "(string escape -- $_tide_prompt_tmpfile)"
echo $_tide_render_gen >\$_tide_prompt_tmpfile.\$fish_pid
PATH="(string escape "$PATH")" CMD_DURATION=$CMD_DURATION fish_key_bindings=$fish_key_bindings fish_bind_mode=$fish_bind_mode $argv[1] >>\$_tide_prompt_tmpfile.\$fish_pid
command mv -f \$_tide_prompt_tmpfile.\$fish_pid \$_tide_prompt_tmpfile
command kill -s USR1 $fish_pid 2>/dev/null" &
    builtin disown

    # A completed job has already mv'd its scratch file away, so its
    # existence means the previous job is still running or died mid-render --
    # only then is there anything to kill/clean up, and only then do we pay
    # for the two external forks.
    test -e $_tide_prompt_tmpfile.$_tide_last_pid &&
        command kill $_tide_last_pid 2>/dev/null &&
        command rm -f $_tide_prompt_tmpfile.$_tide_last_pid
    set -g _tide_last_pid $last_pid

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

    eval "
function fish_prompt
    set -lx _tide_status \$status
    _tide_pipestatus=\$pipestatus if not set -e _tide_repaint
        _tide_dispatch_render _tide_2_line_prompt
    end



    if not contains -- --final-rendering \$argv
        math \$COLUMNS-(string length -V \"\$$prompt_var[1][1]\$$prompt_var[1][3]\")+$column_offset | read -lx dist_btwn_sides

        echo -n $add_newline'$top_left_frame'(string replace @PWD@ (_tide_pwd) \"\$$prompt_var[1][1]\")'$prompt_and_frame_color'
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
    _tide_pipestatus=\$pipestatus if not set -e _tide_repaint
        _tide_dispatch_render _tide_1_line_prompt
    end

    if contains -- --final-rendering \$argv
        echo -n \e\[0J
        add_prefix= _tide_item_character
        echo -n '$color_normal '
    else
        math \$COLUMNS-(string length -V \"\$$prompt_var[1][1]\$$prompt_var[1][2]\")$column_offset | read -lx dist_btwn_sides
        printf '%s' (string replace @PWD@ (_tide_pwd) $add_newline \$$prompt_var[1][1]'$color_normal ')
    end
end

function fish_right_prompt
    if not contains -- --final-rendering \$argv
        string unescape \"\$$prompt_var[1][2]$color_normal\"
    end
end"

end

function _tide_on_fish_exit --on-event fish_exit
    # The last dispatched render job is disowned, so nothing else waits for
    # it -- kill it and confirm it's dead before removing the tmpdir it
    # writes into, or a job that's still starting up (e.g. a nested shell
    # exited right after launch) can fail its redirect into a dir we just
    # deleted and print a spurious warning.
    if set -q _tide_last_pid
        command kill $_tide_last_pid 2>/dev/null
        for _tide_i in (seq 1 10)
            command kill -0 $_tide_last_pid 2>/dev/null || break
            sleep 0.01
        end
    end
    set -q _tide_prompt_tmpdir && command rm -rf $_tide_prompt_tmpdir
end
