---
name: lang-kit
description: How a project's languages work when its .product-kit.json has a "lang" section - each language's table of the app's text is held to the app and to that language's glossary, a changed English page needs its translations in the same pull request, and each release's changes go to the language's native reviewer. Use when a change adds or changes the app's text or a page with translations, when writing a translation, when releasing (the reviewer's list), or when adding a language to a project.
---

# lang-kit: every language, whole and in its own words

`lang-kit` (on PATH from this plugin; `product-kit lang …` is the same; each project keeps a
copy at `Scripts/lang-kit`) reads the project's `.product-kit.json`: `languages` (shared with
docs-kit) and `lang`. The project's CLAUDE.md says which make targets wrap these commands.

## Every language in the same pull request

A change to the app's text, or to an English page with translations, changes every language
with it. Nothing is left for a catch-up later.

- **The app's text.** `lang-kit strings` (often inside `make test`) fails until each language's
  table has every piece of text, nothing the app no longer says, the same placeholders, and its
  glossary's words. Write the translation with the glossary open
  (`lang.glossary`, e.g. `Resources/Localization/<code>.lproj/Glossary.json`): its `terms`
  name the app's windows, features and settings, its `style` says how the language is written
  (how to address the user, punctuation, spacing), and its `avoid` words never appear.
- **The pages.** `lang-kit check [base]` (CI) fails when a branch changes an English page
  (README, a page in `docs/` for users, extra pages) but not its copy in each language, or adds
  a page with none. Change the copy in the same pull request, in the glossary's words. When it's
  deliberately English only (a typo, a link), the pull request's description says so:
  `No translation needed: <why>`; re-run the check after adding it.
- A term the app no longer says fails too: change the glossary, or mark the term
  `"where": "docs"` when only the docs and the website use it.

## Releasing: the native review

Post `lang-kit review <the last release's tag>` on the release's issue: for each language, a
table of what the release says new or differently, English beside it, and the pages that
changed, mentioning the glossary's `reviewer`. Nothing waits on it; their changes follow on
the issue, in pull requests like any other, and go into the glossary where they name something.

## A new language

`lang-kit add <code> [name]` adds it to `languages`, writes its glossary with another
language's terms to translate, and its table, then prints the order:

1. **The glossary first**, settled with the native speaker who asked for it (`reviewer`).
2. **Everything in one pass**, in the glossary's words: the app's table (`lang-kit strings`
   lists what's missing), `README.<code>.md`, a copy of each page in `docs/<code>/`, the
   website's page, `languages.<code>.site`.
3. **Release it**, then the native review.
4. **Its pictures** (product-kit's shots, once there) and, only if wanted, its videos.

## Setting it up in a project

Add a `lang` section to `.product-kit.json` (`docs/lang-kit.md` in product-kit has every key),
then `lang-kit vendor`, and wire `lang-kit strings` into the tests and `lang-kit check` into CI.
The reference is `docs/lang-kit.md` in `~/Work/personal/product-kit`
(kevinabouhanna/product-kit).
