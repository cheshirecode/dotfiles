#!/usr/bin/env python3
"""RemoteOK public API fetch + filter.

Usage: remoteok.py [--country CC] [--fe-only] [--limit N] [--json]
The first payload element is a legal notice, not a job. Exit 0 rows / 1 none / 2 fail.
"""
import argparse, json, sys, urllib.request

FE = ("frontend", "front-end", "react", "full-stack", "fullstack", "web")

def fetch():
    req = urllib.request.Request("https://remoteok.com/api",
                                 headers={"User-Agent": "job-search/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

def select(jobs, country, fe_only):
    hits = []
    for j in jobs:
        if not isinstance(j, dict) or "position" not in j:
            continue
        pos = (j.get("position") or "").strip()
        loc = (j.get("location") or "").strip()
        pl = pos.lower()
        if fe_only and not any(k in pl for k in FE):
            continue
        if country and country.lower() not in loc.lower():
            continue
        hits.append({"title": pos, "company": (j.get("company") or "").strip(),
                     "location": loc, "url": j.get("url", "")})
    return hits

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--country", default="")
    p.add_argument("--fe-only", action="store_true")
    p.add_argument("--limit", type=int, default=15)
    p.add_argument("--json", action="store_true")
    a = p.parse_args()
    try:
        jobs = fetch()
    except Exception as e:
        print(f"fetch failed: {e}", file=sys.stderr); sys.exit(2)
    hits = select(jobs, a.country, a.fe_only)[: a.limit]
    if a.json:
        print(json.dumps(hits, indent=1)); sys.exit(0 if hits else 1)
    for h in hits:
        print(f"- {h['title']} | {h['company']} | {h['location']} | {h['url']}")
    sys.exit(0 if hits else 1)

if __name__ == "__main__":
    main()
