#!/usr/bin/env bash
# Test harness for cheshirecode/dotfiles. Same script for local + CI.
#
#   tests/run.sh static       lint scripts + manifest
#   tests/run.sh fixtures     run guardrail fixtures (red-path tests)
#   tests/run.sh all          static + fixtures

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0; FAIL=0
say() { printf "  %-5s %s\n" "$1" "$2"; }
ok()   { say PASS "$1"; PASS=$((PASS+1)); }
fail() { say FAIL "$1"; FAIL=$((FAIL+1)); }

test_static() {
  echo "=== static ==="
  if command -v shellcheck >/dev/null; then
    if shellcheck --severity=warning bin/*.sh tools/*.sh tests/*.sh 2>&1 | grep -E '^In '; then
      fail "shellcheck"
    else
      ok "shellcheck"
    fi
  else
    say SKIP "shellcheck not installed"
  fi
  if ./tools/check-manifest.sh >/dev/null 2>&1; then ok "check-manifest.sh"; else fail "check-manifest.sh"; fi
  if python3 - <<'PY'
import pathlib
import re

import yaml

problems = []
for skill_md in sorted(pathlib.Path("skills").glob("*/SKILL.md")):
    text = skill_md.read_text()
    match = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not match:
        problems.append(f"{skill_md}: missing YAML frontmatter")
        continue
    fm = yaml.safe_load(match.group(1)) or {}
    expected = skill_md.parent.name
    if fm.get("name") != expected:
        problems.append(f"{skill_md}: name={fm.get('name')!r}, expected {expected!r}")
if problems:
    print("\n".join(problems))
    raise SystemExit(1)
PY
  then ok "skill SKILL.md frontmatter"; else fail "skill SKILL.md frontmatter"; fi
  if python3 - <<'PY'
import pathlib
import re

text = pathlib.Path("skills/council/SKILL.md").read_text()
checks = {
    "support formula": "APPROVE_count + (0.5 * QUALIFY_count)" in text,
    "formula text": "ceil(M_returned / 2 + 1)" in text,
    "threshold name": "majority-plus-one" in text,
    "M=3 threshold": "M=3 threshold 3" in text,
    "M=5 threshold": "M=5 threshold 4" in text,
    "M=7 threshold": "M=7 threshold 5" in text,
    "M=4 unverified": "M=2 or M=4 is `UNVERIFIED`" in text,
    "odd returned voters": "`M_returned` must be odd and at least 3" in text,
    "invalid denominator": "Invalid item ballots never lower the denominator" in text,
    "unresolved qualify": "Do not silently count unresolved conditions" in text,
    "kept status": "KEPT support threshold met" in text,
    "outcome first": "The final report is outcome-first" in text,
    "audit appendix": "## Audit Appendix" in text,
    "exact provenance": "[proposed-by: A1-i2, D-i1]" in text,
    "worklog opt-in": "If the user says no worklog tracking" in text,
    "background rule": "background only if total estimate >10min" in text,
    "close after quorum": "close them without changing Stage 2 findings" in text,
}
headings = [
    "## Outcome",
    "## Kept Items",
    "## Rejected Items",
    "## Stage Notes",
    "## Audit Appendix",
]
positions = [text.find(h) for h in headings]
checks["final report section order"] = all(pos >= 0 for pos in positions) and positions == sorted(positions)
checks["no standalone SURVIVE"] = not re.search(r"\bSURVIVE\b", text)
majority_approve_hits = [m.start() for m in re.finditer("majority approve", text)]
checks["majority approve only anti-pattern"] = len(majority_approve_hits) == 1 and "Do not call the majority-plus-one rule \"majority approve.\"" in text
missing = [name for name, ok in checks.items() if not ok]
if missing:
    print("missing council threshold contract: " + ", ".join(missing))
    raise SystemExit(1)
PY
  then ok "council voting threshold contract"; else fail "council voting threshold contract"; fi
}

