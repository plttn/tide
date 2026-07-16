function _tide_item_go
    if path is $_tide_parent_dirs/go.mod
        _tide_memoize go "$(path resolve (command -s go))" go version | string match -qr "(?<v>[\d.]+)"
        _tide_print_item go $tide_go_icon' ' $v
    end
end
