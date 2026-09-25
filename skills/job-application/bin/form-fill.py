# Runs INSIDE browser-use (helpers pre-imported). Encodes the 2026-09 session's
# form mechanics: React-controlled setters, DataTransfer text attach, chunked
# base64 binary attach, remount-tolerant retry fill, verification dump.
#
# Configure via env:
#   FF_SPEC   JSON fill spec: {"fields":[{"sel","value"}...],
#             "files":[{"sel","name","path"| "b64","mime"}...],
#             "verify":[{"sel","label"}...]}
#   FF_DEADLINE  ms for the remount-tolerant retry loop (default 15000)
#   FF_ALLOW_LEGAL=1  override the legal-field refusal (default refuse)
#
# Policy: fields whose label matches legal-declaration patterns (eligibility,
# visa/sponsorship, demographics) are refused unless FF_ALLOW_LEGAL=1 — those
# are owner-only declarations.
import json, os, re

LEGAL = re.compile(r"eligib|visa|sponsorship|authoriz|ethnic|gender|age\b|race|disabilit", re.I)

def build_js(spec):
    fields = json.dumps(spec.get("fields", []))
    files = json.dumps(spec.get("files", []))
    verify = json.dumps(spec.get("verify", []))
    deadline = int(os.environ.get("FF_DEADLINE", "15000"))
    allow_legal = os.environ.get("FF_ALLOW_LEGAL") == "1"
    return f"""
    const LEGAL = {json.dumps(LEGAL.pattern)};
    const ALLOW_LEGAL = {str(allow_legal).lower()};
    const fields = {fields}, files = {files}, verifySpec = {verify};
    const out = {{refused: [], filled: [], attached: [], missing: []}};
    const isLegal = (sel) => {{
      if (ALLOW_LEGAL) return false;
      const el = document.querySelector(sel);
      const label = el && el.labels && el.labels[0] ? el.labels[0].innerText : '';
      return new RegExp(LEGAL, 'i').test(label);
    }};
    const setField = (sel, val) => {{
      const el = document.querySelector(sel);
      if (!el) return 'missing';
      const proto = el.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype
                  : el.tagName === 'SELECT' ? window.HTMLSelectElement.prototype
                  : window.HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, val);
      el.dispatchEvent(new Event('input', {{bubbles: true}}));
      el.dispatchEvent(new Event('change', {{bubbles: true}}));
      return el.value === val ? 'ok' : 'partial';
    }};
    const attachFile = async (f) => {{
      const input = document.querySelector(f.sel);
      if (!input) return 'missing';
      let content;
      if (f.b64) {{
        const bytes = Uint8Array.from(atob(f.b64), c => c.charCodeAt(0));
        content = [bytes];
      }} else {{
        content = [f.content];
      }}
      const file = new File(content, f.name, {{type: f.mime || 'text/plain'}});
      const dt = new DataTransfer(); dt.items.add(file);
      input.files = dt.files;
      input.dispatchEvent(new Event('change', {{bubbles: true}}));
      return input.files.length === 1 ? 'set ' + file.size + 'B' : 'rejected';
    }};
    const run = async () => {{
      const targets = fields.slice();
      const deadline = Date.now() + {deadline};
      while (Date.now() < deadline && (targets.length || files.length)) {{
        for (let i = targets.length - 1; i >= 0; i--) {{
          const [sel, val] = targets[i];
          if (isLegal(sel)) {{ out.refused.push(sel); targets.splice(i, 1); continue; }}
          const r = setField(sel, val);
          if (r === 'ok') {{ out.filled.push(sel); targets.splice(i, 1); }}
          else if (r === 'partial') {{ targets.splice(i, 1); out.missing.push(sel + ':value-mismatch'); }}
        }}
        for (let i = files.length - 1; i >= 0; i--) {{
          const r = await attachFile(files[i]);
          if (r.startsWith('set ')) {{ out.attached.push(files[i].name + ' ' + r); files.splice(i, 1); }}
          else if (r === 'missing' && !document.querySelector(files[i].sel)) {{ /* remount; retry */ }}
          else {{ out.missing.push(files[i].sel + ':' + r); files.splice(i, 1); }}
        }}
      }}
      out.unfilled = targets.map(t => t[0]);
      out.verify = verifySpec.map(v => {{
        const el = document.querySelector(v.sel);
        return {{label: v.label, present: !!el, value: el ? String(el.value).slice(0, 60) : null,
                files: el && el.files ? el.files.length : undefined}};
      }});
      return out;
    }};
    return await run();
    """

if __name__ == "__main__" or True:
    spec = json.loads(os.environ["FF_SPEC"])
    result = js(build_js(spec))  # harness evaluates with awaitPromise=True
    print(json.dumps(result, indent=1))