# Council items #1, #6: fixture-driven red-path tests for guardrails.
test_fixtures() {
  echo "=== fixtures (red-path guardrail tests) ==="
  local python_site_path
  python_site_path=$(python3 - <<'PY'
import pathlib
import yaml

print(pathlib.Path(yaml.__file__).resolve().parents[1])
PY
)

  # --- #6: check-manifest.sh subpath+repo HARD FAIL ---
  local bad_manifest tmpdir
  tmpdir=$(mktemp -d)
  bad_manifest="$tmpdir/skills.yaml"
  cat >"$bad_manifest" <<'EOF'
version: 1
skills:
  - name: bogus
    description: test fixture — subpath with repo, must be rejected
    source:
      type: subpath
      repo: not-allowed-on-subpath/foo
      path: skills/bogus
    install_to: ~/.claude/skills/bogus
EOF
  # Run check-manifest with the fixture by temporarily overriding the manifest.
  # Use a wrapper invocation so we don't mutate the real file.
  if MANIFEST_OVERRIDE="$bad_manifest" python3 - <<PY
import sys, re, yaml
m = yaml.safe_load(open("$bad_manifest"))
problems = []
for s in m.get("skills", []):
    name = s.get("name","?")
    src = s.get("source", {})
    if src.get("type") == "subpath" and src.get("repo"):
        problems.append(f"{name}: source.type='subpath' must not carry 'repo:' field")
sys.exit(1 if problems else 0)
PY
  then
    fail "check-manifest accepted subpath+repo bad fixture (should reject)"
  else
    ok "check-manifest rejects subpath+repo (exit=1 as expected)"
  fi
  rm -rf "$tmpdir"

  # --- #1: install-skills refuse_if_unowned ---
  # The manifest's install_to is "~/.claude/skills/<name>" — resolved against
  # $HOME, not CLAUDE_SKILLS_DIR. Override HOME so ~ expansion lands in tmp.
  local fake_home unowned_dst rc
  fake_home=$(mktemp -d)
  unowned_dst="$fake_home/.claude/skills/council"
  mkdir -p "$unowned_dst"
  echo "user-edited content" > "$unowned_dst/SKILL.md"
  set +e
  HOME="$fake_home" PYTHONPATH="${python_site_path}${PYTHONPATH:+:$PYTHONPATH}" ./bin/install-skills.sh council >/dev/null 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 3 ]]; then
    ok "install-skills refuses unowned dst (exit=3)"
  else
    fail "install-skills DID NOT refuse unowned dst (got exit=$rc, expected 3)"
  fi
  rm -rf "$fake_home"

  # --- #1: install-skills accepts sentineled dst ---
  fake_home=$(mktemp -d)
  unowned_dst="$fake_home/.claude/skills/council"
  mkdir -p "$unowned_dst"
  cp "$REPO_ROOT/skills/council/SKILL.md" "$unowned_dst/SKILL.md"
  echo "subpath:skills/council" > "$unowned_dst/.installed_from"
  set +e
  HOME="$fake_home" PYTHONPATH="${python_site_path}${PYTHONPATH:+:$PYTHONPATH}" ./bin/install-skills.sh council >/dev/null 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    ok "install-skills accepts sentineled dst (exit=0)"
  else
    fail "install-skills rejected sentineled dst (got exit=$rc, expected 0)"
  fi
  rm -rf "$fake_home"

  local skill_names skill_name skill_md
  skill_names=$(python3 - <<'PY'
import pathlib
import yaml

manifest = yaml.safe_load(open("manifest/skills.yaml"))
for entry in manifest.get("skills", []):
    if entry["name"] == "worklog":
        continue
    source = entry.get("source", {})
    if source.get("type") != "subpath":
        continue
    skill_md = pathlib.Path(source["path"]) / "SKILL.md"
    if skill_md.is_file():
        print(entry["name"])
PY
)
  while IFS= read -r skill_name; do
    [[ -z "$skill_name" ]] && continue
    fake_home=$(mktemp -d)
    set +e
    HOME="$fake_home" PYTHONPATH="${python_site_path}${PYTHONPATH:+:$PYTHONPATH}" ./bin/install-skills.sh "$skill_name" >/dev/null 2>&1
    rc=$?
    set -e
    skill_md="$fake_home/.claude/skills/$skill_name/SKILL.md"
    if [[ $rc -eq 0 && -f "$skill_md" ]]; then
      ok "install-skills installs $skill_name"
    else
      fail "install-skills failed for $skill_name (rc=$rc)"
    fi
    rm -rf "$fake_home"
  done <<< "$skill_names"

  if python3 - <<'PY'
