function _tide_1_line_prompt
    set -e _tide_jj_render_variants
    # The jj segment can only shrink to fit on the left side of the top line
    set -g _tide_jj_fit_slot true
    set -g add_prefix
    _tide_side=left for item in $_tide_left_items
        _tide_item_$item
    end
    set -g _tide_jj_fit_slot false
    set_color $prev_bg_color -b normal
    echo $tide_left_prompt_suffix

    set -g add_prefix
    _tide_side=right for item in $_tide_right_items
        _tide_item_$item
    end
    set_color $prev_bg_color -b normal
    echo $tide_right_prompt_suffix

    # Shorter versions of the jj segment, if it left a placeholder: one last
    # line, each version prefixed with \x1f (scrubbed from jj content, so it
    # can't appear inside one). The shell moves this line out of the render
    # before drawing it (see _tide_store_render).
    set -q _tide_jj_render_variants[1] && printf '\x1f%s' $_tide_jj_render_variants && echo
end

function _tide_item_pwd
    _tide_print_item pwd @PWD@
end
