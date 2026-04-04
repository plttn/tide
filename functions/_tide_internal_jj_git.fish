function _tide_internal_jj_git
    # Returns:
    #   0: inside a jj repo and jj prompt is enabled
    #   1: not inside a jj repo
    #   2: inside a jj repo but jj prompt is disabled via .disable-jj-prompt
    set -l d $PWD
    while test -n "$d"
        if test -d "$d/.jj"
            test -f "$d/.disable-jj-prompt"; and return 2
            return 0
        end
        set d (string replace -r '/[^/]*$' '' -- $d)
    end

    return 1
end
