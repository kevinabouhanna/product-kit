# Phase 4: The plan at a glance

**Milestone:** Phase 4: The plan at a glance · **Status:** Done

**Goal:** every project's plan says at a glance what comes next and what waits on its owner, and
`docs-kit plan` keeps it that way by itself, instead of a session putting it right by hand.

Kevin, on NetworkMonitor#644 (2026-11-13), about a plan that passed `plan check`: "it's
organized in a very bad way". And on 2026-11-14, for every project: what only Kevin can do or
check gets the `needs-you` label and waits in Later, so it never blocks the work.

Both came from the Inbox (scanned 2026-11-15).

Then, the same day, looking at every board: "it doesn't feel consistent … I have a lot of stuff
… I think we should only have three": the Inbox, Needs you, and the Roadmap of Now, Next and
Later.

Then, after comparing a teammate's "software factory" for Claude Code (2026-11-15): every
ticket there gets numbered acceptance criteria before any code, and its pull request names the
test that proves each. Here, an item says **Done when** the same way.

Then, on home-control's board (2026-11-15): an issue Kevin made in the Inbox, a title and a
description with GitHub's **Create new issue**, was hidden at once, because the Inbox showed only
drafts. "I want the Inbox to be seamless, like any issue I create … I just want to type the title
and maybe description, and then it should be added to the list."

## What shipped (15 Nov 2026)

- **The Inbox shows an issue made on the board, not only drafts** (#98, tools 2.14.0): its
  filter is everything not in the plan yet (`is:open no:level no:milestone -is:pr`), on all
  five boards; `plan inbox` lists those issues with the drafts and `--take` places one as it
  is; `plan check` counts one as waiting instead of failing on it.

- **The board's workflows, the same five everywhere** (#93, tools 2.13.1; Kevin: "take care of
  the github workflows point"): the five that keep an issue's Status right, on every board;
  Auto-close issue (which closed phase 4 three times, #78) gone from all five, Auto-add to
  project from the three that had it.
- **Every item says when it's done** (#90, tools 2.13.0): numbered **Done when** points in
  every item's description, written the same way for a request made in a session; `plan check`
  lists an item in Now or Next that has none; the pull request takes each point with the test or
  check that proves it.
- **Three views on every board** (#88, tools 2.12.0): Inbox, Needs you and the Roadmap, in that
  order, and nothing else; a request made in a session goes straight into the plan, with no
  Inbox entry.
- **A "Kevin:" step in a list says what to do** (#83, tools 2.11.2): home-control#359 and #280
  say it as a step of a numbered list, which `plan check` now counts.
- **Found rolling it out** (#80, tools 2.11.1): the closed-issue warning counts only lists of
  what's left (a section describing how something works isn't one), and `product-kit vendor`
  names its issue on the phase's page when the project's upkeep item is closed.
- **The roadmap says what's next** (#73, tools 2.10.0): `plan check`, `sync` and `status` warn,
  without failing, when Now holds nothing real, when an umbrella item hides the work, when a page
  still lists a closed issue as open, and when the board opens on GitHub's starting views;
  `plan sync --views --yes` makes the plan's views (a table per Horizon too) and deletes those.
- **What waits on the owner** (#74, tools 2.11.0): `plan sync` makes the `needs-you` label,
  keeps a labelled item or step in Later and puts it back when the label comes off; `plan check`
  lists them with what each asks of the owner and warns when one doesn't say; the plan's issue
  lists them; the board has a Needs you view. home-control did this by hand before (#616).
- **A reopened phase stays open** (#78): a phase issue sync reopened kept its Status Done, and the
  board's own workflow closed it again at its next change; it's Todo now.

## Not in this phase

- Windows and Android: [phase 3](03-windows-and-android.md).
