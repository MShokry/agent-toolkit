#!/usr/bin/env python3
"""Plan/apply the major toolkit layout move. Standard library; no agent calls."""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import uuid

SCRIPTS = ("oc.sh", "bg-dispatch.sh", "verify-models.sh", "verify-state.sh",
           "verify-spec.sh", "promote-findings.sh", "team.sh", "team-completion.bash",
           "dashboard", "codex-lead.sh", "codex-session.py", "claude-review.sh", "herdr-team.sh")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe(root, path):
    if root not in path.parents:
        raise ValueError("path escapes project: " + str(path))
    for current in (path, *path.parents):
        if current == root:
            break
        if current.is_symlink():
            raise ValueError("symlink refused: " + str(current))


def rewrite(text, moved_task=False, moved_script=False):
    # Only known toolkit commands, never arbitrary project scripts/* or native
    # discovery directories. Native permission resources relocate, not widen.
    names = "|".join(re.escape(name) for name in SCRIPTS)
    text = re.sub(r"(?<!templates/)(?<!TEMPLATES/)(?<!bin/)scripts/(" + names + r")\b",
                  r".agent-pipeline/bin/\1", text)
    # Explicit legacy-discovery instructions must still recognize the old path.
    text = re.sub(r"(?P<legacy>\b(?:old root|legacy|historical root)\s*`?)?"
                  r"\.agent-pipeline/(?P<task>T-(?:[A-Za-z0-9_<*>-]+)\.md|TEMPLATE\.md)",
                  lambda match: match[0] if match["legacy"] else ".agent-pipeline/tasks/" + match["task"], text)
    for token in ("${ID}", "$TASK", "$TASK_ID"):
        text = text.replace(".agent-pipeline/" + token + ".md", ".agent-pipeline/tasks/" + token + ".md")
    if moved_task:
        # Artifact links are relative to task location. Leave project-root paths,
        # historic prose, and runtime artifacts themselves intact.
        text = re.sub(r"(?<=\]\()(?=prompts/|logs/)", "../", text)
    if moved_script:
        text = text.replace('$(dirname "$0")/.."', '$(dirname "$0")/../.."')
        text = text.replace("Path(__file__).resolve().parent.parent", "Path(__file__).resolve().parents[2]")
    return text


def plan(root):
    pipeline = root / ".agent-pipeline"
    safe(root, pipeline)
    if any((root / ".agents" / name).exists() for name in ("TEMPLATE.md", ".toolkit-version")):
        raise ValueError("apply published migration 03 first; never relocate native .agents/skills")
    if not pipeline.is_dir():
        raise ValueError("no scaffolded .agent-pipeline directory")
    for record in pipeline.glob("logs/**/*.dispatch"):
        if not (record / "exit").is_file():
            raise ValueError("unknown/active dispatch blocks migration: " + str(record))
    if list(pipeline.glob(".codex-lead-lock.*")):
        raise ValueError("a live/stale lead lock blocks migration; inspect inactivity explicitly")
    moves = {}
    for source in sorted(pipeline.glob("T-*.md")) + [pipeline / "TEMPLATE.md"]:
        if source.exists() or source.is_symlink():
            if source.name != "TEMPLATE.md" and not re.fullmatch(r"T-[A-Za-z0-9_-]+\.md", source.name):
                raise ValueError("legacy root artifact requires migration 02 first: " + source.name)
            moves[source] = pipeline / "tasks" / source.name
    for name in SCRIPTS:
        source = root / "scripts" / name
        if source.exists() or source.is_symlink():
            moves[source] = pipeline / "bin" / name
    sources = set(moves)
    for folder in (".claude", ".codex", ".opencode", ".agents/skills",
                   ".agent-pipeline/roles", ".agent-pipeline/adapters"):
        directory = root / folder
        safe(root, directory)
        if directory.exists():
            for current, folders, files in os.walk(directory, followlinks=False):
                # Native aliases and installed dependencies are not toolkit
                # configuration. Never traverse or rewrite them.
                folders[:] = [name for name in folders
                              if name not in {"node_modules", ".git", ".cache", "__pycache__", ".venv"}
                              and not (Path(current) / name).is_symlink()]
                for name in files:
                    path = Path(current) / name
                    if path.suffix in {".md", ".toml", ".json", ".jsonc"}:
                        safe(root, path)
                        if path.is_file():
                            sources.add(path)
    for name in ("AGENTS.md", "CLAUDE.md", ".agent-pipeline/README.md", ".agent-pipeline/update.md"):
        path = root / name
        safe(root, path)
        if path.is_file():
            sources.add(path)
    for path in pipeline.glob("*.md"):
        safe(root, path)
        if path.is_file():
            sources.add(path)  # Local core guidance/handoffs remain in place; update known references.
    operations, attention = [], []
    for path in sorted(pipeline.glob("T-*")):
        if path.is_file() and path not in moves:
            attention.append(dict(path=str(path.relative_to(root)),
                                  reason="Legacy artifact retained; review an explicit task/role mapping before migration 02 cleanup."))
    custom_scripts = sorted(str(path.relative_to(root)) for path in (root / "scripts").glob("*")
                            if path.is_file() and path.name not in SCRIPTS)
    if custom_scripts:
        attention.append(dict(paths=custom_scripts,
                              reason="Project scripts retained; inspect custom toolkit callers manually."))
    for source in sorted(sources):
        target = moves.get(source, source)
        safe(root, source)
        safe(root, target)
        if not source.is_file():
            raise ValueError("not a regular file: " + str(source))
        if target != source and target.exists():
            raise ValueError("destination collision: " + str(target))
        old = source.read_bytes()
        text = old.decode("utf-8")
        moved_task = target != source and target.parent == pipeline / "tasks"
        new = rewrite(text, moved_task,
                      source.parent == root / "scripts").encode()
        if moved_task:
            for number, line in enumerate(new.decode().splitlines(), 1):
                if re.search(r"(?<![A-Za-z0-9_/.-])(?:logs|prompts)/", line):
                    attention.append(dict(path=str(target.relative_to(root)), line=number,
                                          reason="Bare/reference-style artifact path needs human review; only inline Markdown links are relocated automatically."))
        if target != source or new != old:
            operations.append(dict(source=str(source.relative_to(root)), target=str(target.relative_to(root)),
                                   sha256=digest(old), result_sha256=digest(new), mode=source.stat().st_mode & 0o777,
                                   diff="\n".join(difflib.unified_diff(text.splitlines(), new.decode().splitlines(), n=1))))
    result = dict(project=str(root), operations=operations, attention=attention,
                  warning="Pause all readers/workers; inspect every diff. Layout only: reviewed upstream merges and new role-table adoption remain required.")
    result["approval"] = digest(json.dumps(result, sort_keys=True).encode())
    return result


