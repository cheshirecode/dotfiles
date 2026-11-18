---
name: lessons-to-guards
description: After a multi-commit feature run, mine git log and session mistakes for failure patterns and convert them into standing guards. A mechanical scanner does the detection; you judge findings, write the guards, and prove each one red. Use when wrapping up a feature session, auditing a repo for missing guards, or when the same class of bug ships twice.
---

# Lessons to guards

After any multi-commit feature run, convert the run's mistakes into standing
guards. A deterministic scanner does the detection; you bring judgment only
where no clean script exists.

## Method

1. **Run the scanner** (stdlib Python, no install):

   ```sh
   python3 <skill-dir>/scripts/lessonscan.py <repo-root> [--config scan.toml] [--strict]
   ```

   Exit 1 = strict findings. Every finding names its class, file:line, the
   matched line, and the fix hint. The scanner is deliberately regex-level:
   it has false positives — triage, never auto-fix. Triage rules:
   - `toHaveCount(0|1)` are absence assertions, already exempt.
   - A literal that is a *fixture fact* (the value comes from a test fixture,
     not from data that grows) is legitimate — allowlist it with a reason in
     `scan.toml` (`[[allowlist]] rule = "drift-count" pattern = "..."`).
   - A literal that mirrors a registry that could grow (grades, pack count,
     skill list) is a real finding — derive it from the registry.

2. **Mine history for what the scanner cannot see.** `git log --oneline`,
   `git show` on fix/test commits. The scanner finds live code smells; history
   finds the *classes* behind past incidents. Verify each known mistake still
   has a code-level trace; stale mistakes are dropped.

3. **Classify.** Eight classes, each backed by three or more independent
   incidents across repos (the evidence bar for a class to exist):

   | Class | Signature | Mechanical detector |
   |---|---|---|
   | drift-keyed check | literal count / total / `file:line` that drifts while truth moves | `drift-count`, `drift-coord` |
   | silent flattening | canonicalizer/serializer collapses nested data without error | `flatten-replacer` |
   | duplicated source of truth | same fact in two places | `duplication` config block |
   | a11y/actionability mismatch | test treats an unreachable element as clickable | (no scanner — UI tests only; review manually) |
   | diagnostic-from-wrong-vantage | feature probed from the wrong state | (no scanner — rule) |
   | symlink-opacity | path logic ignoring/following symlinks; `.bak` residue | `symlink-residue` + symlink fixtures in install tests |
   | exit-code laundering | failures demoted to prints/warnings, exit 0 | `swallow` + `exit-laundering` |
   | string-cast comparison | `str(a) != str(b)` where values are semantically equal | `string-cast` |

   A class without three independent incidents is a hypothesis, not a class —
   keep it as a rule note instead.

4. **Convert each finding to the cheapest standing guard**, in cost order:
   registry-derived count (import the loader, compute the number) >
   canonicalization round-trip test > near-duplicate text lint (token overlap,
   0.8 threshold, corpora configured in `scan.toml`) > set-equality check
   between a directory listing and its registry > document-as-rule when a
   test would false-positive on domain words.

5. **Prove every guard red** on the unfixed code (scratch copy, one mutation,
   record which assertion fired) before trusting green. A guard that passes
   both ways certifies nothing. If a guard catches a live defect, fix the
   defect in the same run and say the guard caught it.

6. **Registry-mirror honesty.** A guard that mirrors literal strings from
   source (widget questions, clap args) is itself a second copy — put the
   mirror in ONE test file with a comment naming the source, and expect to
   update both together. Prefer deriving from source when the source is
   importable.

## Config (`scan.toml`, optional — detectors run with zero config)

```toml
[[allowlist]]
rule = "drift-count"
pattern = "toHaveCount\\(3\\)"   # fixture fact: imported save carries 3 completions

[[duplication]]
name = "story lines vs widget questions"
left  = { glob = "content/cases/*.json", line_regex = '"([^"]{16,})"', min_length = 16 }
right = { glob = "src/engine/widgets/*.ts", line_regex = "'([^']{16,})'", min_length = 16 }
threshold = 0.8

[[set-equality]]
name = "skills on disk vs manifest"
left  = { dir_glob = "skills/*" }
right = { file = "manifest/skills.yaml", line_regex = "- name: (.+)$" }
```

## Evidence base (cross-repo dogfood, 2026-11-14)

| Incident | Repo | Class |
|---|---|---|
| fingerprint replacer-array collapsed nested block pictures to `{}` | maple-math-mysteries | silent flattening |
| e2e `.case-card` count rewritten by hand 12→20→25→39 | maple-math-mysteries | drift-keyed |
| `COUNT_WORD[10]` → "zero of undefined mysteries closed" | maple-math-mysteries | drift-keyed |
| story lines duplicating widget questions, shipped 3 passes running | maple-math-mysteries | duplicated source |
| `SKILL_COMMANDS` registry missed 2 new skills (leak scan blind) | dotfiles | drift-keyed |
| hook lookup beside a symlink skipped the identity gate | dotfiles | symlink-opacity |
| `.bak` copies loaded as second skills ("council.bak ×21") | dotfiles | symlink-opacity |
| repeated `--evidence` flags silently collapsed to the last value | dotfiles | silent flattening |
| accepted-but-unread `--attachment` flag, docs and code disagreed | googleworkspace-cli | duplicated source |
| 93 generated skills failed external validation the generator's tests never ran | googleworkspace-cli | diagnostic-from-wrong-vantage |
| drift-check script exited 0 after matching nothing; versions drifted for 18 releases | googleworkspace-cli | drift-keyed |
| malformed registry → zero skills generated, exit 0, warning only | googleworkspace-cli | exit-code laundering |
| unparseable currency silently became `0.0` in totals | personal-planner-app | silent flattening |
| batch import printed "complete" and exited 0 after failures | personal-planner-app | exit-code laundering |
| `/mnt/c/...2026-01-30.txt` hardcoded in tracked source | personal-planner-app | drift-keyed |

Honest absences: the a11y class found no incidents in non-UI repos (expected —
absence of the failure mode is a coverage gap, not evidence the class is wrong).
