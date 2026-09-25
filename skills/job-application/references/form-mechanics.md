# Form mechanics — gotchas from live use (2026-09)

Hard-won mechanics for automating application forms through the browser
harness. `bin/form-fill.py` encodes all of these; read this when inventing
an approach it does not cover.

1. **React-controlled inputs**: set values with the native prototype value
   setter + `input`/`change` events, never `el.value = ...` (React's value
   tracker reverts blind writes).
2. **Cross-origin embeds**: when the application form is an iframe embed
   (e.g. `www.instacart.careers` embedding Greenhouse), navigate the working
   tab directly to the embed URL
   (`boards.greenhouse.io/embed/job_app?for=<board>&token=<id>`) — the same
   form, now top-level and scriptable.
3. **Flapping/remounting forms**: Greenhouse and Ashby forms intermittently
   unmount and remount sections; programmatic values on blurred fields can be
   reverted. Fill with a fused retry loop (deadline-bounded, per-field
   stickiness checks) in ONE script — never across CLI invocations.
4. **File attach**: `input.files` is assignable from a `DataTransfer` for
   text content. For binaries (docx/pdf), inject base64 in <=48k chunks into
   `window.__*` first, then assemble with `atob` — inlining a 200KB string
   into one `Runtime.evaluate` blows the harness IPC chunk limit.
5. **OOPIF widgets**: some file inputs are unreachable via `DOM.getDocument`
   even with `pierce:true` while `Runtime.evaluate` sees them — prefer the
   DataTransfer path over CDP DOM node surgery.
6. **Owner-only fields**: work eligibility, visa/sponsorship, US
   authorization, demographics are legal declarations — never auto-fill;
   leave EMPTY and list them as human steps. `form-fill.py` refuses them
   unless `FF_ALLOW_LEGAL=1`.
7. **Progressive/modal forms** (Teamtailor-style): email-gated multi-step
   modals often ignore synthetic submit events; budget one attempt, then
   hand the flow to the owner rather than fighting it.
8. **Verification**: end every fill with a structured verify dump (selector,
   presence, value slice, file count) and log it as evidence.
