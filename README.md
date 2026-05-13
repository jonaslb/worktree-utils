# Git Worktree Utilities (Fish - `wt`)

Fish shell utilities for managing git worktrees with this layout:

- `proj_dir/.bare` is the central bare git repository
- `proj_dir/project_name` is the main branch worktree
- `proj_dir/<branch>` is a worktree for any additional branch

Example project path:

- `/base_path/project_name/.bare`
- `/base_path/project_name/project_name`
- `/base_path/project_name/feature-x`

## Commands

`wt` provides these subcommands:

- `wt co <branch>`
- `wt new <new-branch> [base-branch]`
- `wt convert`
- `wt update`
- `wt status`
- `wt prompt-pwd`
- `wt help [install]`

### `wt co <branch>`

Checks out an existing branch into `proj_dir/<branch>`, except `main` which uses `proj_dir/project_name`.

Behavior:

- Uses a local branch if present.
- Falls back to a remote-tracking branch (`<remote>/<branch>`) if needed.
- Runs `uv sync` automatically if the checked out worktree contains `pyproject.toml`.
- Changes directory into the new worktree on success.

### `wt new <new-branch> [base-branch]`

Creates a new branch and worktree at `proj_dir/<new-branch>`.

Behavior:

- Default base branch is `main`.
- Optional second argument sets a different base branch.
- Refuses to create if the new branch already exists (local or remote).
- Runs `uv sync` automatically if the new worktree contains `pyproject.toml`.
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
- Prunes registered worktrees whose filesystem path no longer exists (`git worktree prune`)
- If a legacy `proj_dir/main` worktree for the `main` branch exists, prompts to move it to `proj_dir/project_name`
- Only updates branches that have an upstream tracking branch
- Skips pull (with a note) if branch is ahead or diverged from upstream
- Notes branch/path mismatches, with `main` expected at `proj_dir/project_name`
- Skips detached HEAD worktrees

Note:

- `fetch --all --prune` prunes stale remote-tracking refs, not local branches.
- Pull is only attempted for branches that currently have an upstream.

### `wt status`

Shows one-line status for each registered worktree in the project.

Behavior:

- Prints the main worktree first
- Prints remaining worktrees by most recent commit time
- Includes branch/path mismatch note
- Includes upstream relation (`up-to-date`, `ahead`, `behind`, `diverged`, `no-upstream`)
- Includes dirty summary (`staged`, `unstaged`, `untracked`)

### `wt prompt-pwd`

Prints a fish-prompt-friendly path.

Behavior:

- Uses fish-style path shortening for normal directories
- If inside a wt project (`.bare` found in parent path), keeps `proj_dir` name fully visible
- Still shortens deeper subdirectories according to `fish_prompt_pwd_dir_length`

## Installation (fish)

Copy or symlink these files:

- `functions/wt.fish` -> `~/.config/fish/functions/wt.fish`
- `completions/wt.fish` -> `~/.config/fish/completions/wt.fish`

Example using symlinks from this repo:

```fish
set -l repo (pwd)
ln -sf $repo/functions/wt.fish ~/.config/fish/functions/wt.fish
ln -sf $repo/completions/wt.fish ~/.config/fish/completions/wt.fish
```

Then open a new fish session, or run:

```fish
source ~/.config/fish/functions/wt.fish
```

## Completions

Fish completions are included for:

- subcommands (`co`, `new`, `convert`, `update`, `status`, `prompt-pwd`, `help`)
- branch names for `co`
- base branch suggestions for `new` second argument
- `wt help install`

Branch completion reads from `proj_dir/.bare` when inside a converted project.

## Prompt Integration (fish)

Add this to your `~/.config/fish/config.fish`:

```fish
if not functions -q _wt_original_prompt_pwd
    functions -c prompt_pwd _wt_original_prompt_pwd
end

function prompt_pwd
    if type -q wt
        set -l wt_pwd (wt prompt-pwd 2>/dev/null)
        if test $status -eq 0 -a -n "$wt_pwd"
            echo $wt_pwd
            return
        end
    end
    _wt_original_prompt_pwd
end
```
