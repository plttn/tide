function _tide_sub_items
    if test $COLUMNS -lt 55 -o $LINES -lt 21
        echo 'Terminal size too small; must be at least 55 x 21'
        return 1
    end

    # Loads the wizard's preview machinery, which the editor draws with
    functions --query _tide_sub_configure

    # Preview with the current config, so it shows your own colors and icons
    for var in (set --names | string match -r '^tide_.*')
        set -g fake_$var $$var
    end
    set -g fake_columns $COLUMNS
    test $fake_columns -gt 90 && set fake_columns 90
    set -g fake_lines $LINES

    set -l keep false
    _tide_items_editor && set keep true
    set -l left $fake_tide_left_prompt_items
    set -l right $fake_tide_right_prompt_items
    command -q clear && clear

    for var in (set --names | string match -r '^fake_(?:tide_.*|columns|lines)$')
        set -e $var
    end

    if test $keep = true
        set -U tide_left_prompt_items $left
        set -U tide_right_prompt_items $right
        tide reload
    end
end
