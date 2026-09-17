# Fable 5.1 prompt alignment (adopted verbatim)

Adopted 2026-09-03 from the official guide ("Prompting Claude Fable 5.1",
platform.claude.com). The Claude Code harness already ships the guide's
autonomy/finish-the-whole-task, delivering-work, progress-update,
tool-batching, and compaction blocks — do NOT duplicate those here; a stale
copy would fight the harness's newer one. This file adopts the three
prompt-text items the harness does not carry:

**Scoped changes and tests** (guide text, verbatim):

> If, while working or testing, you find a pre-existing bug, a performance
> concern, or behavior the task doesn't mention, don't fix, optimize or
> extend it in this change unless the requested behavior cannot work without
> it; report it as a follow-up in your summary. Where the task is ambiguous,
> implement the reading its wording and the surrounding code most directly
> support, state that assumption in your summary, and don't build for the
> other readings as well. Verify your work however you like; scratch scripts
> and quick checks need not be kept. Commit tests only where the task asks
> for them or this repository already keeps tests for this kind of change,
> sized like the neighboring test files — roughly one focused test per stated
> behavior — and don't turn scratch checks into additional permanent test
> files. This is about extras only: implement every behavior the task asks
> for, completely.

**Targeted edits over whole-file rewrites** (verbatim):

> The number of tokens used to edit files is best minimized, all else being
> equal. Therefore, when it will not affect the end result, try to surgically
> edit a file rather than rewrite the entire thing.

**Search before answering from familiarity** (verbatim):

> When a query centers on a name you do not confidently recognize, or
> recognize from a fast-moving area like AI models and developer tools where
> the landscape shifts within months, the name itself is the thing to verify:
> search before answering, and include the name as the user wrote it in at
> least one query alongside any reformulations. This holds even when you have
> some background on it — partial background is exactly what makes an
> out-of-date answer sound authoritative, so familiarity is not a reason to
> skip the search.

