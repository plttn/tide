# full credits to https://github.com/nertzy/fish_jj_prompt
# for a lot of the logic here, modified for Tide
function _tide_item_vcs
    _tide_internal_jj_git
    set -l jj_repo_status $status

    # Prefer jj formatting only when we're in a jj repo and jj is actually available.
    if test $jj_repo_status -eq 0; and command -sq jj
        set -l tmpl '
if(self.contained_in("::trunk() & ~::@"),
    "B\n",
    if(self.contained_in("@"),
        change_id.shortest() ++
            if(divergent, "/" ++ change_offset) ++
        "\t" ++
        if(self.contained_in("mine()"), ".", coalesce(author.email().local(), author.name(), ".")) ++
        "\t" ++
        coalesce(
            separate(",",
                if(local_bookmarks, local_bookmarks.join(",")),
            ),
            ".",
        ) ++ "\t" ++
        working_copies ++ "\t" ++
        commit_id.shortest() ++ "\t" ++
        separate(" ",
            if(conflict, "(conflict)"),
            if(divergent, "(divergent)"),
            if(hidden, "(hidden)"),
            coalesce(
                if(empty, "(empty)"),
                "*",
            ),
        ) ++ "\t" ++
        immutable ++ "\t" ++
        if(description, description.first_line(), "(no desc)") ++ "\n"
    ,
        if(self.contained_in("trunk()"),
            ".\n",
            if(local_bookmarks,
                change_id.shortest() ++ "\t" ++ separate(",",
                    local_bookmarks.join(","),
                    if(tags, tags.join(",")),
                ) ++ "\n",
            )
        )
    )
)
'

        set -l raw_lines (jj log --no-pager --no-graph --ignore-working-copy --color=never \
            -r '@ | trunk()..@ | (::trunk() & ~::@)' \
            -T $tmpl 2>/dev/null)
        or return 1

        # Colors
        # if bg color is normal, we can use matching jj colors
        if test $tide_jj_bg_color = normal
            set -f bold_brmagenta (set_color brmagenta)
            set -f magenta (set_color magenta)
            set -f bold_brblue (set_color brblue)
            set -f bold_brgreen (set_color brgreen)
            set -f bold_brred (set_color brred)
            set -f bold_yellow (set_color yellow)
            set -f gray (set_color brblack)
            set -f reset (printf '\e[39m')
        else # else we have a background, so we should just use the color controlled by the theme
            set -f bold_brmagenta (set_color $tide_jj_color)
            set -f magenta (set_color $tide_jj_color)
            set -f bold_brblue (set_color $tide_jj_color)
            set -f bold_brgreen (set_color $tide_jj_color)
            set -f bold_brred (set_color $tide_jj_color)
            set -f bold_yellow (set_color $tide_jj_color)
            set -f gray (set_color $tide_jj_color)
            set -l reset ()
        end

        set -l use_bold true
        set -q fish_jj_prompt_bold; and set use_bold $fish_jj_prompt_bold
        set -l bold ""
        test "$use_bold" = true; and set bold (printf '\e[1m')

        set -l info ""
        set -l has_conflict 0
        set -l has_immutable 0
        set -l behind 0
        set -l ahead 0
        set -l display_bookmarks

        for line in $raw_lines
            if test "$line" = B
                set behind (math $behind + 1)
                continue
            end

            set ahead (math $ahead + 1)
            set -l parts (string split \t -- $line)
            set -l nparts (count $parts)

            if test $nparts -ge 8
                # @ line fields: change_id[1] author[2] bookmarks[3] working_copies[4] commit_id[5] status[6] immutable[7] description[8]
                # Separate (divergent) from other status flags for distinct coloring
                set -l st $parts[6]
                set -l divergent_label ""
                set -l cid_color $bold_brmagenta
                if string match -q '*(divergent)*' -- "$st"
                    set -l divergent_esc (printf '\e[38;5;9m')
                    set divergent_label " $divergent_esc(divergent)$reset"
                    set cid_color $divergent_esc
                    set st (string replace ' (divergent)' '' -- $st)
                    set st (string replace '(divergent) ' '' -- $st)
                    set st (string replace '(divergent)' '' -- $st)
                end
                set -l conflict_label ""
                if string match -q '*(conflict)*' -- "$st"
                    set has_conflict 1
                    set conflict_label " $bold_brred(conflict)$reset"
                    set st (string replace ' (conflict)' '' -- $st)
                    set st (string replace '(conflict) ' '' -- $st)
                    set st (string replace '(conflict)' '' -- $st)
                end
                set -l status_color $bold_brgreen
                if test "$st" = "*"
                    set status_color $bold_yellow
                end
                if test "$parts[7]" = true
                    set has_immutable 1
                end

                # Bookmarks at @
                set -l at_bookmarks ""
                if test "$parts[3]" != "."
                    set -l at_bm_list
                    for bookmark in (string split ',' -- $parts[3])
                        set full_bookmark (string trim -- $bookmark)
                        set bm_components (string split "/" -- $full_bookmark)
                        if test -n "$bm_components[-1]"
                            set -a at_bm_list "$bold_brmagenta$bm_components[-1]$reset"
                        end
                    end
                    if test (count $at_bm_list) -gt 0
                        set at_bookmarks " "(string join ' ' $at_bm_list)
                    end
                end

                # Show workspace if multiple workspaces exist
                set -l workspace_label ""
                set -l wc_count (jj workspace list --no-pager --color=never 2>/dev/null | count)
                if test $wc_count -gt 1; and test -n "$parts[4]"
                    set -l bold_brgreen_color (set_color brgreen)
                    set workspace_label " $bold_brgreen_color$parts[4]$reset"
                end

                # Description (configurable via tide_jj_show_description and tide_jj_description_length)
                set -l show_desc true
                set -q tide_jj_show_description; and set show_desc $tide_jj_show_description
                set -l desc_length 24
                set -q tide_jj_description_length; and set desc_length $tide_jj_description_length
                set -l desc_label ""
                if test -n "$parts[8]"; and test "$show_desc" = true
                    set -l desc $parts[8]
                    if test $desc_length -gt 0; and test (string length -- $desc) -gt $desc_length
                        set desc (string sub -l $desc_length -- $desc)"…"
                    end
                    if test "$parts[8]" = "(no desc)"
                        set desc_label " $status_color$desc$reset"
                    else
                        set desc_label " $desc"
                    end
                end

                set info "$cid_color$parts[1]$reset$at_bookmarks$workspace_label $bold_brblue$parts[5]$reset$conflict_label $status_color$st$reset$divergent_label$desc_label"
            else if test $nparts -eq 2
                # Ancestor with bookmarks: change_id, bookmarks
                set -l cid $parts[1]
                set -l depth_commits (jj log --no-pager --no-graph --ignore-working-copy --color=never \
                    -r "$cid::@ ~ $cid" -T '".\n"' 2>/dev/null)
                set -l depth (count $depth_commits)
                for bookmark in (string split ',' -- $parts[2])
                    set bookmark (string trim -- $bookmark)
                    if test -n "$bookmark"
                        set -l nobold (printf '\e[22m')
                        set -a display_bookmarks "$magenta$bookmark$nobold$magenta↑$depth$reset$bold"
                    end
                end
            end
            # "." lines (nparts=1, not "B") just count toward ahead
        end

        # Assemble prompt
        if test -n "$info"
            if test (count $display_bookmarks) -gt 0
                set info "$info "(string join ' ' $display_bookmarks)
            end
            set -l nobold (printf '\e[22m')
            if test $ahead -gt 0
                set info "$info $nobold$gray↑$ahead$reset"
            end
            if test $behind -gt 0
                set info "$info $nobold$gray↓$behind$reset"
            end
            set -l at_color (set_color green)
            if test $has_conflict -eq 1
                set at_color (printf '\e[38;5;1m')
            else if test $has_immutable -eq 1
                set at_color (printf '\e[38;5;14m')
            end
            set -l parentheses_color (set_color $tide_jj_color)
            if test $tide_jj_bg_color = normal # prints as normal
                set jj_status $( printf '\e[39m%s(%s%s%s%s%s)' "$parentheses_color" "$reset$bold" "$at_color" @ "$reset $info" "$full_reset$parentheses_color" )
            else # prints with bg support
                set jj_status (printf '(%s%s)' @ " $info")
            end
        end

        _tide_print_item vcs $tide_jj_icon' ' (echo -ns "$jj_status";)
        return
    end

    if git branch --show-current 2>/dev/null | string shorten -"$tide_git_truncation_strategy"m$tide_git_truncation_length | read -l location
        git rev-parse --git-dir --is-inside-git-dir | read -fL gdir in_gdir
        set location $_tide_location_color$location
    else if test $pipestatus[1] != 0
        return
    else if git tag --points-at HEAD | string shorten -"$tide_git_truncation_strategy"m$tide_git_truncation_length | read location
        git rev-parse --git-dir --is-inside-git-dir | read -fL gdir in_gdir
        set location '#'$_tide_location_color$location
    else
        git rev-parse --git-dir --is-inside-git-dir --short HEAD | read -fL gdir in_gdir location
        set location @$_tide_location_color$location
    end

    # Operation
    if test -d $gdir/rebase-merge
        # Turn ANY into ALL, via double negation
        if not path is -v $gdir/rebase-merge/{msgnum,end}
            read -f step <$gdir/rebase-merge/msgnum
            read -f total_steps <$gdir/rebase-merge/end
        end
        test -f $gdir/rebase-merge/interactive && set -f operation rebase-i || set -f operation rebase-m
    else if test -d $gdir/rebase-apply
        if not path is -v $gdir/rebase-apply/{next,last}
            read -f step <$gdir/rebase-apply/next
            read -f total_steps <$gdir/rebase-apply/last
        end
        if test -f $gdir/rebase-apply/rebasing
            set -f operation rebase
        else if test -f $gdir/rebase-apply/applying
            set -f operation am
        else
            set -f operation am/rebase
        end
    else if test -f $gdir/MERGE_HEAD
        set -f operation merge
    else if test -f $gdir/CHERRY_PICK_HEAD
        set -f operation cherry-pick
    else if test -f $gdir/REVERT_HEAD
        set -f operation revert
    else if test -f $gdir/BISECT_LOG
        set -f operation bisect
    end

    # Git status/stash + Upstream behind/ahead
    test $in_gdir = true && set -l _set_dir_opt -C $gdir/..
    # Suppress errors in case we are in a bare repo or there is no upstream
    set -l stat (git $_set_dir_opt --no-optional-locks status --porcelain 2>/dev/null)
    string match -qr '(0|(?<stash>.*))\n(0|(?<conflicted>.*))\n(0|(?<staged>.*))
