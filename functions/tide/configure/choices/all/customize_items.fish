function customize_items
    # Not asked in --auto mode, so --auto command lines from before this step
    # existed still work
    if set -q _flag_auto
        _next_choice all/finish
        return
    end

    _tide_title 'Prompt Items'

    _tide_option 1 'Keep these items'
    _tide_display_prompt

    _tide_option 2 'Choose which items show and where'
    echo 'Your choices here are not part of the printed `tide configure --auto` command.'

    _tide_menu (status function)
    # An editor session can't be replayed from the command line, so leave this
    # step out of the printed command
    string match -q -- '--customize_items=*' "$_tide_configure_current_options[-1]" &&
        set -e _tide_configure_current_options[-1]

    switch $_tide_selected_option
        case 'Choose which items show and where'
            if not _tide_items_editor
                # Cancelled: back to this menu
                customize_items
                return
            end
    end
    _next_choice all/finish
end
