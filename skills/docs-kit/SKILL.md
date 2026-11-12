---
name: docs-kit
description: How a project's docs work when it has a .product-kit.json (or .docs-kit.json) - docs/ in the repository is the one source, and the website's docs pages and the GitHub wiki are built from it, never edited; and, when its config has a "plan" section, how its plan is kept the same across milestones, issues, the project board and the phase pages. Use when a change adds or changes what an app says or does (docs-check asks for the docs in the same pull request), when writing or moving a docs page or heading, when publishing the website's docs (with a release), when linking from an app into its docs, when changing the plan or roadmap (a phase, a plan, its order or horizon), or when setting docs or a plan up in a new project.
---

# docs-kit: one source for the docs

`docs/` in the repository is the source. The website's docs pages and the GitHub wiki are
**built** from it by `docs-kit` (on PATH from this plugin; each project keeps a copy at
`Scripts/docs-kit`). Never edit a built page: change `docs/` and rebuild.

What's particular to a project is in its `.product-kit.json` (`.docs-kit.json` before product-kit) at the top of the repository. Its
own CLAUDE.md says when its site is rebuilt and which make targets wrap these commands.

## The docs change with the feature

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

## The website's docs

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

## The wiki

`docs-kit wiki <wiki checkout> [commit]` rewrites the wiki from `docs/`: page names from the
file names (or `wiki.names`), the sidebar from `docs/README.md`'s tables, each language's
pages as `<Page>-<code>`. A GitHub workflow runs it on every push to `main` that touches the
docs, with the project's copy (`python3 -I Scripts/docs-kit wiki wiki "$GITHUB_SHA"`).

## The plan

When `.product-kit.json` has a `plan` section, the project's plan is in four places that must
agree: **milestones** (one per phase), **issues** (each plan an issue in its phase's
milestone, its steps sub-issues), **the project board** (the order: Order, and Horizon Now /
Next / Later), and **the phase pages** (`plan.pages`, each with
`**Milestone:** <milestone title> · **Status:** <Done|Now|Next|Later>` under its title, and an
index written from GitHub).

- **A change to the plan changes all four in the same session**: the issues (open, close,
  move, set a parent), their Order and Horizon on the board, the milestone (open, close, due
  date), and the phase's page (mention every open plan in it as `#N`). Then
  `docs-kit plan status --write` (the pages' Status lines) and `docs-kit plan index` (the index),
  and commit the pages in a pull request.
- `docs-kit plan check` holds them together, in CI. When it fails, it says what disagrees: fix
  whichever side is wrong (GitHub or the page), never the check.
- Status is Done when the milestone is closed or has no open issues, otherwise the earliest
  Horizon among its open issues. An open milestone with nothing left is closed.
- Never edit the index below its first `## ` heading: it's written. The title and text above
  it are the project's own.
- Setting it up: add `"plan": {"pages", "index", "project": {"owner", "number"}, "fields",
  "no_page"}`, give each page its Milestone line (`plan status --write` adds it where the page's
  title is the milestone's), `plan index`, and `plan check` in CI (it reads GitHub with `gh`).

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
