# Fills the jj placeholder in the top line's left side with the widest version
# of the jj segment that still leaves the directory its full width, or the
# narrowest one if none does (the directory then truncates as usual).
# $argv: columns to keep free on the line, the top line's left and right
# sides, then every version of the segment, widest first.
# Runs in the interactive shell on every draw, so builtins only.
function _tide_fit_jj -a reserved left right
    if not string match -q '*@JJ@*' -- $left
        printf '%s' $left
        return
    end

    # The directory's untruncated width, from _tide_pwd itself so its icons
    # are counted the same way. Measuring only skips its marker checks, which
    # don't change the width but do touch the disk for every directory.
    set -l pwd_len 0
    if string match -q '*@PWD@*' -- "$left$right"
        _tide_pwd_measure_only=1 _tide_pwd >/dev/null
        set pwd_len $_tide_pwd_len
    end

    set -l rest (string replace -- @JJ@ '' "$left$right" | string replace -- @PWD@ '' | string length -V)
    set -l budget (math $COLUMNS - $reserved - $pwd_len - $rest)

    set -l jj $argv[-1]
    for variant in $argv[4..]
        if test (string length -V -- $variant) -le $budget
            set jj $variant
            break
        end
    end
    string replace -- @JJ@ $jj $left
end
