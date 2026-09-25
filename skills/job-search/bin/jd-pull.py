#!/usr/bin/env python3
"""Pull plain-text JD from a posting URL; cheapest ladder first.

1. GET with browser UA. 2. og:description (Greenhouse embeds the full JD there).
3. Strip tags of the largest text block. Exit 3 = JS-only shell: escalate to
browser-use. Exit 0 prints text; exit 2 = fetch failure.
"""
import html, re, sys, urllib.request

UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/153.0 Safari/537.36"}
JS_SHELL = re.compile(r"enable JavaScript|requires JavaScript", re.I)

def fetch(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")

def og_description(src):
    m = re.search(r'<meta[^>]+property="og:description"[^>]+content="([^"]+)"', src, re.I)
    if not m:
        m = re.search(r'<meta[^>]+content="([^"]+)"[^>]+property="og:description"', src, re.I)
    return html.unescape(m.group(1)) if m else None

def strip_tags(src):
    s = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", src, flags=re.S | re.I)
    s = html.unescape(re.sub(r"<[^>]+>", " ", s))
    return re.sub(r"[ \t]+", " ", s)

def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr); sys.exit(2)
    try:
        src = fetch(sys.argv[1])
    except Exception as e:
        print(f"fetch failed: {e}", file=sys.stderr); sys.exit(2)
    jd = og_description(src)
    if jd and len(jd) > 200:
        print(jd); sys.exit(0)
    text = strip_tags(src)
    if JS_SHELL.search(text) or len(text) < 600:
        print("JS-only shell; escalate to browser-use", file=sys.stderr); sys.exit(3)
    print(text[:6000]); sys.exit(0)

if __name__ == "__main__":
    main()
