"""shots-kit videos (product-kit#44): videos made by script, remade when a window they show changes.

A video in the manifest's `assets` says how it's made:

  "how": "recorded"   the app driven through a shot and recorded, by the manifest's driver
                      (`"record": {"shot": "<name>", "seconds": 8}`): `product-kit driver
                      ios-simulator` records the simulator; a driver of the project's own
                      answers the same request
  "how": "built"      put together by a command from the current pictures and the app's own
                      text (`"build": {"command": [...]}`, `{out}` the file to write, `{code}`
                      the language, `{site}` and `{repo}` the checkouts): Hyperframes, Remotion,
                      ffmpeg, a poster from the video
  anything else       made by hand: named when a window it shows changed, never remade

It's out of date when a window it `shows` was recorded from a newer app version than it was
`made` from (as the asset check says). `videos` remakes the scripted ones that are, or those
named, or all of them with `--all`; in every language when `"every_language": true` (each
language's copy in its folder) or in the one `"language"` it names; then sets `made`.

Usage: python3 -I videos.py <project checkout> <site checkout or ""> [names] [--all] [--dry-run]
"""

import json
import os
import pathlib
import subprocess
import sys


def say(text: str) -> None:
    print(text, flush=True)


def parts(v: str) -> tuple:
    return tuple(int(x) if x.isdigit() else 0 for x in str(v).split("."))


def main(argv: list[str]) -> int:
    repo = pathlib.Path(argv[0]).resolve()
    site = pathlib.Path(argv[1]).resolve() if len(argv) > 1 and argv[1] else repo
    rest = argv[2:]
    names = {a for a in rest if not a.startswith("--")}
    dry, every = "--dry-run" in rest, "--all" in rest
    config = json.loads((repo / ".product-kit.json").read_text(encoding="utf-8")) \
        if (repo / ".product-kit.json").exists() else {}
    media = config.get("shots", {}).get("media", "assets").rstrip("/")
    manifest_file = site / "shots/shots.json"
    if not manifest_file.exists():
        say(f"videos: no shots/shots.json in {site}")
        return 2
    manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    versions_file = site / "shots/trees/versions.json"
    versions = json.loads(versions_file.read_text(encoding="utf-8")) if versions_file.exists() else {}
    entries = {s["name"]: s for s in manifest.get("shots", [])}
    languages = manifest.get("languages", [])

    def recorded(window: str) -> str | None:
        made = f"{window}.made.txt"
        return versions.get(made) if (site / "shots/trees" / made).exists() else versions.get(f"{window}.txt")

    def in_language(file: str, code: str) -> str:
        lang = next((l for l in languages if l["code"] == code), None)
        if not lang:
            return file
        return lang["assets"] + file[len(media) + 1:] if file.startswith(media + "/") else file

    remade, by_hand, failed = [], [], []
    changed = False
    for asset in manifest.get("assets", []):
        file, how = asset.get("file", ""), asset.get("how")
        shows = asset.get("shows") or []
        newest = max((v for v in (recorded(w) for w in shows) if v), key=parts, default=None)
        stale = bool(newest and asset.get("made") and parts(asset["made"]) < parts(newest))
        if names and file not in names and pathlib.PurePosixPath(file).name not in names:
            continue
        if how not in ("recorded", "built"):
            if stale:
                by_hand.append(f"{file} (made from {asset.get('made')}, its windows from {newest})")
            continue
        if not (stale or names or every):
            continue
        targets = [(asset.get("language"), file)]
        if asset.get("every_language"):
            targets = [(None, file)] + [(l["code"], in_language(file, l["code"])) for l in languages]
        for code, out in targets:
            path = (site if not asset.get("in") == "repo" else repo) / out
            say(f"videos: {'would make' if dry else 'making'} {out} ({how}{', ' + code if code else ''})")
            if dry:
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            try:
                if how == "built":
                    spec = asset.get("build", {})
                    cmd = [a.replace("{out}", str(path)).replace("{code}", code or config.get("lang", {}).get("source", "en"))
                           .replace("{site}", str(site)).replace("{repo}", str(repo)) for a in spec.get("command", [])]
                    if not cmd:
                        raise RuntimeError("`build.command` names no command")
                    r = subprocess.run(cmd, cwd=repo, capture_output=True, text=True, timeout=spec.get("limit", 1800))
                    if r.returncode != 0:
                        raise RuntimeError(f"the build failed (exit {r.returncode}): {(r.stderr or r.stdout).strip()[-300:]}")
                else:
                    spec = asset.get("record", {})
                    driver = manifest.get("driver", {}).get("command")
                    shot = entries.get(spec.get("shot"))
                    if not shot:
                        raise RuntimeError(f"record.shot {spec.get('shot')!r} isn't a shot in the manifest")
                    if driver:
                        request = {"action": "record", "shot": shot, "language": code or "en", "video": str(path),
                                   "seconds": spec.get("seconds", 8), "repo": str(repo)}
                        r = subprocess.run(driver, cwd=repo, input=json.dumps(request), capture_output=True, text=True,
                                           timeout=600)
                        if r.returncode != 0:
                            raise RuntimeError(f"the driver failed (exit {r.returncode}): {r.stderr.strip()[-300:]}")
                    elif manifest.get("app"):
                        # A Mac app's window, recorded by shots-kit itself, in the VM when the
                        # project takes its pictures there (product-kit#65).
                        kit = pathlib.Path(__file__).resolve().parent.parent / "bin" / "shots-kit"
                        cmd = [str(kit), "video", spec["shot"], "--out", str(path.relative_to(site)),
                               "--seconds", str(spec.get("seconds", 8)), "--language", code or "en", "--repo", str(repo)]
                        if site != repo:
                            cmd += ["--site", str(site)]
                        r = subprocess.run(cmd, cwd=repo, capture_output=True, text=True, timeout=1800)
                        if r.returncode != 0:
                            raise RuntimeError(f"the recording failed: {(r.stdout + r.stderr).strip()[-400:]}")
                    else:
                        raise RuntimeError("a recorded video needs the manifest's `driver`, or its `app`")
                if not path.exists() or path.stat().st_size == 0:
                    raise RuntimeError(f"nothing was written at {out}")
                remade.append(out)
            except (RuntimeError, subprocess.TimeoutExpired, OSError) as e:
                failed.append(f"{out}: {e}")
        if not dry and newest and not any(f.startswith(file) for f in failed):
            asset["made"] = newest
            asset.pop("stale", None)
            changed = True
    if changed:
        manifest_file.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if remade:
        say(f"videos: made {len(remade)}: {', '.join(remade)}")
    elif not dry and not failed:
        say("videos: every scripted video is as new as the windows it shows")
    for f in failed:
        say(f"videos: not made: {f}")
    if by_hand:
        say("Made by hand, and older than a window they show; remade only when asked:")
        for b in by_hand:
            say(f"  {b}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
