---
name: shots-kit
description: How a project's website pictures of its macOS app are kept current when its .product-kit.json has a "shots" section - each picture's window is read through the Accessibility API and compared with the tree recorded with it, retaken only when the interface changed, and every image, GIF and video is listed with the window it shows (the asset check). Use when a change alters a window the site or README shows, when adding or renaming a picture or video, when the asset check fails, after a release (retaking pictures), or when setting pictures up in a new project.
---

# shots-kit: pictures that never go stale

`shots-kit` (on PATH from this plugin; `product-kit shots …` is the same) builds itself on first
use. Each project keeps a copy of its source for CI (`shots.vendor`), and its CLAUDE.md says
which make targets wrap it. The site's `shots/shots.json` lists each picture's window; the
trees recorded with them are in `shots/trees/`.

## Never judge pictures by eye

- **What changed:** `shots-kit check` (no retakes) names each window whose interface changed,
  with the diff, and the videos and staged pictures that show one. Read the diff: a new or
  renamed control is a real change; a number or a list's length never shows up.
- **Retake:** `shots-kit update` (after a release, once it's installed) retakes only what
  changed and updates the page. A picture it reports as **not taken** (the Mac was in use)
  doesn't hold anything: say so, and a later run takes it. Never ask the person at the Mac to
  step away.
- **Alt text** describes the interface, not its numbers, so a retake never makes it wrong.
  Rewrite the alt text of a picture retaken for an interface change, from the diff.
- **Videos and staged pictures** are flagged, never remade without asking.
- **A window marked differently** (more of it as data): `shots-kit record <names>`, and check
  the diff it prints covers only the new marks.

## Every asset is listed

`shots-kit coverage` (CI) fails on an image, GIF or video a page, the README or the docs uses
that isn't a shot's picture or listed: on the site in `shots/shots.json`'s `assets`, in the
README and docs in `shots.repo_assets`. A listed asset says the windows it `shows` and the app
version it was `made` from, or `none` and why it shows no window (an icon, a dated record).
When a window it shows changes, it's out of date: remake it and set `made`, or set `stale` to
the issue its remake waits on.

## Sharing the Mac

It takes the app's Mac lane and `screen` itself, only while it reads or takes windows, and puts
the installed app back as it was. Tell the other sessions before a run (the shared-mac skill).
It needs a Retina screen and, for pictures, looks and clicks, the Mac idle.

The reference, with every key, is `docs/shots-kit.md` in `~/Work/personal/product-kit`
(kevinabouhanna/product-kit).