(0|(?<dirty>.*))\n(0|(?<untracked>.*))(\n(0|(?<behind>.*))\t(0|(?<ahead>.*)))?' \
        "$(git $_set_dir_opt stash list 2>/dev/null | count
        string match -r ^UU $stat | count
        string match -r ^[ADMR] $stat | count
        string match -r ^.[ADMR] $stat | count
        string match -r '^\?\?' $stat | count
        git rev-list --count --left-right @{upstream}...HEAD 2>/dev/null)"

    if test -n "$operation$conflicted"
        set -g tide_git_bg_color $tide_git_bg_color_urgent
    else if test -n "$staged$dirty$untracked"
        set -g tide_git_bg_color $tide_git_bg_color_unstable
    end

    _tide_print_item vcs $_tide_location_color$tide_git_icon' ' (set_color white; echo -ns $location
        set_color $tide_git_color_operation; echo -ns ' '$operation ' '$step/$total_steps
        set_color $tide_git_color_upstream; echo -ns ' ⇣'$behind ' ⇡'$ahead
        set_color $tide_git_color_stash; echo -ns ' *'$stash
        set_color $tide_git_color_conflicted; echo -ns ' ~'$conflicted
        set_color $tide_git_color_staged; echo -ns ' +'$staged
        set_color $tide_git_color_dirty; echo -ns ' !'$dirty
        set_color $tide_git_color_untracked; echo -ns ' ?'$untracked)
end
