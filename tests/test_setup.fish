function _tide_decolor
    string replace --all -r '\e(\[[\d;]*|\(B\e\[)m(\co)?' '' "$argv"
end
funcsave _tide_decolor

# Tests that change tide_* universal variables call these around their
# changes. The local test HOME is kept between runs, so a test that erased
# them afterwards left later runs with no prompt items at all.
function _tide_test_save_universals
    set -g _tide_test_saved_names (set -U --names | string match 'tide_*')
    set -g _tide_test_saved_exported
    for name in $_tide_test_saved_names
        set -g _tide_test_saved_$name $$name
        set -qUx $name && set -a _tide_test_saved_exported $name
    end
end
funcsave _tide_test_save_universals

function _tide_test_restore_universals
    for name in (set -U --names | string match 'tide_*')
        set -eU $name
    end
    for name in $_tide_test_saved_names
        set -l saved _tide_test_saved_$name
        if contains -- $name $_tide_test_saved_exported
            set -Ux $name $$saved
        else
            set -U $name $$saved
        end
    end
end
funcsave _tide_test_restore_universals

echo "\
set TERM xterm-256color
set -g _tide_side right" >$__fish_config_dir/conf.d/tide_test_setup.fish
