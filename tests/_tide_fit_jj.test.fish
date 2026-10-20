# RUN: %fish %s
# The jj segment shrinks to fit the top line, giving way to the directory.
# Renders run in a separate fish, so jj has to be a real executable on PATH
# rather than a mocked function.
_tide_test_save_universals
set -U tide_left_prompt_items pwd vcs
set -U tide_right_prompt_items
set -U tide_prompt_add_newline_before false
set -U tide_left_prompt_frame_enabled false
set -U tide_right_prompt_frame_enabled false
set -U tide_prompt_min_cols 1
set -U tide_pwd_icon
set -U tide_pwd_icon_home
set -U tide_pwd_icon_unwritable
set -U tide_jj_fit_width true
set -U tide_jj_show_description true
set -gx LINES 24

set -g fake_bin (mktemp -d)
printf '#!/bin/sh
case "$*" in
  *"workspace list"*) printf "default\\n" ;;
  *"log"*) printf "xyz999\\t.\\tfeature/my-at-bookmark-name\\tdefault\\tdef999\\t*\\tfalse\\ta fairly long description\\nanc111\\tparent-bookmark\\n" ;;
esac
' >$fake_bin/jj
chmod +x $fake_bin/jj
# Under $HOME, so the directory is drawn as a short `~/jj-fit` everywhere
set -l repo $HOME/jj-fit
mkdir -p $repo/.jj
cd $repo

# Renders once at the first width, then redraws at each further width the way
# a terminal resize does: from the same render, without starting a new one.
# $argv[1] picks which line of the drawn prompt to print.
function _draw_widths
    env PATH="$fake_bin:$PATH" fish -i -c '
        set COLUMNS $argv[2]
        fish_prompt >/dev/null
        for i in (seq 1 100)
            set -q _tide_repaint && break
            sleep 0.02
        end
        for columns in $argv[2..]
            set COLUMNS $columns
            _tide_repaint_on_resize
            # Split into lines first: _tide_decolor joins its arguments
            set -l drawn (fish_prompt)
            echo $columns: (_tide_decolor $drawn[$argv[1]])
        end
    ' $argv </dev/null
end

# One line: each step down drops one more field, and the directory always
# keeps its full width
_draw_widths 1 110 85 60 49 42 30 110
# CHECK: 110: ~/jj-fit (@ xyz999 my-at-bookmark-name def999 * a fairly long descriptio… parent-bookmark↑1 ↑2){{ *}}
# CHECK: 85: ~/jj-fit (@ xyz999 my-at-bookmark-name def999 * parent-bookmark↑1 ↑2){{ *}}
# CHECK: 60: ~/jj-fit (@ xyz999 my-at-bookmark-name def999 * ↑2){{ *}}
# CHECK: 49: ~/jj-fit (@ xyz999 my-at-bookmark-name * ↑2){{ *}}
# CHECK: 42: ~/jj-fit (@ xyz999 my-at-bookma… * ↑2){{ *}}
# CHECK: 30: ~/jj-fit (@ xyz999 * ↑2){{ *}}
# CHECK: 110: ~/jj-fit (@ xyz999 my-at-bookmark-name def999 * a fairly long descriptio… parent-bookmark↑1 ↑2){{ *}}

# Turned off, the full segment is drawn whatever the width
set -U tide_jj_fit_width false
_draw_widths 1 30
# CHECK: 30: ~/jj-fit (@ xyz999 my-at-bookmark-name def999 * a fairly long descriptio… parent-bookmark↑1 ↑2){{ *}}
set -U tide_jj_fit_width true

# Two lines: the top line shrinks the same way
set -U tide_left_prompt_items pwd vcs newline character
_draw_widths 1 85 30
# CHECK: 85: ~/jj-fit (@ xyz999 my-at-bookmark-name def999 * parent-bookmark↑1 ↑2){{.*}}
# CHECK: 30: ~/jj-fit (@ xyz999 * ↑2){{.*}}

# On the bottom line it isn't fitted, and no placeholder is left behind
set -U tide_left_prompt_items pwd newline vcs character
_draw_widths 2 30
# CHECK: 30: {{.*}}(@ xyz999 my-at-bookmark-name def999 * a fairly long descriptio… parent-bookmark↑1 ↑2){{.*}}

cd /
command rm -r $fake_bin $repo
functions -e _draw_widths
_tide_test_restore_universals
