#!/usr/bin/env python3
"""Run one UI build/preview/browser-case cycle against an exact Git revision."""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath


def git(repo, *args):
    return subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, check=True
    ).stdout.strip()


def command(value, label):
    if not isinstance(value, list) or not value or any(
        not isinstance(part, str) or not part for part in value
    ):
        raise ValueError(f"{label} must be a nonempty argv list")
    return value


def load_manifest(path):
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError("manifest must be an object")
    revision = data.get("revision")
    if not isinstance(revision, str) or not re.fullmatch(
        r"(?:[0-9a-f]{40}|[0-9a-f]{64})", revision
    ):
        raise ValueError("revision must be a full Git commit ID")
    browser = data.get("browser")
    if not isinstance(browser, str) or not browser.strip():
        raise ValueError("browser must name the user's main browser")
    command(data.get("build"), "build")
    if "preview" not in data:
        raise ValueError("preview must be explicit: null or deploy/verify commands")
    preview = data["preview"]
    if preview is not None:
        if not isinstance(preview, dict):
            raise ValueError("preview must be null or an object")
        command(preview.get("verify"), "preview.verify")
        if "deploy" in preview:
            command(preview["deploy"], "preview.deploy")
    cases = data.get("cases")
    if not isinstance(cases, list) or not cases:
        raise ValueError("cases must be a nonempty list")
    ids, artifacts = set(), set()
    for case in cases:
        if not isinstance(case, dict):
            raise ValueError("each case must be an object")
        case_id = case.get("id")
        if not isinstance(case_id, str) or not re.fullmatch(r"[a-z][a-z0-9_-]*", case_id):
            raise ValueError("case id must use lowercase letters, digits, _ or -")
        if case_id in ids:
            raise ValueError(f"duplicate case id: {case_id}")
        ids.add(case_id)
        for field in ("given", "when", "then"):
            if not isinstance(case.get(field), str) or not case[field].strip():
                raise ValueError(f"{case_id}.{field} must be nonempty")
        command(case.get("check"), f"{case_id}.check")
        artifact = case.get("artifact")
        if not isinstance(artifact, str):
            raise ValueError(f"{case_id}.artifact must be a relative output path")
        parts = PurePosixPath(artifact)
        if parts.is_absolute() or not parts.parts or any(
            part in (".", "..") for part in parts.parts
        ):
            raise ValueError(f"{case_id}.artifact must stay within the output directory")
        if artifact in artifacts:
            raise ValueError(f"duplicate case artifact: {artifact}")
        artifacts.add(artifact)
    return data


def source_matches(repo, revision):
    return git(repo, "rev-parse", "HEAD") == revision and not git(
        repo, "status", "--porcelain", "--untracked-files=normal"
    )


def write_report(path, report):
    pending = path.with_suffix(".pending")
    pending.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    os.replace(pending, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--timeout-seconds", type=int, default=600)
    parser.add_argument("--allow-deploy", action="store_true")
    args = parser.parse_args()
    if args.timeout_seconds < 1:
        parser.error("timeout must be positive")

    try:
        manifest_bytes = args.manifest.read_bytes()
        data = load_manifest(args.manifest)
        repo = Path(git(Path.cwd(), "rev-parse", "--show-toplevel")).resolve()
        if not source_matches(repo, data["revision"]):
            raise ValueError("HEAD differs from revision or the worktree is dirty")
        preview = data["preview"]
        if preview is not None and "deploy" in preview and not args.allow_deploy:
            raise ValueError("preview.deploy requires --allow-deploy and prior authorization")
        if args.output_dir:
            output = args.output_dir.resolve()
            if os.path.commonpath((repo, output)) == str(repo):
                raise ValueError("output directory must be outside the repository")
            output.mkdir(parents=True, exist_ok=False)
        else:
            output = Path(tempfile.mkdtemp(prefix="ui-feature-gate-")).resolve()
    except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        print(f"ui-feature-gate: setup failed: {exc}", file=sys.stderr)
        return 2

    report_path = output / "result.json"
    report = {
        "revision": data["revision"],
        "browser": data["browser"],
        "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "status": "running",
        "steps": [],
    }
    write_report(report_path, report)
    env = dict(os.environ)
    env.update(
        UI_VALIDATION_REVISION=data["revision"],
        UI_VALIDATION_BROWSER=data["browser"],
        UI_VALIDATION_OUTPUT_DIR=str(output),
    )

    def fail(label, reason):
        report["status"] = "failed"
        report["failed_step"] = label
        report["reason"] = reason
        write_report(report_path, report)
        print(f"ui-feature-gate: {label} failed ({reason}); report {report_path}", file=sys.stderr)
        return 1

    def run_step(label, argv, case_id=None):
        log_name = label.replace(":", "-") + ".log"
        log_path = output / log_name
        step_env = dict(env)
        if case_id:
            step_env["UI_VALIDATION_CASE_ID"] = case_id
        with log_path.open("wb") as log:
            try:
                result = subprocess.run(
                    argv, cwd=repo, env=step_env, stdout=log,
                    stderr=subprocess.STDOUT, timeout=args.timeout_seconds, check=False,
                )
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = 124
            except OSError:
                code = 127
        step = {"name": label, "exit_code": code, "log": log_name}
        report["steps"].append(step)
        write_report(report_path, report)
        if code != 0:
            return fail(label, f"exit {code}")
        if not source_matches(repo, data["revision"]):
            return fail(label, "source revision changed or worktree became dirty")
        return 0

    if run_step("build", data["build"]):
        return 1
    if preview is not None:
        if "deploy" in preview and run_step("preview:deploy", preview["deploy"]):
            return 1
        if run_step("preview:verify", preview["verify"]):
            return 1
        verify_log = output / "preview-verify.log"
        if data["revision"] not in verify_log.read_text(errors="replace").splitlines():
            return fail("preview:verify", "exact revision marker missing")

    for case in data["cases"]:
        case_id = case["id"]
        artifact = output / case["artifact"]
        if artifact.exists() or artifact.is_symlink():
            return fail(f"case:{case_id}", "artifact existed before case ran")
        if run_step(f"case:{case_id}", case["check"], case_id):
            return 1
        if artifact.is_symlink() or not artifact.is_file() or artifact.stat().st_size == 0:
            return fail(f"case:{case_id}", "browser evidence artifact missing or empty")
        report["steps"][-1]["artifact"] = case["artifact"]
        write_report(report_path, report)

    report["status"] = "passed"
    write_report(report_path, report)
    print(f"ui-feature-gate: pass {len(data['cases'])} cases at {data['revision'][:12]}; report {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
