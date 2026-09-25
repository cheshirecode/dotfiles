# Runs INSIDE browser-use (helpers pre-imported). Configure via env:
#   LJ_MODE=keyword|company  LJ_QUERY="Staff Frontend Engineer"
#   LJ_LOCATION=Canada       LJ_COMPANY=<slug>  LJ_LIMIT=8  LJ_FORMAT=markdown|json
# Read-only: navigates in the working tab, never types or clicks into forms.
import json, os, time

def card_js():
    return """
    const all = Array.from(document.querySelectorAll('div')).filter(d => {
      const t=(d.innerText||''); return t.includes('Posted') && t.length > 70 && t.length < 400; });
    const seen = new Set(), out = [];
    for (const d of all) {
      const t = (d.innerText||'').replace(/\\n+/g,' | ').trim();
      if (seen.has(t)) continue;
      seen.add(t); out.push(t.slice(0,190));
    }
    return out;
    """

def clean_row(c):
    parts = [p.strip() for p in c.split(" | ")]
    if "(Verified job)" in c and len(parts) > 6:
        c = " | ".join(parts[5:])
    elif len(parts) > 5:
        c = " | ".join(parts[3:])
    if "Posted" not in c:  # over-sliced footer fragment: keep the full block
        c = " | ".join(parts)[:190]
    return c[:190]

def grab():
    cards = js(card_js())
    seen, rows = set(), []
    for c in cards:
        r = clean_row(c)
        if r and r[:60] not in seen:
            seen.add(r[:60]); rows.append(r)
    return rows[: int(os.environ.get("LJ_LIMIT", "8"))]

mode = os.environ.get("LJ_MODE", "keyword")
if mode == "company":
    slug = os.environ.get("LJ_COMPANY", "")
    goto_url(f"https://www.linkedin.com/company/{slug}/jobs/")
else:
    from urllib.parse import quote
    q = quote(os.environ.get("LJ_QUERY", "Software Engineer"))
    loc = quote(os.environ.get("LJ_LOCATION", "Canada"))
    goto_url(f"https://www.linkedin.com/jobs/search/?keywords={q}&f_WT=2&location={loc}")
wait_for_load(); time.sleep(4)
activate_tab(current_tab()); time.sleep(1)
rows = grab()
if not rows:  # virtualized list may need one nudge; retry once
    scroll(0, 300); time.sleep(2); rows = grab()
fmt = os.environ.get("LJ_FORMAT", "markdown")
print(json.dumps(rows, indent=1) if fmt == "json" else "\n---\n".join(rows))
print(f"rows: {len(rows)}")
