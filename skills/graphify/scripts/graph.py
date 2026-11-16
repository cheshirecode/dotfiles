#!/usr/bin/env python3
"""Offline graph navigation with checkout-bound, content-verified generations."""

import argparse
from contextlib import contextmanager
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time
import uuid

CAP = 8000


class GraphError(Exception):
    pass


def digest(path):
    with path.open("rb") as stream:
        result = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
        return result.hexdigest()


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, sort_keys=True) + "\n")
    temporary.replace(path)


def git(repo, *args):
    return subprocess.check_output(
        ["git", "-C", str(repo), *args], stderr=subprocess.PIPE
    )


@contextmanager
def locked(state):
    state.mkdir(parents=True, exist_ok=True)
    lock = state / "operation.lock"
    try:
        lock.mkdir()
    except FileExistsError:
        raise GraphError(
            f"Lock exists: {lock}; inspect owner before manual recovery."
        ) from None
    try:
        write_json(lock / "owner.json", {"pid": os.getpid(), "host": platform.node()})
        yield
    finally:
        (lock / "owner.json").unlink(missing_ok=True)
        lock.rmdir()


def preview(path, code):
    header = f"exit={code} bytes={path.stat().st_size} artifact={path}\n".encode()
    suffix = b"\n[Truncated; full output retained in artifact.]\n"
    with path.open("rb") as stream:
        content = stream.read(max(0, CAP - len(header) - len(suffix)))
    return (
        header + content + (suffix if len(content) < path.stat().st_size else b"\n")
    )[:CAP]


