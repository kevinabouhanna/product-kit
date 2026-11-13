"""shots-kit migrate (product-kit#36): one list of every picture, GIF and video, where it can be one.

Folds the README's and the docs' list (`shots.repo_assets`) into the manifest (`shots/shots.json`)
when both are on the same branch: no site (the manifest is in the project's checkout), or a site
in a folder of it (`shots.site: "site"`). Then removes the README's list and its key from the
config. A site on another branch or in another repository keeps its own list, so that each
branch's pull requests pass the asset check on their own; it says so and changes nothing.

Usage: python3 -I migrate.py <project checkout>
"""

import json
import os
import pathlib
import subprocess
import sys


def say(text: str) -> None:
    print(f"migrate: {text}")


def main_checkout(repo: pathlib.Path) -> pathlib.Path:
    """The project's main checkout, which a site's path is relative to (as shots-kit reads it)."""
    r = subprocess.run(["git", "-C", str(repo), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                       capture_output=True, text=True)
    return pathlib.Path(r.stdout.strip()).parent if r.returncode == 0 else repo


def main(argv: list[str]) -> int:
    repo = pathlib.Path(argv[0] if argv else ".").resolve()
    config_file = repo / ".product-kit.json"
    if not config_file.exists():
        say(f"no .product-kit.json in {repo}")
        return 2
    config = json.loads(config_file.read_text(encoding="utf-8"))
    shots = config.get("shots", {})
    list_path = shots.get("repo_assets", "assets.json")
    readme_list = repo / list_path
    if not readme_list.exists():
        say(f"nothing to fold in: there's no {list_path}, so the manifest is the one list already")
        return 0

    site = shots.get("site")
    if site:
        site_dir = (main_checkout(repo) / site).resolve()
        main = main_checkout(repo).resolve()
        if main != site_dir and main not in site_dir.parents:
            say(f"the site ({site}) is on another branch or in another repository, so it keeps its own list: "
                f"each branch's pull requests pass the asset check on their own, and `coverage` reads both "
                f"lists as one (product-kit#36). Nothing changed.")
            return 1
        # The same branch: the site's folder in this checkout.
        site_dir = (repo / os.path.relpath(site_dir, main)).resolve()
    else:
        site_dir = repo
    manifest_file = site_dir / "shots/shots.json"
    if not manifest_file.exists():
        say(f"no manifest at {manifest_file.relative_to(repo)}")
        return 2

    manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    listed = json.loads(readme_list.read_text(encoding="utf-8")).get("assets", [])
    assets = manifest.setdefault("assets", [])
    have = {(a.get("file"), a.get("in")) for a in assets}
    where = "repo" if site_dir != repo else None
    added = 0
    for entry in listed:
        entry = dict(entry)
        if where:
            entry["in"] = where
        if (entry.get("file"), entry.get("in")) in have:
            continue
        assets.append(entry)
        added += 1
    manifest_file.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    readme_list.unlink()
    shots.pop("repo_assets", None)
    config_file.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    say(f"folded {added} of {list_path}'s {len(listed)} entries into {manifest_file.relative_to(repo)}"
        + (' (each `"in": "repo"`)' if where else "")
        + f", removed {list_path} and `shots.repo_assets`. Run `shots-kit coverage`, then commit them together.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
