# docs-kit: the docs

One source for a project's docs (#36). `docs/` in the repository is the source; the
website's docs pages and the GitHub wiki are built from it and never edited; a check holds the
docs to the features they describe.

It's the docs part of [product-kit](../README.md), a plugin in the `kevinabouhanna`
marketplace (it was a plugin of its own in claude-parallel-sessions until product-kit#2):

```
claude plugin install product-kit@kevinabouhanna --scope user
```

That puts `docs-kit` on PATH and gives every session the `docs-kit` skill. `docs-kit` is one
Python file using the standard library only, so it runs anywhere: on this Mac, in `local-ci`,
in a GitHub workflow. Each project keeps a copy at `Scripts/docs-kit` (`docs-kit vendor`), so
its CI needs no plugin.

## Why one source

The docs live where people read them (GitHub, the wiki, the website), and copies edited by
hand drift. `docs/` in the repository makes the best source: it's reviewed in the same pull
request as the feature, versioned with the code, checkable, and free for Claude to read
locally. The wiki is a separate git repository with no pull requests or checks, so it makes a
poor one; the website is a build output. (NetworkMonitor#334 has the whole decision.)

## Commands

| Command | Does |
|---|---|
| `docs-kit check [base]` | Fails when the branch changes what the app says or does (`check.needs_docs`) and no page for users, unless the pull request's description says `No docs needed: <why>`. Reads the description with `gh pr view` (`PR=<n>` names the pull request; `PR_BODY` gives the text instead). |
| `docs-kit site <site checkout> [commit]` | The website's docs pages, in the site's own template, rendered by GitHub. |
| `docs-kit wiki <wiki checkout> [commit]` | The wiki: every page, Home, the sidebar and the footer; removes pages whose doc is gone. |
| `docs-kit anchors` | Every page the site publishes, with its address and anchors, as JSON. |
| `docs-kit vendor [--check]` | Copies this file to the project's `Scripts/docs-kit`, or says whether that copy is this one. |
| `docs-kit init` | Writes a starting `.product-kit.json`. |
| `docs-kit -C <dir> …` | Runs as if started in `<dir>`, as `git -C` does. |

## `.product-kit.json`

The config docs-kit shares with [lang-kit](lang-kit.md): one file, one list of languages.
docs-kit reads `.docs-kit.json` when a project has no `.product-kit.json` yet; renaming it is
all a project needs to do (`git mv .docs-kit.json .product-kit.json`).

At the top of the repository. NetworkMonitor's is a full example.

| Key | Meaning |
|---|---|
| `repo` | `owner/name` on GitHub. Required. |
| `name` | The project's name, for templates (`{{project}}`). |
| `branch` | The default branch, for links to files (`main`). |
| `docs` | The docs folder (`docs`). `docs/README.md` is the index: its `## ` sections and the links in its tables' first column make the site's and the wiki's navigation. |
| `extra_pages` | Pages outside `docs/` that are part of them: `{"SECURITY.md": {"copy": "security.md", "slug": "security"}}`. `copy` is its translations' file name in `docs/<code>/`; `slug` its name on the site. |
| `developer_pages` | Pages for people working on the project. The wiki has them; the site leaves them on GitHub; they don't satisfy the check. |
| `languages` | `{"<code>": {"name": "简体中文", "site": "zh"}}`: each translation, in `docs/<code>/` with its own `README.md`, its name, and its folder on the site. |
| `check.needs_docs` | Rules: `{"paths": [globs], "except": [globs], "lines": "regex"}`. A changed file under `paths` (and not `except`) needs docs; with `lines`, only when a changed line matches it. `**/` matches any depth, including none. |
| `check.phrase` | The line that excuses it (`No docs needed`). |
| `site.url` | The site's address, for canonical and alternate links. |
| `site.folder` | Where the pages go under each language's folder (`docs`). |
| `site.language`, `site.language_name` | The source language's code and name (`en`, `English`). |
| `site.templates` | `{"<code>": "path in the site checkout"}`, one per language; the source language's is used for any without one. |
| `site.strip_lines` | Regexes: lines left out of the site's pages (a page's own language switch, which the template has). |
| `wiki.names` | Wiki page names for files, where the file name won't do. |
| `wiki.home` | Text above the index on the wiki's Home; `{web}` is the repository's address. |
| `vendor` | Where the project's copy lives (`Scripts/docs-kit`). |

## The website's pages

Each page for users becomes `<lang folder>/<folder>/<page>/index.html`, the index
`<lang folder>/<folder>/index.html`. A page is rendered by GitHub's Markdown API as GitHub shows
a file, so tables, alerts, code and HTML look as they do there. Each heading gets GitHub's
anchor (computed from the Markdown, as github-slugger does), so a link written for GitHub
works on the site. Links between pages become links between the site's pages; images point at
the repository at the commit built from; other files and pages for developers link to GitHub.

The template is the site's own: a page of HTML with these placeholders.

| Placeholder | Is |
|---|---|
| `{{title}}` | The page's `# ` heading |
| `{{description}}` | Its first paragraph, up to 160 characters |
| `{{lang}}` | Its language code |
| `{{root}}` | The way back to the site's top (`../../`) |
| `{{url}}` | Its full address |
| `{{alternates}}` | `<link rel="alternate" hreflang>` for each language it's in |
| `{{switch}}` | Links to it in the other languages (`data-lang` on each) |
| `{{nav}}` | The index's sections and pages, as a list; the page itself has `aria-current=page` |
| `{{content}}` | The page |
| `{{source}}`, `{{commit}}`, `{{commit_url}}` | Its file on GitHub, the commit built from |

`DOCS_KIT_RENDER` names a command to render with instead of GitHub (Markdown in, HTML out),
for tests and for working offline.

## Tests

`tests/test-docs-kit.sh`, run by `tests/run.sh` with the rest. It builds a
small project in a temporary folder and checks each command, offline.
