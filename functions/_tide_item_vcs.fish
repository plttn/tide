function _tide_item_vcs
    _tide_internal_jj_git
    set -l jj_repo_status $status

    # Prefer jj formatting only when we're in a jj repo and jj is actually available.
    if test $jj_repo_status -eq 0; and command -sq jj
        _tide_internal_vcs_jj
        return
    end

    _tide_internal_vcs_git
end