def apply(root, proposal, approval, inactive):
    if not inactive or approval != proposal["approval"]:
        raise ValueError("apply requires --workers-inactive and --approve with the exact reviewed plan digest")
    if not proposal["operations"]:
        return None
    lock = root / ".agent-pipeline/.layout-lock"
    lock.mkdir()  # no automatic stale-lock removal
    backup = root / (".agent-pipeline/.layout-backup-" + uuid.uuid4().hex)
    completed = []
    try:
        backup.mkdir(mode=0o700)
        (backup / "plan.json").write_text(json.dumps(proposal, indent=2))
        for operation in proposal["operations"]:
            source, target = (root / operation[key] for key in ("source", "target"))
            safe(root, source)
            safe(root, target)
            old = source.read_bytes()
            if digest(old) != operation["sha256"]:
                raise ValueError("source changed after plan: " + str(source))
            new = rewrite(old.decode(), target != source and target.parent == root / ".agent-pipeline/tasks",
                          source.parent == root / "scripts").encode()
            saved = backup / operation["source"]
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, saved)
            if digest(saved.read_bytes()) != operation["sha256"]:
                raise ValueError("source changed during backup: " + str(source))
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_name(target.name + ".layout-" + uuid.uuid4().hex)
            with temporary.open("xb") as output:
                output.write(new)
            temporary.chmod(operation["mode"])
            if target != source:
                try:
                    os.link(temporary, target)  # atomic publication; never overwrite a collision
                finally:
                    temporary.unlink()
                completed.append(operation)
                if digest(source.read_bytes()) != operation["sha256"]:
                    raise ValueError("source changed before move; concurrent edit preserved")
                source.unlink()
            else:
                if digest(source.read_bytes()) != operation["sha256"]:
                    temporary.unlink()
                    raise ValueError("source changed before rewrite; concurrent edit preserved")
                os.replace(temporary, target)
                completed.append(operation)
        return str(backup)
    except BaseException:
        print("migration failed; retained backup/plan: " + str(backup), file=sys.stderr)
        # Restore only our known bytes. Never erase edits made concurrently by
        # someone else; retain backup/plan for explicit recovery in that case.
        for operation in reversed(completed):
            source, target = (root / operation[key] for key in ("source", "target"))
            if target.exists() and digest(target.read_bytes()) != operation["result_sha256"]:
                print("migration rollback preserved concurrent edit: " + str(target), file=sys.stderr)
                continue
            saved = backup / operation["source"]
            if target != source:
                if source.exists():
                    target.unlink(missing_ok=True)
                    continue
                shutil.copy2(saved, source)
                target.unlink(missing_ok=True)
            else:
                shutil.copy2(saved, source)
        raise
    finally:
        lock.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("plan", "apply"))
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--approve")
    parser.add_argument("--workers-inactive", action="store_true")
    args = parser.parse_args()
    if args.project.is_symlink():
        raise ValueError("project symlink refused")
    root = args.project.resolve(strict=True)
    proposal = plan(root)
    if args.operation == "plan":
        print(json.dumps(proposal, indent=2))
    else:
        backup = apply(root, proposal, args.approve, args.workers_inactive)
        print(json.dumps(dict(applied=len(proposal["operations"]), backup=backup,
                              next="Review/merge upstream contracts/scripts, bootstrap missing files, validate, then refresh provenance.")))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit("migrate-layout: " + str(error))