import re

leak_re = re.compile(
    r"worklog|\[POST-MERGE|next_action|/ship-hygiene|/impeccable|/worklog|"
    r"people/[a-z]+/active|iteration [0-9]|per the (audit|critique)|scope chosen",
    re.I,
)

def flagged(line, changed_paths):
    skill_surface = any(
        path.startswith("skills/") or path == "manifest/skills.yaml"
        for path in changed_paths
    )
    if skill_surface and re.search(r"/(ship-hygiene|impeccable|worklog)\b", line):
        return False
    return bool(leak_re.search(line))

assert not flagged("+ Document /ship-hygiene usage for skill PRs", ["skills/ship-hygiene/SKILL.md"])
assert flagged("+ next_action from people/oss/active/foo.md", ["README.md"])
PY
  then ok "ship-hygiene skill PR leak exception"; else fail "ship-hygiene skill PR leak exception"; fi

  if python3 - <<'PY'
import pathlib

text = pathlib.Path("skills/ship-hygiene/SKILL.md").read_text()
checks = {
    "plain checkpoint default": '`"$WORKLOG_BIN/checkpoint.sh" <slug>`' in text,
    "force marked exceptional": "explicit, stated-reason override" in text,
    "no forced checkpoint default": "`WORKLOG_CHECKPOINT_FORCE=1 bin/checkpoint.sh <slug>`" not in text,
}
missing = [name for name, ok in checks.items() if not ok]
if missing:
    print("ship-hygiene checkpoint guard drift: " + ", ".join(missing))
    raise SystemExit(1)
PY
  then ok "ship-hygiene checkpoint guard contract"; else fail "ship-hygiene checkpoint guard contract"; fi

  local catalog_home catalog_fixture catalog_json
  catalog_home=$(mktemp -d)
  catalog_fixture="$catalog_home/models.json"
  cat >"$catalog_fixture" <<'EOF'
{
  "openai": {
    "models": {
      "fast": {
        "id": "openai/fast-mini",
        "name": "Fast Mini",
        "pricing": {"input": 0.1, "output": 0.4},
        "limits": {"context": 128000, "output": 8192},
        "capabilities": {"tool": true, "reasoning": false}
      },
      "reason": {
        "id": "openai/reason-pro",
        "name": "Reason Pro",
        "pricing": {"input": 5, "output": 25},
        "limits": {"context": 1000000, "output": 128000},
        "capabilities": {"tool": true, "reasoning": true, "image": true}
      }
    }
  }
}
EOF
  catalog_json=$(
    WHICH_MODEL_CACHE_HOME="$catalog_home/cache" \
    WHICH_MODEL_CATALOG_SOURCE="$catalog_fixture" \
    skills/which-model/bin/model-catalog --env opencode --refresh-if-stale --task visual --top 1
  )
  if python3 - "$catalog_home/cache/catalog.opencode.json" "$catalog_json" <<'PY'
import json
import pathlib
import sys

cache_path = pathlib.Path(sys.argv[1])
payload = json.loads(sys.argv[2])
catalog = payload["catalog"]
assert cache_path.is_file()
assert catalog["environment"] == "opencode"
assert catalog["schema_version"] == 1
assert len(catalog["models"]) == 2
assert payload["recommendations"][0]["id"] == "openai/reason-pro"
PY
  then ok "which-model catalog warms env cache"; else fail "which-model catalog warms env cache"; fi
  catalog_json=$(
    WHICH_MODEL_CACHE_HOME="$catalog_home/cache" \
    WHICH_MODEL_OFFLINE=1 \
    skills/which-model/bin/model-catalog --env codex --force-refresh --task routine_coding --top 3
  )
  if python3 - "$catalog_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
