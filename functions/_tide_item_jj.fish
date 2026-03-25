function _tide_item_jj
    if not command -sq jj; or not jj root --quiet &>/dev/null
        return 1
    end

    jj log -r@ -n1 --no-graph --color never -T '
        separate("\n",
            if(bookmarks, bookmarks.map(|x| x.name()).join(" "), change_id.shortest()),
            if(conflict, "1", "0"),
            diff.files().len(),
        )
    ' 2>/dev/null | read -fL location conflicted modified

    if test "$conflicted" = "1"
        set -g tide_jj_bg_color $tide_git_bg_color_urgent
    else if test "$modified" != "0" -a "$modified" != ""
        set -g tide_jj_bg_color $tide_git_bg_color_unstable
    end

    _tide_print_item jj $_tide_location_color$tide_jj_icon' ' (
        echo -ns $location
        if test "$conflicted" = "1"
            set_color $tide_git_color_conflicted; echo -ns " ~"
        end
        if test "$modified" != "0" -a "$modified" != ""
            set_color $tide_git_color_dirty; echo -ns " !"$modified
        end
    )
end
