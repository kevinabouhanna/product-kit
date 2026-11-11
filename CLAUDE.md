# product-kit

The plugin for what a product shows people: docs, pictures, videos, languages (#1 is the plan).
`~/.claude/CLAUDE.md` has the workflow (issue → pull request → merge → install), carried
through without asking. What's particular here:

- **Work in a worktree of your own**, never in the main checkout: `EnterWorktree` with the
  branch's name (`<short-name>-<issue>`); a hook makes `.claude/worktrees/<branch>` from a
  fresh `origin/main`, and another refuses edits in the main checkout.
- **CI:** `local-ci <pr>` from your worktree, in the background (seconds). It runs
  `tests/run.sh` as the `tests` check. Merge once it passes.
- **Once merged:** `gh pr merge N --squash` (without `--delete-branch`, which removes the
  worktree you're in), `ExitWorktree` with `remove`, `git pull --ff-only` in the main checkout,
  then `git branch -D <branch>` and `git push origin --delete <branch>`.
- **Install on this Mac:** `claude plugin marketplace update kevinabouhanna && claude plugin
  update product-kit@kevinabouhanna`. New sessions pick it up.
- **Projects keep copies.** A change to a tool a project vendors (`bin/docs-kit`, `bin/lang-kit`,
  `shots/shots-kit.swift` → `Scripts/…`) bumps its version (`VERSION`, `shotsKitVersion`) and is
  followed by a pull request in each such project with `<tool> vendor` (NetworkMonitor today).
  It's tooling only there: no app release.
- **shots-kit drives a real app** (unless the project draws its own pictures, `render`, which its
  tests cover). Its tests cover what reads files; a change to how it reads,
  takes or masks windows is checked by running `check` against NetworkMonitor's app before and
  after, and comparing. Never on Kevin's screen while he works (claude-parallel-sessions#62):
  in a VM (`shots-kit check --vm`, #10; `mac-vm run`, the shared-mac skill), or behind the silent idle gate
  (`MAC_LANE=screen MAC_LANE_IDLE=90 mac-lane …`), telling the other sessions first.
- **Generic, never one project's.** What's particular to a project goes in its config
  (`.product-kit.json`), never in the code. NetworkMonitor is the first user; each part is
  proved on a second project before it's called done.
- **Plain words** in commands, messages and docs, as in Kevin's apps.
- Sharing the Mac (lanes, the screen, worktrees) is the `shared-mac` plugin's; use `mac-lane`
  when it's on PATH, and work without it when it isn't.