def offline(state):
    if platform.system() == "Darwin" and shutil.which("sandbox-exec"):
        profile = state / "offline.sb"
        profile.write_text("(version 1)\n(allow default)\n(deny network*)\n")
        return ["sandbox-exec", "-f", str(profile)]
    if platform.system() == "Linux":
        # Containers must have no external interfaces and no network-admin capability.
        interfaces = Path("/sys/class/net")
        status = Path("/proc/self/status")
        if interfaces.exists() and status.exists():
            caps = [
                int(line.split()[1], 16)
                for line in status.read_text().splitlines()
                if line.startswith(("CapEff:", "CapPrm:", "CapAmb:", "CapBnd:"))
            ]
            active = {
                p.name
                for p in interfaces.iterdir()
                if p.is_dir() and int((p / "flags").read_text().strip(), 16) & 1
            }
            routed = {
                line.split()[0]
                for line in Path("/proc/net/route").read_text().splitlines()[1:]
                if line.strip()
            }
            routes6 = Path("/proc/net/ipv6_route")
            routed6 = (
                {
                    line.split()[-1]
                    for line in routes6.read_text().splitlines()
                    if line.strip()
                }
                if routes6.exists()
                else set()
            )
            if (
                active <= {"lo"}
                and routed <= {"lo"}
                and routed6 <= {"lo"}
                and caps
                and not any(value & (1 << 12) for value in caps)
            ):
                return []
        if (
            shutil.which("unshare")
            and subprocess.run(
                ["unshare", "-n", "true"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            ).returncode
            == 0
        ):
            return ["unshare", "-n", "--"]
    raise GraphError(
        "No network-denied runtime; use source search. See setup reference."
    )


class Workspace:
    def __init__(self, repo, environment, state=None, excludes=()):
        self.repo = Path(
            os.fsdecode(git(repo, "rev-parse", "--show-toplevel")).strip()
        ).resolve()
        git_dir = Path(
            os.fsdecode(git(repo, "rev-parse", "--absolute-git-dir")).strip()
        ).resolve()
        self.state = (state or git_dir / "graphify-skill").resolve()
        self.environment = environment.resolve()
        if self.state == self.repo or (
            self.state.is_relative_to(self.repo)
            and not self.state.is_relative_to(git_dir)
        ):
            raise GraphError(
                "State must be outside source or inside checkout Git metadata."
            )
        if self.environment.is_relative_to(self.repo):
            raise GraphError("Tool environment must be outside the source checkout.")
        self.excludes = sorted(excludes)

    def claim(self):
        identity = {"checkout": str(self.repo)}
        owner = self.state / "owner.json"
        if owner.exists() and json.loads(owner.read_text()) != identity:
            raise GraphError("State belongs to another physical checkout.")
        write_json(owner, identity)
        (self.state / "logs").mkdir(exist_ok=True)

    def snapshot(self, destination=None):
        # Stage exactly the Git-visible regular files; never follow external symlinks.
        names = set(
            git(
                self.repo,
                "ls-files",
                "-z",
                "--cached",
                "--others",
                "--exclude-standard",
            ).split(b"\0")
        )
        files = {}
        for raw in sorted(names - {b""}):
            name = os.fsdecode(raw)
            if any(fnmatch.fnmatchcase(name, pattern) for pattern in self.excludes):
                continue
            source = self.repo / name
            if source.is_symlink() or any(
                p.is_symlink() for p in source.parents if p != self.repo
            ):
                raise GraphError(f"Symlink input requires explicit exclusion: {name}")
            if not source.exists():
                continue
            if not source.is_file():
                raise GraphError(f"Non-file input requires explicit exclusion: {name}")
            content = source.read_bytes()
            files[name] = hashlib.sha256(content).hexdigest()
            if destination:
                target = destination / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)
        python = self.environment / "bin/python"
        packages = subprocess.check_output(
            [
                str(python),
                "-c",
                "import importlib.metadata,json;print(json.dumps(sorted((d.metadata['Name'],d.version) for d in importlib.metadata.distributions())))",
            ]
        )
        return {
            "checkout": str(self.repo),
            "files": files,
            "excludes": self.excludes,
            "environment": str(self.environment),
            "packages": hashlib.sha256(packages).hexdigest(),
            "launcher": digest(Path(__file__)),
            "requirements": digest(
                Path(__file__).parents[1] / "references/requirements.txt"
            ),
        }

    def fresh(self):
        pointer = self.state / "current.json"
        if not pointer.exists():
            raise GraphError("No accepted graph; use source search or request refresh.")
        record = json.loads(pointer.read_text())
        generation = (self.state / "generations" / record["generation"]).resolve()
        if generation.parent != (self.state / "generations").resolve():
            raise GraphError("Invalid generation path.")
        graph = generation / "graph.json"
        if (
            record["input"] != self.snapshot()
            or not graph.is_file()
            or record["graph"] != digest(graph)
        ):
            raise GraphError("Graph is stale; use source search or request refresh.")
        return record, generation

    def run(self, args, generation, name):
        env = dict(os.environ)
        # Graph-only deterministic extraction; no model backend or project configuration.
        env.update(
            GRAPHIFY_BACKEND="none",
            GRAPHIFY_OUT=str(generation),
            GRAPHIFY_MAX_WORKERS="2",
            PYTHONHASHSEED="0",
        )
        log = self.state / "logs" / f"{time.time_ns()}-{name}.log"
        with log.open("wb") as stream:
            result = subprocess.run(
                [*offline(self.state), str(self.environment / "bin/graphify"), *args],
                cwd=generation / "source",
                env=env,
                stdout=stream,
                stderr=subprocess.STDOUT,
            )
        return result.returncode, log

    def refresh(self):
        offline(self.state)  # Fail before staging if enforcement is unavailable.
        generation = self.state / "generations" / uuid.uuid4().hex
        source = generation / "source"
        source.mkdir(parents=True)
        before = self.snapshot(source)
        # Fresh output every time: no graph, manifest, stat-index or AST cache reuse.
        code, log = self.run(
            ["extract", str(source), "--code-only", "--no-dedup", "--max-workers", "2"],
            generation,
            "refresh",
        )
        if code:
            sys.stdout.buffer.write(preview(log, code))
            return code
        graph = generation / "graph.json"
        if before != self.snapshot() or not graph.is_file():
            raise GraphError(
                f"Inputs changed or graph missing; prior generation preserved. Artifact: {log}"
            )
        write_json(
            self.state / "current.json",
            {"input": before, "generation": generation.name, "graph": digest(graph)},
        )
        sys.stdout.buffer.write(preview(log, code))
        return code

    def query(self, command, values):
        record, generation = self.fresh()
        args = [command, *values, "--graph", str(generation / "graph.json")]
        if command == "query":
            args += ["--depth", "1", "--budget", "1500"]
        code, log = self.run(args, generation, command)
        after, _ = self.fresh()
        if after != record:
            raise GraphError(
                f"Generation changed during query; output withheld at {log}"
            )
        sys.stdout.buffer.write(preview(log, code))
        return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--environment", type=Path, required=True)
    parser.add_argument("--state", type=Path)
    parser.add_argument("--exclude", action="append", default=[])
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("status", "refresh"):
        commands.add_parser(name)
    for name, count in (("query", 1), ("explain", 1), ("path", 2)):
        commands.add_parser(name).add_argument("values", nargs=count)
    args = parser.parse_args()
    try:
        workspace = Workspace(args.repo, args.environment, args.state, args.exclude)
        with locked(workspace.state):
            workspace.claim()
            if args.command == "status":
                _, generation = workspace.fresh()
                print(f"Fresh graph: {generation / 'graph.json'}")
                return 0
            if args.command == "refresh":
                return workspace.refresh()
            return workspace.query(args.command, args.values)
    except (
        GraphError,
        OSError,
        subprocess.CalledProcessError,
        ValueError,
        KeyError,
    ) as error:
        print(
            f"graphify: {error}\nFallback: rg / Serena on current source.",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())
