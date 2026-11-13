---
name: docs-kit
description: How a project's docs work when it has a .product-kit.json (or .docs-kit.json), starting with its plan - docs/PLAN.md and a page per phase kept the same as GitHub (one root plan issue, a phase issue per phase, items and steps as sub-issues, milestones, the project board's Level, Order and Horizon) by docs-kit plan init, sync and check; then docs/ as the one source, with the website's docs pages and the GitHub wiki built from it, never edited. Use at the start of every new project (plan init), when the owner says to scan the inbox or the ideas (plan inbox: bugs from the logs, features as specs, ideas and research as research issues, each fitted into the plan in order with its dependencies, then --take each), in every session that changes the plan or roadmap (a new item or issue, a phase finished, a new order or horizon: plan sync, then plan check), when an issue isn't in the plan, when a change adds or changes what an app says or does (docs-check asks for the docs in the same pull request), when writing or moving a docs page or heading, when publishing the website's docs (with a release), when linking from an app into its docs, or when setting docs up in a new project.
---

# docs-kit: one source for the docs

`docs/` in the repository is the source. The website's docs pages and the GitHub wiki are
**built** from it by `docs-kit` (on PATH from this plugin; each project keeps a copy at
`Scripts/docs-kit`). Never edit a built page: change `docs/` and rebuild.

Its stages, in the order a project meets them: 1. **the plan** (below), from the first day;
2. **docs for users**, with each feature; 3. **the wiki and the website**, built from `docs/`;
4. **pictures** (the shots-kit skill). Translations (lang-kit) run through 2 to 4.

What's particular to a project is in its `.product-kit.json` (`.docs-kit.json` before product-kit) at the top of the repository. Its
own CLAUDE.md says when its site is rebuilt and which make targets wrap these commands.

## Stage 1: the plan

A project's docs start with its plan, before any website, wiki or picture. When
`.product-kit.json` has a `plan` section, the plan is in the repository and on GitHub, and they
must agree:

| | In the repository | On GitHub |
|---|---|---|
| The plan | `docs/PLAN.md` | one root issue, label `plan`, pinned; its description written by docs-kit |
| Phases | a page each in `plan.pages`, with `**Milestone:** <title> · **Status:** <Done\|Now\|Next\|Later>` under its title | a milestone, and a phase issue of the same title (label `phase`, in the milestone, under the plan); sub-phases are phase issues under a phase issue |
| Items | mentioned (`#N`) on their phase's page | sub-issues of their phase issue |
| Steps | | sub-issues of items, any depth |

The board: **Level** (Plan, Phase, Item, Step) is docs-kit's; **Order** and **Horizon** (Now,
Next, Later) are set on items, and steps copy them.

- **A new project:** write `docs/PLAN.md` and the phase pages with the owner, add `"plan":
  {"pages", "index", "project": {"owner", "number"}}` to `.product-kit.json`, run
  `docs-kit plan init` (`--dry-run` first: it says everything it will make), and put
  `docs-kit plan check` in CI.
- **Every session that changes the plan** (a new item, a phase finished, a new order) changes
  both places: the pages for what was decided; the issues (a new item as a sub-issue of its
  phase issue, or just in its milestone) and their Order and Horizon on the board. Then
  `docs-kit plan sync` (it makes the rest follow: phase issues, sub-issues, milestones, Levels,
  copied values, the root issue, the Status lines, the index; it prints every change), then
  `docs-kit plan check`, which must pass. Commit the pages in a pull request.
- When `plan check` fails it says what disagrees. What `sync` would change, run `sync` for;
  the rest (an issue with no milestone, an item with no Horizon, a page that doesn't mention an
  item) put right by hand, on whichever side is wrong. Never weaken the check.
- `sync` never deletes, never closes an item or a step, and leaves an open issue's Status alone.
  It closes a phase issue only when nothing in the phase is open.
- Never edit the root issue's description or the index below its first `## `: they're written.
- GitHub can't move a board's views by API: tell the owner to drag **Now · Next · Later** to
  the first tab once.
