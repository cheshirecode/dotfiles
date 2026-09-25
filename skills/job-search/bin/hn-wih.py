#!/usr/bin/env python3
"""HN 'Who is hiring' job-post extraction via the public Algolia API.

Usage: hn-wih.py [--month YYYY-MM] [--country] [--remote-only]
       [--fe-only] [--limit N] [--json]
A job post is a comment whose first line matches COMPANY | ROLE | ...
Exit: 0 rows; 1 no rows; 2 fetch failure.
"""
import argparse, datetime, html, json, re, sys, urllib.parse, urllib.request

API = "https://hn.algolia.com/api/v1"
POST_SHAPE = re.compile(r"^[A-Za-z0-9][^|]{1,40}\s*\|\s*[^|]{2,80}\s*\|")
FE = re.compile(r"front[- ]?end|full[- ]?stack|react|web engineer|software engineer", re.I)
CA = re.compile(r"canada|canadian|toronto|vancouver|montreal|ottawa|\bon\b.*canada", re.I)
REM = re.compile(r"\bremote\b", re.I)

def get(path, **params):
    url = API + path + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "job-search/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

def latest_thread(month=None):
    hits = get("/search_by_date", query='"who is hiring"', tags="ask_hn",
               hitsPerPage=5)["hits"]
    if month:
        name = f"Who is hiring? ({month.split('-')[0]}/{month.split('-')[1].lstrip('0')} 20{month[2:4]})"
        for h in hits:
            if month[4:6].lstrip("0") in h["title"] and h["title"].startswith("Ask HN: Who is hiring?"):
                return h
    return hits[0]

def clean(t):
    t = html.unescape(t or "")
    t = re.sub(r"<[^>]+>", " ", t)
    return re.sub(r"\s+", " ", t).strip()

def parse_posts(comments):
    posts = []
    for c in comments:
        t = clean(c.get("comment_text"))
        if not t or not POST_SHAPE.match(t):
            continue
        posts.append({"text": t, "hn_url": f"https://news.ycombinator.com/item?id={c['objectID']}",
                      "created_at": c.get("created_at", "")})
    return posts

def select(posts, country, remote_only, fe_only, max_age_days=21):
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=max_age_days)
    hits = []
    for p in posts:
        t = p["text"]
        if p.get("created_at"):
            try:
                posted = datetime.datetime.fromisoformat(p["created_at"].replace("Z", "+00:00"))
                if posted < cutoff:
                    continue
            except ValueError:
                pass
        if remote_only and not REM.search(t):
            continue
        if fe_only and not FE.search(t.split("|")[1] if "|" in t else t):
            continue
        if country and not CA.search(t):
            continue
        hits.append({"head": t[:220], "url": p["hn_url"]})
    return hits

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--month", default=None, help="YYYY-MM; default latest")
    p.add_argument("--country", action="store_true", help="keep Canada mentions")
    p.add_argument("--remote-only", action="store_true")
    p.add_argument("--fe-only", action="store_true")
    p.add_argument("--max-age-days", type=int, default=21, help="drop posts older than this")
    p.add_argument("--limit", type=int, default=15)
    p.add_argument("--json", action="store_true")
    a = p.parse_args()
    try:
        thread = latest_thread(a.month)
        comments = get("/search_by_date", tags=f"comment,story_{thread['objectID']}",
                       hitsPerPage=1000)["hits"]
    except Exception as e:
        print(f"fetch failed: {e}", file=sys.stderr); sys.exit(2)
    hits = select(parse_posts(comments), a.country, a.remote_only, a.fe_only,
                  a.max_age_days)[: a.limit]
    if a.json:
        print(json.dumps(hits, indent=1)); sys.exit(0 if hits else 1)
    for h in hits:
        print(f"- {h['head']} | {h['url']}")
    sys.exit(0 if hits else 1)

if __name__ == "__main__":
    main()
