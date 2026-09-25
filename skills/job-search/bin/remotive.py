#!/usr/bin/env python3
"""Remotive public remote-jobs API fetch + filter.

Usage: remotive.py [--country CC] [--fe-only] [--limit N] [--json]
API: https://remotive.com/api/remote-jobs (documented, no key).
Exit 0 rows / 1 none / 2 fail.
"""
import argparse, json, re, sys, urllib.request

FE = re.compile(r"front[- ]?end|full[- ]?stack|react|web engineer|software engineer|staff|principal|lead", re.I)

def fetch(limit):
    url = f"https://remotive.com/api/remote-jobs?limit={limit}"
    req = urllib.request.Request(url, headers={"User-Agent": "job-search/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r).get("jobs", [])

def select(jobs, country, fe_only):
    hits = []
    for j in jobs:
        title = (j.get("title") or "").strip()
        loc = (j.get("candidate_required_location") or "").strip()
        if fe_only and not FE.search(title):
            continue
        if country and country.lower() not in (loc.lower() + " worldwide anywhere global"):
            continue
        hits.append({"title": title, "company": (j.get("company_name") or "").strip(),
                     "location": loc, "url": j.get("url", "")})
    return hits

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--country", default="")
    p.add_argument("--fe-only", action="store_true")
    p.add_argument("--limit", type=int, default=100)
    p.add_argument("--json", action="store_true")
    a = p.parse_args()
    try:
        jobs = fetch(a.limit)
    except Exception as e:
        print(f"fetch failed: {e}", file=sys.stderr); sys.exit(2)
    hits = select(jobs, a.country, a.fe_only)
    if a.json:
        print(json.dumps(hits, indent=1)); sys.exit(0 if hits else 1)
    for h in hits:
        print(f"- {h['title']} | {h['company']} | {h['location']} | {h['url']}")
    sys.exit(0 if hits else 1)

if __name__ == "__main__":
    main()
