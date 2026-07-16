function _tide_memoize -a name key
    if not set -q _tide_prompt_tmpdir
        # No per-session tmpdir to cache into (e.g. called outside a real
        # prompt render, such as directly from a test) -- just run it.
        $argv[3..] 2>&1
        return
    end

    set -l file $_tide_prompt_tmpdir/memo_$name
    if test -e $file
        read -lz whole <$file
        set -l parts (string split -m1 \n -- $whole)
        if test "$parts[1]" = "$key"
            printf '%s' $parts[2]
            return 0
        end
    end
    set -l val ($argv[3..] 2>&1)
    or return 1
    string join \n -- $val | read -lz joined
    printf '%s\n%s' $key $joined >$file
    printf '%s' $joined
end
