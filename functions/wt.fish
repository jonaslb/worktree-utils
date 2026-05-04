function _wt_usage
    echo "wt: git worktree helper for fish"
    echo
    echo "Usage:"
    echo "  wt co <branch>"
    echo "  wt new <new-branch> [base-branch]"
    echo "  wt rm [-f] <branch> [branch ...]"
    echo "  wt prune-merged"
    echo "  wt convert"
    echo "  wt update"
    echo "  wt status"
    echo "  wt prompt-pwd"
    echo "  wt help [install]"
    echo
    echo "Commands:"
    echo "  co           Checkout an existing branch into proj_dir/<branch> (main uses proj_dir/project_name)"
    echo "  new          Create a new branch from main (or a provided base branch)"
    echo "  rm           Remove a branch and its worktree (confirms if not merged)"
    echo "  prune-merged Remove all branches merged into main"
    echo "  convert      Convert a normal repo to the .bare + worktree layout"
    echo "  update       Pull updates for tracking branches across worktrees, and offer main path migration"
    echo "  status       Show one-line status for all project worktrees"
    echo "  prompt-pwd   Print prompt path with full project name when in wt layout"
    echo "  help         Show command help"
end

function _wt_install_help
    echo "Installation (fish):"
    echo "  1. Copy functions/wt.fish to ~/.config/fish/functions/wt.fish"
    echo "  2. Copy completions/wt.fish to ~/.config/fish/completions/wt.fish"
    echo
    echo "Or symlink both files from this repo into your fish config."
end

function _wt_find_project_dir
    set -l dir (pwd)
    while true
        if test -d "$dir/.bare"
            echo "$dir"
            return 0
        end

        if test "$dir" = "/"
            return 1
        end

        set dir (dirname "$dir")
    end
end

function _wt_main_worktree_path
    set -l project_dir "$argv[1]"
    echo "$project_dir/"(basename "$project_dir")
end

function _wt_branch_worktree_path
    set -l project_dir "$argv[1]"
    set -l branch "$argv[2]"
    if test "$branch" = "main"
        _wt_main_worktree_path "$project_dir"
        return 0
    end

    echo "$project_dir/$branch"
end

function _wt_cd_main_worktree_or_project
    set -l project_dir "$argv[1]"
    set -l main_path (_wt_main_worktree_path "$project_dir")
    if test -d "$main_path"
        cd "$main_path"
        return $status
    end

    set -l legacy_path "$project_dir/main"
    if test -d "$legacy_path"
        cd "$legacy_path"
        return $status
    end

    cd "$project_dir"
end

function _wt_autodetect_repo_projects
    set -l path "$argv[1]"
    if test -z "$path"
        set path (pwd)
    end

    set -l detected
    if test -f "$path/pyproject.toml"
        set detected $detected pyproject
    end

    printf "%s\n" $detected
end

function _wt_sync_repo_projects
    set -l path "$argv[1]"

    for project_type in (_wt_autodetect_repo_projects "$path")
        switch "$project_type"
            case pyproject
                echo "Detected pyproject project in $path; running uv sync ..."
                command uv sync --directory "$path"
                or return 1
        end
    end
end

function _wt_ref_exists
    set -l bare "$argv[1]"
    set -l ref "$argv[2]"
    command git --git-dir "$bare" show-ref --verify --quiet "$ref"
end

function _wt_find_remote_ref
    set -l bare "$argv[1]"
    set -l branch "$argv[2]"

    for remote in (command git --git-dir "$bare" remote)
        set -l remote_ref "refs/remotes/$remote/$branch"
        if _wt_ref_exists "$bare" "$remote_ref"
            echo "$remote/$branch"
            return 0
        end
    end

    return 1
end

function _wt_is_registered_worktree_path
    set -l bare "$argv[1]"
    set -l path "$argv[2]"
    command git --git-dir "$bare" worktree list --porcelain | string match -q -- "worktree $path"
end

