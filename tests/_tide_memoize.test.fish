# RUN: %fish %s
set -l tmpdir (mktemp -d)

# No $_tide_prompt_tmpdir set: runs directly, no caching, no error.
set -e _tide_prompt_tmpdir
_tide_memoize noop keyA echo direct # CHECK: direct

set -gx _tide_prompt_tmpdir $tmpdir
set -l counter (mktemp)
echo 0 >$counter

function _memoized_call -a counter
    set -l n (cat $counter)
    math $n + 1 >$counter
    echo v1.2.3
end

# First call: cache miss, underlying command runs (counter -> 1).
_tide_memoize thing keyA _memoized_call $counter # CHECK: v1.2.3
cat $counter # CHECK: 1

# Second call, same key: cache hit, underlying command does not run again.
_tide_memoize thing keyA _memoized_call $counter # CHECK: v1.2.3
cat $counter # CHECK: 1

# Key changes: cache miss again (counter -> 2).
_tide_memoize thing keyB _memoized_call $counter # CHECK: v1.2.3
cat $counter # CHECK: 2

# Multi-line output round-trips intact through both the miss and hit paths.
function _multiline_call
    echo line-one
    echo line-two
end
_tide_memoize multi keyA _multiline_call
# CHECK: line-one
# CHECK: line-two
_tide_memoize multi keyA _multiline_call
# CHECK: line-one
# CHECK: line-two

command rm -r $tmpdir $counter
