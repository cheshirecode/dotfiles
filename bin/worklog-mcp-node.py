#!/usr/bin/env python3
"""Find a suitable user Node, or install a checksum-verified private Node 22 runtime."""
import argparse
import fcntl
import hashlib
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import uuid


def healthy(node):
    if not node or "codex-path" in str(node):
        return False
    npm = Path(node).parent / "npm"
    if not npm.exists() and not (str(node) == shutil.which("node") and shutil.which("npm")):
        return False
    try:
        return subprocess.run([str(node), "-e", "const [a,b]=process.versions.node.split('.').map(Number);process.exit(a>20||a===20&&b>=11?0:1)"],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def download(url, target, resume=False):
    print(f"worklog-mcp: downloading {target.name}", file=sys.stderr)
    continuation = ["--continue-at", "-"] if resume and target.exists() else []
    subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error", *continuation,
                    "--connect-timeout", "15", "--max-time", "600", url, "--output", str(target)],
                   check=True, timeout=620)


def resolve(managed=False):
    current = shutil.which("node")
    if not managed and healthy(current):
        return str(Path(current).absolute())
    base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "worklog-mcp"
    runtime = base / "node"
    base.mkdir(parents=True, exist_ok=True)
    with (base / "node-install.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if healthy(runtime / "bin/node"):
            return str(runtime / "bin/node")
        system = {"Darwin": "darwin", "Linux": "linux"}.get(platform.system())
        arch = {"arm64": "arm64", "aarch64": "arm64", "x86_64": "x64", "AMD64": "x64"}.get(platform.machine())
        if not system or not arch:
            raise ValueError("automatic Node setup supports macOS/Linux on arm64/x64; install Node >=20.11 and npm yourself")
        origin = "https://nodejs.org/dist/latest-v22.x/"
        with tempfile.TemporaryDirectory(prefix="node-setup-", dir=base) as tmp:
            tmp = Path(tmp)
            sums = tmp / "SHASUMS256.txt"
            download(origin + sums.name, sums)
            suffix = f"-{system}-{arch}.tar.xz"
            candidates = [line.split() for line in sums.read_text().splitlines() if line.endswith(suffix)]
            if len(candidates) != 1:
                raise ValueError("Node release manifest did not identify one runtime")
            expected, filename = candidates[0]
            if "/" in filename or not filename.startswith("node-v22."):
                raise ValueError("invalid Node release filename")
            # Keep partial archives across retries; verify the complete release
            # digest before extraction. A version URL cannot change mid-download.
            archive = base / filename
            version = filename.split("-")[1]
            download(f"https://nodejs.org/dist/{version}/{filename}", archive, resume=True)
            with archive.open("rb") as content:
                digest = hashlib.sha256()
                for chunk in iter(lambda: content.read(1024 * 1024), b""):
                    digest.update(chunk)
            if digest.hexdigest() != expected:
                archive.unlink()
                raise ValueError("Node checksum mismatch; runtime was not installed")
            unpacked = tmp / "runtime"
            unpacked.mkdir()
            subprocess.run(["tar", "-xJf", str(archive), "--strip-components=1", "-C", str(unpacked)], check=True)
            if not healthy(unpacked / "bin/node"):
                raise ValueError("downloaded Node runtime failed its health check")
            if runtime.exists():
                previous = base / ("node-previous-" + uuid.uuid4().hex)
                runtime.rename(previous)
            unpacked.rename(runtime)
            archive.unlink()
            print(f"worklog-mcp: installed private {filename.removesuffix('.tar.xz')}", file=sys.stderr)
        return str(runtime / "bin/node")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--managed", action="store_true", help="use the private runtime even when a suitable Node is on PATH")
    args = parser.parse_args()
    try:
        print(resolve(args.managed))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f"worklog-mcp: Node setup failed: {error}\n")