function _wt_write_zed_project_name
    set -l project_dir "$argv[1]"
    set -l worktree_path "$argv[2]"

    set -l base_name (string sub -s 1 -l 16 -- (basename "$project_dir"))
    set -l wt_name (_wt_worktree_name "$project_dir" "$worktree_path")
    set -l project_name "$base_name/$wt_name"

    set -l zed_dir "$worktree_path/.zed"
    set -l settings_file "$zed_dir/settings.json"

    mkdir -p "$zed_dir"

    set -l gitignore_file "$zed_dir/.gitignore"
    if not test -f "$gitignore_file"
        printf "# Automatically created by wt\n*\n" > "$gitignore_file"
    end

    if test -f "$settings_file"
        python3 -c "
import json, sys
path, name = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}
data['project_name'] = name
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$settings_file" "$project_name"
    else
        printf '{\n  "project_name": "%s"\n}\n' "$project_name" > "$settings_file"
    end
end

function _wt_co
    if test (count $argv) -ne 1
        echo "Usage: wt co <branch>" >&2
        return 1
    end

    set -l branch "$argv[1]"
    set -l project_dir (_wt_find_project_dir)
    if test $status -ne 0
        echo "Not inside a worktree project (missing .bare in parent path)." >&2
        return 1
    end

    set -l bare "$project_dir/.bare"
    set -l target (_wt_branch_worktree_path "$project_dir" "$branch")

    if test -e "$target"
        if _wt_is_registered_worktree_path "$bare" "$target"
            cd "$target"
            return 0
        end

        echo "Target path already exists and is not a registered worktree: $target" >&2
        return 1
    end

    mkdir -p (dirname "$target")

    if _wt_ref_exists "$bare" "refs/heads/$branch"
        command git --git-dir "$bare" worktree add "$target" "$branch"
    else
        set -l remote_ref (_wt_find_remote_ref "$bare" "$branch")
        if test $status -eq 0
            command git --git-dir "$bare" worktree add --track -b "$branch" "$target" "$remote_ref"
        else
            echo "Branch '$branch' does not exist. Use 'wt new $branch' to create it." >&2
            return 1
        end
    end

    if test $status -ne 0
        return $status
    end

    _wt_write_zed_project_name "$project_dir" "$target"
    _wt_sync_repo_projects "$target"
    or return 1
    cd "$target"
end

function _wt_new
    if test (count $argv) -lt 1 -o (count $argv) -gt 2
        echo "Usage: wt new <new-branch> [base-branch]" >&2
        return 1
    end

    set -l new_branch "$argv[1]"
    set -l base_branch "main"
    if test (count $argv) -eq 2
        set base_branch "$argv[2]"
    end

    set -l project_dir (_wt_find_project_dir)
    if test $status -ne 0
        echo "Not inside a worktree project (missing .bare in parent path)." >&2
        return 1
    end

    set -l bare "$project_dir/.bare"

    if _wt_ref_exists "$bare" "refs/heads/$new_branch"
        echo "Branch '$new_branch' already exists." >&2
        return 1
    end

    set -l existing_remote (_wt_find_remote_ref "$bare" "$new_branch")
    if test $status -eq 0
        echo "Branch '$new_branch' already exists on remote as '$existing_remote'." >&2
        return 1
    end

    set -l base_ref ""
    if _wt_ref_exists "$bare" "refs/heads/$base_branch"
        set base_ref "$base_branch"
    else
        set -l remote_ref (_wt_find_remote_ref "$bare" "$base_branch")
        if test $status -eq 0
            set base_ref "$remote_ref"
        else
            echo "Base branch '$base_branch' was not found." >&2
            return 1
        end
    end

    set -l target (_wt_branch_worktree_path "$project_dir" "$new_branch")
    if test -e "$target"
        echo "Target path already exists: $target" >&2
        return 1
    end

    mkdir -p (dirname "$target")
    command git --git-dir "$bare" worktree add -b "$new_branch" "$target" "$base_ref"
    if test $status -ne 0
        return $status
    end

    _wt_write_zed_project_name "$project_dir" "$target"
    _wt_sync_repo_projects "$target"
    or return 1
    cd "$target"
