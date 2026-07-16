function _tide_item_ruby
    if path is $_tide_parent_dirs/{*.gemspec,Gemfile,Rakefile,.ruby-version}
        _tide_memoize ruby "$(path resolve (command -s ruby))" ruby --version | string match -qr "(?<v>[\d.]+)"
        _tide_print_item ruby $tide_ruby_icon' ' $v
    end
end
