# shots-kit: the pictures

A project's pictures of its macOS app, on its website or only in its README, kept current
without anyone looking at them, and every image, GIF and video listed with the window it
shows (#6). It gets them one of two ways: from **the installed app**, whose windows it opens
and reads on the screen (NetworkMonitor), or **drawn by the project itself**, out of sight,
from made-up data (claude-profiles-mac, #8). It's the pictures part of
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

## Pictures the project draws itself

Some apps can draw their own windows into image files: a debug command that renders a view
from a file of made-up data, with no window on any screen. claude-profiles-mac's
`--snapshot-panel <fixture.json> <dir>` draws its dropdown that way. Then the manifest's
**`render`** says how: a command that builds the app, and one that draws every picture into a
folder (`{out}`). Each shot names its `file` and the drawing it comes from (`render`).

- `check` builds, draws, and compares each drawing with its picture, pixel by pixel (a
  picture saved differently with the same pixels is the same). A pixel that differs is a
  change, so the drawing has to be **the same every run**: its data, its clock and its settings
  fixed, in the project. It names what's made by hand from a shot that changed, as above.
- `update` copies the drawings that differ over their pictures.
- No app is opened, nothing appears on the screen, no Mac lane is taken, and no permission is
  needed, so it runs anywhere, any time. The drawing has to stay **out of sight**: no window on
  any screen, no Dock icon. That's the project's job.
- `tree`, `record`, `audit`, `--look` and `--language` are for an app's windows, not drawings.

```json
{
  "render": {
    "build": ["./build.sh"],
    "command": ["env", "TZ=UTC", "build/App.app/Contents/MacOS/App", "--snapshot", "shots/demo.json", "{out}"]
  },
  "shots": [{"name": "dropdown", "file": "docs/images/dropdown.png", "render": "panel-dark.png"}],
  "assets": [{"file": "docs/images/logo.png", "none": "the app's icon"}]
}
```

## Without a website

With no `shots.site` (and no `--site`), `shots/shots.json` is in the project's own checkout
and its files are the repo's. `coverage` then checks the README's and the docs' assets against
that one list: `shots.repo_assets` isn't used.

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
| `vendor [--check]` | Copies the tool's source into the project (`shots.vendor`), so its CI can build it without the plugin, with `AccessibilityAudit.swift` beside it unless the project has its own (`shots.audit`). |
| `version` | |

Options: `--site DIR` (the site's checkout), `--repo DIR` (the project's; the checkout this
runs in by default), `--app PATH` (another copy of the app, such as a development build),
`--language CODE` (one language only), `--vm` and `--here` (in a VM, or on this Mac's screen;
below), `--wait-away MINUTES` (wait, silently and with the lanes free, for the Mac to be idle,
for the shots that need the real screen).

## Sharing the Mac

On this Mac (not `--vm`), it needs Accessibility and Screen Recording for the terminal it runs in, and a Retina screen.
It takes the app's Mac lane and `screen` (`mac-lane`, from the shared-mac plugin) only while it
reads or takes windows. Reading a tree needs no focus; a picture, a look or a real click needs
the window in front, which happens only while the Mac is idle (`MAC_LANE_IDLE`, 90 s by
default). Otherwise those shots are reported as **not taken**, and why; nobody is ever asked to
step away. It quits and relaunches the app, and however the run ends puts the installed copy
back running if it was, with its windows where they were.

## In a VM

`--vm` (or `shots.vm.default` in the config, unless `--here`) takes the pictures in a
throwaway macOS VM rather than on this Mac's screen (#10): `mac-vm`, from the shared-mac
plugin. The VM has its own screen, pointer and focus, so nothing shows on the person's screens,
no shot waits for the Mac to be idle or is reported as not taken, real clicks are fine, and
this Mac's copy of the app is never quit. `check`, `update`, `record`, `tree` and `audit` go
there; the commands that read files stay here.

1. Into a shared folder go the tool itself, the app (the manifest's, or `--app`; zipped, as a
   bundle's links don't survive the shared folder), a copy of the project's and the site's files
   (what git tracks), and `vm.files`.
2. `mac-vm run --display <vm.display>` boots a clone of the golden image with that screen.
   Inside, the app is installed where the manifest says, `vm.files` go to the same place,
   `vm.setup` runs from the project's copy, then the same command, which takes the VM's screen
   whenever it needs it.
3. Each file the run changed or added comes back to the site and the project. Nothing else is
   touched, so a change made here meanwhile stays.

The VM is a fresh Mac: none of this Mac's data, settings, accounts or apps unless `vm.files`
and `vm.setup` put them there, and its own wallpaper and scale. A project switching to it
compares a run's pictures with its current ones first. It takes no Mac lane; `mac-vm` holds
one of the two VM lanes. One VM run per site at a time.

## `.product-kit.json`

`shots`, every key optional, and `site.url` (shared with docs-kit).

| Key | Meaning |
|---|---|
| `shots.site` | The site's checkout, from the project's main checkout, so it's the same from any worktree: `../NetworkMonitor-site`. Without it (or `--site`), the manifest is the project's own. |
| `shots.repo_assets` | The README's and the docs' list of their assets (`assets.json`), when there's a site. |
| `shots.lane` | The app's Mac lane (its bundle id's last part, lowercased). |
| `shots.launch.background` | Launch arguments that open the app's windows behind the others without activating it, for commands that only read trees: `["-background", "YES"]`. The app has to support them. |
| `shots.launch.language` | Launch arguments that show the app in a language, `{code}` for its code (`["-AppleLanguages", "({code})"]`). |
| `shots.strings` | The app's table for a language in its bundle, for naming elements in that language (`Contents/Resources/{code}.lproj/Localizable.strings`). |
| `shots.audit` | The project's own `AccessibilityAudit.swift` to build with, so `audit` uses the rules its tests do; product-kit's copy otherwise. |
| `shots.vendor` | Where `vendor` copies the source (`Scripts/shots-kit.swift`). |
| `shots.vm.default` | `true`: run in a VM unless `--here` (#10). |
| `shots.vm.display` | The VM's screen in pixels, shown at 2x: `3200x2000` (1600×1000 points, the default), big enough for the app's windows. |
| `shots.vm.files` | Files and folders of this Mac copied to the same place in the VM before the app opens (`~` the home folder): the app's data and settings, for pictures that show them. |
| `shots.vm.setup` | A command run in the VM from the project's copy, after the app is installed (`$SHOTS_APP`) and before any picture: the app's first-run state. |
| `shots.branches` | `{"site": "gh-pages", "repo": "main"}`: the branches the asset check's report names. |
| `site.url` | The site's address: links to `assets/…` written with it (a social card's `<meta>`) are the site's. |

## `shots/shots.json`

On the site, or in the project's checkout when it has none. NetworkMonitor's (on its `gh-pages`) is the full example of an app's windows; claude-profiles-mac's (on `main`) of drawings.

| Key | Meaning |
|---|---|
| `app`, `bundle` | The installed app and its bundle id. Not with `render`. |
| `render` | Pictures the project draws itself: `build` and `command`, `{out}` for the folder. Its shots have only `name`, `file` and `render`. |
| `shots` | One per picture or checked window: `name`, `file` (the picture, from the site's root; none for a window only checked), `open` (launch arguments), `window` (its title, or an element such as `AXPopover`), `click`, `scroll`, `waitFor`, `when` (taken only when that shot's window changed: a costly one), `skipIf`, `ignore`, `data` (regions that are data: `from`, `until`, `skip`, `optional`), `crop`, `areas` (clickable areas on the page: `match`, `element`, `parent`, `pad`, `h`), `always`. |
| `assets` | Every other image, GIF and video the site uses: `file`, and `shows` (shots) with `made` (the app version), or `none` (why it shows no window), and `stale` (the issue its remake waits on). |
| `languages` | Other languages the site has a page in: `code`, `page`, `assets` (its pictures' folder), `specs` (labels the app's table can't translate). Each shot is taken again in each. |

An element is written `Role:label`, `Role:~part of a label` or `Outer>Inner`.

## A new project

Pictures the project draws (no app to open, no screen): `shots/shots.json` with `render`, its
drawings made the same every run, `shots-kit check` until every picture is as drawn, then
`shots-kit vendor` and `coverage` in CI. Otherwise:

1. A `shots` section in `.product-kit.json`, and `shots/shots.json` on the site with a shot
   for each picture (`shots-kit tree <name>` prints what a window reads as, for its `data`).
2. `shots-kit update` once, to record every tree, then `shots-kit coverage` until every asset
   is listed.
3. `shots-kit vendor`, and `coverage` in CI (built with
   `swiftc -O -parse-as-library <vendored copy> <AccessibilityAudit.swift>`).
4. After each release, once it's installed: `shots-kit update`.

## Tests

`tests/test-shots-kit.sh`, run by `tests/run.sh`: it builds, runs `coverage-test`, and checks
the asset check, the config and vendoring on a made-up project and site, `check` and
`update` on a made-up project that draws its own pictures, and a run in a VM with a stand-in
for `mac-vm` (what goes in, what comes back, the config). What needs an app and the screen is
checked against NetworkMonitor's pictures when the tool changes.

## Not yet

macOS apps only (a project's own drawings could be anything's), and one Swift file holding both what's the same everywhere (the manifest, the
asset check, the diffs, the page) and what's macOS's (the Accessibility API, ScreenCaptureKit,
launching). They separate when a second platform comes (web pages, Windows apps: #1, step 5).