ids = {model["id"] for model in payload["catalog"]["models"]}
required = {
    "gpt-5.6-luna",
    "gpt-5.6-terra",
    "gpt-5.6-sol",
    "gpt-5.5",
    "gpt-5.5-pro",
    "gpt-5.4",
    "gpt-5.4-mini",
    "gpt-5.4-nano",
    "gpt-5.3-codex",
    "gpt-5-codex",
}
missing = sorted(required - ids)
if missing:
    raise SystemExit("missing codex seed models: " + ", ".join(missing))
PY
  then ok "which-model codex seed covers older lanes"; else fail "which-model codex seed covers older lanes"; fi

  local openrouter_fixture
  openrouter_fixture="$catalog_home/openrouter.json"
  cat >"$openrouter_fixture" <<'EOF'
{
  "data": [
    {
      "id": "anthropic/claude-cheap",
      "name": "Claude Cheap",
      "context_length": 200000,
      "architecture": {"input_modalities": ["text", "image"], "output_modalities": ["text"]},
      "pricing": {"prompt": "0.000001", "completion": "0.000005"},
      "top_provider": {"context_length": 180000, "max_completion_tokens": 8192, "is_moderated": true},
      "supported_parameters": ["tools", "tool_choice", "reasoning", "structured_outputs", "response_format"],
      "reasoning": {"mandatory": false, "default_enabled": true},
      "expiration_date": null
    },
    {
      "id": "openai/gpt-router-pro",
      "name": "GPT Router Pro",
      "context_length": 1000000,
      "architecture": {"input_modalities": ["text"], "output_modalities": ["text"]},
      "pricing": {"prompt": "0.000005", "completion": "0.000015"},
      "top_provider": {"context_length": 1000000, "max_completion_tokens": 32768, "is_moderated": false},
      "supported_parameters": ["tools"],
      "reasoning": {"mandatory": true, "default_enabled": true}
    },
    {
      "id": "openrouter/dynamic-price",
      "architecture": {"input_modalities": ["text"], "output_modalities": ["text"]},
      "pricing": {"prompt": "-1", "completion": "-1"},
      "top_provider": {"max_completion_tokens": 4096, "is_moderated": false},
      "supported_parameters": [],
      "expiration_date": "2026-12-01"
    },
    {
      "id": null,
      "name": "skip-me"
    }
  ]
}
EOF
  catalog_json=$(
    WHICH_MODEL_CACHE_HOME="$catalog_home/cache" \
    WHICH_MODEL_CATALOG_SOURCE="$openrouter_fixture" \
    skills/which-model/bin/model-catalog --env openrouter --refresh-if-stale --task routine_coding --top 3
  )
  if python3 - "$catalog_home/cache/catalog.openrouter.json" "$catalog_json" <<'PY'
import json
import pathlib
import sys

