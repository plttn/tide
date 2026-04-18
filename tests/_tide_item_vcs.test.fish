# RUN: %fish %s
_tide_parent_dirs

function _git
    git $argv >/dev/null 2>&1
end

function _vcs_item
    _tide_decolor (_tide_item_vcs)
end

# Create directory
set -l dir (mktemp -d)
mkdir -p $dir/{normal-repo, bare-repo, submodule-repo, massive-status-repo, no-jj, jj-repo/.jj, bin}

# Not in a VCS repo
cd $dir
_vcs_item # CHECK:

# -------- git repo tests --------
cd $dir/normal-repo
_git init
_git branch -m main

# Branch
_vcs_item # CHECK: main

# .git dir
cd .git/
_vcs_item # CHECK: main
cd ..

# Untracked
echo >foo
_vcs_item # CHECK: main ?1

# Staged
_git add foo
_vcs_item # CHECK: main +1

git config --local user.email "you@example.com"
git config --local user.name "Your Name"
_git commit -am 'Add foo'

# Dirty
echo hello >foo
_vcs_item # CHECK: main !1

# Stash
_git stash
_vcs_item # CHECK: main *1

_git stash pop
_git commit -am 'Append hello to foo'

# SHA
_git checkout HEAD~
_vcs_item # CHECK: {{@\w*}}

# --- Long branches ---
_git checkout main
_git checkout -b very_long_branch_name
set -lx tide_git_truncation_length 10
set -lx tide_git_truncation_strategy
_vcs_item # CHECK: very_long…
set -lx tide_git_truncation_strategy l
_vcs_item # CHECK: …anch_name

# Branch same length as tide_git_truncation_length
_git checkout -b 10charhere
_vcs_item # CHECK: 10charhere

# -------- bare repo test --------
cd $dir/bare-repo
_git init --bare
_git branch -m main
_vcs_item # CHECK: main

# ------ submodule repo test ------
cd $dir/submodule-repo
_git init
_git branch -m main

# temporary workaround for git bug https://bugs.launchpad.net/ubuntu/+source/git/+bug/1993586
_git -c protocol.file.allow=always submodule add $dir/normal-repo
_vcs_item # CHECK: main +2
cd normal-repo
_vcs_item # CHECK: 10charhere
cd ..

echo >new_main_git_file
_vcs_item # CHECK: main +2 ?1
echo >normal-repo/new_submodule_file
_vcs_item # CHECK: main +2 !1 ?1
cd normal-repo
_vcs_item # CHECK: 10charhere ?1

# --- Massive git status ---
cd $dir/massive-status-repo
_git init
_git branch -m main
mock git "--no-optional-locks status --porcelain" "string repeat -n100000 'D  some-file-name'\n"
_vcs_item # CHECK: main +100000

# -------- jj repo tests --------
cd $dir/no-jj
_vcs_item # CHECK:

printf '#!/bin/sh\ncmd="$*"\ncase "$cmd" in\n  *"workspace list"*) printf "default\\n" ;;\n  *"log"*) printf "abc123\\t.\\tbookmark/main\\tdefault\\tdef456\\t*\\tfalse\\tdesc\\n" ;;\n  *) exit 0 ;;\nesac\n' >$dir/bin/jj
chmod +x $dir/bin/jj
set -gx PATH $dir/bin $PATH

cd $dir/jj-repo
_vcs_item # CHECK: (@ abc123 main def456 * desc ↑1)

set -g tide_jj_show_description false
_vcs_item # CHECK: (@ abc123 main def456 * ↑1)

touch .disable-jj-prompt
_vcs_item # CHECK:

# ------ cleanup ------
command rm -r $dir
