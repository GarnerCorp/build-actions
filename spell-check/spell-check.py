#!/usr/bin/env python3

import json
import os
import re
import subprocess
import sys
from pathlib import Path

HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)")


def added_lines(base, head):
    diff = subprocess.run(["git", "diff", "--unified=0", f"{base}...{head}"],
                          capture_output=True, text=True, check=True).stdout
    added, path, line = {}, None, 0
    for row in diff.split("\n"):
        hunk = HUNK.match(row)
        if row.startswith("diff --git "):
            path, line = None, 0
        elif hunk:
            line = int(hunk.group(1))
        elif path is None and row.startswith("+++ b/"):
            path = row[6:]
        elif line and row.startswith("+"):
            added.setdefault(path, []).append((line, row[1:]))
            line += 1
    return added


def split(added, limit):
    parts, rows, size, current = [], [], 0, None
    for path, lines in added.items():
        for number, text in lines:
            row = f"{number}\t{text}"
            if size + len(row) > limit and rows:
                parts.append("\n".join(rows))
                rows, size, current = [], 0, None
            if current != path:
                current = path
                rows.append(f"--- {path}")
                size += len(rows[-1]) + 1
            rows.append(row)
            size += len(row) + 1
    if rows:
        parts.append("\n".join(rows))
    return parts


def sent_lines(parts):
    sent, path = {}, None
    for part in parts:
        for row in part.split("\n"):
            if row.startswith("--- "):
                path = row[4:]
            else:
                number, _, text = row.partition("\t")
                sent[(path, int(number))] = text
    return sent


def announce(message):
    print(f"::notice ::Spell check {message}", file=sys.stderr)


def report(name, value):
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a", encoding="utf-8") as record:
            print(f"{name}={value}", file=record)


def plan(work_dir):
    base, head = os.environ.get("BASE_SHA"), os.environ.get("HEAD_SHA")
    if not base or not head:
        sys.exit("This action reads the lines added by a pull request, "
                 "so it needs a `pull_request` event")
    try:
        added = added_lines(base, head)
    except subprocess.CalledProcessError as error:
        sys.exit(f"{error.stderr.strip()} -- check out with `fetch-depth: 0`")

    per_file = int(os.environ.get("MAX_ADDED_LINES") or 4000)
    left_out = [f"{path} ({len(lines)} added lines)"
                for path, lines in added.items() if len(lines) > per_file]
    kept = {path: lines for path, lines in added.items() if len(lines) <= per_file}

    most = int(os.environ.get("MAX_REQUESTS") or 10)
    parts = split(kept, 200000)
    if len(parts) > most:
        left_out.append(f"{len(parts) - most} request(s) over the limit of {most}")
        parts = parts[:most]

    prompt = Path(os.environ.get("PROMPT_FILE") or Path(__file__).parent / "prompt.md").read_text(encoding="utf-8").strip()
    for number, part in enumerate(parts, 1):
        Path(f"{work_dir}/part-{number}.txt").write_text(part, encoding="utf-8")
        Path(f"{work_dir}/request-{number}.txt").write_text(
            f"{prompt}\n\n<pull-request>\n{part}\n</pull-request>\n", encoding="utf-8")

    announce(f"reading {len(sent_lines(parts))} added line(s) from {len(kept)} file(s) "
             f"in {len(parts)} request(s)")
    if left_out:
        announce(f"skipped: {', '.join(left_out)}")
    report("requests", len(parts))


def grounded(found, sent):
    kept, seen = [], set()
    for finding in found:
        if not isinstance(finding, dict):
            continue
        where = (finding.get("path"), finding.get("line"), finding.get("found"))
        word, expected = where[2], finding.get("expected")
        if not word or not isinstance(word, str) or not isinstance(expected, str):
            continue
        text = sent.get(where[:2])
        if text is None or word not in text or word == expected or where in seen:
            continue
        seen.add(where)
        kept.append((*where, expected, text.replace(word, expected)))
    return kept


def review(work_dir):
    parts, found = [], []
    for name in sorted(os.listdir(work_dir)):
        if name.startswith("part-"):
            parts.append(Path(f"{work_dir}/{name}").read_text(encoding="utf-8"))
        elif name.startswith("findings-"):
            try:
                found += json.loads(Path(f"{work_dir}/{name}").read_text(encoding="utf-8"))["findings"]
            except (OSError, ValueError, KeyError, TypeError):
                announce(f"could not read {name}; its findings are not reported")
    kept = grounded(found, sent_lines(parts))

    with open(os.environ["REVIEW"], "w", encoding="utf-8") as review_file:
        json.dump({"event": "COMMENT", "comments": [
            {"path": path, "line": number, "side": "RIGHT",
             "body": f"`{word}` \N{RIGHTWARDS ARROW} `{expected}`"
                     f"\n\n```suggestion\n{suggestion}\n```"}
            for path, number, word, expected, suggestion in kept]}, review_file)

    dropped = len(found) - len(kept)
    announce(f"found {len(kept)} suggestion(s)"
             + (f", dropped {dropped} unverifiable finding(s)" if dropped else ""))

    if kept and (summary := os.environ.get("GITHUB_STEP_SUMMARY")):
        with open(summary, "a", encoding="utf-8") as table:
            print("## Spelling\n\nFile|Line|Found|Expected\n-|-|-|-", file=table)
            for path, number, word, expected, _ in kept:
                print(f"{path}|{number}|`{word}`|`{expected}`", file=table)
            print(file=table)
    report("count", len(kept))


if __name__ == "__main__":
    (plan if sys.argv[1] == "plan" else review)(os.environ["WORK_DIR"])
