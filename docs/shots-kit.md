# shots-kit: the pictures

A website's pictures of a macOS app, kept current without anyone looking at them, and every
image, GIF and video listed with the window it shows (#6). It's the pictures part of
[product-kit](../README.md): `shots-kit` on PATH, or `product-kit shots …`. It grew out of
NetworkMonitor's `site-shots` (NetworkMonitor#329 and after), and NetworkMonitor's
`docs/development.md#website-pictures` has the whole story of how it reads a window.

## How it works

Each picture on the site has an entry in the site's **`shots/shots.json`**: the launch
arguments that open its window, anything to click first, which parts of the window are data
(numbers, lists) rather than interface, an optional crop, and the clickable areas laid over the
picture on the page. For each entry, shots-kit opens the installed app and reads the window
through the Accessibility API: each element's role, labels and size, with the data masked. It
compares that **tree** with the one recorded when the picture was taken
(`shots/trees/<name>.txt`). New numbers or a longer list change nothing; a new button, a
renamed setting or a moved section does. Because it reads the tree rather than looking at the
picture, a check costs nothing and never tires.

A change only to how something looks (a colour, an icon, spacing) leaves the tree the same, so
each picture also keeps its **look**, a small thumbnail of its colours outside what's masked
(`<name>.look`). That's advice, not a failure.

Videos and staged pictures aren't taken by the tool: they're listed with the windows they show
and the app version they were **made** from, and **flagged** for remaking by hand when one of
those windows changes.

## Commands

| Command | Does |
|---|---|
| `check [--look] [names]` | What changed in each window, and which videos and staged pictures show one that did. Exits 1 if anything did. `--look` compares looks too, which needs each window in front: only while the Mac is idle. |
| `update [names]` | Retakes the pictures whose window changed (or the ones named), records their trees and looks, and updates the page: each picture's size, its clickable areas, and `?v=` on every asset link. Copies the README's pictures from the site's. |
| `record <names>` | Records the named windows' trees as they read now, without retaking their pictures: after marking more of a window as data. |
| `tree <name>` | Prints a window's masked tree, for writing its entry. |
| `audit [names]` | Each window checked for what VoiceOver can't name, with real data in its lists. |
| `readme` | Copies the site's pictures the README uses into it, in every language. Files only. |
| `coverage` | **The asset check**: every image, GIF and video the site, the README and the docs use is a shot's picture or listed, with the windows it shows (`shows` and `made`) or why it shows none (`none`). Files only, so it runs in CI. |
| `coverage-test` | Where `coverage` looks for media, on made-up pages. |
| `vendor [--check]` | Copies the tool's source into the project (`shots.vendor`), so its CI can build it without the plugin. |
| `version` | |

Options: `--site DIR` (the site's checkout), `--repo DIR` (the project's; the checkout this
runs in by default), `--app PATH` (another copy of the app, such as a development build),
`--language CODE` (one language only), `--wait-away MINUTES` (wait, silently and with the
lanes free, for the Mac to be idle, for the shots that need the real screen).

## Sharing the Mac

It needs Accessibility and Screen Recording for the terminal it runs in, and a Retina screen.
It takes the app's Mac lane and `screen` (`mac-lane`, from the shared-mac plugin) only while it
reads or takes windows. Reading a tree needs no focus; a picture, a look or a real click needs
the window in front, which happens only while the Mac is idle (`MAC_LANE_IDLE`, 90 s by
default). Otherwise those shots are reported as **not taken**, and why; nobody is ever asked to
step away. It quits and relaunches the app, and however the run ends puts the installed copy
back running if it was, with its windows where they were.

## `.product-kit.json`

`shots`, every key optional, and `site.url` (shared with docs-kit).

| Key | Meaning |
|---|---|
| `shots.site` | The site's checkout, from the project's main checkout, so it's the same from any worktree: `../NetworkMonitor-site`. Without it, give `--site`. |
| `shots.repo_assets` | The README's and the docs' list of their assets (`assets.json`). |
| `shots.lane` | The app's Mac lane (its bundle id's last part, lowercased). |
| `shots.launch.background` | Launch arguments that open the app's windows behind the others without activating it, for commands that only read trees: `["-background", "YES"]`. The app has to support them. |
| `shots.launch.language` | Launch arguments that show the app in a language, `{code}` for its code (`["-AppleLanguages", "({code})"]`). |
| `shots.strings` | The app's table for a language in its bundle, for naming elements in that language (`Contents/Resources/{code}.lproj/Localizable.strings`). |
| `shots.audit` | The project's own `AccessibilityAudit.swift` to build with, so `audit` uses the rules its tests do; product-kit's copy otherwise. |
| `shots.vendor` | Where `vendor` copies the source (`Scripts/shots-kit.swift`). |
| `shots.branches` | `{"site": "gh-pages", "repo": "main"}`: the branches the asset check's report names. |
| `site.url` | The site's address: links to `assets/…` written with it (a social card's `<meta>`) are the site's. |

## `shots/shots.json`

On the site. NetworkMonitor's (on its `gh-pages`) is the full example.

| Key | Meaning |
|---|---|
| `app`, `bundle` | The installed app and its bundle id. |
| `shots` | One per picture or checked window: `name`, `file` (the picture, from the site's root; none for a window only checked), `open` (launch arguments), `window` (its title, or an element such as `AXPopover`), `click`, `scroll`, `waitFor`, `when` (taken only when that shot's window changed: a costly one), `skipIf`, `ignore`, `data` (regions that are data: `from`, `until`, `skip`, `optional`), `crop`, `areas` (clickable areas on the page: `match`, `element`, `parent`, `pad`, `h`), `always`. |
| `assets` | Every other image, GIF and video the site uses: `file`, and `shows` (shots) with `made` (the app version), or `none` (why it shows no window), and `stale` (the issue its remake waits on). |
| `languages` | Other languages the site has a page in: `code`, `page`, `assets` (its pictures' folder), `specs` (labels the app's table can't translate). Each shot is taken again in each. |

An element is written `Role:label`, `Role:~part of a label` or `Outer>Inner`.

## A new project

1. A `shots` section in `.product-kit.json`, and `shots/shots.json` on the site with a shot
   for each picture (`shots-kit tree <name>` prints what a window reads as, for its `data`).
2. `shots-kit update` once, to record every tree, then `shots-kit coverage` until every asset
   is listed.
3. `shots-kit vendor`, and `coverage` in CI (built with
   `swiftc -O -parse-as-library <vendored copy> <AccessibilityAudit.swift>`).
4. After each release, once it's installed: `shots-kit update`.

## Tests

`tests/test-shots-kit.sh`, run by `tests/run.sh`: it builds, runs `coverage-test`, and checks
the asset check, the config and vendoring on a made-up project and site. What needs an app and
the screen is checked against NetworkMonitor's pictures when the tool changes.

## Not yet

macOS apps only, and one Swift file holding both what's the same everywhere (the manifest, the
asset check, the diffs, the page) and what's macOS's (the Accessibility API, ScreenCaptureKit,
launching). They separate when a second platform comes (web pages, Windows apps: #1, step 5).
