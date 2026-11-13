#!/usr/bin/env python3
"""A stand-in for `gh` that keeps a small GitHub in a JSON file, for docs-kit's plan tests.

DOCS_KIT_GH="python3 -I tests/fake-github.py <state.json>" makes docs-kit run this instead of
gh, with gh's arguments. It answers the plan's reads (a page of FAKE_PAGE open issues at a
time) and applies its writes (issues, sub-issues, milestones, labels, the board's fields,
items, values and views), logging each call to <state.json>.log. Beside the state file:
`flaky` (a count of calls that fail first) and `signed-out` (gh isn't signed in)."""

import json
import os
import pathlib
import re
import sys

state_path = pathlib.Path(sys.argv[1])
args = sys.argv[2:]
here = state_path.parent
log = state_path.with_suffix(".log")


def note(text: str) -> None:
    with log.open("a") as f:
        f.write(text + "\n")


if (here / "signed-out").exists():
    sys.exit("To get started with GitHub CLI, please run:  gh auth login\n"
             "Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.")
flaky = here / "flaky"
writing = any(a.startswith("query=mutation") for a in args) or "-X" in args
if flaky.exists() and int(flaky.read_text() or 0) > 0 and (writing or not os.environ.get("FAKE_FLAKY_WRITES")):
    # FAKE_FLAKY_WRITES: only writes fail, as when a write's connection never opens.
    flaky.write_text(str(int(flaky.read_text()) - 1))
    sys.exit(os.environ.get("FAKE_FLAKY_SAID", "connection reset by peer"))

S = json.loads(state_path.read_text())
B = S["board"]


def save() -> None:
    state_path.write_text(json.dumps(S, indent=1))


def new_id(prefix: str) -> str:
    S["next"] += 1
    return f"{prefix}{S['next']}"


def issue(number) -> dict:
    return S["issues"][str(number)]


def by_id(node_id: str) -> dict:
    return next(i for i in S["issues"].values() if i["id"] == node_id)


def field(name_or_id: str) -> dict | None:
    return next((f for f in B["fields"] if name_or_id in (f["name"], f["id"])), None)


# --- reading gh's arguments

def options(argv):
    fields, method, path, stdin = {}, "GET", None, None
    k = 0
    while k < len(argv):
        a = argv[k]
        if a in ("-f", "-F"):
            key, _, value = argv[k + 1].partition("=")
            fields[key] = value
            k += 2
        elif a == "-X":
            method = argv[k + 1]
            k += 2
        elif a == "-H":
            k += 2
        elif a == "--input":
            stdin = sys.stdin.read()
            k += 2
        else:
            if a not in ("api", "graphql"):
                path = a
            k += 1
    return fields, method, path, stdin


# --- a small GraphQL literal parser, for mutations

def parse_value(text: str, at: int):
    while text[at] in " \n\t,":
        at += 1
    c = text[at]
    if c == '"':
        value, end = json.JSONDecoder().raw_decode(text, at)
        return value, end
    if c == "{":
        obj, at = {}, at + 1
        while True:
            while text[at] in " \n\t,":
                at += 1
            if text[at] == "}":
                return obj, at + 1
            m = re.compile(r"(\w+)\s*:").match(text, at)
            value, at = parse_value(text, m.end())
            obj[m.group(1)] = value
    if c == "[":
        items, at = [], at + 1
        while True:
            while text[at] in " \n\t,":
                at += 1
            if text[at] == "]":
                return items, at + 1
            value, at = parse_value(text, at)
            items.append(value)
    m = re.compile(r"-?\d+(\.\d+)?|\w+").match(text, at)
    word = m.group(0)
    if re.fullmatch(r"-?\d+(\.\d+)?", word):
        return float(word), m.end()
    return {"true": True, "false": False, "null": None}.get(word, word), m.end()


def mutations(text: str):
    at = text.index("{") + 1
    while True:
        m = re.compile(r"\s*(?:(\w+)\s*:\s*)?(\w+)\(input:\s*").match(text, at)
        if not m:
            return
        value, at = parse_value(text, m.end())
        at = text.index(")", at) + 1
        depth, at = 0, text.index("{", at)
        while True:
            depth += {"{": 1, "}": -1}.get(text[at], 0)
            at += 1
            if depth == 0:
                break
        yield (m.group(1) or m.group(2)), m.group(2), value


# --- answers

