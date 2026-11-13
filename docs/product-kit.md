# product-kit: the command

`product-kit` (on PATH from the plugin) reaches each part, and does what's across them:

| Command | Does |
|---|---|
| `product-kit docs …`, `lang …`, `shots …` | The same as `docs-kit …`, `lang-kit …`, `shots-kit …`. |
| `product-kit version` | The one version every tool carries (#33). |
| `product-kit projects [--json]` | Every project that uses product-kit (a `.product-kit.json` or `.docs-kit.json` one or two folders under `~/Work`), the copies of the tools it keeps for its CI, their versions, and which are behind. |
| `product-kit vendor --all [--dry-run] [--only NAME,…]` | Brings every project's copies up to this version, below. |
| `product-kit bump <version>` | Sets the version in every tool, for a change to product-kit. |

## One version

docs-kit, lang-kit and shots-kit carry the same version (`VERSION` in the first two,
`shotsKitVersion` in the third), and the tests fail when they don't. A change to any tool bumps
them all with `product-kit bump <version>`: a project's copy is then behind whichever tool
changed, and `projects` says so.

## Every project's copies in one go

Each project keeps a copy of the tools it runs in CI (`docs-kit vendor`, `lang-kit vendor`,
`shots-kit vendor`), so its CI needs no plugin. After a change here, `product-kit vendor --all`
does, in each project whose copy differs from this version's:

1. an issue, "Update product-kit's tools to <version>", under the project's **upkeep** item when
   its config names one (`"upkeep": <issue>`, where a project with a plan keeps its tooling
   chores, so the plan stays whole). A project with a plan and no upkeep item isn't done: name
   the item once with `--only <project> --upkeep <issue>`, and its config keeps it;
2. a worktree of its default branch, `product-kit-<version>-<issue>`;
3. the new copies, each where the project keeps it (`vendor`, `lang.vendor`, `shots.vendor`);
4. what the new version needs in the project's config, when a version moved something out of
   the code (below);
5. the project's plan synced, when it has one and the issue went under its upkeep item;
6. a commit, the branch pushed, and a pull request that closes the issue;
7. the worktree and the local branch removed, whatever happened.

It prints one line per project: the pull request and what changed, "up to date", or "not done"
and why. It doesn't merge: each project's own CI runs on the pull request, and merging follows
that project's rules. `--dry-run` says what it would do and changes nothing; `--only` takes
project names. `PRODUCT_KIT_PROJECTS` (folders, `:` between them) looks somewhere else than
`~/Work`, and `PRODUCT_KIT_GH` runs another command than `gh`: the tests use both.

### When a version moves something into the config

A project's behaviour stays the same across a version that moved something out of the code. Each
such move has a migration that `vendor --all` runs, adding to the project's config what it relied
on, and saying so in the pull request:

| Version | Moved | A project gets |
|---|---|---|
| shots-kit 1.4.0 (#32) | The byte and network units, and the menu-bar readout's width | `shots.masks` and `shots.keep_width`, when its pictures are of an app's windows |
