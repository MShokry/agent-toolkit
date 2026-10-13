"""Check an installed team read-only, and its runtime scripts in mocked copies.

Usage: python3 test/project.py --project /path/to/project
Never launches live workers, hooks, servers, or application/device tests.
"""
import argparse
import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
PROJECT = None


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


runtime = load("runtime_tests", ROOT / "test/runtime.py")


class InstalledRuntimeTests(runtime.RuntimeTests):
    def setUp(self):
        super().setUp()
        # Keep synthetic fixture config/credentials and mocked CLIs. Exercise
        # actual installed script bytes; test-specific fake workers stay fake.
        for name in ("oc.sh", "bg-dispatch.sh", "verify-models.sh", "codex-lead.sh",
                     "codex-session.py", "claude-review.sh", "herdr-team.sh", "task-record.py"):
            source = PROJECT / ".agent-pipeline/bin" / name
            if source.exists():
                shutil.copy2(source, self.pipeline / "bin" / name)


class InstalledContractTests(unittest.TestCase):
    def text(self, name):
        return (PROJECT / name).read_text()

    def test_central_layout_and_complete_contracts(self):
        self.assertFalse(list((PROJECT / ".agent-pipeline").glob("T-*.md")))
        self.assertFalse((PROJECT / ".agent-pipeline/TEMPLATE.md").exists())
        for role in ("leader", "planner", "implementer", "reviewer", "tester"):
            self.assertTrue((PROJECT / f".agent-pipeline/roles/{role}.md").is_file())
        self.assertIn("<!-- task-schema: 2 -->", self.text(".agent-pipeline/tasks/TEMPLATE.md"))
        self.assertIn("| Role | Backend | Model | Family | Session / thread |",
                      self.text(".agent-pipeline/tasks/TEMPLATE.md"))

    def test_guide_embeds_exact_leader_and_models(self):
        guide = self.text(".agent-pipeline/README.md")
        embedded = guide.split("<!-- BEGIN GENERATED LEADER CONTRACT -->", 1)[1].split(
            "<!-- END GENERATED LEADER CONTRACT -->", 1)[0].strip()
        self.assertEqual(embedded, self.text(".agent-pipeline/roles/leader.md").split("\n", 1)[1].strip())
        stamp = dict(re.findall(r"^([a-z_]+):\s*([^\n]+)", self.text(".agent-pipeline/.toolkit-version"), re.M))
        for key in ("builder_model", "reviewer_model", "reviewer_fallback_model", "tester_model"):
            self.assertIn("`" + stamp[key].strip() + "`", guide)
        self.assertNotRegex(guide, r"__[A-Z_]+__")

    def test_worker_context_is_not_lead_routing(self):
        entry = self.text("AGENTS.md")
        self.assertIn("CLAUDE.md", entry)
        self.assertNotRegex(entry, r"roles/leader\.md|invoke.*feature|For unassigned feature")
        for name, role in (("builder", "implementer"), ("reviewer", "reviewer"), ("tester", "tester")):
            body = self.text(f".opencode/agent/{name}.md").split("---", 2)[2]
            self.assertIn(f".agent-pipeline/roles/{role}.md", body)
            self.assertNotIn("roles/leader.md", body)
            self.assertNotIn(".agent-pipeline/README.md", body)
            self.assertLess(len(body.split()), 150)

    def test_reviewer_denies_and_narrow_state_grants(self):
        reviewer = self.text(".opencode/agent/reviewer.md").split("---", 2)[1]
        for action in ("edit", "write", "patch", "task"):
            self.assertRegex(reviewer, rf"(?m)^  {action}: deny$")
        tester = self.text(".opencode/agent/tester.md").split("---", 2)[1]
        self.assertEqual(tester.count('".agent-pipeline/tasks/T-*.md": allow'), 2)
        self.assertNotIn('".agent-pipeline/**": allow', tester)
        leader = self.text(".opencode/agents/leader.md").split("---", 2)[1]
        self.assertNotIn('resource: ".agent-pipeline/**"', leader)
        for folder in ("tasks", "prompts", "logs"):
            self.assertIn(f'resource: ".agent-pipeline/{folder}/**"', leader)

    def test_loop_ownership_and_approval_gates(self):
        leader = self.text(".agent-pipeline/roles/leader.md")
        for fragment in ("explicit spec approval", "silence", "Review loop count",
                         "Test-fix loops", "Spec bounces", "≤1", "≤2",
                         "Never merge, stage, commit, or push", "immutable binding"):
            self.assertIn(fragment, leader)
        self.assertIn("never the worker", leader)
        self.assertIn("never implement feature code", self.text(".agent-pipeline/README.md").lower())

    def test_script_syntax(self):
        import ast
        for path in (PROJECT / ".agent-pipeline/bin").iterdir():
            if path.suffix in (".sh", ".bash"):
                result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            elif path.suffix == ".py" or path.name == "dashboard":
                ast.parse(path.read_text(), filename=str(path))

    def test_structural_scripts_match_tested_upstream_bytes(self):
        for name in ("verify-state.sh", "verify-spec.sh", "task-record.py", "verify-models.sh",
                     "bg-dispatch.sh", "oc.sh", "codex-session.py", "codex-lead.sh", "claude-review.sh"):
            self.assertEqual((PROJECT / ".agent-pipeline/bin" / name).read_bytes(),
                             (ROOT / "templates/scripts" / (name + ".tmpl")).read_bytes(), name)

    def test_installed_dashboard_has_tested_numeric_sort(self):
        source = ROOT / "integrations/herdr/dashboard.py"
        installed = PROJECT / ".agent-pipeline/bin/dashboard"
        self.assertEqual(source.read_bytes(), installed.read_bytes())
        import importlib.machinery
        loader = importlib.machinery.SourceFileLoader("installed_dashboard", str(installed))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        dashboard = importlib.util.module_from_spec(spec)
        loader.exec_module(dashboard)
        records = [{"task": Path("T-2.md"), "status": "done"},
                   {"task": Path("T-10.md"), "status": "draft"}]
        self.assertEqual([row["task"].stem for row in dashboard.ordered_records(records)], ["T-10", "T-2"])
        self.assertEqual([row["task"].stem for row in dashboard.ordered_records(records, "number")], ["T-2", "T-10"])

    def test_findings_promotion_in_disposable_fixture(self):
        with tempfile.TemporaryDirectory(prefix="toolkit-project-findings-") as directory:
            root = Path(directory)
            binary = root / ".agent-pipeline/bin"
            tasks = root / ".agent-pipeline/tasks"
            binary.mkdir(parents=True); tasks.mkdir()
            source = PROJECT / ".agent-pipeline/bin/promote-findings.sh"
            shutil.copy2(source, binary)
            # Respect a docs-directory customization without assuming a project.
            docs = "Document" if "Document/" in source.read_text() else "docs"
            (root / docs).mkdir()
            document_path = root / docs / "Testing.md"
            document_path.write_text("# Testing\n")
            (tasks / "T-999.md").write_text("## Findings for docs\n"
                f"- [{docs}/Testing.md] Complete statement.\n"
                "- [../escape.md] must not escape\n## Open questions\nnone\n")
            command = ["bash", str(binary / "promote-findings.sh"), "T-999"]
            first = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            document = document_path.read_bytes()
            self.assertIn(b"Complete statement.", document)
            self.assertFalse((root / "escape.md").exists())
            subprocess.run(command, cwd=root, check=True, capture_output=True)
            self.assertEqual(document_path.read_bytes(), document)


def main():
    global PROJECT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    args = parser.parse_args()
    PROJECT = args.project.resolve(strict=True)
    suite = unittest.TestSuite()
    for case in (InstalledContractTests, InstalledRuntimeTests):
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(case))
    layout = load("installed_layout_tests", ROOT / "test/layout.py")
    layout.records = layout.module("installed_records", PROJECT / ".agent-pipeline/bin/task-record.py")
    layout.migration = layout.module("installed_migration", PROJECT / ".agent-pipeline/bin/migrate-layout.py")
    suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(layout.LayoutTests))
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    sys.exit(not result.wasSuccessful())


if __name__ == "__main__":
    main()
