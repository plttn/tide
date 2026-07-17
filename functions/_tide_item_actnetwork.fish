function _tide_item_actnetwork
    set -f active_interfaces (nmcli -g type c show --active)
    set -f icon

    if string match -q wireguard $active_interfaces
        set -a icon '󰒄 '
    end
    if string match -q gsm $active_interfaces
        set -a icon ' '
    end
    if string match -q '*-wireless' $active_interfaces
        set -a icon ' '
    end
    if string match -q '*-ethernet' $active_interfaces
        set -a icon '󰈀 '
    end

    if not string length -q $icon
        set icon '󰛵 '
    end

    _tide_print_item actnetwork $icon
end