end

function _wt_convert
    if test (count $argv) -ne 0
        echo "Usage: wt convert" >&2
        return 1
    end

    set -l repo_root (command git rev-parse --show-toplevel 2>/dev/null)
    if test $status -ne 0
        echo "Not inside a git repository." >&2
        return 1
    end

    if test -d "$repo_root/.bare"
        echo "Repository already appears converted (.bare exists)." >&2
        return 1
    end

    if not test -d "$repo_root/.git"
        echo "This repo is not a normal checkout with a .git directory." >&2
        return 1
    end

    set -l current_branch (command git -C "$repo_root" branch --show-current)
    if test -z "$current_branch"
        echo "Detached HEAD is not supported for conversion." >&2
        return 1
    end

    set -l dirty (command git -C "$repo_root" status --porcelain --untracked-files=normal)
    if test -n "$dirty"
        echo "Working tree is not clean. Commit/stash/remove changes before conversion." >&2
        return 1
    end

    mv "$repo_root/.git" "$repo_root/.bare"
    or return 1

    command git --git-dir "$repo_root/.bare" config --bool core.bare true
    or return 1
    command git --git-dir "$repo_root/.bare" config --unset core.worktree >/dev/null 2>&1

    set -l main_path (_wt_main_worktree_path "$repo_root")
    command git --git-dir "$repo_root/.bare" worktree add "$main_path" "$current_branch"
    or return 1

    for entry in (command find "$repo_root" -mindepth 1 -maxdepth 1)
        set -l name (basename "$entry")
        if test "$name" = ".bare" -o "$entry" = "$main_path"
            continue
        end
        rm -rf "$entry"
    end

    _wt_write_zed_project_name "$repo_root" "$main_path"
    echo "Conversion complete. Main worktree: $main_path"
end

function _wt_list_worktree_paths
    set -l bare "$argv[1]"
    command git --git-dir "$bare" worktree list --porcelain | command awk '/^worktree / { sub(/^worktree /, ""); print }'
end

function _wt_worktree_name
    set -l project_dir "$argv[1]"
    set -l path "$argv[2]"
    set -l project_prefix (string escape --style=regex -- "$project_dir/")
    string replace -r "^$project_prefix" "" -- "$path"
end

function _wt_worktree_path_matches_branch
    set -l project_dir "$argv[1]"
    set -l path "$argv[2]"
    set -l branch "$argv[3]"
    set -l expected_path (_wt_branch_worktree_path "$project_dir" "$branch")
    test "$path" = "$expected_path"
end

function _wt_offer_main_worktree_migration
    set -l project_dir "$argv[1]"
    set -l bare "$argv[2]"
    set -l legacy_path "$project_dir/main"
    set -l canonical_path (_wt_main_worktree_path "$project_dir")

    if test "$legacy_path" = "$canonical_path"
        return 0
    end

    if not _wt_is_registered_worktree_path "$bare" "$legacy_path"
        return 0
    end

    set -l branch (command git -C "$legacy_path" symbolic-ref --quiet --short HEAD 2>/dev/null)
    if test "$branch" != "main"
        return 0
    end

    if test -e "$canonical_path"
        echo "[main] legacy main worktree is at $legacy_path, but target already exists: $canonical_path" >&2
        echo "[main] Move or remove the target manually, then run wt update again." >&2
        return 1
    end

    read -l -P "Move main worktree from $legacy_path to $canonical_path? [y/N] " confirm
    if not string match -qi -- 'y' "$confirm"
        echo "[main] keeping legacy path: $legacy_path"
        return 0
    end

    set -l old_cwd (pwd)
    set -l moved_cwd ""
    if test "$old_cwd" = "$legacy_path"
        set moved_cwd "$canonical_path"
    else if string match -q -- "$legacy_path/*" "$old_cwd"
        set -l rel (string replace "$legacy_path/" "" -- "$old_cwd")
        set moved_cwd "$canonical_path/$rel"
    end

    if test -n "$moved_cwd"
        cd "$project_dir"
        or return 1
    end

    mkdir -p (dirname "$canonical_path")
    command git --git-dir "$bare" worktree move "$legacy_path" "$canonical_path"
    or return $status

    _wt_write_zed_project_name "$project_dir" "$canonical_path"

    if test -n "$moved_cwd"
        cd "$moved_cwd"
        or return 1
    end

    echo "[main] moved main worktree to $canonical_path"
