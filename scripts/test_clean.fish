#!/usr/bin/env fish

set -l cache_home $XDG_CACHE_HOME
test -n "$cache_home" || set cache_home $HOME/.cache
set -l test_home $cache_home/tide-test-home

if test -d $test_home
    command rm -r $test_home
    echo "Removed $test_home"
else
    echo "Nothing to clean: $test_home does not exist"
end