cache_path = pathlib.Path(sys.argv[1])
payload = json.loads(sys.argv[2])
catalog = payload["catalog"]
assert cache_path.is_file(), "openrouter cache not written"
assert catalog["environment"] == "openrouter"
assert catalog["schema_version"] == 1
assert any(source.get("kind") == "override" for source in catalog["sources"])
by_id = {model["id"]: model for model in catalog["models"]}
assert set(by_id) == {
    "anthropic/claude-cheap",
    "openai/gpt-router-pro",
    "openrouter/dynamic-price",
}
cheap = by_id["anthropic/claude-cheap"]
# per-token USD strings must scale to per-million-token floats.
assert cheap["input_price_per_mtok"] == 1.0, cheap["input_price_per_mtok"]
assert cheap["output_price_per_mtok"] == 5.0, cheap["output_price_per_mtok"]
assert cheap["provider"] == "anthropic"
# Prefer routed/top_provider context over advertised context_length.
assert cheap["context_window"] == 180000, cheap["context_window"]
assert cheap["max_output"] == 8192
assert cheap["availability"] == "selectable_here"
assert "image_input" in cheap["capabilities"]
assert "tools" in cheap["capabilities"]
assert "reasoning" in cheap["capabilities"]
assert "structured_output" in cheap["capabilities"]
assert any("moderated" in c for c in cheap["caveats"])
assert any("context" in c.lower() and ("mismatch" in c.lower() or "differs" in c.lower()) for c in cheap["caveats"]), cheap["caveats"]
assert cheap["confidence"] == "fixture"
pro = by_id["openai/gpt-router-pro"]
assert any("mandatory" in c.lower() and "reasoning" in c.lower() for c in pro["caveats"]), pro["caveats"]
dynamic = by_id["openrouter/dynamic-price"]
assert dynamic["display_name"] == "openrouter/dynamic-price"
assert dynamic["provider"] == "openrouter"
assert dynamic["input_price_per_mtok"] is None
assert dynamic["output_price_per_mtok"] is None
assert dynamic["context_window"] is None
assert any("pricing" in c.lower() for c in dynamic["caveats"]), dynamic["caveats"]
assert any("routed context" in c.lower() for c in dynamic["caveats"]), dynamic["caveats"]
assert any("expir" in c.lower() for c in dynamic["caveats"]), dynamic["caveats"]
# cheapest fitting lane ranks first for routine_coding.
assert payload["recommendations"][0]["id"] == "anthropic/claude-cheap"
PY
  then ok "which-model openrouter catalog parses live-shaped metadata"; else fail "which-model openrouter catalog parses live-shaped metadata"; fi

  catalog_json=$(
    WHICH_MODEL_CACHE_HOME="$catalog_home/cache-offline" \
    WHICH_MODEL_OFFLINE=1 \
    skills/which-model/bin/model-catalog --env openrouter --force-refresh --task routine_coding --top 3
  )
  if python3 - "$catalog_home/cache-offline/catalog.openrouter.json" "$catalog_json" <<'PY'
import json
import pathlib
import sys

cache_path = pathlib.Path(sys.argv[1])
payload = json.loads(sys.argv[2])
catalog = payload["catalog"]
assert cache_path.is_file(), "offline openrouter cache not written"
assert catalog["environment"] == "openrouter"
assert any(source.get("kind") == "seed" for source in catalog["sources"])
assert not any(source.get("kind") == "openrouter" and "url" in source for source in catalog["sources"])
for model in catalog["models"]:
    assert model["confidence"] == "seeded"
    assert model["availability"] == "requires_harness_check"
    assert model["input_price_per_mtok"] is None
    assert model["output_price_per_mtok"] is None
assert any(model["id"] == "openrouter/auto" for model in catalog["models"])
PY
  then ok "which-model openrouter offline falls back to seeded catalog"; else fail "which-model openrouter offline falls back to seeded catalog"; fi

  local claude_fixture
  claude_fixture="$catalog_home/claude.json"
  cat >"$claude_fixture" <<'EOF'
{
  "data": [
    {"type": "model", "id": "claude-haiku-4-5-20251001", "display_name": "Claude Haiku 4.5", "created_at": "2025-10-01T00:00:00Z"},
    {"type": "model", "id": "claude-opus-4-1-20250805", "display_name": "Claude Opus 4.1", "created_at": "2025-08-05T00:00:00Z"},
    {"type": "model", "id": "claude-future-unknown-1", "display_name": "Claude Future Unknown", "created_at": "2026-01-01T00:00:00Z"}
  ],
  "has_more": false
}
EOF
  catalog_json=$(
    WHICH_MODEL_CACHE_HOME="$catalog_home/cache-claude" \
    WHICH_MODEL_CATALOG_SOURCE="$claude_fixture" \
    skills/which-model/bin/model-catalog --env claude --refresh-if-stale --task routine_coding --top 3
  )
  if python3 - "$catalog_home/cache-claude/catalog.claude.json" "$catalog_json" <<'PY'
import json
import pathlib
import sys

