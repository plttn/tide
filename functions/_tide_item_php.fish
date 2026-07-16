function _tide_item_php
    if path is $_tide_parent_dirs/composer.json
        _tide_memoize php "$(path resolve (command -s php))" php --version | string match -qr "(?<v>[\d.]+)"
        _tide_print_item php $tide_php_icon' ' $v
    end
end
