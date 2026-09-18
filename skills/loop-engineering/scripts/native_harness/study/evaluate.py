"""Controller-owned checks with bounded subprocesses and immutable expected data."""

import json
from pathlib import Path
import sqlite3
import subprocess
import sys

from corpus import TASKS


PYTHON_DRIVER = """
import copy,json,sys
sys.dont_write_bytecode=True
sys.path.insert(0,'src')
try:
 import repair
 data=json.load(sys.stdin);before=copy.deepcopy(data)
 value=repair.run(data)
 assert data==before,'input mutated'
except Exception as e:value={'error':type(e).__name__}
print(json.dumps(value))
"""


def js_driver(task):
    body = task.driver or "return await require('./src/repair.cjs')(data);"
    return """
const fs=require('fs');const data=JSON.parse(fs.readFileSync(0,'utf8'));
const before=JSON.stringify(data);
(async()=>{try{const value=await (async()=>{BODY})();
 if(JSON.stringify(data)!==before)throw Error('input mutated');return value;
 }catch(e){return {error:e.name};}})().then(v=>process.stdout.write(JSON.stringify(v)));
""".replace("BODY", body)


def prepare(task, workspace, reference=False):
    workspace = Path(workspace)
    source = workspace / task.filename
    source.parent.mkdir(parents=True, exist_ok=True)
    source.write_text(task.reference if reference else task.broken)
    examples = [{"input": x, "expected": y} for x, y in task.cases[:2]]
    (workspace / "README.md").write_text(
        "# Repair contract\n\n"
        + task.contract
        + "\n\nEditable file: "
        + task.filename
        + "\n\nPublic examples:\n```json\n"
        + json.dumps(examples, indent=2)
        + "\n```\n"
    )
    if task.setup == "file-bytes":
        for name, data in {
            "data/a b.txt": b"abc",
            "data/x.txt": b"1234",
            "data/*": b"!",
            "-dash": b"xy",
        }.items():
            path = workspace / name
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(data)


def execute(task, workspace, data):
    if task.language == "sql":
        conn = sqlite3.connect(":memory:")
        try:
            conn.executescript(task.setup)
            for table, rows in data.items():
                if rows:
                    columns = ",".join("?" for _ in rows[0])
                    conn.executemany(
                        'INSERT INTO "' + table + '" VALUES (' + columns + ")", rows
                    )
            conn.commit()
            conn.execute("PRAGMA query_only=ON")
            steps = [0]

            def limit():
                steps[0] += 1
                return int(steps[0] > 1000)

            conn.set_progress_handler(limit, 1000)
            return [
                list(row)
                for row in conn.execute((Path(workspace) / task.filename).read_text())
            ]
        except sqlite3.Error as error:
            return {"error": type(error).__name__}
        finally:
            conn.close()
    if task.language == "python":
        command, input_text = [sys.executable, "-c", PYTHON_DRIVER], json.dumps(data)
    elif task.language == "javascript":
        command, input_text = ["node", "-e", js_driver(task)], json.dumps(data)
    else:
        command, input_text = ["/bin/bash", task.filename, *data["args"]], data["stdin"]
    try:
        result = subprocess.run(
            command,
            input=input_text,
            cwd=workspace,
            capture_output=True,
            text=True,
            timeout=3,
        )
        if task.language == "shell":
            return {"code": result.returncode, "stdout": result.stdout}
        if result.returncode:
            return {"process_exit": result.returncode}
        return json.loads(result.stdout)
    except (subprocess.TimeoutExpired, ValueError, OSError) as error:
        return {"evaluator_error": type(error).__name__}


def grade(task, workspace, public=False):
    cases = task.cases[:2] if public else task.cases
    checks = []
    for index, (data, expected) in enumerate(cases, 1):
        actual = execute(task, workspace, data)
        passed = json.dumps(actual, sort_keys=True) == json.dumps(
            expected, sort_keys=True
        )
        checks.append(
            {
                "name": task.name + ":case-" + str(index),
                "pass": passed,
                "actual": actual,
                "expected": expected,
            }
        )
    return {
        "checks": checks,
        "passed": sum(c["pass"] for c in checks),
        "total": len(checks),
        "success": bool(checks) and all(c["pass"] for c in checks),
    }


def calibrate(output):
    import tempfile

    rows = []
    for task in TASKS:
        with tempfile.TemporaryDirectory(prefix="study-control-") as temporary:
            prepare(task, temporary)
            broken = grade(task, temporary)
            prepare(task, temporary, reference=True)
            fixed = grade(task, temporary)
        rows.append(
            {
                "task": task.name,
                "language": task.language,
                "broken": broken,
                "reference": fixed,
            }
        )
    Path(output).write_text(json.dumps(rows, indent=2) + "\n")
    return rows


if __name__ == "__main__":
    rows = calibrate(sys.argv[1])
    bad = [
        r["task"]
        for r in rows
        if r["broken"]["success"] or not r["reference"]["success"]
    ]
    print(
        json.dumps(
            {
                "tasks": len(rows),
                "cases": sum(r["reference"]["total"] for r in rows),
                "invalid_controls": bad,
                "artifact": sys.argv[1],
            }
        )
    )
    raise SystemExit(bool(bad))
