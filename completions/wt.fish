function __wt_find_project_dir
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

function __wt_branches
    set -l project_dir (__wt_find_project_dir)
    if test $status -eq 0
        command git --git-dir "$project_dir/.bare" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
        return
    end

    command git branch --format='%(refname:short)' 2>/dev/null
end

complete -c wt -f
complete -c wt -n '__fish_use_subcommand' -a 'co' -d 'Checkout existing branch worktree'
complete -c wt -n '__fish_use_subcommand' -a 'new' -d 'Create new branch worktree'
complete -c wt -n '__fish_use_subcommand' -a 'convert' -d 'Convert repo to .bare worktree layout'
complete -c wt -n '__fish_use_subcommand' -a 'update' -d 'Pull updates for tracking worktrees'
complete -c wt -n '__fish_use_subcommand' -a 'help' -d 'Show help'

complete -c wt -n '__fish_seen_subcommand_from co' -a '(__wt_branches)'
complete -c wt -n '__fish_seen_subcommand_from new; and test (count (commandline -opc)) -ge 3' -a '(__wt_branches)'
complete -c wt -n '__fish_seen_subcommand_from help' -a 'install'
