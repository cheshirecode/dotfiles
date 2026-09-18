#!/usr/bin/env python3
"""Refuse to publish when a code link does not resolve at the ref it names.

check_html.py reads the document. This reads the repositories the document
points at, which is where the interesting failures live: the target resolves
and the claim about it is wrong.

    verify_links.py page.html --repo NAME=/path/to/clone \
        --forge-host git.example.com --forge-namespace example-org [--branch main]

Exit 0 clean, 1 findings, 2 usage. See ../references/gates.md.
"""
import argparse
import collections
import pathlib
import re
import subprocess
import sys

SHA = re.compile(r"^[0-9a-f]{7,40}$")


def git(repo, *args):
    p = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def build_patterns(host, namespace):
    base = r"^https://%s/%s/([A-Za-z0-9._-]+)/-?/?" % (re.escape(host), re.escape(namespace))
    return (
        re.compile(base + r"blob/([^/]+)/([^\"#]+?)(?:#L(\d+)(?:-L?(\d+))?)?$"),
        re.compile(base + r"tree/([^/]+)/([^\"#]+?)$"),
    )


def verify(html, repos, host, namespace, branch):
    problems, notes = [], []

    # Fail closed: a missing clone means the links were NOT verified. That is a
    # finding, not a reason to print OK.
    for name, path in sorted(repos.items()):
        if git(path, "rev-parse", "--git-dir")[0] != 0:
            problems.append(f"no {name} clone at {path} - links CANNOT be verified")
    if problems:
        return problems, notes

    for name, path in sorted(repos.items()):
        rc, head, _ = git(path, "rev-parse", f"origin/{branch}")
        notes.append(f"{name}: ancestry measured against origin/{branch} "
                     f"{head[:8] if rc == 0 else '(absent)'}")
        if rc != 0:
            problems.append(f"{name}: no origin/{branch} to measure reachability against")
    if problems:
        return problems, notes

    blob_re, tree_re = build_patterns(host, namespace)
    expect = {m.group(1): m.group(2) for m in re.finditer(
        r'<a\b[^>]*href="([^"]+)"[^>]*data-expect="([^"]+)"', html)}

    hrefs = re.findall(r'href="([^"]+)"', html)
    hosts = collections.Counter(
        re.match(r"https://([^/]+)", u).group(1) if u.startswith("https://") else "#fragment"
        for u in hrefs)
    verified = unrecognised = 0

    for url in sorted(set(hrefs)):
        if host not in url:
            continue
        blob, tree = blob_re.match(url), tree_re.match(url)
        if not (blob or tree):
            # Silence is the dangerous shape: an unrecognised form is NOT
            # verified, so it is reported rather than passed over.
            unrecognised += 1
            problems.append(f"unrecognised link form, so NOT checked: {url}")
            continue
        m = blob or tree
        repo, ref, filepath = m.group(1), m.group(2), m.group(3)
        first, last = (m.group(4), m.group(5)) if blob else (None, None)

        if repo not in repos:
            problems.append(f"unknown repo in link: {repo} ({url})")
            continue
        path = repos[repo]

        if first and not SHA.match(ref):
            problems.append(
                f"line anchor on a moving ref {ref!r}: {url} - a line anchor "
                "asserts 'line N says X', true at exactly one commit; pin it to a sha")
            continue

        if git(path, "cat-file", "-e", f"{ref}^{{commit}}")[0] != 0:
            problems.append(f"ref {ref} does not exist in {repo}: {url}")
            continue

        # Existing is not reachable: cat-file answers for an object no branch
        # contains, so a pin to a rebased-away commit passes existence and is
        # still dead. Ancestry is the check that measures the claim.
        if SHA.match(ref) and git(path, "merge-base", "--is-ancestor",
                                  ref, f"origin/{branch}")[0] != 0:
            problems.append(
                f"{ref[:8]} is not an ancestor of origin/{branch} in {repo} - "
                f"dead citation: {url}")
            continue

        if git(path, "cat-file", "-e", f"{ref}:{filepath}")[0] != 0:
            problems.append(f"{filepath} absent at {ref[:8]} in {repo}: {url}")
            continue

        if first:
            rc, blobtext, _ = git(path, "show", f"{ref}:{filepath}")
            lines = blobtext.splitlines()
            lo, hi = int(first), int(last or first)
            if hi > len(lines):
                problems.append(
                    f"{filepath}@{ref[:8]} has {len(lines)} lines, link cites L{hi}: {url}")
                continue
            # Line-exists is not line-says. data-expect declares what the cited
            # range must contain, so "name the symbol" becomes a gate.
            want = expect.get(url)
            if want and want not in "\n".join(lines[lo - 1:hi]):
                problems.append(
                    f"L{lo}-{hi} of {filepath}@{ref[:8]} no longer contains "
                    f"{want!r}: {url}")
                continue
        verified += 1

    notes.append(f"verified {verified} link(s); {unrecognised} unrecognised")
    notes.append("host coverage (only the forge host is checkable here): " +
                 ", ".join(f"{h}={n}" for h, n in hosts.most_common()))
    return problems, notes


def _repo(value):
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected NAME=/path/to/clone")
    name, path = value.split("=", 1)
    if not name.strip() or not path.strip():
        raise argparse.ArgumentTypeError("expected NAME=/path/to/clone")
    return name.strip(), path.strip()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("path", type=pathlib.Path)
    ap.add_argument("--repo", type=_repo, action="append", default=[], required=True,
                    metavar="NAME=/path", help="repeatable; a clone to resolve links against")
    ap.add_argument("--forge-host", required=True, metavar="HOST")
    ap.add_argument("--forge-namespace", required=True, metavar="NS")
    ap.add_argument("--branch", default="main", help="branch reachability is measured against")
    args = ap.parse_args(argv)

    try:
        html = args.path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"verify_links: cannot read {args.path}: {exc}", file=sys.stderr)
        return 2

    problems, notes = verify(html, dict(args.repo), args.forge_host,
                             args.forge_namespace, args.branch)
    for n in notes:
        print(f"  {n}")
    if problems:
        print(f"verify_links: {args.path} must not be published:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    print(f"verify_links: OK ({args.path})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