def value_of(item: dict | None, name: str):
    if not item or item["values"].get(name) is None:
        return None
    v, f = item["values"][name], field(name)
    if not f:
        return None
    return {"SINGLE_SELECT": {"name": v}, "NUMBER": {"number": v}, "DATE": {"date": v}}.get(f["dataType"], {"text": v})


def issue_node(i: dict, query: str) -> dict:
    item = B["items"].get(str(i["number"]))
    project_item = None
    if item:
        project_item = {"id": item["id"], "project": {"number": B["number"], "owner": {"login": B["owner"]}}}
        for alias, name in re.findall(r"(v_\w+): fieldValueByName\(name: (\"(?:[^\"\\]|\\.)*\")\)", query):
            project_item[alias] = value_of(item, json.loads(name))
    parent = S["issues"].get(str(i["parent"])) if i.get("parent") else None
    return {"id": i["id"], "number": i["number"], "title": i["title"], "state": i["state"], "body": i.get("body", ""),
            "isPinned": i.get("pinned", False),
            "milestone": next(({"number": m["number"], "title": m["title"]} for m in S["milestones"]
                               if m["title"] == i.get("milestone")), None),
            "parent": {"number": parent["number"], "state": parent["state"]} if parent else None,
            "labels": {"nodes": [{"name": n} for n in i.get("labels", [])]},
            "projectItems": {"nodes": [project_item] if project_item else []}}


