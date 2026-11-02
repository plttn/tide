# RUN: %fish %s
_tide_parent_dirs

function _direnv
    _tide_decolor (_tide_item_direnv)
end

# Observe the effective colors at the rendering boundary, before ANSI stripping.
function _tide_print_item -a item
    printf '%s %s %s %s\n' $item $tide_direnv_color $tide_direnv_bg_color $argv[2]
end

set -e DIRENV_DIR
set -lx tide_direnv_icon ▼
set -lx tide_direnv_color green
set -lx tide_direnv_bg_color black
set -lx tide_direnv_color_denied red
set -lx tide_direnv_bg_color_denied white

_direnv # CHECK:

set -lx DIRENV_DIR
mock direnv status "echo Found RC allowed 0"
_direnv # CHECK: direnv green black ▼

mock direnv status "echo Found RC allowed 1"
_direnv # CHECK: direnv red white ▼

mock direnv status "echo Found RC allowed 2"
_direnv # CHECK: direnv red white ▼

# Call directly in the same shell to detect color overrides leaking between calls.
_tide_item_direnv # CHECK: direnv red white ▼
mock direnv status "echo Found RC allowed 0"
_tide_item_direnv # CHECK: direnv green black ▼

mock direnv status "echo Found RC allowed false"
_tide_item_direnv # CHECK: direnv red white ▼
mock direnv status "echo Found RC allowed true"
_tide_item_direnv # CHECK: direnv green black ▼

# Only Found determines the style, even when Loaded disagrees.
mock direnv status "printf '%s\\n' 'Loaded RC allowed 0' 'Found RC allowed 1'"
_direnv # CHECK: direnv red white ▼
mock direnv status "printf '%s\\n' 'Loaded RC allowed 2' 'Found RC allowed 0'"
_direnv # CHECK: direnv green black ▼

mock direnv status "echo Found RC allowed 10"
_direnv # CHECK: direnv green black ▼
mock direnv status "echo Found RC allowed unknown"
_direnv # CHECK: direnv green black ▼
mock direnv status "echo Loaded RC allowed 2"
_direnv # CHECK: direnv green black ▼