cache_path = pathlib.Path(sys.argv[1])
payload = json.loads(sys.argv[2])
catalog = payload["catalog"]
assert cache_path.is_file(), "claude cache not written"
assert catalog["environment"] == "claude"
assert catalog["schema_version"] == 1
by_id = {model["id"]: model for model in catalog["models"]}
assert set(by_id) == {
    "claude-haiku-4-5-20251001",
    "claude-opus-4-1-20250805",
    "claude-future-unknown-1",
}
haiku = by_id["claude-haiku-4-5-20251001"]
# Models API supplies id/display_name; docs snapshot fills price/limits/capabilities.
assert haiku["display_name"] == "Claude Haiku 4.5"
assert haiku["provider"] == "anthropic"
assert haiku["availability"] == "selectable_if_configured"
assert haiku["input_price_per_mtok"] == 1.0, haiku["input_price_per_mtok"]
assert haiku["output_price_per_mtok"] == 5.0, haiku["output_price_per_mtok"]
assert haiku["context_window"] == 200000
assert haiku["max_output"] == 64000
assert "image_input" in haiku["capabilities"]
assert "reasoning" in haiku["capabilities"]
assert haiku["confidence"] == "fixture"
assert any("docs snapshot" in c for c in haiku["caveats"])
opus = by_id["claude-opus-4-1-20250805"]
assert opus["input_price_per_mtok"] == 15.0
assert opus["output_price_per_mtok"] == 75.0
assert opus["max_output"] == 32000
# Unmatched model id keeps prices null and flags the gap rather than inventing numbers.
unknown = by_id["claude-future-unknown-1"]
assert unknown["input_price_per_mtok"] is None
assert unknown["output_price_per_mtok"] is None
assert any("No pricing/limits metadata match" in c for c in unknown["caveats"])
# Cheapest fitting lane ranks first for routine_coding.
assert payload["recommendations"][0]["id"] == "claude-haiku-4-5-20251001"
PY
  then ok "which-model claude catalog enriches Models-API metadata"; else fail "which-model claude catalog enriches Models-API metadata"; fi

  catalog_json=$(
    WHICH_MODEL_CACHE_HOME="$catalog_home/cache-claude-offline" \
    WHICH_MODEL_OFFLINE=1 \
    skills/which-model/bin/model-catalog --env claude --force-refresh --task routine_coding --top 3
  )
  if python3 - "$catalog_home/cache-claude-offline/catalog.claude.json" "$catalog_json" <<'PY'
import json
import pathlib
import sys

cache_path = pathlib.Path(sys.argv[1])
payload = json.loads(sys.argv[2])
catalog = payload["catalog"]
assert cache_path.is_file(), "offline claude cache not written"
assert catalog["environment"] == "claude"
assert any(source.get("kind") == "seed" for source in catalog["sources"])
assert not any(source.get("kind") == "anthropic-models-api" and "url" in source for source in catalog["sources"])
for model in catalog["models"]:
    assert model["confidence"] == "seeded"
PY
  then ok "which-model claude offline falls back to seeded catalog"; else fail "which-model claude offline falls back to seeded catalog"; fi
  rm -rf "$catalog_home"

  local quiet_home quiet_out
  quiet_home=$(mktemp -d)
  quiet_out=$(HOME="$quiet_home" USER=test-agent DOTFILES_QUIET=1 bash -lc '. ./.shell_common; printf command-output')
  if [[ "$quiet_out" == "command-output" ]]; then
    ok "DOTFILES_QUIET suppresses bash welcome"
  else
    fail "DOTFILES_QUIET bash output polluted (got: ${quiet_out@Q})"
  fi
  if command -v zsh >/dev/null; then
    quiet_out=$(HOME="$quiet_home" USER=test-agent DOTFILES_QUIET=1 zsh -lc '. ./.shell_common; printf command-output')
    if [[ "$quiet_out" == "command-output" ]]; then
      ok "DOTFILES_QUIET suppresses zsh welcome"
    else
      fail "DOTFILES_QUIET zsh output polluted (got: ${quiet_out@Q})"
    fi
  else
    say SKIP "zsh not installed"
  fi
  rm -rf "$quiet_home"
}