end

function _wt_ahead_behind
    set -l path "$argv[1]"
    set -l upstream "$argv[2]"
    if test -z "$upstream"
        return 1
    end
    set -l counts_raw (command git -C "$path" rev-list --left-right --count HEAD..."$upstream" 2>/dev/null)
    set -l counts (string split \t -- "$counts_raw")
    if test (count $counts) -lt 2
        set counts (string split ' ' -- "$counts_raw")
    end
    if test (count $counts) -lt 2
        return 1
    end
    echo "$counts[1]"
    echo "$counts[2]"
end

function _wt_dirty_counts
    set -l path "$argv[1]"
    set -l staged 0
    set -l unstaged 0
    set -l untracked 0

    for line in (command git -C "$path" status --porcelain --untracked-files=normal 2>/dev/null)
        if string match -q -- '?? *' "$line"
            set untracked (math "$untracked + 1")
            continue
        end

        set -l index_state (string sub -s 1 -l 1 -- "$line")
        set -l worktree_state (string sub -s 2 -l 1 -- "$line")
        if test "$index_state" != " "
            set staged (math "$staged + 1")
        end
        if test "$worktree_state" != " "
            set unstaged (math "$unstaged + 1")
        end
    end

    echo $staged
    echo $unstaged
    echo $untracked
end

function _wt_rm
    set -l force 0
    set -l branches

    for arg in $argv
        switch "$arg"
            case -f
                set force 1
            case '-*'
                echo "Usage: wt rm [-f] <branch> [branch ...]" >&2
                return 1
            case '*'
                set branches $branches "$arg"
        end
    end

    if test (count $branches) -eq 0
        echo "Usage: wt rm [-f] <branch> [branch ...]" >&2
        return 1
    end

    set -l project_dir (_wt_find_project_dir)
    if test $status -ne 0
        echo "Not inside a worktree project (missing .bare in parent path)." >&2
        return 1
    end

    set -l bare "$project_dir/.bare"
    set -l failed 0

    for branch in $branches
        if test "$branch" = "main"
            echo "Cannot remove the main worktree." >&2
            set failed 1
            continue
        end

        if not _wt_ref_exists "$bare" "refs/heads/$branch"
            echo "Branch '$branch' does not exist." >&2
            set failed 1
            continue
        end

        set -l merged 0
        if _wt_ref_exists "$bare" "refs/heads/main"
            set -l branch_tip (command git --git-dir "$bare" rev-parse "refs/heads/$branch" 2>/dev/null)
            set -l merge_base (command git --git-dir "$bare" merge-base "refs/heads/main" "refs/heads/$branch" 2>/dev/null)
            if test -n "$merge_base" -a "$merge_base" = "$branch_tip"
                set merged 1
            end
        end

        set -l do_force $force
        if test "$do_force" -eq 0 -a "$merged" -eq 0
            read -l -P "Branch '$branch' is not merged into main. Remove anyway? [y/N] " confirm
            if not string match -qi -- 'y' "$confirm"
                echo "Skipping '$branch'."
                continue
            end
            set do_force 1
        end

        set -l target (_wt_branch_worktree_path "$project_dir" "$branch")

        if string match -q -- "$target/*" (pwd); or test (pwd) = "$target"
            _wt_cd_main_worktree_or_project "$project_dir"
            or return 1
        end

        if _wt_is_registered_worktree_path "$bare" "$target"
            if test "$do_force" -eq 1
                command git --git-dir "$bare" worktree remove --force "$target"
            else
                command git --git-dir "$bare" worktree remove "$target"
            end
            if test $status -ne 0
                rm -rf "$target"
                command git --git-dir "$bare" worktree prune
            end
        else if test -d "$target"
            rm -rf "$target"
        end

        if test "$do_force" -eq 1
            command git --git-dir "$bare" branch -D "$branch"
        else
            command git --git-dir "$bare" branch -d "$branch"
        end
        if test $status -ne 0
            set failed 1
        end
    end

    return $failed