def read(query: str, fields: dict) -> dict:
    if "structure: issues" in query:
        note("read the plan" + (f" after={fields['after']}" if fields.get("after") else ""))
        size = int(os.environ.get("FAKE_PAGE", "100"))
        start = int(fields.get("after") or 0)
        open_ = [i for i in sorted(S["issues"].values(), key=lambda i: i["number"]) if i["state"] == "OPEN"]
        page = open_[start:start + size]
        wanted = set(json.loads(re.search(r"labels: (\[[^\]]*\])", query).group(1)))
        board = None
        if B.get("owner", "").lower() == fields.get("board", "").lower() and int(fields.get("number", 0)) == B["number"]:
            board = {"id": B["id"], "title": B["title"],
                     "fields": {"nodes": [{k: v for k, v in f.items()} for f in B["fields"]]},
                     "views": {"nodes": B["views"]}}
        return {"repository": {
            "id": S["repo_id"],
            "milestones": {"nodes": S["milestones"]},
            "labels": {"nodes": S["labels"]},
            "issues": {"pageInfo": {"hasNextPage": start + size < len(open_), "endCursor": str(start + size)},
                       "nodes": [issue_node(i, query) for i in page]},
            "structure": {"nodes": [issue_node(i, query) for i in sorted(S["issues"].values(), key=lambda i: i["number"])
                                    if set(i.get("labels", [])) & wanted]}},
            "repositoryOwner": {"__typename": B.get("type", "User"), "projectV2": board}}
    if "items(first: 100" in query:
        note("read the board's items")
        nodes = []
        for number, item in B["items"].items():
            i = S["issues"].get(number)
            nodes.append({"id": item["id"], "content": {"number": int(number), "state": i["state"] if i else "CLOSED",
                                                         "repository": {"nameWithOwner": S["repo"]}},
                          "v_status": value_of(item, "Status")})
        return {"node": {"items": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": nodes}}}
    if query.startswith("query { nodes(ids:"):
        ids = re.findall(r'"(I\d+)"', query)
        note("read issues by id")
        return {"nodes": [issue_node(by_id(x), query) for x in ids]}
    found = re.findall(r"(i(\d+)): issue\(number: (\d+)\)", query)
    if found:
        note("read issues " + " ".join(n for _, n, _ in found))
        return {"repository": {alias: issue_node(S["issues"][n], query) if n in S["issues"] else None
                               for alias, n, _ in found}}
    raise SystemExit(f"fake-github: a query it doesn't know: {query[:200]}")


def mutate(query: str) -> dict:
    out = {}
    for alias, name, v in mutations(query):
        note(f"{name}")
        if name == "createIssue":
            S["next"] += 1
            number = max([int(n) for n in S["issues"]] + [0]) + 1
            labels = [l["name"] for l in S["labels"] if l["id"] in v.get("labelIds", [])]
            milestone = next((m["title"] for m in S["milestones"] if m["id"] == v.get("milestoneId")), None)
            node = {"id": f"I{number}", "number": number, "title": v["title"], "state": "OPEN", "body": v.get("body", ""),
                    "labels": labels, "milestone": milestone, "parent": None}
            S["issues"][str(number)] = node
            if os.environ.get("FAKE_AUTOADD"):
                # The board's auto-add workflow: new issues land on it by themselves.
                B["items"][str(number)] = {"id": new_id("PVTI_"), "values": {"Status": "Todo"}}
            out[alias] = {"issue": {"id": node["id"], "number": number}}
        elif name == "addSubIssue":
            child = by_id(v["subIssueId"])
            if child.get("parent") and not v.get("replaceParent"):
                return {"errors": [{"message": "Issue may not contain duplicate sub-issues"}]}
            child["parent"] = by_id(v["issueId"])["number"]
            out[alias] = {"clientMutationId": None}
        elif name == "updateIssue":
            i = by_id(v["id"])
            if "milestoneId" in v:
                i["milestone"] = next(m["title"] for m in S["milestones"] if m["id"] == v["milestoneId"])
            if "body" in v:
                i["body"] = v["body"]
            out[alias] = {"clientMutationId": None}
        elif name in ("closeIssue", "reopenIssue"):
            by_id(v["issueId"])["state"] = "CLOSED" if name == "closeIssue" else "OPEN"
            out[alias] = {"clientMutationId": None}
        elif name == "pinIssue":
            by_id(v["issueId"])["pinned"] = True
            out[alias] = {"clientMutationId": None}
        elif name == "addProjectV2ItemById":
            i = by_id(v["contentId"])
            if str(i["number"]) in B["items"]:
                return {"errors": [{"message": "Content already exists in this project"}]}
            B["items"].setdefault(str(i["number"]), {"id": new_id("PVTI_"), "values": {}})
            out[alias] = {"item": {"id": B["items"][str(i["number"])]["id"]}}
        elif name in ("updateProjectV2ItemFieldValue", "clearProjectV2ItemFieldValue"):
            f = field(v["fieldId"])
            item = next(it for it in B["items"].values() if it["id"] == v["itemId"])
            value = v.get("value") or {}
            if "singleSelectOptionId" in value:
                value = next(o["name"] for o in f["options"] if o["id"] == value["singleSelectOptionId"])
            else:
                value = next(iter(value.values()), None)
            item["values"][f["name"]] = value
            out[alias] = {"clientMutationId": None}
        elif name == "createProjectV2Field":
            f = {"id": new_id("PVTF_"), "databaseId": S["next"], "name": v["name"], "dataType": v["dataType"]}
            if v.get("singleSelectOptions"):
                f["options"] = [{"id": new_id("o"), "name": o["name"]} for o in v["singleSelectOptions"]]
            B["fields"].append(f)
            out[alias] = {"projectV2Field": f}
        elif name == "updateProjectV2View":
            view = next(x for x in B["views"] if x["id"] == v["viewId"])
            view["filter"] = v["filter"]
            out[alias] = {"clientMutationId": None}
        else:
            raise SystemExit(f"fake-github: a mutation it doesn't know: {name}")
    save()
    return out


def rest(method: str, path: str, body: dict) -> dict:
    note(f"{method} {path}")
    if path.endswith("/labels"):
        label = {"id": new_id("L"), "name": body["name"]}
        S["labels"].append(label)
        save()
        return {"node_id": label["id"], "name": body["name"]}
    if path.endswith("/milestones"):
        number = max([m["number"] for m in S["milestones"]] + [0]) + 1
        m = {"id": new_id("M"), "number": number, "title": body["title"], "state": "OPEN", "dueOn": None}
        S["milestones"].append(m)
        save()
        return {"node_id": m["id"], "number": number}
    if path.endswith("/views"):
        view = {"id": new_id("PVTV_"), "number": len(B["views"]) + 1, "name": body["name"],
                "filter": body.get("filter"), "layout": body["layout"], "sort_by": body.get("sort_by"),
                "group_by": body.get("group_by"), "vertical_group_by": body.get("vertical_group_by")}
        B["views"].append(view)
        save()
        return view
    raise SystemExit(f"fake-github: a REST call it doesn't know: {method} {path}")


fields, method, path, stdin = options(args)
if path is None or "graphql" in args:
    query = fields["query"]
    answer = {"data": mutate(query) if query.lstrip().startswith("mutation") else read(query, fields)}
    if "errors" in answer["data"]:
        answer = {"data": None, "errors": answer["data"]["errors"]}
        print(json.dumps(answer))
        sys.exit(1)
else:
    answer = rest(method, path, json.loads(stdin) if stdin else {})
print(json.dumps(answer))