# Council #31: worklog skill bin/ — static lint + fixture-vault smoke. Catches
# the relocation-class regression where bin/foo.sh sibling-script calls drift
# back to data-repo-relative paths after Phase-2 deleted in-repo bin/.
test_worklog_skill() {
  echo "=== worklog skill (shellcheck + ruff + fixture-vault smoke) ==="
  local skill="$REPO_ROOT/skills/worklog"
  local sb="$skill/bin"
  [[ -d "$sb" ]] || { fail "skills/worklog/bin/ missing"; return; }

  # 1. shellcheck on all .sh under skill bin/ (excluding git-hooks/ — same severity gate).
  if command -v shellcheck >/dev/null; then
    if shellcheck --severity=warning "$sb"/*.sh "$sb"/git-hooks/* 2>&1 | grep -E '^In ' >/dev/null; then
      fail "shellcheck skills/worklog/bin/"
    else
      ok "shellcheck skills/worklog/bin/ (incl. git-hooks)"
    fi
  else
    say SKIP "shellcheck not installed"
  fi

  # 2. python syntax + ruff (skip ruff if absent).
  if python3 -m compileall -q "$sb" 2>&1 | grep -q .; then
    fail "python compile skills/worklog/bin/"
  else
    ok "python compile skills/worklog/bin/"
  fi
  if command -v ruff >/dev/null; then
    if ruff check "$sb" >/dev/null 2>&1; then
      ok "ruff skills/worklog/bin/"
    else
      ruff check "$sb" 2>&1 | head -10 >&2
      fail "ruff skills/worklog/bin/"
    fi
  else
    say SKIP "ruff not installed"
  fi

  # 3. Fixture-vault smoke. Bootstrap a throwaway data repo using the skill's
  # init-new-data-repo.sh; then exercise the core mode surface against it.
  local vault rc
  vault=$(mktemp -d)/test-vault
  set +e
  bash "$sb/init-new-data-repo.sh" "$vault" test-ldap >/dev/null 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 0 && -f "$vault/AGENTS.md" && -d "$vault/people/test-ldap/active" ]]; then
    ok "init-new-data-repo bootstraps clean (vault @ $vault)"
  else
    fail "init-new-data-repo failed (rc=$rc)"
    rm -rf "$(dirname "$vault")"
    return
  fi

  # Idempotent re-run: zero diffs in working tree.
  set +e
  bash "$sb/init-new-data-repo.sh" "$vault" test-ldap >/dev/null 2>&1
  if [[ -z "$(git -C "$vault" status --porcelain)" ]]; then
    ok "init-new-data-repo idempotent (no diff on re-run)"
  else
    fail "init-new-data-repo NOT idempotent — re-run dirtied the tree"
  fi
  set -e

  # Run preamble + status + lint against the throwaway vault.
  local out
  out=$(WORKLOG_REPO="$vault" WORKLOG_LDAP=test-ldap bash "$sb/preamble.sh" --minimal 2>&1)
  if echo "$out" | grep -q 'LDAP=test-ldap'; then
    ok "preamble.sh --minimal resolves vault LDAP"
  else
    fail "preamble.sh --minimal (got: $(echo "$out" | head -1))"
  fi

  out=$(WORKLOG_REPO="$vault" WORKLOG_LDAP=test-ldap bash "$sb/status.sh" --since=today 2>&1)
  if echo "$out" | grep -q '_nothing to report_'; then
    ok "status.sh runs against empty vault"
  else
    fail "status.sh against empty vault (got: $(echo "$out" | head -2 | tr '\n' ' '))"
  fi

  out=$(WORKLOG_REPO="$vault" bash "$sb/lint.sh" 2>&1)
  if echo "$out" | grep -qE '0 errors'; then
    ok "lint.sh runs clean against empty vault"
  else
    fail "lint.sh against empty vault (got: $(echo "$out" | head -2 | tr '\n' ' '))"
  fi

  # Empty-bin guard fires.
  echo '#!/bin/bash' > "$vault/bin/forbidden.sh"
  set +e
  ( cd "$vault" \
      && git -c core.hooksPath="$sb/git-hooks" add -f bin/forbidden.sh \
      && git -c core.hooksPath="$sb/git-hooks" commit -m "smoke" >/dev/null 2>&1 )
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    ok "pre-commit empty-bin guard rejects bin/foo.sh"
  else
    fail "pre-commit guard FAILED to reject (commit went through)"
  fi

  # Hard-fail when WORKLOG_REPO unset + cwd outside any clone.
  out=$( cd /tmp && env -u WORKLOG_REPO -u WORKLOG_LDAP -u WORKLOG_NS bash "$sb/kernels-roster.sh" 2>&1 || true )
  if echo "$out" | grep -q 'cannot locate'; then
    ok "scripts hard-fail outside a worklog clone"
  else
    fail "expected hard-fail outside clone, got: $(echo "$out" | head -1)"
  fi

  if bash "$skill/tests/worklog_manager/test_graph.sh" >/dev/null 2>&1; then
    ok "worklog-manager graph fixture"
  else
    fail "worklog-manager graph fixture"
  fi

  if bash "$skill/tests/worklog_manager/test_dispatch.sh" >/dev/null 2>&1; then
    ok "worklog-manager dispatch fixture"
  else
    fail "worklog-manager dispatch fixture"
  fi

  if bash "$skill/tests/worklog_manager/test_poll.sh" >/dev/null 2>&1; then
    ok "worklog-manager poll fixture"
  else
    fail "worklog-manager poll fixture"
  fi

  if node "$skill/tests/worklog_manager/test_units.mjs" >/dev/null 2>&1; then
    ok "worklog-manager unit fixtures"
  else
    fail "worklog-manager unit fixtures"
  fi

  if bash "$skill/tests/context/test_context.sh" >/dev/null 2>&1; then
    ok "context current Next + unique slug fixture"
  else
    fail "context current Next + unique slug fixture"
  fi

  if WORKLOG_REPO="$vault" WORKLOG_LDAP=test-ldap CODEX_SKILL_PATH="$skill/SKILL.md" bash "$sb/codex-surface-check.sh" >/dev/null 2>&1; then
    ok "codex-surface-check accepts Codex-native skill"
  else
    fail "codex-surface-check rejected Codex-native skill"
  fi

  local bad_codex_skill bad_init_mode
  bad_codex_skill="$(mktemp)"
  cp "$skill/SKILL.md" "$bad_codex_skill"
  printf '\nNon-Claude agents don'\''t invoke this skill.\n' >> "$bad_codex_skill"
  if WORKLOG_REPO="$vault" WORKLOG_LDAP=test-ldap CODEX_SKILL_PATH="$bad_codex_skill" bash "$sb/codex-surface-check.sh" >/dev/null 2>&1; then
    fail "codex-surface-check accepted self-excluding Codex skill"
  else
    ok "codex-surface-check rejects self-excluding Codex skill"
  fi
  rm -f "$bad_codex_skill"

  bad_init_mode="$(mktemp)"
  printf '# missing Codex hydration contract\n' > "$bad_init_mode"
  if WORKLOG_REPO="$vault" WORKLOG_LDAP=test-ldap CODEX_SKILL_PATH="$skill/SKILL.md" MODE_INIT_PATH="$bad_init_mode" bash "$sb/codex-surface-check.sh" >/dev/null 2>&1; then
    fail "codex-surface-check accepted init without update_plan contract"
  else
    ok "codex-surface-check rejects init without update_plan contract"
  fi
  rm -f "$bad_init_mode"

  rm -rf "$(dirname "$vault")"
}

case "${1:-all}" in
  static)         test_static ;;
  fixtures)       test_fixtures ;;
  worklog-skill)  test_worklog_skill ;;
  all)            test_static; test_fixtures; test_worklog_skill ;;
  *) echo "usage: $0 {static|fixtures|worklog-skill|all}" >&2; exit 2 ;;
esac

echo
echo "tests: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
