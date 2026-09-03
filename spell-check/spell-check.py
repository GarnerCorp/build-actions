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


def plan(artifact_dir):
    base, head = os.environ.get("BASE_SHA"), os.environ.get("HEAD_SHA")
    if not base or not head:
        sys.exit("This action reads the lines added by a pull request, "
                 "so it needs a `pull_request` event")
    try:
        added = added_lines(base, head)
    except subprocess.CalledProcessError as error:
        sys.exit(f"{error.stderr.strip()} -- check out with `fetch-depth: 0`")

    per_file = int(os.environ.get("MAX_ADDED_LINES") or 4000)
    left_out = [f"{path} ({len(lines)} "
                f"added {'line' if len(lines) == 1 else 'lines'})"
                for path, lines in added.items() if len(lines) > per_file]
    kept = {path: lines for path, lines in added.items() if len(lines) <= per_file}

    most = int(os.environ.get("MAX_MODEL_REQUESTS") or 10)
    parts = split(kept, 200000)
    if len(parts) > most:
        left_out.append(f"{len(parts) - most} requests over the limit of {most}")
        parts = parts[:most]

    prompt = Path(os.environ.get("PROMPT_FILE") or Path(__file__).parent / "prompt.md").read_text(encoding="utf-8").strip()
    for number, part in enumerate(parts, 1):
        Path(f"{artifact_dir}/part-{number}.txt").write_text(part, encoding="utf-8")
        Path(f"{artifact_dir}/request-{number}.txt").write_text(
            f"{prompt}\n\n<pull-request>\n{part}\n</pull-request>\n", encoding="utf-8")

    lines, files, requests = len(sent_lines(parts)), len(kept), len(parts)
    announce(f"reading {lines} added {'line' if lines == 1 else 'lines'} "
             f"from {files} {'file' if files == 1 else 'files'} "
             f"in {requests} {'request' if requests == 1 else 'requests'}")
    if left_out:
        announce(f"skipped: {', '.join(left_out)}")
    report("requests", len(parts))


def grounded(findings, sent):
    kept, seen = [], set()
    for finding in findings:
        if not isinstance(finding, dict):
            continue
        where = (finding.get("path"), finding.get("line"), finding.get("misspelling"))
        word, correction = where[2], finding.get("correction")
        if not word or not isinstance(word, str) or not isinstance(correction, str):
            continue
        text = sent.get(where[:2])
        if text is None or word not in text or word == correction or where in seen:
            continue
        seen.add(where)
        kept.append((*where, correction, text.replace(word, correction)))
    return kept


def review(artifact_dir):
    parts, findings = [], []
    for name in sorted(os.listdir(artifact_dir)):
        if name.startswith("part-"):
            parts.append(Path(f"{artifact_dir}/{name}").read_text(encoding="utf-8"))
        elif name.startswith("findings-"):
            try:
                findings += json.loads(Path(f"{artifact_dir}/{name}").read_text(encoding="utf-8"))["findings"]
            except (OSError, ValueError, KeyError, TypeError):
                announce(f"could not read {name}; its findings are not reported")
    kept = grounded(findings, sent_lines(parts))

    with open(os.environ["REVIEW"], "w", encoding="utf-8") as review_file:
        json.dump({"event": "COMMENT", "comments": [
            {"path": path, "line": number, "side": "RIGHT",
             "body": f"`{word}` \N{RIGHTWARDS ARROW} `{correction}`"
                     f"\n\n```suggestion\n{suggestion}\n```"}
            for path, number, word, correction, suggestion in kept]}, review_file)

    dropped = len(findings) - len(kept)
    announce(f"reported {len(kept)} "
             f"{'suggestion' if len(kept) == 1 else 'suggestions'}"
             + (f", dropped {dropped} unverifiable "
                f"{'finding' if dropped == 1 else 'findings'}" if dropped else ""))

    if kept and (summary := os.environ.get("GITHUB_STEP_SUMMARY")):
        with open(summary, "a", encoding="utf-8") as table:
            print("## Spelling\n\nFile|Misspelling|Correction\n-|-|-", file=table)
            repository = f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}"
            for path, number, word, correction, _ in kept:
                link = f"{repository}/blame/{os.environ['HEAD_SHA']}/{path}#L{number}"
                print(f"[{Path(path).name}:{number}]({link})|`{word}`|`{correction}`", file=table)
            print(file=table)
    report("count", len(kept))


if __name__ == "__main__":
    (plan if sys.argv[1] == "plan" else review)(os.environ["ARTIFACT_DIR"])
