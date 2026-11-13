# docs-kit, stage 1: the plan

Every project starts with a plan, before any website, wiki or picture: `docs/PLAN.md` and a page
per phase, written in sessions between the project's owner and Claude. The work itself is
organised on GitHub: milestones, issues and a project board. `docs-kit plan` keeps the two the
same, so the to-do list on GitHub is always the plan in the docs (#18, #22).

## The model

| | In the repository | On GitHub |
|---|---|---|
| **The plan** | `docs/PLAN.md` | **One root issue**, "The plan: <name>", labelled `plan` and pinned. Its description is written by docs-kit: the plan's first paragraph, then every item in the roadmap's order (Now, Next, Later), then the finished phases. It's the parent of everything else, and always up to date. |
| **Phases** | A page each in `docs/phases/` | A **milestone**, and a **phase issue**: the milestone's title, labelled `phase`, in its milestone, a sub-issue of the plan. Open while the phase has work, closed when it's done. A phase may have sub-phases: phase issues under a phase issue, each with its own milestone and page. |
| **Items** | Mentioned (`#N`) on their phase's page | Sub-issues of their phase issue: the things to build. |
| **Steps** | | Sub-issues of an item, at any depth. |

**The project board** holds the order:

| Field | Set by | Is |
|---|---|---|
| **Level** | docs-kit, from the tree | Plan, Phase, Item or Step |
| **Order** | you, on each item | Its place in the roadmap (1, 2, 3; 4.5 slots one between) |
| **Horizon** | you, on each item | Now, Next or Later: the field's choices, in their order |
| **Start**, **Target** | you, on each item (optional) | Rough dates, for the Roadmap view |
| any field in `plan.inherit` | you, on each item | A Track, say |

A step copies its item's Order, Horizon and `inherit` fields. A phase's Horizon is its items'
earliest, its Order their lowest, its Start and Target their earliest and latest. Closed issues
are Done; an open issue's Status (Todo, In Progress) is left as it is. Everything in the plan is
on the board, and everything under a phase is in that phase's milestone.

A phase's **Status**, on its page's line, is Done when its milestone is closed or has nothing
open, otherwise the earliest Horizon among its open issues:

```
# Phase 1: Lights

**Milestone:** Phase 1: Lights · **Status:** Now
```

The rest of the page is the project's own: the goal, the decisions, what's left. It mentions
(`#N`, anywhere) every open item in its phase; steps and other phases' issues can be mentioned
or not.

## Commands

| Command | Does |
|---|---|
| `docs-kit plan init [--dry-run]` | Sets a new project up, and is safe to run again: the board's fields (Level, Order, Horizon, and Start and Target when named), a milestone for each page and each page's Milestone line, the labels, the root issue, a phase issue per phase, and three views; then `sync`. |
| `docs-kit plan sync [--dry-run]` | Makes GitHub follow the tree, and the generated files follow GitHub: see below. Prints every change in plain words; `--dry-run` only prints them. |
| `docs-kit plan check` | Fails when anything `sync` would change, or anything it can't (below). One line when all is well (and one more when entries are waiting in the Inbox, which never fails it). For CI. |
| `docs-kit plan inbox [--json]` | What's waiting in the board's Inbox, oldest first: title, Kind (or "kind not set"), note, when and by whom, item id. `plan ideas` is the same. [The Inbox](#the-inbox). |
| `docs-kit plan inbox --take <item> --phase "<milestone>" …` | Takes one entry into the plan as an issue, with its spec. [The Inbox](#the-inbox). |
| `docs-kit plan set <issue> [Field=value …] [--blocked-by N …]` | Moves an issue in the plan (its Order, say) or records what it waits for, then syncs. |
| `docs-kit plan index [--check]` | Writes the index (`sync` does too), or says whether it's up to date. |
| `docs-kit plan status [--write]` | Each page's Milestone and Status line as GitHub has it; `--write` puts it on the pages (and adds the line where a page's title is its milestone's). |

### What `sync` does

1. Makes the labels, the root issue (and pins it), and a phase issue for each milestone that
   has a page or is open.
2. Puts each phase issue under the plan, in its milestone.
3. Puts each open issue that isn't under a phase under its milestone's phase issue (an open
   step goes with its top-most parent).
4. Puts everything under a phase in that phase's milestone, and on the board.
5. Sets each Level; copies items' values to their steps; sets each phase's values from its items.
6. Closes a phase issue when nothing under it or in its milestone is open, and reopens it when
   something is. Sets closed issues Done.
7. Writes the root issue's and the phase issues' descriptions, the pages' Status lines and the
   index.

It never deletes anything, never closes an item or a step, and never changes an open issue's
Status. It reads GitHub with `gh` (signed in), 100 issues at a time, and writes in batches.

### What only you can put right

`plan check` and `plan sync` list these, in plain words:

- an open issue that isn't in the plan and can't be placed (no milestone, or directly under the
  plan): give it a milestone, or make it a sub-issue of an item;
- an item with no Horizon on the board;
- a page that doesn't mention an open item in its phase;
- an open milestone with no page (unless `plan.no_page` lists it), or with nothing open in it
  (close it);
- a page with no Milestone line, or naming a milestone GitHub doesn't have, or the same one as
  another page;
- two root issues, two phase issues for one milestone, a phase issue under an item;
- a field the config names that the board hasn't, or of the wrong kind (`init` adds the plan's
  own).

### The views

`plan init` makes these, or puts their filters right when they exist:

| View | Shows |
|---|---|
| **Now · Next · Later** | A board of the open items, a column per Horizon, in Order. |
| **Roadmap** | A timeline of the open phases and items, grouped by milestone, in Order. |
| **In order** | A table of the open items and steps, grouped by Horizon, in Order. |
| **Inbox** | A table of the board's drafts, with their Kind: the owner's inbox (made when it's missing; an "Ideas" view from before is renamed; never otherwise changed). |

A filter put right keeps the view's layout.

GitHub's API can't move a view: the first tab is what a project opens on. Drag **Now · Next ·
Later** to the left of the others once, on the board's page.

### The index and the root issue

The index (`plan.index`, `docs/phases/README.md`, which GitHub shows under the folder's files)
and the root issue's description share a table per Horizon (`| Order | Plan | Phase |`, by
Order, then the milestone's due date, then number) and a Done line of the finished phases. The
index keeps the text above its first `## ` heading; neither has a date, so each changes only
when GitHub does.

## The Inbox

Everything the owner wants to tell the project between sessions goes in the board's **Inbox**
view, by hand, with no session needed: a bug, a feature, an idea, something to research. It's
"every human input": an entry is a *draft* on the board, no issue yet, nothing in the plan,
nothing `plan check` fails on (it only says how many are waiting).

**Adding an entry:** **+ Add item** at the bottom of the Inbox table, a title, Enter. Then,
optionally: the **Kind** cell (Bug, Feature, Idea or Research), and the title clicked open to
add a note (what happened or what it's for, an example, a link). Kind can be left empty: the
session works it out.

| Kind | Is |
|---|---|
| **Bug** | Something broken or wrong |
| **Feature** | Something new the app should do |
| **Idea** | A thought to explore, not decided yet |
| **Research** | Something to find out before deciding |

### "Scan the inbox"

When the owner says **"scan the inbox"** (or "scan the ideas", "look at what I added"), the
session:

1. runs `docs-kit plan inbox` (oldest first, with each Kind, note and item id) and works out the
   Kind of any entry without one;
2. handles each by its kind:
   - **Bug:** reads the app's logs first, quotes the lines that explain it in the issue, and
     places it by severity: a bug that breaks daily use goes ahead of features (Now, early in
     the Order);
   - **Feature:** a spec, in plain words: **Why** (the owner's words quoted), **What**, **Done
     when**;
   - **Idea** or **Research:** a research or decision issue, not a build: what to find out, and
     how the decision will be made;
3. fits every entry into the plan in the most logical order:
   - **where it belongs:** its phase, and a step of an existing item when it is one
     (`--parent`);
   - **what it depends on:** recorded with GitHub's issue dependencies ("blocked by":
     `--blocked-by N`, or `docs-kit plan set <issue> --blocked-by N` for one already in the
     plan);
   - **what moves:** when the new entry should come first, the others' Order changes too
     (`docs-kit plan set <issue> Order=<N>`);
4. asks the owner only where the intent is genuinely unclear;
5. takes each in:

   ```
   docs-kit plan inbox --take <item id> --phase "<milestone>" --horizon <Now|Next|Later> --order <N> \
     [--kind <Kind>] [--blocked-by <N>] [--set Track=<value>] --body-file <spec.md> [--title "<clearer title>"]
   docs-kit plan inbox --take <item id> --phase "<milestone>" --parent <item number> --body-file <spec.md>
   ```

   The draft becomes an issue in the repository (the same card on the board, its Kind kept;
   a Bug also gets the repository's `bug` label, where there is one), with the spec as its
   description, under its phase issue (or the item), in the milestone, with its values; then
   `sync` runs;
6. says each new item on its phase's page, runs `docs-kit plan check`, and tells the owner where
   each entry went (its number, kind, phase, horizon and place) and what moved.

`--set Field=value` sets any field of the board; `--order` takes a decimal to slot one between
two. The view was called Ideas before; `plan init` and `plan sync` rename it in place, keeping
its layout and filter, and make the Kind field and show it there.

## Changing the plan

Every session that changes the plan (a new item, a phase finished, a new order) changes it in
both places and runs:

1. the pages and `docs/PLAN.md`, for what was decided;
2. the issues (a new item as a sub-issue of its phase issue, or in its milestone), its Order and
   Horizon on the board;
3. `docs-kit plan sync`, which makes the rest follow;
4. `docs-kit plan check`, which passes, then the pages in a pull request.

A new project: write `docs/PLAN.md` and the phase pages with the owner, add the `plan` section
to `.product-kit.json`, run `docs-kit plan init`, and put `docs-kit plan check` in CI.

## The config

```json
"plan": {
  "pages": "docs/phases",
  "index": "docs/phases/README.md",
  "doc": "docs/PLAN.md",
  "project": { "owner": "kevinabouhanna", "number": 8 },
  "fields": { "order": "Order", "horizon": "Horizon", "level": "Level", "start": "Start", "target": "Target" },
  "inherit": ["Track"],
  "no_page": ["Ideas"]
}
```

| Key | Meaning |
|---|---|
| `pages` | The folder of phase pages (`docs/phases`). Every `.md` in it but the index is a phase page. |
| `index` | The index (`<pages>/README.md`). |
| `doc` | The plan in words (`docs/PLAN.md`): its first paragraph opens the root issue. |
| `intro` | Text to open the root issue with instead. |
| `title` | The root issue's title (`The plan: <name>`). |
| `project` | The project board: its `owner` (a user or an organization; the repository's owner if left out) and `number`. |
| `fields` | The board's field names, where they aren't `Order`, `Horizon`, `Level`, `Status` and `Kind`. `start` and `target` are used only when named. |
| `inherit` | More fields a step copies from its item. |
| `labels` | `{"plan": "plan", "phase": "phase"}`: the labels, if not these. |
| `done` | The Status for closed issues (`Done`). |
| `no_page` | Open milestones that deliberately have no page; they still get a phase issue. |

`repo` and `plan` are all a project needs in `.product-kit.json` for this stage.

`DOCS_KIT_GH` names a command run instead of `gh`, with the same arguments: the tests give it
`tests/fake-github.py`, a stand-in GitHub that keeps its state in a file.
