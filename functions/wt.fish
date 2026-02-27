function _wt_usage
    echo "wt: git worktree helper for fish"
    echo
    echo "Usage:"
    echo "  wt co <branch>"
    echo "  wt new <new-branch> [base-branch]"
    echo "  wt convert"
    echo "  wt update"
    echo "  wt help [install]"
    echo
    echo "Commands:"
    echo "  co       Checkout an existing branch into proj_dir/<branch>"
    echo "  new      Create a new branch from main (or a provided base branch)"
    echo "  convert  Convert a normal repo to the .bare + worktree layout"
    echo "  update   Pull updates for tracking branches across worktrees"
    echo "  help     Show command help"
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
    set -l target "$project_dir/$branch"

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

    set -l target "$project_dir/$new_branch"
    if test -e "$target"
        echo "Target path already exists: $target" >&2
        return 1
    end

    mkdir -p (dirname "$target")
    command git --git-dir "$bare" worktree add -b "$new_branch" "$target" "$base_ref"
    if test $status -ne 0
        return $status
    end

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

    command git --git-dir "$repo_root/.bare" worktree add "$repo_root/main" "$current_branch"
    or return 1

    for entry in (command find "$repo_root" -mindepth 1 -maxdepth 1)
        set -l name (basename "$entry")
        if test "$name" = ".bare" -o "$name" = "main"
            continue
        end
        rm -rf "$entry"
    end

    echo "Conversion complete. Main worktree: $repo_root/main"
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
    echo "Fetching remotes for $project_dir ..."
    command git --git-dir "$bare" fetch --all --prune
    if test $status -ne 0
        return $status
    end

    set -l paths (command git --git-dir "$bare" worktree list --porcelain | command awk '/^worktree / { sub(/^worktree /, ""); print }')
    for path in $paths
        if test "$path" = "$bare"
            continue
        end

        set -l project_prefix (string escape --style=regex -- "$project_dir/")
        set -l wt_name (string replace -r "^$project_prefix" "" -- "$path")
        set -l branch (command git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null)

        if test -z "$branch"
            echo "[$wt_name] detached HEAD at $path; skipping"
            continue
        end

        if test "$wt_name" != "$branch"
            echo "[$wt_name] branch/path mismatch: branch is '$branch' (path: $path)"
        end

        set -l upstream (command git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
        if test -z "$upstream"
            echo "[$wt_name] $branch has no upstream; skipping"
            continue
        end

        set -l counts_raw (command git -C "$path" rev-list --left-right --count HEAD..."$upstream")
        set -l counts (string split \t -- "$counts_raw")
        if test (count $counts) -lt 2
            set counts (string split ' ' -- "$counts_raw")
        end
        if test (count $counts) -lt 2
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
        case convert
            _wt_convert $argv[2..-1]
        case update
            _wt_update $argv[2..-1]
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
