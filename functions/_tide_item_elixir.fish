function _tide_item_elixir
    path is $_tide_parent_dirs/mix.exs &&
        _tide_print_item elixir $tide_elixir_icon' ' (_tide_memoize elixir "$(path resolve (command -s elixir))" elixir --short-version)
end
