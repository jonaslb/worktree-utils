# gwt-utils

Fish shell utilities for managing git worktrees with this layout:

- `proj_dir/.bare` is the central bare git repository
- `proj_dir/main` is the main branch worktree
- `proj_dir/<branch>` is a worktree for any additional branch

Example project path:

- `/base_path/project_name/.bare`
- `/base_path/project_name/main`
- `/base_path/project_name/feature-x`

## Commands

`wt` provides these subcommands:

- `wt co <branch>`
- `wt new <new-branch> [base-branch]`
- `wt convert`
- `wt update`
- `wt help [install]`

### `wt co <branch>`

Checks out an existing branch into `proj_dir/<branch>`.

Behavior:

- Uses a local branch if present.
- Falls back to a remote-tracking branch (`<remote>/<branch>`) if needed.
- Changes directory into the new worktree on success.

### `wt new <new-branch> [base-branch]`

Creates a new branch and worktree at `proj_dir/<new-branch>`.

Behavior:

- Default base branch is `main`.
- Optional second argument sets a different base branch.
- Refuses to create if the new branch already exists (local or remote).
- Changes directory into the new worktree on success.

Examples:

```fish
wt new feature/login
wt new hotfix/api-v2 release/2026.02
```

### `wt convert`

Converts a normal git checkout into this structure:

- `.git` becomes `.bare`
- Creates `main` worktree from current branch
- Removes the original root working-tree files after `main` is created

Safety checks:

- Must run inside a normal git repo (with a `.git` directory)
- Requires a clean working tree (no staged/unstaged/untracked files)
- Refuses detached HEAD

### `wt update`

Runs update checks across all registered worktrees under `proj_dir/.bare`.

Behavior:

- Fetches all remotes first (`fetch --all --prune`)
- Only updates branches that have an upstream tracking branch
- Skips pull (with a note) if branch is ahead or diverged from upstream
- Notes branch/path mismatches when `relative_worktree_path != current_branch`
- Skips detached HEAD worktrees

## Installation (fish)

Copy or symlink these files:

- `functions/wt.fish` -> `~/.config/fish/functions/wt.fish`
- `completions/wt.fish` -> `~/.config/fish/completions/wt.fish`

Example using symlinks from this repo:

```fish
ln -sf /home/jlb/git/gwt-utils/functions/wt.fish ~/.config/fish/functions/wt.fish
ln -sf /home/jlb/git/gwt-utils/completions/wt.fish ~/.config/fish/completions/wt.fish
```

Then open a new fish session, or run:

```fish
source ~/.config/fish/functions/wt.fish
```

## Completions

Fish completions are included for:

- subcommands (`co`, `new`, `convert`, `update`, `help`)
- branch names for `co`
- base branch suggestions for `new` second argument
- `wt help install`

Branch completion reads from `proj_dir/.bare` when inside a converted project.
