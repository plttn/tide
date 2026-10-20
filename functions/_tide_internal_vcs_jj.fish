# full credits to https://github.com/nertzy/fish_jj_prompt
# for a lot of the logic here, modified for Tide
function _tide_internal_vcs_jj
    # A bare "M\n" line is emitted immediately before a commit's own content
    # line whenever that commit has more than one parent. It only fires for
    # @ and ahead-of-trunk commits (never the trunk() boundary itself, since
    # merges are common in a long-lived trunk's own history and are
    # irrelevant to the ahead-path's shape) -- it lets the loop below detect,
    # for free from this single jj invocation, whether every bookmarked
    # ancestor's position in $raw_lines can be trusted as its distance from
    # @. That trust breaks the moment the ahead-path branches: jj's log
    # order fully drains one parent line before the other, so a bookmark on
    # the second-visited branch gets a position inflated by the first
    # branch's length.
    set -l tmpl '
if(self.contained_in("::trunk() & ~::@"),
    "B\n",
    if(self.contained_in("@"),
        if(parents.len() > 1, "M\n") ++
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
            if(parents.len() > 1, "M\n") ++
            if(local_bookmarks,
                change_id.shortest() ++ "\t" ++ separate(",",
                    local_bookmarks.join(","),
                    if(tags, tags.join(",")),
                ) ++ "\n",
                "\n",
            )
        )
    )
)
'

    set -l raw_lines (jj log --no-pager --no-graph --ignore-working-copy --color=never \
        -r '@ | trunk()..@ | (::trunk() & ~::@)' \
        -T $tmpl 2>/dev/null)
    or return 1

    # Descriptions/bookmarks/tags are freeform text (unlike git refnames),
    # so scrub control/ESC bytes before they ever reach the terminal -- a
    # crafted commit description could otherwise inject escape sequences.
    # \t is preserved: it's this template's field separator.
    set raw_lines (string replace -ra '[\x00-\x08\x0b-\x1f\x7f]' '' -- $raw_lines)

    # If the ahead-path never branches, each bookmarked ancestor's position
    # in $raw_lines (tracked below via $ahead) equals its distance from @,
    # so we can skip the per-bookmark `jj log` call entirely. A single "M"
    # line anywhere means it doesn't, and every bookmark falls back to the
    # old per-cid query for correctness.
    set -l has_merge 0
    contains -- M $raw_lines
    and set has_merge 1

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

    # Bookmark names are often long ticket slugs, so cap each one's length
    # (configurable via tide_jj_bookmark_length; 0 disables truncation).
    set -l bm_length 24
    set -q tide_jj_bookmark_length; and set bm_length $tide_jj_bookmark_length

    set -l info ""
    set -l has_conflict 0
    set -l has_immutable 0
    set -l behind 0
    set -l ahead 0
    set -l display_bookmarks
    set -l ancestor_depth_forks 0

    for line in $raw_lines
        if test "$line" = B
            set behind (math $behind + 1)
            continue
        end
        if test "$line" = M
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
            set -l at_bookmarks_short ""
            if test "$parts[3]" != "."
                set -l at_bm_list
                set -l at_bm_short_list
                for bookmark in (string split ',' -- $parts[3])
                    set full_bookmark (string trim -- $bookmark)
                    set bm_components (string split "/" -- $full_bookmark)
                    set -l at_bm $bm_components[-1]
                    if test -n "$at_bm"
                        if test $bm_length -gt 0; and test (string length -- $at_bm) -gt $bm_length
                            set at_bm (string sub -l $bm_length -- $at_bm)"…"
                        end
                        set -a at_bm_list "$bold_brmagenta$at_bm$reset"
                        # A shorter cut, used only when the prompt runs out of room
                        set -l at_bm_short $bm_components[-1]
                        test (string length -- $at_bm_short) -gt 12 && set at_bm_short (string sub -l 12 -- $at_bm_short)"…"
                        set -a at_bm_short_list "$bold_brmagenta$at_bm_short$reset"
                    end
                end
                if test (count $at_bm_list) -gt 0
                    set at_bookmarks " "(string join ' ' $at_bm_list)
                    set at_bookmarks_short " "(string join ' ' $at_bm_short_list)
                end
            end

            # Show workspace if multiple workspaces exist
            set -l workspace_label ""
            set -l wc_count (jj workspace list --no-pager --color=never --ignore-working-copy 2>/dev/null | count)
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

            # Kept as separate pieces so shorter versions can drop some of them
            set -f at_cid "$cid_color$parts[1]$reset"
            set -f at_bm_full "$at_bookmarks$workspace_label"
            set -f at_bm_short "$at_bookmarks_short$workspace_label"
            set -f at_commit " $bold_brblue$parts[5]$reset"
            set -f at_flags "$conflict_label $status_color$st$reset$divergent_label"
            set -f at_desc $desc_label
            set info 1
        else if test $nparts -eq 2
            # Ancestor with bookmarks: change_id, bookmarks
            set -l cid $parts[1]
            set -l depth ""
            if test $has_merge -eq 1
                # Depth requires one extra `jj log` fork per ancestor bookmark;
                # cap it so a deep stack of bookmarks on a merge-containing
                # ahead-path can't fork unboundedly -- bookmarks beyond the
                # cap still show, just without the `↑depth` suffix.
                if test $ancestor_depth_forks -lt 3
                    set ancestor_depth_forks (math $ancestor_depth_forks + 1)
                    set -l depth_commits (jj log --no-pager --no-graph --ignore-working-copy --color=never \
                        -r "$cid::@ ~ $cid" -T '".\n"' 2>/dev/null)
                    set depth (count $depth_commits)
                end
            else
                set depth (math $ahead - 1)
            end
            for bookmark in (string split ',' -- $parts[2])
                set bookmark (string trim -- $bookmark)
                if test -n "$bookmark"
                    if test $bm_length -gt 0; and test (string length -- $bookmark) -gt $bm_length
                        set bookmark (string sub -l $bm_length -- $bookmark)"…"
                    end
                    set -l nobold (printf '\e[22m')
                    if test -n "$depth"
                        set -a display_bookmarks "$magenta$bookmark$nobold$magenta↑$depth$reset$bold"
                    else
                        set -a display_bookmarks "$magenta$bookmark$reset$bold"
                    end
                end
            end
        end
        # "." lines and blank lines (nparts=1, not "B"/"M") just count toward ahead
    end

    # Assemble prompt
    set -l variants
    if test -n "$info"
        set -l ancestors ""
        if test (count $display_bookmarks) -gt 0
            set ancestors " "(string join ' ' $display_bookmarks)
        end
        set -l counts ""
        set -l nobold (printf '\e[22m')
        if test $ahead -gt 0
            set counts "$counts $nobold$gray↑$ahead$reset"
        end
        if test $behind -gt 0
            set counts "$counts $nobold$gray↓$behind$reset"
        end
        set -l at_color (set_color green)
        if test $has_conflict -eq 1
            set at_color (printf '\e[38;5;1m')
        else if test $has_immutable -eq 1
            set at_color (printf '\e[38;5;14m')
        end
        set -l parentheses_color (set_color $tide_jj_color)

        # The full segment first, then shorter versions, each dropping one more
        # optional field: description, ancestor bookmarks, commit id, then a
        # shorter cut of the bookmark at @, and last only the change id, status
        # and ahead/behind counts.
        for body in "$at_bm_full$at_commit$at_flags$at_desc$ancestors" \
            "$at_bm_full$at_commit$at_flags$ancestors" \
            "$at_bm_full$at_commit$at_flags" \
            "$at_bm_full$at_flags" \
            "$at_bm_short$at_flags" \
            "$at_flags"
            set -l info "$at_cid$body$counts"
            set -l variant
            if test $tide_jj_bg_color = normal # prints as normal
                set variant $( printf '\e[39m%s(%s%s%s%s%s)' "$parentheses_color" "$reset$bold" "$at_color" @ "$reset $info" "$full_reset$parentheses_color" )
            else # prints with bg support
                set variant (printf '(%s%s)' @ " $info")
            end
            contains -- "$variant" $variants || set -a variants "$variant"
        end
        set jj_status $variants[1]
    end

    # Where the line prompt allows it (the top line, left side), leave a
    # placeholder and hand over every version: the shell fills in the widest
    # one that still leaves the directory its full width when it draws the
    # prompt (see _tide_fit_jj), so it also adapts on resize.
    if test "$tide_jj_fit_width" = true; and test "$_tide_jj_fit_slot" = true; and set -q variants[2]
        set -g _tide_jj_render_variants $variants
        set jj_status @JJ@
    end

    _tide_print_item jj $tide_jj_icon' ' (echo -ns "$jj_status";)
end