- **The Inbox:** everything the owner adds by hand between sessions (a bug, a feature, an
  idea, research) is a draft in the board's **Inbox** view, with an optional **Kind**; `plan
  check` mentions them and never fails on them. Never take an entry in unasked. When the owner
  says "scan the inbox" (or "scan the ideas"): `docs-kit plan inbox`; work out each entry's Kind
  when it's empty; a **Bug** starts from the app's logs (quote what explains it) and is placed by
  severity (one that breaks daily use goes ahead of features, Now); a **Feature** gets a spec
  (Why with the owner's words quoted, What, Done when); an **Idea** or **Research** becomes a
  research or decision issue (what to find out, how to decide), not a build. Fit each where it
  logically belongs: a step of an existing item when it is one (`--parent`), what it depends on
  (`--blocked-by N`: GitHub's "blocked by"), and move other items' Order when it should come
  first (`docs-kit plan set <issue> Order=<N>`). Ask only where the intent is genuinely unclear.
  Take each in with `docs-kit plan inbox --take <item> --phase "<milestone>" --horizon <H>
  --order <N> --body-file <spec.md>`, mention each new item on its phase's page, `docs-kit plan
  check`, then tell the owner where each went and what moved.

The reference is `docs/docs-kit-plan.md` in product-kit.

## Stage 2: the docs change with the feature

`docs-kit check [base]` (CI runs it, often as `make docs-check`) fails a pull request that
changes what the app says or does (the files and lines in `check.needs_docs`) and no page for
its users.

- When it fails, **write the docs**: change the page in `docs/` that describes the feature,
  and its translations (`docs/<code>/`), in the same pull request. Use the app's own words
  for features and settings.
- Only when the docs really don't need it (a typo in a label, a fix that changes nothing a
  user reads about), add a line to the pull request's description and run it again:
  `No docs needed: <why>`.
- Pages for developers (`developer_pages`) don't count: they're not what users read.

## Headings are addresses

Each heading's anchor is GitHub's (`## Pause and resume` → `#pause-and-resume`), the same on
GitHub, the wiki and the website. An app may link to them, so renaming a heading moves an
address. `docs-kit anchors` lists every page's address and anchors as JSON: a project's tests
can hold its links to it. For an address that must outlive its heading's wording, put
`<a id="name"></a>` on the line before the heading.

## Stage 3: the website's docs

`docs-kit site <site checkout>` (or `docs-kit -C <app checkout> site <site checkout>`) writes
each page for users to `<lang folder>docs/<page>/index.html` in the site's own template
(`site.templates`), rendered by GitHub (`gh api /markdown`, so `gh` must be signed in), with
images from the repository at that commit. Pages it built before and no longer builds are
removed (`docs/.docs-kit-pages` lists them). Templates use `{{title}}`, `{{description}}`,
`{{lang}}`, `{{root}}`, `{{url}}`, `{{alternates}}`, `{{switch}}`, `{{nav}}`, `{{content}}`,
`{{source}}`, `{{commit}}`, `{{commit_url}}`, `{{project}}`.

Rebuild it **when the app is released**, in the release's site pull request, so the site
describes the version people can download. A fix to the docs alone can be published the same
way at any time.

## Stage 3: the wiki

`docs-kit wiki <wiki checkout> [commit]` rewrites the wiki from `docs/`: page names from the
file names (or `wiki.names`), the sidebar from `docs/README.md`'s tables, each language's
pages as `<Page>-<code>`. A GitHub workflow runs it on every push to `main` that touches the
docs, with the project's copy (`python3 -I Scripts/docs-kit wiki wiki "$GITHUB_SHA"`).

## The project's copy

`docs-kit vendor` copies the plugin's `docs-kit` to `Scripts/docs-kit` (or `vendor` in the
config), so CI and GitHub workflows run without the plugin. `docs-kit vendor --check` says
whether the copy is behind. Update the copy in its own pull request.

## A new project

1. `docs-kit init` writes a starting `.product-kit.json` (a project using only the plan needs
   just `repo` and `plan`). Fill in:
   - `check.needs_docs`: `[{"paths": [globs], "except": [globs], "lines": "regex"}]`, the
     files (and, optionally, the changed lines) that change what users see;
   - `developer_pages`, `extra_pages` (pages outside `docs/`, such as `SECURITY.md`, with
     `copy` (its file name in each `docs/<code>/`) and `slug`);
   - `languages`: `{"<code>": {"name": "…", "site": "<folder on the site>"}}`;
   - `site`: `url`, `folder`, `templates` (one per language), `strip_lines`;
   - `wiki`: `names`, `home` (text above the index on the wiki's Home; `{web}` is the
     repository's address).
2. `docs-kit vendor`, a `docs-check` in CI, the wiki workflow if it has a wiki, and the site's
   templates if it has a site.
3. Say in its CLAUDE.md when the site's docs are rebuilt.

The reference, with every config key, is `docs/docs-kit.md` in
`~/Work/personal/product-kit` (kevinabouhanna/product-kit).
