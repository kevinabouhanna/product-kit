# Phase 4: The plan at a glance

**Milestone:** Phase 4: The plan at a glance · **Status:** Now

**Goal:** every project's plan says at a glance what comes next and what waits on its owner, and
`docs-kit plan` keeps it that way by itself, instead of a session putting it right by hand.

Kevin, on NetworkMonitor#644 (2026-11-13), about a plan that passed `plan check`: "it's
organized in a very bad way". And on 2026-11-14, for every project: what only Kevin can do or
check gets the `needs-you` label and waits in Later, so it never blocks the work.

Both came from the Inbox (scanned 2026-11-15).

- **#74 What waits on the owner:** the `needs-you` label made, kept in Later and put back
  when it comes off, listed by `plan check`, and a Needs you view on the board. Until now each
  project did this by hand (home-control#616).
- **#78 A reopened phase stays open:** a phase issue sync reopened kept its Status Done, and the
  board's own workflow closed it again at its next change (#72, three times).

Done 15 Nov 2026:

- **The roadmap says what's next** (#73, tools 2.10.0): `plan check` warns when Now holds nothing
  real, when an umbrella item hides the work, when a page still lists a closed issue as open, and
  when the board opens on GitHub's starting views; `plan sync --views --yes` makes the plan's
  views and deletes those.

## Not in this phase

- Windows and Android: [phase 3](03-windows-and-android.md).
