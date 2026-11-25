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
| `docs-kit plan init [--dry-run]` | Sets a new project up, and is safe to run again: the board's fields (Level, Order, Horizon, and Start and Target when named), a milestone for each page and each page's Milestone line, the labels, the root issue, a phase issue per phase, and the plan's views; then `sync`. |
| `docs-kit plan sync [--dry-run]` | Makes GitHub follow the tree, and the generated files follow GitHub: see below. Prints every change in plain words; `--dry-run` only prints them. |
| `docs-kit plan sync --views [--yes]` | The same, and the board's three views made or put right ([the views](#the-views)); with `--yes`, every other view is deleted. |
| `docs-kit plan check` | Fails when anything `sync` would change, or anything it can't (below). One line when all is well (and one more when entries are waiting in the Inbox, which never fails it), then [what to look at](#what-to-look-at), which never fails it either. For CI. |
| `docs-kit plan check --pr [<base>]` | The same, in a pull request's CI: unless the pull request changes the plan's files, what GitHub changed after its branch was taken is a warning, not a failure. [In a pull request](#in-a-pull-request). |
| `docs-kit plan inbox [--json]` | What's waiting in the board's Inbox, oldest first: title, Kind (or "kind not set"), note, when and by whom, item id, and the issue's number for an issue made on the board. `plan ideas` is the same. [The Inbox](#the-inbox). |
| `docs-kit plan inbox --take <item, or #N> --phase "<milestone>" …` | Takes one entry into the plan, with its spec: a draft becomes an issue; an issue made on the board is placed as it is. [The Inbox](#the-inbox). |
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
5. Sets each Level; moves what [waits on the owner](#what-waits-on-the-owner) to Later, and
   back when its label comes off; copies items' values to their steps; sets each phase's values
   from its items.
6. Reopens a closed milestone that has open work in it (an entry taken into a finished phase, an
   issue reopened there), so its page and the index no longer say Done; closing a milestone stays
   the owner's step. Closes a phase issue when nothing under it or in its milestone is open, and
   reopens it when something is, with its Status Todo (a board closes an issue that's Done the
   next time it changes). Sets closed issues Done.
7. Writes the root issue's and the phase issues' descriptions, the pages' Status lines and the
   index.

It never deletes anything (but the board's other views, when asked with `--views --yes`), never
closes an item or a step, and never changes an open issue's Status. It reads GitHub with `gh`
(signed in), 100 issues at a time, and writes in batches.

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

### In a pull request

`plan check` reads GitHub as it is now. In a pull request's CI that's a problem: as soon as any
session opens a new item, every other open pull request's CI fails until that session's own plan
pull request merges, even one that touches no plan page (home-control, 15 Nov 2026, #101). So a
project's CI says it's checking a pull request, and the check then fails only on what that pull
request can put right:

```
python3 -I scripts/docs-kit plan check ${CI_PR:+--pr}
```

`local-ci` sets `CI_PR` (the pull request's number), `CI_SHA` (its head) and `CI_BASE` (the
branch it goes into) for every job; by hand, or on `main`, there's no `CI_PR`, so the check is
the full one. With `--pr`:

- **A pull request that changes the plan's files** (a page or the index in `plan.pages`, the
  plan, `.product-kit.json`) is the plan's own: checked in full, exactly as by hand.
- **Any other pull request** is checked against GitHub as it was when its branch's `main` was
  taken: the fork, where its head (`CI_SHA`, or `HEAD`) meets `origin/<base>` (`CI_BASE`, or
  the config's `branch`, `main`; or the `<base>` given). What only GitHub changing since then
  explains is a warning, naming the issue and when (`#775 made 15 Nov 09:45`, `#768 closed …`,
  `moved on the board …`): a new item no page mentions, with no Horizon, not under its phase
  yet; an issue closed since; and anything about no issue in particular (the index, the plan's
  or a phase's description, a milestone) while anything changed. The session that made the
  change puts it right in its plan pull request, which is checked in full. What was already
  wrong at the fork still fails: an item made before it that no page mentions is the plan's
  `main` out of step, not someone's work in progress.
- **On `main`** (nothing between the fork and the head) it's the full check.

The fork's time is its commit's; an issue's are when it was made, closed or last changed on
GitHub, and when its card on the board last changed.

### What to look at

A plan whose pages and GitHub agree can still not say what comes next: NetworkMonitor's passed
`plan check` the day Kevin found it "organized in a very bad way" (NetworkMonitor#644). So
`plan check`, `plan sync` and `plan status` also list these, one line each with what to do.
They're warnings: they never fail the check.

- **Nothing real in Now:** Now is empty, or holds only the upkeep item (`upkeep` in the config),
  while Next or Later have items. A phase finished and nothing moved up. It names the next item
  and the `docs-kit plan set` that moves it.
- **An umbrella in Now or Next:** an item whose steps are all done but one (the board shows the
  umbrella, not the work left: make that step an item and close the umbrella), or whose title
  repeats its phase's ("Ad blocking that holds up" under "Phase 2: Ad blocking that holds up").
- **A closed issue listed with what's still to do:** a phase page (one not Done) that names a
  closed issue of its phase first in a line of a list of what's left: a list item under a
  heading about what's planned or left ("The plans", "Issues", "What's left", "Next"), or a row
  of a table with an Order, Horizon, Plan, Issue, Item or Step column. A section that describes
  how something works doesn't count, nor what a page says is finished: under a heading with
  "done", "shipped", "built" or "released" in it, after a paragraph that starts with one of
  those words, or in an item that says so ("done 14 Nov", "(fixed", struck through, ticked).
- **A board that isn't the plan's three views:** views besides Inbox, Needs you and Roadmap
  (GitHub's starting ones, "Backlog", "Team items", "My items", or older ones of the plan's), or
  one of the three missing; or [workflows](#the-workflows) on besides the plan's five.
- **An item that doesn't show its analysis, or say whether it needs a design** (#105): an open
  item in Now or Next (the upkeep item aside) with no **Analysis** heading or label with something
  under it, or no **Design:** line saying `needed` or `not needed` ([analysis and design](#analysis-and-design-before-its-built)).
- **An item that doesn't say when it's done** (#90): an open item in Now or Next (the upkeep
  item aside) whose description has no **Done when**: a heading, a label or a line of its own
  that starts with those words (bold, quoted, ticked or with an emoji before them is fine), with
  its points after it on that line or under it. "It's done when…" inside a sentence, one in a
  code block, or a heading with nothing under it doesn't count. Items made before the rule are
  listed too, once, until their description says it.

### When an item is done (#90)

Every item says **Done when**, as numbered points, before anyone builds it (Kevin, 2026-11-15,
after comparing a teammate's "software factory" for Claude Code). Each point is something a test
or a check can show from outside: what someone sees or can do, what a command prints. "The code
is clean" isn't one. A point that needs the owner (their phone, their accounts) says so, and the
item gets [`needs-you`](#what-waits-on-the-owner) for it.

```
**Done when:**
1. The list shows each request's votes, and a click on ▲ adds one.
2. "Most votes" sorts the list; newest first stays the default.
3. A vote survives a reload.
```

The pull request that closes the item takes each point with the test or check that proves it,
or says why none can (`3. A vote survives a reload: tests/votes.test.ts "keeps a vote after a
reload"`). A point no test covers is either given one or said plainly, so the gap is seen.

### Analysis and design, before it's built

Every item shows its **Analysis** and says whether it needs **Design**, before anyone builds it
(Kevin, 2026-11-17, claude-parallel-sessions#181: "You analyze the plan, and if you have any
questions, you ask. You give the result of your analysis, and after the result, we design.
Sometimes we might design; sometimes we might not. If it's a new feature, we have to design; if
it's an adjustment to a feature, we have to design").

- **Analysis**: a section of its own, in plain words: what it touches (the files, windows,
  commands or other projects), the options and the one chosen, the risks, and **Questions**:
  "none", or each question, which then waits on the owner as a
  [`needs-you`](#what-waits-on-the-owner) step while the rest goes on. A bug's analysis quotes
  the log lines that explain it.
- **Design:** one line: `needed: artifact` (a page to look at, published as an Artifact),
  `needed: live demo` (the real thing running: a VM recording, screenshots, a local preview), or
  `not needed: <why>` (or a **Design** heading with that on the line under it). A new feature, or a change to what people see, needs one; a fix that
  changes nothing on screen, a tool or a doc doesn't. When it's needed, the design's link goes on
  the issue (in a comment that starts **Design**) before the build starts.

```
## Analysis
Touches the list window and its store. Options: sort in the store (chosen: one place, tested) or
in the view. Risk: an old store has no vote counts; they start at 0.
Questions: none.

**Design:** needed: artifact

**Done when:**
1. …
```

`plan check` lists an open item in Now or Next (the upkeep item aside) with no Analysis section
or no Design line, as it does one without **Done when**. It never fails on them.

### The views

Every board has three views, the same on every project, in this order (Kevin, 2026-11-15, #88):

| View | Shows |
|---|---|
| **Inbox** | A table of what the owner adds by hand, with its Kind, until "scan the inbox" takes it into the plan: `is:open no:level no:milestone -is:pr`, every draft and every issue made on the board that isn't in the plan yet (#98). An issue of the plan has a Level, or a milestone until `sync` gives it one. Made by `sync` when it's missing (an "Ideas" view from before is renamed), or its filter put right (`is:draft`, from before, hid an issue made there), the same on every board. |
| **Needs you** | A table of the open issues that [wait on the owner](#what-waits-on-the-owner), in Order. Made by `sync` when it's missing; never otherwise changed. |
| **Roadmap** | The whole plan: a board of the open items, a column each for Now, Next and Later, in Order. Made by `plan init` and `plan sync --views`, or its filter put right. |

Nothing else. `plan sync --views --yes` deletes every other view (GitHub's starting ones, and
the plan's older Now · Next · Later, Now, Next, Later and In order tables), and makes a Roadmap
that was a timeline again as a board; without `--yes` it only says what it would delete.
`plan check` says when a board has others, or lacks one of the three.

GitHub's API can't move a view, only make and delete one. The three are made in their order, so
on a board whose other views are gone they read Inbox, Needs you, Roadmap.

### The workflows

A board has GitHub's built-in workflows (its **Workflows** button). The plan keeps five, the
same on every board (#93), which keep an issue's Status right between syncs:

| Workflow | Does |
|---|---|
| Auto-add sub-issues to project | A new step of an item on the board goes on the board too |
| Item added to project | Its Status is Todo |
| Item closed | Its Status is Done |
| Pull request linked to issue | Its Status is In Progress |
| Pull request merged | Its Status is Done |

Not these: **Auto-close issue** closes an issue whose Status is set to Done, so an issue would
close because a field changed (it closed phase 4 three times, #78); an issue closes when its pull
request merges, and a phase when `plan sync` finds it done. **Auto-add to project** puts every
new issue and pull request on the board; `plan sync` puts the plan's there itself. `plan check`
names any other workflow that's on, and `plan sync --views --yes` deletes it with the views:
GitHub's API can delete a workflow, not turn one off. One that's off is left alone.

### The index and the root issue

The index (`plan.index`, `docs/phases/README.md`, which GitHub shows under the folder's files)
and the root issue's description share a table per Horizon (`| Order | Plan | Phase |`, by
Order, then the milestone's due date, then number) and a Done line of the finished phases. The
root issue also lists what's waiting on the owner. The index keeps the text above its first
`## ` heading; neither has a date, so each changes only when GitHub does.

## What waits on the owner

The owner testing is the last resort, and they never block the work (Kevin, 2026-11-14,
home-control#616). Every check Claude can do, Claude does; only what truly needs the owner (their
phone, their accounts, a purchase, hardware only they can touch, a choice only they can make)
waits on them. Such an issue, or the part of it that needs them split into its own step:

- gets the **`needs-you`** label, which `plan sync` makes where it's missing ("Waits on Kevin:
  only Kevin can do or check this. Kept in Later until then.");
- says what to do in a short section of its description named after the owner, in plain words:

  ```
  ## Kevin:

  Plug the new plug in and add it in Mi Home on your phone. Nothing else.
  ```

- goes to **Later**: `plan sync` moves it there, a step too (it doesn't copy its item's Horizon
  while it waits), and keeps where it was in its description, out of sight
  (`<!-- docs-kit: before needs-you, Horizon Now -->`). Its Order stays: that's its place.

When the owner has done it, take the label off: `plan sync` puts the issue back in the Horizon
it had and forgets the note, unless someone has moved it in the meantime. A step goes back with
its item.

`plan check` lists what's waiting, each with the first words of its section, and warns (never
fails) about one that doesn't say what the owner should do. The root issue lists them under
"Waiting on Kevin", and the board's **Needs you** view (`is:open label:needs-you`), made when
it's missing, shows them.

The owner's name is the first name on the board owner's GitHub profile, or `plan.owner` in the
config, or "the owner"; the section may also be called "You:" or "Owner:", and a step of a list
that starts with the name counts too ("1. **Kevin:** in the Alexa app, …").

## The Inbox

Everything the owner wants to tell the project between sessions goes in the board's **Inbox**
view, by hand, with no session needed: a bug, a feature, an idea, something to research. It's
"every human input": an entry is anything open on the board that isn't in the plan yet (no
Level), a *draft* or an issue made there, and nothing `plan check` fails on (it only says how
many are waiting).

**Adding an entry,** either way, and it stays in the list (Kevin, 2026-11-15, #98: "I just want
to type the title and maybe description, and then it should be added to the list"):

- **+ Add item** at the bottom of the Inbox table, a title, Enter: a draft. Click the title
  open to add a note.
- The **+** at the bottom of the table, then **Create new issue**: a title and a description at
  once, an issue in the repository, on the board, outside the plan until it's taken in.

Then, optionally, the **Kind** cell (Bug, Feature, Idea or Research). The note says what
happened or what it's for, an example, a link. Kind can be left empty: the session works it
out.

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
     the Order); its **Analysis** is those lines and what they show, its **Design:** usually
     `not needed`, and its **Done when** says what shows it's fixed;
   - **Feature:** a spec, in plain words: **Why** (the owner's words quoted), **What**, its
     **Analysis** and a **Design:** line ([analysis and design](#analysis-and-design-before-its-built)),
     **Done when** ([numbered points](#when-an-item-is-done-90));
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

   A draft becomes an issue in the repository (the same card on the board, its Kind kept); an
   issue made on the board stays the same issue (`--take` takes its item id or its number,
   `#731`). Either way a Bug also gets the repository's `bug` label, where there is one, the spec
   becomes its description (without `--body-file`, the owner's own words stay), and it goes
   under its phase issue (or the item), in the milestone, with its values; then `sync` runs;
6. says each new item on its phase's page, runs `docs-kit plan check`, and tells the owner where
   each entry went (its number, kind, phase, horizon and place) and what moved.

`--set Field=value` sets any field of the board; `--order` takes a decimal to slot one between
two. The view was called Ideas before; `plan init` and `plan sync` rename it in place, keeping
its layout, and make the Kind field and show it there.

### A request made in a session

What the owner asks for in a session (in the terminal, not on GitHub) needs no Inbox entry
(Kevin, 2026-11-15, #88): "you don't have to add it to inbox; you can adjust the plan
accordingly." The session assesses it the same way as an Inbox entry (its kind, where it
belongs, what it depends on, what should come first), writes it the same spec (**Why**,
**What**, **Done when**, #90), opens its issue in the plan with
`gh issue create` and a milestone (or as a sub-issue of its item), gives it its Order and Horizon
(`docs-kit plan set`), moves others where it should come first, says it on its phase's page,
runs `plan sync` and `plan check`, and says where it went.

## Changing the plan

Every session that changes the plan (a new item, a phase finished, a new order) changes it in
both places and runs:

1. the pages and `docs/PLAN.md`, for what was decided;
2. the issues (a new item as a sub-issue of its phase issue, or in its milestone), its Order and
   Horizon on the board;
3. `docs-kit plan sync`, which makes the rest follow;
4. `docs-kit plan check`, which passes, then the pages in a pull request.

A new project: write `docs/PLAN.md` and the phase pages with the owner, add the `plan` section
to `.product-kit.json`, run `docs-kit plan init`, and put `docs-kit plan check ${CI_PR:+--pr}` in CI
([in a pull request](#in-a-pull-request)).

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
| `labels` | `{"plan": "plan", "phase": "phase", "needs_you": "needs-you"}`: the labels, if not these. |
| `owner` | The owner's name, for "Waits on Kevin" and the "Kevin:" section, when their GitHub profile's first name isn't it. |
| `done` | The Status for closed issues (`Done`). |
| `no_page` | Open milestones that deliberately have no page; they still get a phase issue. |

`repo` and `plan` are all a project needs in `.product-kit.json` for this stage.

`DOCS_KIT_GH` names a command run instead of `gh`, with the same arguments: the tests give it
`tests/fake-github.py`, a stand-in GitHub that keeps its state in a file.