end

function _wt_prune_merged
    if test (count $argv) -ne 0
        echo "Usage: wt prune-merged" >&2
        return 1
    end

    set -l project_dir (_wt_find_project_dir)
    if test $status -ne 0
        echo "Not inside a worktree project (missing .bare in parent path)." >&2
        return 1
    end

    set -l bare "$project_dir/.bare"

    if not _wt_ref_exists "$bare" "refs/heads/main"
        echo "No 'main' branch found." >&2
        return 1
    end

    set -l merged_branches (command git --git-dir "$bare" branch --merged main --format='%(refname:short)' 2>/dev/null)
    set -l pruned 0

    for branch in $merged_branches
        if test "$branch" = "main"
            continue
        end

        set -l target (_wt_branch_worktree_path "$project_dir" "$branch")

        if string match -q -- "$target/*" (pwd); or test (pwd) = "$target"
            _wt_cd_main_worktree_or_project "$project_dir"
            or return 1
        end

        if _wt_is_registered_worktree_path "$bare" "$target"
            command git --git-dir "$bare" worktree remove --force "$target"
            if test $status -ne 0
                rm -rf "$target"
                command git --git-dir "$bare" worktree prune
            end
        else if test -d "$target"
            rm -rf "$target"
        end

        command git --git-dir "$bare" branch -d "$branch"
        if test $status -ne 0
            echo "Failed to delete branch '$branch'" >&2
        else
            echo "Removed merged branch: $branch"
            set pruned (math "$pruned + 1")
        end
    end

    if test "$pruned" -eq 0
        echo "No merged branches to prune."
    else
        echo "Pruned $pruned merged branch(es)."
    end
end

function _wt_update
    if test (count $argv) -ne 0
        echo "Usage: wt update" >&2
        return 1
    end

    set -l project_dir (_wt_find_project_dir)
    if test $status -ne 0
        echo "Not inside a worktree project (missing .bare in parent path)." >&2
        return 1
    end

    set -l bare "$project_dir/.bare"
    _wt_offer_main_worktree_migration "$project_dir" "$bare"
    or return 1

    echo "Fetching remotes for $project_dir ..."
    command git --git-dir "$bare" fetch --all --prune
    if test $status -ne 0
        return $status
    end

    for path in (_wt_list_worktree_paths "$bare")
        if test "$path" = "$bare"
            continue
        end

        _wt_write_zed_project_name "$project_dir" "$path"
        set -l wt_name (_wt_worktree_name "$project_dir" "$path")
        set -l branch (command git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null)

        if test -z "$branch"
            echo "[$wt_name] detached HEAD at $path; skipping"
            continue
        end

        if not _wt_worktree_path_matches_branch "$project_dir" "$path" "$branch"
            echo "[$wt_name] branch/path mismatch: branch is '$branch' (path: $path)"
        end

        set -l upstream (command git -C "$path" for-each-ref --format='%(upstream:short)' "refs/heads/$branch" 2>/dev/null)
        if test -z "$upstream"
            echo "[$wt_name] $branch has no upstream; skipping"
            continue
        end

        set -l counts (_wt_ahead_behind "$path" "$upstream")
        if test $status -ne 0 -o (count $counts) -lt 2
            echo "[$wt_name] could not compute ahead/behind for $branch; skipping"
            continue
        end

        set -l ahead "$counts[1]"
        set -l behind "$counts[2]"

        if test "$ahead" -gt 0 -a "$behind" -gt 0
            echo "[$wt_name] $branch diverged from $upstream (ahead $ahead, behind $behind); skipping pull"
            continue
        end

        if test "$ahead" -gt 0
            echo "[$wt_name] $branch is ahead of $upstream by $ahead; skipping pull"
            continue
        end

        if test "$behind" -eq 0
            echo "[$wt_name] $branch is up to date with $upstream"
            continue
        end

        echo "[$wt_name] pulling $branch from $upstream (behind $behind) ..."
        command git -C "$path" pull --ff-only
        if test $status -ne 0
            echo "[$wt_name] pull failed"
        end
    end
