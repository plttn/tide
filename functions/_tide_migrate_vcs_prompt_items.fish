function _tide_migrate_vcs_prompt_items
    for prompt_side in left right
        set -l var_name tide_{$prompt_side}_prompt_items
        set -l items $$var_name

        contains git $items; or contains jj $items; or continue

        set -l migrated_items
        set -l inserted_vcs false
        for item in $items
            switch $item
                case git jj
                    if test "$inserted_vcs" = false
                        set -a migrated_items vcs
                        set inserted_vcs true
                    end
                case '*'
                    set -a migrated_items $item
            end
        end

        test "$items" = "$migrated_items"; and continue
        set -U $var_name $migrated_items
    end
end
