---
name: product-kit
description: A project's plan, docs, translations, pictures and videos, kept current by scripts. Use in a project with a .product-kit.json (or .docs-kit.json) when starting it, changing its plan or scanning its inbox, changing what its app says or shows, adding a language, picture or video, releasing, or changing product-kit itself.
---

# product-kit

Scripts do the work; you write only the words. Run the command, read its short output, and do
what it says. What's particular to the project is in its `.product-kit.json`; its CLAUDE.md
names the make targets and where its copies of the tools are (`Scripts/` or `scripts/`). On
PATH: `product-kit`, `docs-kit`, `lang-kit`, `shots-kit` (`product-kit docs|lang|shots …` is
the same).

**The order for every change**, language running through it: words (the app's text and the
docs, in every language, in one pull request) → build and release → pictures (retaken where
the interface changed) → videos → publish (README, wiki, website) → native review.

## When this happens, run this

| When | Run | And |
|---|---|---|
| A new project | Write `docs/PLAN.md` and `docs/phases/*.md` with the owner, then `docs-kit plan init` (`--dry-run` first) | `docs-kit plan check` in CI |
| The plan changes (a new issue, a new order, a phase done) | `docs-kit plan sync`, then `docs-kit plan check`, which must pass | Mention each new item (`#N`) on its phase's page; a new item is a sub-issue of its phase issue |
| The owner says "scan the inbox" | `docs-kit plan inbox` | Follow [Scan the inbox](../../docs/docs-kit-plan.md#scan-the-inbox); never take an entry in unasked |
| The app's text changes | `lang-kit strings` until it passes; translate with the language's glossary open | `docs-kit check` asks for the page in `docs/` that describes it, in every language |
| An English page changes | Its copy in every language, in the same pull request (`lang-kit check`) | Deliberately English only: `No translation needed: <why>` in the pull request |
| No docs are needed after all | `No docs needed: <why>` in the pull request, then `docs-kit check` again | Pages for developers don't count |
| A window a picture shows changes | After the release is installed: `shots-kit check`, then `shots-kit update` | Rewrite the alt text of each retaken picture from the diff it prints |
| A new image, GIF or video | List it: `shots-kit coverage` until it passes | It names the windows it shows, or why none |
| A release | `lang-kit review <last tag>` on the release's issue; `docs-kit site <site>` from the tag; `shots-kit update` once installed | Videos it flags are remade only when asked |
| A new language | `lang-kit add <code> [name]` | Follow the order it prints |
| A changed heading | `docs-kit anchors` | An app may link to it: `<a id="…">` keeps an old address |
| product-kit's own tools changed | In product-kit: `product-kit bump <version>`, then `product-kit vendor --all` | Each project's pull request merges by its own CI and rules |

## Never

- Edit what's built: the website's docs pages, the wiki, the plan's root issue and phase issues'
  descriptions, `docs/phases/README.md`. Change the source and rebuild.
- Judge a picture by eye, or weaken a check to make it pass.
- Remake a video by hand without asking, or ask the person at the Mac to step away: a picture
  reported as not taken is taken by a later run.
- Put one project's particulars in product-kit's code: they go in the project's config.

Alt text describes the interface, not its numbers, so a retake never makes it wrong.

## The references

Read only the one you need, in the plugin's folder (two folders up from this skill's):
`docs/docs-kit.md` (docs, website, wiki), `docs/docs-kit-plan.md` (the plan, the inbox),
`docs/lang-kit.md` (languages), `docs/shots-kit.md` (pictures and videos),
`docs/product-kit.md` (projects, versions). Sharing the Mac (lanes, VMs, the screen) is the
shared-mac skill's.