end

function _wt_print_status_line
    set -l project_dir "$argv[1]"
    set -l path "$argv[2]"
    set -l wt_name (_wt_worktree_name "$project_dir" "$path")
    set -l branch (command git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null)

    set -l branch_label "$branch"
    set -l upstream_desc ""
    set -l mismatch ""
    if test -z "$branch"
        set branch_label "(detached)"
        set upstream_desc "detached-head"
    else
        if not _wt_worktree_path_matches_branch "$project_dir" "$path" "$branch"
            set mismatch " mismatch(path!=branch)"
        end

        set -l upstream (command git -C "$path" for-each-ref --format='%(upstream:short)' "refs/heads/$branch" 2>/dev/null)
        if test -z "$upstream"
            set upstream_desc "no-upstream"
        else
            set -l counts (_wt_ahead_behind "$path" "$upstream")
            if test $status -ne 0 -o (count $counts) -lt 2
                set upstream_desc "upstream-unknown($upstream)"
            else
                set -l ahead "$counts[1]"
                set -l behind "$counts[2]"
                if test "$ahead" -gt 0 -a "$behind" -gt 0
                    set upstream_desc "diverged +$ahead/-$behind vs $upstream"
                else if test "$ahead" -gt 0
                    set upstream_desc "ahead +$ahead vs $upstream"
                else if test "$behind" -gt 0
                    set upstream_desc "behind -$behind vs $upstream"
                else
                    set upstream_desc "up-to-date with $upstream"
                end
            end
        end
    end

    set -l dirty_counts (_wt_dirty_counts "$path")
    set -l staged "$dirty_counts[1]"
    set -l unstaged "$dirty_counts[2]"
    set -l untracked "$dirty_counts[3]"
    set -l dirty_desc "clean"
    if test "$staged" -gt 0 -o "$unstaged" -gt 0 -o "$untracked" -gt 0
        set dirty_desc "dirty(staged:$staged unstaged:$unstaged untracked:$untracked)"
    end

    printf "%-24s %-24s %-38s %s%s\n" "$wt_name" "$branch_label" "$upstream_desc" "$dirty_desc" "$mismatch"
end

function _wt_status
    if test (count $argv) -ne 0
        echo "Usage: wt status" >&2
        return 1
    end

    set -l project_dir (_wt_find_project_dir)
    if test $status -ne 0
        echo "Not inside a worktree project (missing .bare in parent path)." >&2
        return 1
    end

    set -l bare "$project_dir/.bare"
    set -l all_paths (_wt_list_worktree_paths "$bare")
    set -l main_path (_wt_main_worktree_path "$project_dir")

    printf "%-24s %-24s %-38s %s\n" "worktree" "branch" "upstream" "dirty"
    printf "%-24s %-24s %-38s %s\n" "--------" "------" "--------" "-----"

    if contains -- "$main_path" $all_paths
        _wt_print_status_line "$project_dir" "$main_path"
    end

    set -l sortable
    set -l sep (printf '\x1f')
    for path in $all_paths
        if test "$path" = "$bare" -o "$path" = "$main_path"
            continue
        end
        if not string match -q -- "$project_dir/*" "$path"
            continue
        end
        set -l ts (command git -C "$path" log -1 --format=%ct HEAD 2>/dev/null)
        if test -z "$ts"
            set ts 0
        end
        set sortable $sortable "$ts$sep$path"
    end

    for row in (printf "%s\n" $sortable | command sort -r -n -k1,1)
        set -l fields (string split "$sep" -- "$row")
        if test (count $fields) -lt 2
            continue
        end
        _wt_print_status_line "$project_dir" "$fields[2]"
    end
