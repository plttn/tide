set -l tide_test_setup $__fish_config_dir/conf.d/tide_test_setup.fish
if test -f $tide_test_setup
    command rm $tide_test_setup
end
