# Phase 2: Any Mac or iPhone project

**Milestone:** Phase 2: Any Mac or iPhone project · **Status:** Later

**Goal:** tools that work for any Mac or iPhone project, a new project set up in one command,
and everything it shows people (docs, pictures, videos, languages, store pages) kept current by
scripts rather than tokens.

Kevin (2026-11-13, on #1):

> When I was viewing the issue, I noticed that there is a lot of stuff that is still
> NetworkMonitor-specific. To finalize this, we want it to work for any new project to have a
> complete system to kickstart the project and have everything updated and up to date with
> whatever requirements change, and it should be done in a smart way.
> 1. To have docs, images, videos, and languages all updated with the latest info.
> 2. It should be done with scripting so that we can reduce token cost.
>
> And it should be intelligent enough in case we have any scenario that is specific to a new
> project; we can update it to take care of gaps we didn't take into consideration. […] Our
> focus for now will be on the Mac and iOS ecosystems; no need to take care of Windows or
> Android. That will be for later phases.

The phase issue is #30, where this was planned.

## What was still NetworkMonitor's (2026-11-13)

| Where | What | What it means |
|---|---|---|
| `shots/shots-kit.swift:592-608` | The parts of a window that change by themselves (dates, times, amounts) are recognised only in English and Chinese, and the amounts only as network units (KB/s, Mbps) | In a French or Arabic app, or one showing money or a battery %, every picture would look "changed" on every check |
| `shots-kit.swift:628` | A rule for NetworkMonitor's menu-bar readout (keeps its width) | Another menu-bar app inherits NetworkMonitor's special case |
| `shots-kit.swift:508`, `:1423`, `:1484` | The website's pictures must be in `assets/`, and clickable areas only on `index.html` | A website laid out differently isn't understood |
| `shots-kit.swift:93`, `:245` | A window's labels are translated from the app's `.strings` table only | A web-view app (home-control) can't be pictured in another language |
| Two lists of pictures | The site's `shots/shots.json` and the README's `assets.json` | Two lists to keep, in two places |
| One 2,931-line file | shots-kit's core and its macOS part never split | No room for an iPhone driver |
| Skills, docs, help text | Written in NetworkMonitor's terms | Sessions in other projects get the wrong directions |
| NetworkMonitor's release checklist | The website's version line, alt text, videos, the translation review, by hand | Every new project would copy a page of steps |
| Not built | `product-kit init` and `product-kit status` | No kickstart, and no one place to see what's stale |
| Nothing for iPhone | Simulator pictures, App Store pages, Apple's other text | An iPhone app gets nothing yet |

## How it works

- **Scripts do the work; Claude only writes words.** Every check is a script that runs in CI and
  prints one line when all is well. When something needs Claude (a translation, a paragraph, alt
  text), the script hands over exactly that piece and what's needed to write it.
- **Only what changed**: pictures of windows whose interface changed, translations of text that
  changed, the docs paragraph that describes it, videos that show a changed window.
- **One config, one list of assets, one list of languages, one skill.**
- **What we didn't think of**: a project's own extension, a `gap` issue here the same day, moved
  into product-kit when a second project needs it; `product-kit doctor` finds gaps by itself.
- **Proved on more than one project**: NetworkMonitor, claude-profiles-mac, home-control, and the
  small test apps in `tests/`.

## Decisions (Kevin, 2026-11-13)

1. **Videos** are made by script, in every language; hand-made ones are flagged and never
   remade without asking.
2. **iPhone** parts are proved on a tiny test app inside product-kit.
3. **App Store uploads**: not now. product-kit prepares and checks the pages; sending them to
   Apple is thought about once there's something to upload.
4. **Translation drafts by a cheaper model**: measure first, then decide.

## The items

Now: make it generic.

- #31 product-kit runs on its own plan.
- #32 Take out what's still NetworkMonitor's: dates in every language, its units, its site's layout.
- #33 Every project's copy of the tools updated in one go, with one version.
- #34 One small skill, so every session costs fewer tokens.
- #35 shots-kit: one core, and a driver for each kind of app.
- #36 One list of every picture, GIF and video.
- #37 Extensions for what a project needs, and a doctor that finds the gaps.
- #38 `product-kit status`: one short list of what's out of date.

Next: cheaper upkeep, the kickstart, iPhone.

- #39 Translate and document only what changed: small packets for Claude.
- #40 One place for the facts and the pitch.
- #41 All of Apple's text in every language, and right to left.
- #42 `product-kit init`: a new project set up in one command.
- #43 iPhone and iPad pictures, from the simulator, out of sight.

Later: videos, store pages, web views, the proof.

- #44 Videos made by script, in every language.
- #65 Recorded videos of a Mac app, and NetworkMonitor's live.mp4 by script.
- #45 App Store pages and release notes, in every language.
- #46 Apps built on web views (home-control), and the website itself checked.
- #47 Prove it: a new project from nothing, and every project current.

## Not in this phase

- Sharing the Mac (lanes, the screen, VMs, simulators out of sight): the shared-mac plugin.
- Designing a website or an app: the `hallmark` and `impeccable` skills.
- Windows and Android: [phase 3](03-windows-and-android.md).
