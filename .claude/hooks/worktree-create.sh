#!/bin/bash
#
# WorktreeCreate: makes .claude/worktrees/<name> on branch <name>.
#
# Claude Code's own worktrees are on a branch called worktree-<name>; here a
# branch is named after its issue (settings-v2-9), so EnterWorktree, `claude -w`
# and background sessions all use the name as given. A new branch starts from
# the remote's default branch, freshly fetched, without tracking it (so a bare
# `git push` can never go to the default branch); an existing one is checked out
# as it is. The path printed on the last line is how Claude Code learns where
# the worktree is, so git's own messages go to stderr.

set -euo pipefail

input=$(cat)
name=$(jq -r '.name' <<<"$input")
cwd=$(jq -r '.cwd' <<<"$input")

common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir)
main=$(cd "$(dirname "$common")" && pwd -P)
path="$main/.claude/worktrees/$name"
base=$(git -C "$main" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)

if git -C "$main" show-ref --verify --quiet "refs/heads/$name"; then
  git -C "$main" worktree add "$path" "$name" >&2
else
  git -C "$main" fetch --quiet origin "${base#origin/}" >&2
  git -C "$main" worktree add --no-track -b "$name" "$path" "$base" >&2
fi

echo "$path"
