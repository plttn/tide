function fish_prompt
end # In case this file gets loaded non-interactively, e.g by conda
status is-interactive || exit

_tide_remove_unusable_items
_tide_cache_variables
_tide_parent_dirs
source (functions --details _tide_pwd)

set -l prompt_var _tide_prompt_$fish_pid
set -g $prompt_var
set -q _tide_prompt_tmpfile || set -g _tide_prompt_tmpfile (mktemp) # global so `tide reload` reuses it instead of leaking one per reload

set_color normal | read -l color_normal
status fish-path | read -l fish_path

if string match -i homebrew/Cellar $fish_path
    set fish_path (string replace -r '/Cellar/[^/]+/[^/]+/bin/' '/bin/' $fish_path)
end

# _tide_repaint prevents us from creating a second background job
function _tide_refresh_prompt --on-signal SIGUSR1 --inherit-variable prompt_var
    set -g $prompt_var (cat $_tide_prompt_tmpfile 2>/dev/null)
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

    # The job renders into a private scratch file (suffixed with its own
    # pid) and atomically renames it over the shared tmpfile, so the
    # SIGUSR1 handler can never read a partial write from a newer job. The
    # tmpfile path crosses into the job string-escaped and is expanded as a
    # variable there, never re-parsed as syntax, so any TMPDIR is safe.
    $fish_path -c "set _tide_pipestatus $_tide_pipestatus
set _tide_parent_dirs $_tide_parent_dirs
set _tide_prompt_tmpfile "(string escape -- $_tide_prompt_tmpfile)"
PATH="(string escape "$PATH")" CMD_DURATION=$CMD_DURATION fish_key_bindings=$fish_key_bindings fish_bind_mode=$fish_bind_mode $argv[1] >\$_tide_prompt_tmpfile.\$fish_pid
command mv -f \$_tide_prompt_tmpfile.\$fish_pid \$_tide_prompt_tmpfile
command kill -s USR1 $fish_pid 2>/dev/null" &
    builtin disown

    # A job killed mid-render leaves its scratch file behind; its pid is
    # the scratch suffix, so remove it only when the kill actually landed
    command kill $_tide_last_pid 2>/dev/null && command rm -f $_tide_prompt_tmpfile.$_tide_last_pid
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
    _tide_status=\$status _tide_pipestatus=\$pipestatus if not set -e _tide_repaint
        _tide_dispatch_render _tide_2_line_prompt
    end



    if not contains -- --final-rendering \$argv
        math \$COLUMNS-(string length -V \"\$$prompt_var[1][1]\$$prompt_var[1][3]\")+$column_offset | read -lx dist_btwn_sides

        echo -n $add_newline'$top_left_frame'(string replace @PWD@ (_tide_pwd) \"\$$prompt_var[1][1]\")'$prompt_and_frame_color'
        string repeat -Nm(math max 0, \$dist_btwn_sides-\$_tide_pwd_len) '$tide_prompt_icon_connection'

        echo \"\$$prompt_var[1][3]$top_right_frame\"
    end
    echo -n \e\[0J\"$bot_left_frame\$$prompt_var[1][2]$color_normal \"
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
    rm -f $_tide_prompt_tmpfile $_tide_prompt_tmpfile.$_tide_last_pid
end
