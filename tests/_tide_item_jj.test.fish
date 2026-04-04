# RUN: %fish %s
_tide_parent_dirs

function _jj_item
    _tide_decolor (_tide_item_jj)
end

set -l jj_mock_script 'if string match -q "log *" -- "$argv"
        printf "abc123\t.\tbookmark/main\tdefault\tdef456\t*\tfalse\tdesc\n"
    else if string match -q "workspace list *" -- "$argv"
        printf "default\n"
    else
        true
    end'
mock jj \* "$jj_mock_script"

set -l dir (mktemp -d)
mkdir -p $dir/{no-jj,jj-repo/.jj}

cd $dir/no-jj
_jj_item # CHECK:

cd $dir/jj-repo
_jj_item # CHECK: (@ abc123 main def456 * ↑1)

touch .disable-jj-prompt
_jj_item # CHECK:

command rm -r $dir
