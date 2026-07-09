# RUN: %fish %s
set -l dead_pid (fish -c 'echo $fish_pid')

set -U _tide_prompt_$dead_pid ''
set -U _tide_prompt_$fish_pid ''
set -U _tide_prompt_notanumber ''
set -U some_other_var_$dead_pid ''

_tide_migrate_orphaned_prompt_vars

set -U --names | string match _tide_prompt_$dead_pid | count # CHECK: 0
set -U --names | string match _tide_prompt_$fish_pid | count # CHECK: 1
set -U --names | string match _tide_prompt_notanumber | count # CHECK: 1
set -U --names | string match some_other_var_$dead_pid | count # CHECK: 1

set -e _tide_prompt_$fish_pid _tide_prompt_notanumber some_other_var_$dead_pid
