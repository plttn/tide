function _tide_remove_unusable_items --on-variable PATH
    # Remove tool-specific items for tools the machine doesn't have installed.
    #
    # Each lookup below walks every PATH directory, which is slow where PATH
    # holds slow directories: WSL adds the Windows ones under /mnt/c, where a
    # missing tool costs ~60 ms, and over a second for the default items. So
    # the answer is kept in universal variables, keyed on PATH and the prompt
    # items, and an unchanged key reuses it: a new shell, or a tool (mise,
    # direnv, ...) setting PATH to the same value again on every prompt.
    # Reusing an earlier shell's answer sets $_tide_unusable_items_reused, and
    # fish_prompt then re-checks in the background with --refresh, so a tool
    # installed or removed since is still picked up.
    set -e _tide_unusable_items_reused
    # Escaped, so joining the list with spaces for comparison is unambiguous
    set -l key (string escape -- $PATH '|' $tide_left_prompt_items '|' $tide_right_prompt_items)
    if not contains -- --refresh $argv && test "$key" = "$_tide_unusable_items_key" && set -q _tide_left_items
        # the answer for this exact PATH and items is already stored
        set -g _tide_unusable_items_reused
        return
    end

    set -l removed_items
    for item in aws bun crystal direnv distrobox docker elixir gcloud go java kubectl nix_shell node php pulumi python ruby rustc terraform toolbox vcs zig
        contains $item $tide_left_prompt_items $tide_right_prompt_items || continue

        set -l cli_names $item
        switch $item
            case distrobox # there is no 'distrobox' command inside the container
                set cli_names distrobox-export # 'distrobox-export' and 'distrobox-host-exec' are available
            case nix_shell
                set cli_names nix nix-shell
            case python
                set cli_names python python3
            case vcs
                set cli_names git
        end
        type --query $cli_names || set -a removed_items $item
    end

    # The lookups can take a while, so if the prompt items changed meanwhile
    # (e.g. `tide configure` in another shell), this answer is for the old
    # ones: leave the result to the check that change triggers.
    set -l key_now (string escape -- $PATH '|' $tide_left_prompt_items '|' $tide_right_prompt_items)
    test "$key" = "$key_now" || return

    set -l left (for item in $tide_left_prompt_items
        contains $item $removed_items || echo $item
    end)
    set -l right (for item in $tide_right_prompt_items
        contains $item $removed_items || echo $item
    end)
    # Universal writes reach every running shell, so skip them when nothing
    # changed (the usual outcome of a --refresh)
    test "$left" = "$_tide_left_items" || set -U _tide_left_items $left
    test "$right" = "$_tide_right_items" || set -U _tide_right_items $right
    test "$key" = "$_tide_unusable_items_key" || set -U _tide_unusable_items_key $key
end