end

function _wt_prompt_dir_length
    set -l dir_length 1
    if set -q fish_prompt_pwd_dir_length
        if string match -qr '^[0-9]+$' -- "$fish_prompt_pwd_dir_length"
            set dir_length "$fish_prompt_pwd_dir_length"
        end
    end
    echo "$dir_length"
end

function _wt_shorten_parts
    set -l dir_length "$argv[1]"
    set -l parts $argv[2..-1]
    set -l part_count (count $parts)
    set -l out

    for idx in (seq 1 $part_count)
        set -l part "$parts[$idx]"
        if test "$dir_length" -gt 0 -a "$idx" -lt "$part_count"
            set part (string sub -s 1 -l "$dir_length" -- "$part")
        end
        set out $out "$part"
    end

    string join / -- $out
end

function _wt_shorten_absolute_path
    set -l path "$argv[1]"
    set -l dir_length "$argv[2]"

    if test "$path" = "/"
        echo "/"
        return 0
    end

    set -l home "$HOME"
    if test "$path" = "$home"
        echo "~"
        return 0
    end

    if string match -q -- "$home/*" "$path"
        set -l rel (string replace "$home/" "" -- "$path")
        set -l parts (string split / -- "$rel")
        set -l shortened (_wt_shorten_parts "$dir_length" $parts)
        echo "~/$shortened"
        return 0
    end

    set -l rel (string replace -r '^/' '' -- "$path")
    set -l parts (string split / -- "$rel")
    set -l shortened (_wt_shorten_parts "$dir_length" $parts)
    echo "/$shortened"
end

function _wt_shorten_relative_path
    set -l rel "$argv[1]"
    set -l dir_length "$argv[2]"
    set -l parts (string split / -- "$rel")
    _wt_shorten_parts "$dir_length" $parts
end

function wt_prompt_pwd
    set -l cwd (pwd)
    set -l dir_length (_wt_prompt_dir_length)
    set -l project_dir (_wt_find_project_dir)

    if test $status -ne 0
        _wt_shorten_absolute_path "$cwd" "$dir_length"
        return 0
    end

    if test "$cwd" = "$project_dir"
        set -l parent (dirname "$project_dir")
        set -l parent_display (_wt_shorten_absolute_path "$parent" "$dir_length")
        set -l project_name (basename "$project_dir")
        echo "$parent_display/$project_name"
        return 0
    end

    if string match -q -- "$project_dir/*" "$cwd"
        set -l parent (dirname "$project_dir")
        set -l parent_display (_wt_shorten_absolute_path "$parent" "$dir_length")
        set -l project_name (basename "$project_dir")
        set -l rel (string replace "$project_dir/" "" -- "$cwd")
        set -l rel_display (_wt_shorten_relative_path "$rel" "$dir_length")
        echo "$parent_display/$project_name/$rel_display"
        return 0
    end

    _wt_shorten_absolute_path "$cwd" "$dir_length"
end

function wt
    if test (count $argv) -eq 0
        _wt_usage
        return 0
    end

    switch "$argv[1]"
        case co
            _wt_co $argv[2..-1]
        case new
            _wt_new $argv[2..-1]
        case rm
            _wt_rm $argv[2..-1]
        case prune-merged
            _wt_prune_merged $argv[2..-1]
        case convert
            _wt_convert $argv[2..-1]
        case update
            _wt_update $argv[2..-1]
        case status
            _wt_status $argv[2..-1]
        case prompt-pwd
            wt_prompt_pwd
        case help -h --help
            if test (count $argv) -ge 2 -a "$argv[2]" = "install"
                _wt_install_help
            else
                _wt_usage
            end
        case '*'
            echo "Unknown subcommand: $argv[1]" >&2
            _wt_usage >&2
            return 1
    end
end
