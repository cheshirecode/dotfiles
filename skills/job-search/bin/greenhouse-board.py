#!/usr/bin/env python3
"""Fetch a public Greenhouse board and render engineering rows.

Usage: greenhouse-board.py <board-token> [--company NAME] [--country CC]
       [--remote-only] [--limit N] [--json]
Exit: 0 rows found; 1 no rows after filters; 2 fetch/parse failure.
"""
import argparse, json, sys, urllib.request

ENG = ("engineer", "developer", "software", "frontend", "front-end",
       "full stack", "full-stack", "web")

def fetch(board, job_id=None):
    path = f"jobs/{job_id}" if job_id else "jobs"
    url = f"https://boards-api.greenhouse.io/v1/boards/{board}/{path}"
    req = urllib.request.Request(url, headers={"User-Agent": "job-search/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        payload = json.load(r)
    return payload.get("jobs", []) if job_id is None else payload

def select(jobs, country, remote_only):
    hits = []
    for j in jobs:
        title = (j.get("title") or "").strip()
        loc = (j.get("location") or {}).get("name", "")
        tl, ll = title.lower(), loc.lower()
        if not any(k in tl for k in ENG):
            continue
        if remote_only and "remote" not in ll:
            continue
        if country and country.lower() not in ll:
            continue
        hits.append({"title": title, "location": loc,
                     "url": j.get("absolute_url", ""), "id": j.get("id")})
    return hits

def main():
    p = argparse.ArgumentParser()
    p.add_argument("board")
    p.add_argument("--company", default="")
    p.add_argument("--country", default="")
    p.add_argument("--remote-only", action="store_true")
    p.add_argument("--limit", type=int, default=20)
    p.add_argument("--json", action="store_true")
    p.add_argument("--jd", type=int, default=None, help="print full JD text for one job id")
    a = p.parse_args()
    try:
        if a.jd:
            import re, html as _html
            d = fetch(a.board, a.jd)
            txt = re.sub(r"<[^>]+>", "\n", _html.unescape(d.get("content", "")))
            print(d.get("title", ""), "\n" + d.get("location", {}).get("name", ""), "\n\n" +
                  re.sub(r"\n{2,}", "\n", txt).strip())
            sys.exit(0)
        jobs = fetch(a.board)
    except Exception as e:
        print(f"fetch failed: {e}", file=sys.stderr); sys.exit(2)
    hits = select(jobs, a.country, a.remote_only)[: a.limit]
    if a.json:
        print(json.dumps(hits, indent=1)); sys.exit(0 if hits else 1)
    for h in hits:
        print(f"- {h['title']} | {a.company or 'Greenhouse'} | {h['location']} | {h['url']}")
    sys.exit(0 if hits else 1)

if __name__ == "__main__":
    main()
