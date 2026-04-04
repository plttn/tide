# RUN: %fish %s
_tide_parent_dirs

function _jj_git_status
    _tide_internal_jj_git
    echo $status
end

set -l dir (mktemp -d)

cd $dir
_jj_git_status # CHECK: 1

mkdir -p $dir/jj-repo/.jj
cd $dir/jj-repo
_jj_git_status # CHECK: 0

mkdir -p $dir/jj-repo/nested/deeper
cd $dir/jj-repo/nested/deeper
_jj_git_status # CHECK: 0

touch $dir/jj-repo/.disable-jj-prompt
_jj_git_status # CHECK: 2

cd $dir
_jj_git_status # CHECK: 1

command rm -r $dir
