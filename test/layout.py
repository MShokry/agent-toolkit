"""Major layout/schema migration regressions; no agents or live model calls."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    result = importlib.util.module_from_spec(spec)
    loader.exec_module(result)
    return result


records = module("task_records", ROOT / "templates/scripts/task-record.py.tmpl")
migration = module("layout_migration", ROOT / "bin/migrate-layout.py")


def table():
    return """**Status:** draft
**Class decided by:** pending
**Claude review approved:** off

## Role assignments

| Role | Backend | Model | Family | Session / thread |
| --- | --- | --- | --- | --- |
| planner | codex | codex/plan | openai | native_plan |
| implementer | opencode | a/build | openai | ses_build |
| reviewer | opencode | b/review | anthropic | ses_review |
| tester | opencode | a/test | openai | ses_test |
"""


class LayoutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="toolkit-layout-")
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name).resolve()

    def write(self, name, text):
        path = self.project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def snapshot(self):
        return {str(path.relative_to(self.project)): path.read_bytes()
                for path in self.project.rglob("*") if path.is_file()
                and not any(part.startswith(".layout-backup-") for part in path.parts)}

    def old_project(self):
        self.write(".agent-pipeline/TEMPLATE.md", "LOCAL TEMPLATE\n")
        self.write(".agent-pipeline/T-001.md", "**Status:** done\n[patch](logs/T-001/builder-1.patch)\n")
        self.write("scripts/oc.sh", '#!/bin/bash\nROOT="$(cd "$(dirname "$0")/.." && pwd)"\n# LOCAL RULE\n')
        (self.project / "scripts/oc.sh").chmod(0o755)
        self.write("scripts/user-owned.sh", "UNRELATED\n")
        self.write(".claude/commands/feature.md", "CUSTOM RULE\nRead .agent-pipeline/T-001.md; run scripts/oc.sh\n")
        self.write(".agents/skills/user/SKILL.md", "NATIVE SKILL\n")
        self.write(".agent-pipeline/.toolkit-version", "toolkit_sha: original\n")
        self.write(".agent-pipeline/.oc-password", "secret")
        (self.project / ".agent-pipeline/.oc-password").chmod(0o600)

    def test_plan_is_read_only_and_apply_preserves_customizations_and_provenance(self):
        self.old_project()
        before = self.snapshot()
        proposal = migration.plan(self.project)
        self.assertEqual(before, self.snapshot())
        with self.assertRaises(ValueError):
            migration.apply(self.project, proposal, "wrong", True)
        self.assertEqual(before, self.snapshot())
        backup = migration.apply(self.project, proposal, proposal["approval"], True)
        self.assertEqual(Path(backup).stat().st_mode & 0o777, 0o700)
        self.assertIn("LOCAL RULE", (self.project / ".agent-pipeline/bin/oc.sh").read_text())
        self.assertIn('/../.."', (self.project / ".agent-pipeline/bin/oc.sh").read_text())
        self.assertEqual((self.project / ".agent-pipeline/bin/oc.sh").stat().st_mode & 0o777, 0o755)
        self.assertEqual((self.project / ".agent-pipeline/.oc-password").stat().st_mode & 0o777, 0o600)
        self.assertIn("](../logs/", (self.project / ".agent-pipeline/tasks/T-001.md").read_text())
        for path in ("scripts/user-owned.sh", ".agent-pipeline/.toolkit-version", ".agent-pipeline/.oc-password",
                     ".agents/skills/user/SKILL.md"):
            self.assertEqual((self.project / path).read_bytes(), before[path])
        self.assertFalse((self.project / ".agent-pipeline/T-001.md").exists())
        self.assertFalse((self.project / "scripts/oc.sh").exists())
        self.assertEqual(migration.plan(self.project)["operations"], [])

    def test_collision_symlink_unknown_dispatch_and_legacy_artifact_fail_closed(self):
        self.old_project()
        collision = self.write(".agent-pipeline/tasks/T-001.md", "COLLISION")
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "collision"):
            migration.plan(self.project)
        self.assertEqual(before, self.snapshot())
        collision.unlink()
        link = self.project / ".agent-pipeline/tasks"
        link.rmdir()
        link.symlink_to(self.project / "scripts", target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            migration.plan(self.project)
        link.unlink()
        pending = self.project / ".agent-pipeline/logs/T-001/builder-1.dispatch"
        pending.mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, "active dispatch"):
            migration.plan(self.project)
        (pending / "exit").write_text("0")
        artifact = self.write(".agent-pipeline/T-001.request.md", "OLD ARTIFACT")
        with self.assertRaisesRegex(ValueError, "migration 02"):
            migration.plan(self.project)
        artifact.unlink()
        self.assertTrue(migration.plan(self.project)["operations"])

    def test_failed_apply_rolls_back_only_owned_changes(self):
        self.old_project()
        proposal = migration.plan(self.project)
        before = self.snapshot()
        original = migration.shutil.copy2
        calls = 0

        def fail_second_backup(source, target):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("injected backup failure")
            return original(source, target)

        with patch.object(migration.shutil, "copy2", fail_second_backup):
            with self.assertRaisesRegex(OSError, "injected"):
                migration.apply(self.project, proposal, proposal["approval"], True)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse((self.project / ".agent-pipeline/.layout-lock").exists())

    def test_native_skill_directory_alias_is_preserved_not_followed(self):
        self.old_project()
        alias = self.project / ".claude/skills/user"
        alias.parent.mkdir(parents=True)
        alias.symlink_to("../../.agents/skills/user", target_is_directory=True)
        proposal = migration.plan(self.project)
        self.assertFalse(any(".claude/skills/user/" in row["source"] for row in proposal["operations"]))
        migration.apply(self.project, proposal, proposal["approval"], True)
        self.assertEqual(os.readlink(alias), "../../.agents/skills/user")
        # Symlinked files that could otherwise be rewritten still fail closed.
        (self.project / ".claude/commands/alias.md").symlink_to("feature.md")
        with self.assertRaisesRegex(ValueError, "symlink"):
            migration.plan(self.project)

    def test_installed_native_dependencies_are_not_rewritten(self):
        self.old_project()
        dependency = self.write(".opencode/node_modules/package/README.md", "scripts/oc.sh\n")
        link = self.project / ".opencode/node_modules/.bin/tool"
        link.parent.mkdir()
        link.symlink_to("../package/README.md")
        proposal = migration.plan(self.project)
        self.assertFalse(any("node_modules" in row["source"] for row in proposal["operations"]))
        migration.apply(self.project, proposal, proposal["approval"], True)
        self.assertEqual(dependency.read_text(), "scripts/oc.sh\n")
        self.assertTrue(link.is_symlink())

    def test_changed_source_invalidates_reviewed_plan(self):
        self.old_project()
        proposal = migration.plan(self.project)
        self.write("scripts/oc.sh", "USER EDIT AFTER PLAN")
        updated = migration.plan(self.project)
        self.assertNotEqual(proposal["approval"], updated["approval"])
        before = self.snapshot()
        with self.assertRaises(ValueError):
            migration.apply(self.project, updated, proposal["approval"], True)
        self.assertEqual(before, self.snapshot())

    def test_unmoved_guidance_keeps_relative_links_and_plan_reports_leftovers(self):
        self.old_project()
        guide = self.write(".agent-pipeline/GUIDE.md", "[record](logs/T-001/builder-1.patch)\n")
        task = self.project / ".agent-pipeline/T-001.md"
        task.write_text(task.read_text() + "[patch]: logs/T-001/builder-1.patch\nBare prompts/T-001/builder-1.md\n")
        artifact = self.write(".agent-pipeline/T-001.build1.jsonl", "HISTORICAL TRANSCRIPT\n")
        proposal = migration.plan(self.project)
        paths = [row.get("path") for row in proposal["attention"]]
        self.assertIn(".agent-pipeline/T-001.build1.jsonl", paths)
        self.assertIn(".agent-pipeline/tasks/T-001.md", paths)
        self.assertTrue(any("scripts/user-owned.sh" in row.get("paths", []) for row in proposal["attention"]))
        migration.apply(self.project, proposal, proposal["approval"], True)
        self.assertEqual(guide.read_text(), "[record](logs/T-001/builder-1.patch)\n")
        self.assertEqual(artifact.read_text(), "HISTORICAL TRANSCRIPT\n")
        migrated = (self.project / ".agent-pipeline/tasks/T-001.md").read_text()
        self.assertIn("](../logs/", migrated)
        self.assertIn("[patch]: logs/", migrated)  # Explicit attention, not guessed syntax.

    def test_legacy_discovery_prose_survives_path_rewrite(self):
        old_gate = "Check old root\n  `.agent-pipeline/T-*.md`, and legacy `.agents/T-*.md`.\n"
        self.assertEqual(migration.rewrite(old_gate), old_gate)
        self.assertEqual(migration.rewrite("Read `.agent-pipeline/T-001.md`.\n"),
                         "Read `.agent-pipeline/tasks/T-001.md`.\n")

    def test_new_table_and_legacy_records_are_readable(self):
        self.assertEqual(set(records.assignments(table())), set(records.ROLES))
        self.assertIsNone(records.assignments("**OpenCode builder session id:** ses_old\n"))
        for role in records.ROLES:
            self.assertIn("pending", (ROOT / "templates/agents-state/TEMPLATE.md.tmpl").read_text())

    def test_internal_claude_agent_ids_are_not_external_reviewer_uuids(self):
        internal = table().replace("| planner | codex | codex/plan | openai | native_plan |",
                                   "| planner | claude | claude/sonnet | anthropic | agent_child123 |")
        self.assertIsNotNone(records.assignments(internal))
        external = internal.replace("| reviewer | opencode | b/review | anthropic | ses_review |",
                                    "| reviewer | claude | claude/sonnet | anthropic | agent_child123 |")
        with self.assertRaises(ValueError):
            records.assignments(external)

    def test_pending_class_attribution_only_passes_before_approval(self):
        binary = self.project / ".agent-pipeline/bin"
        binary.mkdir(parents=True)
        for name in ("verify-state.sh", "task-record.py"):
            (binary / name).write_bytes((ROOT / f"templates/scripts/{name}.tmpl").read_bytes())
        state = self.write(".agent-pipeline/tasks/T-001.md", table())
        command = ["bash", str(binary / "verify-state.sh"), "T-001"]
        first = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        state.write_text(table().replace("Status:** draft", "Status:** spec-approved"))
        second = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("pending after spec approval", second.stderr)
        state.write_text(state.read_text().replace("decided by:** pending", "decided by:** human"))
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)

    def test_invalid_tables_fail_closed(self):
        for invalid in (
            table().replace("ses_test", "ses_build"),
            table().replace("native_plan", "ses_wrong_backend"),
            table().replace("a/build", "codex/wrong_alias"),
            table().replace("b/review", "claude/wrong_backend"),
            table().replace("| tester | opencode | a/test | openai | ses_test |", ""),
            table() + "| tester | opencode | a/test | openai | ses_other |\n",
            table() + "**OpenCode reviewer session id:** ses_old\n",
        ):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    records.assignments(invalid)

    def test_new_schema_marker_prevents_accidental_legacy_downgrade(self):
        with self.assertRaisesRegex(ValueError, "missing Role assignments"):
            records.assignments("<!-- task-schema: 2 -->\n**Status:** draft\n")
        with self.assertRaisesRegex(ValueError, "unsupported"):
            records.assignments("<!-- task-schema: 3 -->\n" + table())
        self.assertIsNotNone(records.assignments("<!-- task-schema: 2 -->\n" + table()))

    def test_review_identity_and_claude_consent_are_required(self):
        evidence = "\n## Review verdicts\n### Pass 1 — today — verdict: PASS\n"
        self.assertIsNotNone(records.assignments(table() + evidence))
        for family in ("openai", "pending", "unknown"):
            with self.assertRaises(ValueError):
                records.assignments(table().replace("anthropic", family) + evidence)
        claude = table().replace("| reviewer | opencode | b/review | anthropic | ses_review |",
                                 "| reviewer | claude | claude/sonnet | anthropic | 11111111-1111-1111-1111-111111111111 |")
        with self.assertRaisesRegex(ValueError, "consent"):
            records.assignments(claude)
        self.assertIsNotNone(records.assignments(claude.replace("approved:** off", "approved:** on")))

    def record_command(self, operation, *args):
        return subprocess.run([sys.executable, str(ROOT / "templates/scripts/task-record.py.tmpl"), operation,
                               str(self.project / ".agent-pipeline/tasks/T-001.md"), "reviewer", "opencode", *args],
                              capture_output=True, text=True)

    def test_model_change_requires_a_fresh_role_binding(self):
        state = self.write(".agent-pipeline/tasks/T-001.md", table())
        self.assertNotEqual(self.record_command("session", "b/review").returncode, 0)
        result = self.record_command("bind", "b/review", "--session", "ses_review")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.record_command("session", "b/review").stdout.strip(), "ses_review")
        state.write_text(table().replace("b/review", "b/newmodel"))
        self.assertNotEqual(self.record_command("bind", "b/newmodel", "--session", "ses_review").returncode, 0)
        state.write_text(state.read_text().replace("ses_review", "ses_fresh"))
        self.assertEqual(self.record_command("bind", "b/newmodel", "--session", "ses_fresh").returncode, 0)
        self.assertEqual(self.record_command("session", "b/newmodel").stdout.strip(), "ses_fresh")


if __name__ == "__main__":
    unittest.main()
