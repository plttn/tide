function _tide_migrate_orphaned_prompt_vars
    for name in (set -U --names | string match -r '^_tide_prompt_\d+$')
        set -l pid (string replace -r '^_tide_prompt_' '' -- $name)

        test "$pid" = "$fish_pid" && continue
        # A live PID that no longer belongs to us (EPERM) means our shell already
        # exited, so treat that the same as ESRCH: the var is orphaned either way.
        command kill -0 $pid 2>/dev/null && continue

        set -e $name
    end
end
