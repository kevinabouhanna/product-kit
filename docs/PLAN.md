# The plan

product-kit keeps everything a product shows people current and in every language: its plan,
its docs, its pictures and videos, its store pages and their translations, for the README, the
wiki, the website and the App Store. It does the work with scripts, so a Claude session spends
its tokens only on the words, and it sets a new project up in one command.

This file is the map. Each phase has a page in [`phases/`](phases/), a GitHub milestone and a
phase issue; each thing to build in it is an issue under that phase issue. The live order is the
[project board](https://github.com/users/kevinabouhanna/projects/11), and
[`phases/README.md`](phases/README.md) lists it, written by `docs-kit plan sync`.

## The parts

| Part | Does |
|---|---|
| `docs-kit` | The plan (this file, its phase pages and GitHub kept the same), then `docs/` as the one source of the website's docs pages and the wiki |
| `lang-kit` | Every language's text held to the app and to its glossary; a changed page needs its translations; what each release changed, for the native reviewer |
| `shots-kit` | Every picture, GIF and video listed with what it shows, and retaken only when the interface it shows changed |
| `product-kit` | One command for all of them; `init` and `status` come in phase 2 |

## The order, for every change

Language runs through every step, since a translated picture is a picture of the translated app:

1. **Words**: the app's text and the docs, in every language, in the same pull request.
2. **Build and release.**
3. **Pictures**: retaken in every language, only where the interface changed.
4. **Videos**: remade by script where they show a changed window; hand-made ones flagged.
5. **Publish**: README, wiki, website, store pages.
6. **Native review**, after the release; nothing waits on it.

## How it's built

- **Scripts do the work; Claude only writes words.** Every check is a script that prints one
  line when all is well. When something needs Claude, the script hands over exactly that piece.
- **Only what changed**, everywhere: pictures, translations, docs paragraphs, videos.
- **Generic, never one project's.** What's particular to a project goes in its
  `.product-kit.json`, or in an extension of its own. Each part is proved on a second project,
  and on the test apps in `tests/`.
- **Mac and iPhone first.** Windows and Android come in a later phase.

## The phases

| Phase | What it gives | Page |
|---|---|---|
| **1. Out of NetworkMonitor** | The three tools moved out of NetworkMonitor into one plugin, working for a second Mac app | [01-out-of-networkmonitor](phases/01-out-of-networkmonitor.md) |
| **2. Any Mac or iPhone project** | Nothing of one project left in the code, a new project set up in one command, everything kept current by scripts, iPhone pictures, scripted videos, App Store pages | [02-any-mac-or-iphone-project](phases/02-any-mac-or-iphone-project.md) |
| **3. Windows and Android** | The same for Windows and Android apps | [03-windows-and-android](phases/03-windows-and-android.md) |

Phase numbers are names, not the order: the board's Order is.

On GitHub the plan is one tree of issues: the pinned root issue, "The plan: product-kit", whose
description lists every item in order; under it a phase issue per phase; under each phase issue
its items; under an item its steps. `docs-kit plan check` runs in local CI, so the pages, the
issues, the milestones and the board never drift apart.
