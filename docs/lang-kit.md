# lang-kit: the languages

Every language a product speaks, kept whole and in its own words (#4). It's the languages part
of [product-kit](../README.md): `lang-kit` on PATH, or `product-kit lang …`.

Each language has a **table** of the app's text and a **glossary**: its words for the app's
windows, features and settings, settled with a native speaker before anything else is
translated. lang-kit holds each table to the app and to its glossary, asks for a page's
translations when the English page changes, lists what each release changed for the
language's reviewer, and starts a new language. It grew out of NetworkMonitor's Chinese
(NetworkMonitor#428, #434).

One Python file, the standard library only. Each project keeps a copy at `Scripts/lang-kit`
(`lang-kit vendor`), so its CI needs no plugin.

## Commands

| Command | Does |
|---|---|
| `lang-kit strings` | For each language: every piece of text translated, nothing the app no longer says, the same placeholders as the English, and the glossary's words. Fails on any. |
| `lang-kit check [base]` | Fails when the branch changes an English page and not its copy in each language, or adds a page with no copy, unless the pull request's description says `No translation needed: <why>`. Reads the description with `gh pr view` (`PR=<n>` names the pull request; `PR_BODY` gives the text instead). `base` is `origin/main` by default. |
| `lang-kit review <from> [to]` | Markdown for each language's reviewer: what's new or changed in its table between two commits or tags (English beside it, in the table's order) and the pages that changed. |
| `lang-kit add <code> [name]` | Starts a language: adds it to `languages`, writes its glossary from another language's terms (to translate) and its table, and prints the order to do the rest in. |
| `lang-kit keys` | The text to translate, one per line. |
| `lang-kit todo [--since REF] [--json]` | Only what to translate, per language: text new or missing, and text whose English changed since `REF` (with the translation it had); each with where the code says it and only the glossary terms it uses, and the language's style and words to avoid. A small packet, in place of the whole table and glossary (#39: 7 pieces of NetworkMonitor's Chinese, 1.3 KB against 78 KB). |
| `lang-kit apply <file>` | Writes `{"<code>": {"<key>": "<translation>"}}` into each table, in its own format (`.strings`, `.xcstrings`, JSON, `.resx`, Qt), then checks them as `strings` does. |
| `lang-kit vendor [--check]` | Copies this file to the project's `Scripts/lang-kit`, or says whether that copy is this one. |
| `lang-kit -C <dir> …` | Runs as if started in `<dir>`. |

## `.product-kit.json`

The config lang-kit shares with [docs-kit](docs-kit.md). It reads `.docs-kit.json` when
there's no `.product-kit.json`.

| Key | Meaning |
|---|---|
| `languages` | `{"<code>": {"name": "简体中文", "site": "zh"}}`: each translation. Shared with docs-kit. |
| `lang.source` | The source language's code (`en`; else `site.language`). |
| `lang.strings.format` | `strings` (Apple), `xcstrings` (Xcode's string catalog, plurals included), `stringsdict` (Apple's counts), `json` (nested objects flattened with dots), `resx` (.NET), `ts` (Qt), or `command`: a kind lang-kit doesn't read, read by the project's own command (#37). |
| `lang.strings.read` | With `command`: the command, from the checkout, `{file}` for a file holding the table and `{code}` for its language: `["python3", "scripts/read-properties", "{file}", "{code}"]`. It prints the table as JSON, `{"key": "text"}`, and exits 0. Its placeholders are compared as `printf`'s unless `lang.strings.placeholders` says otherwise. |
| `lang.strings.path` | Where a language's table is, with `{code}`: `Resources/Localization/{code}.lproj/Localizable.strings`. One file for every language with `xcstrings`. |
| `lang.strings.source_path` | The source language's table, where it isn't `path` with its code (`Strings.resx` beside `Strings.{code}.resx`). |
| `lang.strings.keys.scan` | Globs of source files to read the text to translate from, when the source language has no table of its own (NetworkMonitor's keys are the English, written inside `L("…")`). Without it, the keys are the source table's (or, for Qt, every message the tables list). |
| `lang.strings.keys.except` | Globs left out of the scan. |
| `lang.strings.keys.plist` | An Info.plist whose text people see is the text to translate: its permission prompts (`…UsageDescription`), its names and its copyright, or the keys `keys.plist_keys` lists. For `InfoPlist.strings`, which has no English table of its own. |
| `lang.more` | More tables than the main one, each like `lang.strings` (`format`, `path`, `source_path`, `keys`) and checked the same way: the permission prompts (`InfoPlist.strings` with `keys.plist`), counts (`stringsdict`), Shortcuts' phrases (`AppShortcuts.xcstrings`), a widget's or an extension's table (#41). `todo` gives a packet per table; `apply --table <path>` writes into one; `add` sets up a new language's. |

**Apple's other text (#41).** `stringsdict` is a format of its own. A text that varies by count
(a `.stringsdict`, or a catalog's `variations.plural`) needs every form its language has for
whole numbers: `other` in Chinese, Japanese and Korean; `one` and `other` in English, French
and most others; `one`, `few`, `many` and `other` in Russian and Polish; all six in Arabic.
**A language written right to left** (Arabic, Hebrew, Persian, Urdu…): `lang-kit add` says what it
needs (`<div dir="rtl">` around its Markdown pages, `dir="rtl"` on its site page; macOS mirrors
the app by itself for its pictures), and `product-kit doctor` names a README that isn't marked.
| `lang.strings.keys.call` | The function the text is passed to (`L`), or `pattern`: a regex whose first group is the literal. |
| `lang.strings.placeholders` | `printf` (`%@`, `%1$d`), `braces` (`{0}`, `{name}`), `qt` (`%1`), or `none`. Each format has its own by default. |
| `lang.glossary` | Where a language's glossary is, with `{code}`. Each language must have one when this is set. |
| `lang.pages` | `[{"page": "docs/*.md", "copy": "docs/{code}/{name}", "except": [...]}]`: the English pages and where their copies are (`{name}` the file's name, `{path}` its path). Without it: `README.md` → `README.{code}.md`, each of docs-kit's `extra_pages` with a `copy`, and `docs/*.md` → `docs/{code}/<page>`, leaving out `developer_pages`. A `*` stays within its folder. |
| `lang.phrase` | The line that excuses an English-only change (`No translation needed`). |
| `lang.vendor` | Where the project's copy lives (`Scripts/lang-kit`). |

### The glossary

```json
{
  "language": "zh-Hans",
  "name": "简体中文",
  "reviewer": "their-github-login",
  "style": ["Address the user as 你, never 您."],
  "avoid": [{ "text": "您", "why": "the app addresses the user as 你" }],
  "terms": [
    { "en": "Settings", "text": "设置", "everywhere": true },
    { "en": "Ads and Trackers", "text": "广告与跟踪器", "note": "the section's name" },
    { "en": "Wiki", "text": "Wiki", "where": "docs" }
  ]
}
```

`lang-kit strings` holds the table to it:

- a term whose English is a whole piece of the app's text translates to exactly the term;
- with `"everywhere": true`, every piece of the app's text that says the English, as a whole
  word in any case, holds the term too;
- no translation uses an `avoid` word;
- a term the app no longer says fails, unless it's `"where": "docs"`, a name only the docs and
  the website use.

The terms are in English words whatever the table's keys are (JSON's `menu.quit`, a .resx
name): lang-kit compares through the source table's text. `style` is for whoever translates;
nothing checks it.

## A new project

1. `lang-kit add <code> <name>` (it writes a `.product-kit.json` if there's none), then set
   `lang.strings` to where the tables are, and `lang.glossary`.
2. `lang-kit vendor`; `lang-kit strings` in the tests, `lang-kit check` in CI;
   `lang-kit review` in the release steps.
3. Say in its CLAUDE.md that every language changes in the same pull request.

## Tests

`tests/test-lang-kit.sh`, run by `tests/run.sh`: a small project for each format in a
temporary folder, and each command checked against it, offline.
