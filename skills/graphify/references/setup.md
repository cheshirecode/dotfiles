# Explicit setup and index maintenance

Provision an existing Python 3.12+ interpreter, Git and `uv` through the host's
normal tool management. Select a new external environment path, an installed
skill path and the target checkout. Do not silently download an interpreter.
These commands download pinned Graphify dependencies; run only for setup:

```sh
UV_PYTHON_DOWNLOADS=never uv venv --python "$python_executable" "$tool_env"
UV_PYTHON_DOWNLOADS=never uv pip sync --python "$tool_env/bin/python" \
  "$skill_dir/references/requirements.txt"
```

The lock pins Graphify to a source revision and dependencies to versions; it is
not a wheel/hash lock. `requirements.in` records direct dependency inputs. Use
a new environment for a requested upgrade and validate it before switching;
do not mutate an environment while another checkout uses it.

Graph operations enforce network denial: macOS uses `sandbox-exec`; Linux uses
`unshare -n` when permitted, or an existing namespace with only loopback active/routed and
without network-admin capabilities. A container launched with `--network none
--cap-drop ALL` is one option. Bind the checkout, skill, and separate tool
environment at stable paths and keep state private. Provision the container's
own Python dependencies in an explicit network-enabled setup phase; host venvs
are not portable across operating systems. Unsupported enforcement fails closed.

Choose corpus exclusions with the target owner. Then build and check:

```sh
python3 "$skill_dir/scripts/graph.py" --repo "$checkout" --environment "$tool_env" refresh
python3 "$skill_dir/scripts/graph.py" --repo "$checkout" --environment "$tool_env" status
```

Use the same `--exclude` arguments for both commands and future queries. No
project-local wrapper or configuration is required. Fresh generation extraction
intentionally forgoes cache reuse to avoid stale stat-based fast paths.

Validate a neutral disposable Git fixture before adoption: actual extraction and
query/path results; same-size restored-mtime mutation and rebuild; file deletion;
linked-worktree isolation; failed/interrupted refresh; concurrent state access;
network denial; oversized output and source-search fallback. Keep control tests
with a fake executable separate from actual Graphify runtime proof.

Serena is a separate capability: use its existing setup guidance when requested.
If configuring it alongside Graphify, isolate `SERENA_HOME` and project data per
physical checkout, pin the chosen language servers, and avoid switching projects
under fixed metadata. This skill installs no Serena or language-server packages.
