"""Context boundaries and scaffold profiles. No model or live service calls."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ContextTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="toolkit-context-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        binary = self.base / "bin"
        binary.mkdir()
        mock = binary / "opencode"
        mock.write_text('#!/bin/sh\n[ "$1" = --version ] || exit 99\necho "opencode 2.0.18"\n')
        mock.chmod(0o755)
        self.env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"])

    def init(self, target, *args):
        return subprocess.run(["bash", str(ROOT / "bin/init.sh"), "--target", str(target), *args],
                              env=self.env, capture_output=True, text=True, timeout=20)

    def project(self, profile, *args):
        target = self.base / profile
        target.mkdir()
        result = self.init(target, "--project-name", "context", "--leader", profile, *args)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return target

    @staticmethod
    def snapshot(target):
        return {str(p.relative_to(target)): p.read_bytes() for p in target.rglob("*") if p.is_file()}

    def test_selected_leaders_are_lean_self_contained_and_stamped(self):
        entrypoints = {"claude": ".claude/commands/feature.md",
                       "codex": ".agents/skills/feature/SKILL.md",
                       "opencode": ".opencode/commands/feature.md"}
        for profile, expected_count in (("claude", 26), ("codex", 26), ("opencode", 25)):
            with self.subTest(profile=profile):
                target = self.project(profile)
                files = self.snapshot(target)
                self.assertEqual(len(files) - 2, expected_count)  # stamp + customization marker
                stamp = target / ".agent-pipeline/.toolkit-version"
                self.assertIn(f"leader_tools:  {profile}\n", stamp.read_text())
                self.assertIn("extras:        none\n", stamp.read_text())
                for leader, entry in entrypoints.items():
                    self.assertEqual((target / entry).exists(), leader == profile)
                for extra in ("dashboard", "team.sh", "herdr-team.sh", "codex-lead.sh", "claude-review.sh"):
                    self.assertFalse((target / ".agent-pipeline/bin" / extra).exists())
                for role in ("leader", "planner", "implementer", "reviewer", "tester"):
                    self.assertTrue((target / f".agent-pipeline/roles/{role}.md").exists())
                self.assertTrue((target / ".opencode/agent/builder.md").exists())
                before = self.snapshot(target)
                self.assertEqual(self.init(target, "--update").returncode, 0)
                self.assertEqual(self.snapshot(target), before)
                (target / ".agent-pipeline/.needs-customization").unlink()
                self.assertEqual(self.init(target).returncode, 0)
                self.assertFalse((target / ".agent-pipeline/.needs-customization").exists())
                self.assertEqual(stamp.read_bytes(), before[".agent-pipeline/.toolkit-version"])

    def test_optional_extras_and_native_workers_only_add_needed_dependencies(self):
        target = self.project("opencode", "--extras", "herdr", "--reviewer-model", "claude/sonnet",
                              "--reviewer-fallback-model", "codex/review", "--tester-model", "codex/test")
        for path in (".agent-pipeline/bin/dashboard", ".agent-pipeline/bin/herdr-team.sh", ".agent-pipeline/bin/claude-review.sh",
                     ".claude/agents/reviewer.md", ".codex/agents/reviewer_fallback.toml",
                     ".codex/agents/tester.toml", ".agent-pipeline/adapters/claude.md",
                     ".agent-pipeline/adapters/codex.md"):
            self.assertTrue((target / path).is_file(), path)
        for path in (".agent-pipeline/bin/team.sh", ".codex/hooks.json", ".claude/commands/feature.md",
                     ".codex/agents/planner.toml", ".opencode/agent/reviewer.md", ".opencode/agent/tester.md"):
            self.assertFalse((target / path).exists(), path)
        self.assertEqual(self.init(target, "--update").returncode, 0)

    def test_launcher_extra_has_dashboard_and_capture_dependencies(self):
        target = self.project("codex", "--extras", "launcher")
        for path in (".agent-pipeline/bin/team.sh", ".agent-pipeline/bin/dashboard", ".agent-pipeline/bin/codex-lead.sh",
                     ".agent-pipeline/bin/codex-session.py", ".codex/hooks.json"):
            self.assertTrue((target / path).is_file(), path)
        self.assertFalse((target / ".agent-pipeline/bin/herdr-team.sh").exists())

    def test_profile_changes_preserve_files_customizations_and_baseline(self):
        target = self.project("all")
        local = target / ".claude/commands/feature.md"
        local.write_text(local.read_text() + "\nLOCAL RULE\n")
        before = self.snapshot(target)
        preview = self.init(target, "--update", "--leader", "opencode", "--extras", "none")
        self.assertEqual(preview.returncode, 1)  # portable README describes the new selection
        self.assertIn(".agent-pipeline/README.md", preview.stdout)
        self.assertEqual(self.snapshot(target), before)
        self.assertEqual(self.init(target, "--leader", "opencode", "--extras", "none").returncode, 0)
        self.assertEqual(self.snapshot(target), before)
        self.assertEqual(self.init(target, "--refresh-stamp", "--leader", "opencode", "--extras", "none").returncode, 0)
        self.assertEqual(local.read_bytes(), before[".claude/commands/feature.md"])
        self.assertIn("leader_tools:  opencode", (target / ".agent-pipeline/.toolkit-version").read_text())
        self.assertEqual((target / ".agent-pipeline/README.md").read_bytes(), before[".agent-pipeline/README.md"])
        self.assertEqual(self.init(target, "--update").returncode, 1)  # README still needs reviewed merge

    def test_legacy_stamps_keep_complete_installation(self):
        target = self.project("all")
        stamp = target / ".agent-pipeline/.toolkit-version"
        stamp.write_text("\n".join(line for line in stamp.read_text().splitlines()
                                   if not line.startswith(("leader_tools:", "extras:"))) + "\n")
        before = self.snapshot(target)
        self.assertEqual(self.init(target, "--update").returncode, 0)
        self.assertEqual(self.init(target).returncode, 0)
        self.assertEqual(self.snapshot(target), before)

    def test_unstamped_lean_recovery_does_not_expand_profile(self):
        target = self.project("codex", "--reviewer-model", "codex/review",
                              "--reviewer-fallback-model", "claude/sonnet", "--tester-model", "codex/test",
                              "--test-dir", "checks", "--extras", "launcher")
        stamp = target / ".agent-pipeline/.toolkit-version"
        stamp.unlink()
        before = self.snapshot(target)
        result = self.init(target, "--update")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.snapshot(target), before)
        self.assertFalse(stamp.exists())

    def test_invalid_profiles_write_nothing(self):
        target = self.base / "invalid"
        target.mkdir()
        for args in (("--leader", "openai"), ("--extras", "all,herdr"),
                     ("--extras", "dashboard,,herdr"), ("--extras", "herdr,")):
            self.assertNotEqual(self.init(target, "--project-name", "context", *args).returncode, 0)
            self.assertEqual(self.snapshot(target), {})

    def test_refresh_preserves_project_stamp_extensions_and_notes(self):
        target = self.project("all")
        stamp = target / ".agent-pipeline/.toolkit-version"
        extension = "\n# Approved project roster\nplanner_model: local/plan\nbuilder_fallback_model: local/build\n"
        stamp.write_text(stamp.read_text() + extension)
        self.assertEqual(self.init(target, "--refresh-stamp").returncode, 0)
        self.assertIn(extension, stamp.read_text())
        first = stamp.read_bytes()
        self.assertEqual(self.init(target, "--refresh-stamp").returncode, 0)
        self.assertEqual(first, stamp.read_bytes())

    def test_missing_legacy_fallback_does_not_select_new_provider(self):
        target = self.project("opencode")
        stamp = target / ".agent-pipeline/.toolkit-version"
        stamp.write_text("\n".join(line for line in stamp.read_text().splitlines()
                                   if not line.startswith("reviewer_fallback_model:")) + "\n")
        before = self.snapshot(target)
        preview = self.init(target, "--update")
        self.assertIn("keeping it disabled (none)", preview.stdout)
        self.assertEqual(before, self.snapshot(target))
        self.assertEqual(self.init(target, "--refresh-stamp").returncode, 0)
        self.assertIn("reviewer_fallback_model: none", stamp.read_text())

    def test_unstamped_ambiguous_fallback_requires_explicit_choice(self):
        target = self.project("opencode", "--reviewer-fallback-model", "none")
        stamp = target / ".agent-pipeline/.toolkit-version"
        stamp.unlink()
        leader = target / ".agent-pipeline/roles/leader.md"
        leader.write_text(leader.read_text().replace("reviewer fallback `none`", "fallback deliberately disabled"))
        before = self.snapshot(target)
        preview = self.init(target, "--update")
        self.assertNotEqual(preview.returncode, 0)
        self.assertIn("cannot recover reviewer fallback", preview.stderr)
        self.assertEqual(before, self.snapshot(target))

        explicit = self.init(target, "--update", "--reviewer-fallback-model", "none")
        self.assertNotIn("cannot recover reviewer fallback", explicit.stderr)
        self.assertEqual(before, self.snapshot(target))

    def test_unstamped_legacy_ambiguous_fallback_requires_explicit_choice(self):
        target = self.project("opencode", "--reviewer-fallback-model", "none")
        pipeline = target / ".agent-pipeline"
        (pipeline / ".toolkit-version").unlink()
        pipeline.rename(target / ".agents")
        legacy = target / ".agents"
        (legacy / "tasks/TEMPLATE.md").rename(legacy / "TEMPLATE.md")
        (legacy / "tasks").rmdir()
        leader = legacy / "roles/leader.md"
        leader.write_text(leader.read_text().replace("reviewer fallback `none`", "fallback deliberately disabled"))
        before = self.snapshot(target)
        preview = self.init(target, "--update")
        self.assertNotEqual(preview.returncode, 0)
        self.assertIn("cannot recover reviewer fallback", preview.stderr)
        self.assertEqual(before, self.snapshot(target))
        explicit = self.init(target, "--update", "--reviewer-fallback-model", "none")
        self.assertNotIn("cannot recover reviewer fallback", explicit.stderr)
        self.assertEqual(before, self.snapshot(target))

    def test_runtime_contract_word_budgets_and_role_boundaries(self):
        budgets = {"leader": 1150, "planner": 400, "implementer": 450, "reviewer": 450, "tester": 400}
        for role, budget in budgets.items():
            text = (ROOT / f"templates/pipeline/roles/{role}.md.tmpl").read_text()
            self.assertLessEqual(len(text.split()), budget, role)
            if role != "leader":
                self.assertNotIn("roles/leader.md", text)
                self.assertNotIn("adapters/", text)
        for backend in ("opencode", "claude", "codex"):
            self.assertLessEqual(len((ROOT / f"templates/pipeline/adapters/{backend}.md.tmpl").read_text().split()), 400)
        guidance = (ROOT / "templates/codex/AGENTS.md.tmpl").read_text()
        self.assertIn("Explicit worker assignment takes precedence", guidance)
        self.assertLessEqual(len(guidance.split()), 180)
        for role in ("builder", "reviewer", "tester"):
            text = (ROOT / f"templates/opencode/agent/{role}.md.tmpl").read_text().split("---", 2)[2]
            self.assertLessEqual(len(text.split()), 100)
            self.assertNotIn("roles/leader.md", text)

    def test_planner_does_not_load_historical_lead_context(self):
        for name in ("templates/opencode/agents/planner.md.tmpl",
                     "templates/claude/agents/planner.md.tmpl",
                     "templates/codex/agents/planner.toml.tmpl",
                     "templates/pipeline/roles/planner.md.tmpl"):
            text = (ROOT / name).read_text()
            self.assertNotIn("LEAD-HANDOFF.md", text, name)
            self.assertNotIn("roles/leader.md", text, name)

    def test_neutral_contract_links_resolve_without_other_harness_files(self):
        target = self.project("opencode")
        for path in target.rglob("*"):
            if path.is_file() and path.suffix == ".md":
                for reference in re.findall(r"\.agent-pipeline/(?:roles|adapters)/[a-z]+\.md", path.read_text()):
                    self.assertTrue((target / reference).is_file(), (path, reference))

    def test_refactor_does_not_change_opencode_permission_values(self):
        # Fingerprints of pre-refactor ordered permission blocks (comments
        # excluded). Any future intentional permission change needs live review
        # and explicit approval, not a context-cleanup update to this baseline.
        expected = {"builder": "bc99ab88778a2b20ef56d5375907415e12a209fe8d4d3b092f83e49dbbfcd82b",
                    "reviewer": "de4166a6f31342c6d133a3ba42d926608a7919f29803f52c97af1fcbc10b23b7",
                    "tester": "e282280bc578352fcb418eee44f58103bb8b21859977982bb1164606822ed8ca"}
        for role, digest in expected.items():
            front = (ROOT / f"templates/opencode/agent/{role}.md.tmpl").read_text().split("---", 2)[1]
            block = front[front.index("permission:"):]
            if role == "tester":
                # Approved major-layout narrowing: task grants no longer cover
                # executable bin/ or role contracts. Action/effect values stay.
                self.assertIn('".agent-pipeline/tasks/T-*.md": allow', block)
                self.assertNotIn('".agent-pipeline/**": allow', block)
                block = block.replace('.agent-pipeline/tasks/T-*.md', '.agent-pipeline/**')
            normalized = "\n".join(line.rstrip() for line in block.splitlines()
                                   if line.strip() and not line.lstrip().startswith("#"))
            self.assertEqual(hashlib.sha256(normalized.encode()).hexdigest(), digest, role)

    def test_migration_links_resolve_after_unreleased_consolidation(self):
        expected = {"01-delivery-contract.md", "02-artifact-layout.md",
                    "03-pipeline-directory.md", "04-team-upgrade.md"}
        self.assertEqual({p.name for p in (ROOT / "migrations").glob("*.md")}, expected)
        obsolete = ("04-role-sessions.md", "05-codex-workers.md",
                    "06-lead-resume-claude-review.md", "07-lean-context.md")
        for path in [ROOT / "README.md", ROOT / "CHANGELOG.md", *(ROOT / "docs").glob("*.md")]:
            text = path.read_text()
            for name in obsolete:
                self.assertNotIn(name, text, path)
            for reference in re.findall(r"\]\(((?:\.\./)*migrations/[^)#]+\.md)(?:#[^)]*)?\)", text):
                self.assertTrue((path.parent / reference).is_file(), (path, reference))

    def test_updater_preserves_selection_and_blocks_partial_dispatch(self):
        text = (ROOT / "templates/claude/commands/toolkit-update.md.tmpl").read_text()
        self.assertIn("Repeat approved", text)
        self.assertIn("stamp refresh", text)
        self.assertIn("Smaller profiles never delete", text)
        self.assertIn("Dependencies before entrypoint switches", text)
        self.assertIn("No dispatch while reconciliation is incomplete", text)

    def test_portable_readme_embeds_exact_leader_body_and_selected_team(self):
        target = self.project("opencode", "--reviewer-model", "claude/sonnet",
                              "--reviewer-fallback-model", "codex/review", "--tester-model", "codex/test")
        guide = (target / ".agent-pipeline/README.md").read_text()
        embedded = guide.split("<!-- BEGIN GENERATED LEADER CONTRACT -->", 1)[1].split(
            "<!-- END GENERATED LEADER CONTRACT -->", 1)[0].strip()
        leader = (target / ".agent-pipeline/roles/leader.md").read_text().split("\n", 1)[1].strip()
        self.assertEqual(embedded, leader)
        self.assertIn("Installed lead profile: **opencode**", guide)
        self.assertIn("Optional extras: **none**", guide)
        for assignment in ("claude/sonnet", "codex/review", "codex/test"):
            self.assertIn(assignment, guide)
        self.assertNotRegex(guide, r"__[A-Z_]+__")
        self.assertIn("Sharing a file grants no repository access", guide)
        self.assertIn("Keep this guide out of worker prompts", guide)
        self.assertIn("Missing planner/worker dispatch is a blocker", guide)
        self.assertLessEqual(len(guide.split()), 1900)
        for path in (ROOT / "templates").rglob("*.tmpl"):
            if path != ROOT / "templates/pipeline/README.md.tmpl":
                self.assertNotIn(".agent-pipeline/README.md", path.read_text(), path)
        self.assertEqual(self.init(target, "--update").returncode, 0)

    def test_portable_readme_bootstrap_preview_and_customization_are_additive(self):
        target = self.project("codex")
        guide = target / ".agent-pipeline/README.md"
        original = guide.read_bytes()
        guide.unlink()  # Simulate an older stamped scaffold without the new README.
        before = self.snapshot(target)
        result = self.init(target, "--update", "--only", ".agent-pipeline/README.md")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("new", result.stdout)
        self.assertEqual(self.snapshot(target), before)
        self.assertEqual(self.init(target).returncode, 0)
        self.assertEqual(guide.read_bytes(), original)
        guide.write_bytes(original + b"\nLOCAL TEAM RULE\n")
        customized = self.snapshot(target)
        self.assertEqual(self.init(target).returncode, 0)
        self.assertEqual(self.snapshot(target), customized)
        preview = self.init(target, "--update", "--only", ".agent-pipeline/README.md", "--diff")
        self.assertEqual(preview.returncode, 1)
        self.assertIn("LOCAL TEAM RULE", preview.stdout)
        self.assertEqual(self.snapshot(target), customized)


if __name__ == "__main__":
    unittest.main()
