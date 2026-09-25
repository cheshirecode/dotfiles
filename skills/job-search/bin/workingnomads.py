#!/usr/bin/env python3
"""Working Nomads exposed-jobs API fetch + filter.

Usage: workingnomads.py [--country CC] [--fe-only] [--json]
API: https://www.workingnomads.com/api/exposed_jobs (public, no key).
Exit 0 rows / 1 none / 2 fail.
"""
import argparse, json, re, sys, urllib.request

FE = re.compile(r"front[- ]?end|full[- ]?stack|react|staff|principal|web engineer|software engineer", re.I)
CA = re.compile(r"canada|worldwide|anywhere|global|north america|americas", re.I)

def fetch():
    req = urllib.request.Request("https://www.workingnomads.com/api/exposed_jobs",
                                 headers={"User-Agent": "job-search/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

def select(jobs, country, fe_only):
    hits = []
    for j in jobs:
        title = (j.get("title") or "").strip()
        loc = (j.get("location") or "").strip()
        if fe_only and not FE.search(title):
            continue
        if country and not CA.search(loc + " worldwide anywhere"):
            continue
        hits.append({"title": title, "company": (j.get("company_name") or "").strip(),
                     "location": loc, "url": j.get("url", "")})
    return hits

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--country", default="")
    p.add_argument("--fe-only", action="store_true")
    p.add_argument("--json", action="store_true")
    a = p.parse_args()
    try:
        jobs = fetch()
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
