#!/usr/bin/env python3
"""Herdr adapter contracts, with a fake CLI. No real panes or model calls."""

import contextlib
import copy
import importlib.util
import io
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
PLUGIN_ROOT = ROOT / "integrations/herdr"
SPEC = importlib.util.spec_from_file_location("herdr_plugin", PLUGIN_ROOT / "plugin.py")
plugin = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(plugin)


class FakeHerdr:
    def __init__(self, project):
        self.calls = []
        self.next_id = 2
        self.fail_board = False
        self.panes = {
            "w1:p1": {
                "pane_id": "w1:p1", "terminal_id": "term_lead", "workspace_id": "w1", "tab_id": "w1:t1",
                "cwd": str(project), "foreground_cwd": str(project / "src"), "agent": "opencode",
                "agent_status": "idle", "agent_session": {
                    "agent": "opencode", "source": "herdr:opencode", "kind": "id", "value": "ses_MixedCASE123",
                },
            },
        }

    def create_pane(self, cwd):
        pane_id = "w1:p" + str(self.next_id)
        self.next_id += 1
        pane = {"pane_id": pane_id, "terminal_id": "term_" + pane_id, "workspace_id": "w1",
                "tab_id": "w1:t1", "cwd": cwd}
        self.panes[pane_id] = pane
        return copy.deepcopy(pane)

    def __call__(self, *args):
        self.calls.append(args)
        if args[:2] == ("pane", "get"):
            if args[2] not in self.panes:
                raise plugin.PluginError("not_found")
            return {"pane": copy.deepcopy(self.panes[args[2]])}
        if args[:2] == ("agent", "get"):
            return {"agent": copy.deepcopy(self.panes[args[2]])}
        if args[:2] == ("pane", "list"):
            return {"panes": [copy.deepcopy(p) for p in self.panes.values() if p["workspace_id"] == args[3]]}
        if args[:2] == ("pane", "split"):
            return {"pane": self.create_pane(args[args.index("--cwd") + 1])}
        if args[:3] == ("plugin", "pane", "open"):
            if self.fail_board:
                raise plugin.PluginError("simulated board failure")
            return {"plugin_pane": {"pane": self.create_pane(args[args.index("--cwd") + 1])}}
        if args[:2] in (("pane", "report-metadata"), ("pane", "rename"), ("agent", "focus"), ("agent", "prompt")):
            return {"type": "ok"}
        raise AssertionError("Unexpected Herdr operation: " + repr(args))


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="toolkit-herdr-", dir=os.environ.get("TMPDIR"))
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.project = self.base / "project with 'quotes' and $spaces"
        (self.project / ".agents").mkdir(parents=True)
        (self.project / ".claude/commands").mkdir(parents=True)
        (self.project / ".opencode/agents").mkdir(parents=True)
        (self.project / "src").mkdir()
        (self.project / ".agents/TEMPLATE.md").write_text("template\n")
        (self.project / ".claude/commands/feature.md").write_text("canonical flow\n")
        (self.project / ".opencode/agents/leader.md").write_text("adapter\n")
        self.fake = FakeHerdr(self.project)
        self.env = {
            "HERDR_BIN_PATH": "/fake/herdr", "HERDR_SOCKET_PATH": str(self.base / "herdr.sock"),
            "HERDR_PLUGIN_STATE_DIR": str(self.base / "state"), "HERDR_PANE_ID": "w1:p1",
            "HERDR_WORKSPACE_ID": "w1", "HERDR_PLUGIN_CONTEXT_JSON": json.dumps({"focused_pane_id": "w1:p1"}),
        }
        env_patch = patch.dict(os.environ, self.env, clear=True)
        env_patch.start()
        self.addCleanup(env_patch.stop)
        api_patch = patch.object(plugin, "herdr", self.fake)
        api_patch.start()
        self.addCleanup(api_patch.stop)
        self.path = plugin.binding_path(self.project, "w1")

    def run_action(self, action, *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            plugin.main([action, *args])
        return output.getvalue()

    def binding(self):
        return json.loads(self.path.read_text())

    def test_adoption_never_launches_or_prompts_and_preserves_project(self):
        before = {p: p.read_bytes() for p in self.project.rglob("*") if p.is_file()}
        output = self.run_action("adopt")
        self.assertIn("No prompt or process launched", output)
        self.assertEqual(self.binding()["session"]["value"], "ses_MixedCASE123")
        self.assertEqual(self.binding()["project"], str(self.project))
        self.assertEqual([call[:2] for call in self.fake.calls],
                         [("pane", "get"), ("agent", "get"), ("pane", "report-metadata")])
        self.assertEqual(before, {p: p.read_bytes() for p in self.project.rglob("*") if p.is_file()})
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_context_target_takes_precedence_over_environment_pane(self):
        os.environ["HERDR_PANE_ID"] = "w9:p9"
        self.run_action("adopt")
        self.assertEqual(self.binding()["pane_id"], "w1:p1")

    def test_plugin_cwd_is_never_the_project_fallback(self):
        self.fake.panes["w1:p1"].pop("cwd")
        self.fake.panes["w1:p1"].pop("foreground_cwd")
        with self.assertRaisesRegex(plugin.PluginError, "No absolute project cwd"):
            self.run_action("adopt")
        self.assertFalse(self.path.exists())

    def test_unscaffolded_project_is_not_initialized(self):
        (self.project / ".agents/TEMPLATE.md").unlink()
        with self.assertRaisesRegex(plugin.PluginError, "never scaffolds"):
            self.run_action("adopt")
        self.assertFalse(self.path.exists())

    def test_explicit_wrong_project_is_rejected(self):
        other = self.base / "other"
        (other / ".agents").mkdir(parents=True)
        (other / ".claude/commands").mkdir(parents=True)
        (other / ".agents/TEMPLATE.md").write_text("template")
        (other / ".claude/commands/feature.md").write_text("flow")
        with self.assertRaisesRegex(plugin.PluginError, "different project"):
            self.run_action("adopt", "--project", str(other))

    def test_shell_or_unrecognized_agent_cannot_be_adopted(self):
        self.fake.panes["w1:p1"]["agent"] = None
        with self.assertRaisesRegex(plugin.PluginError, "recognized"):
            self.run_action("adopt")
        self.assertFalse(self.path.exists())

    def test_global_plugin_bindings_are_scoped_by_server_workspace_and_project(self):
        first = self.path
        self.assertNotEqual(first, plugin.binding_path(self.project, "w2"))
        self.assertNotEqual(first, plugin.binding_path(self.base, "w1"))
        os.environ["HERDR_SOCKET_PATH"] = str(self.base / "other.sock")
        self.assertNotEqual(first, plugin.binding_path(self.project, "w1"))

    def test_focus_uses_recorded_session_not_latest_worker(self):
        self.run_action("adopt")
        worker = self.fake.create_pane(str(self.project))
        worker.update(agent="opencode", agent_session={**self.binding()["session"], "value": "ses_NewestWorker"})
        self.fake.panes[worker["pane_id"]] = worker
        self.run_action("focus-leader")
        self.assertEqual(self.fake.calls[-1], ("agent", "focus", "w1:p1"))

    def test_native_restore_can_find_same_session_in_new_terminal(self):
        self.run_action("adopt")
        pane = self.fake.panes.pop("w1:p1")
        pane.update(pane_id="w1:p8", terminal_id="term_restored")
        self.fake.panes["w1:p8"] = pane
        os.environ["HERDR_PLUGIN_CONTEXT_JSON"] = json.dumps({"focused_pane_id": "w1:p8"})
        self.run_action("focus-leader")
        self.assertEqual(self.fake.calls[-1], ("agent", "focus", "w1:p8"))

    def test_replaced_session_is_not_focused_or_prompted(self):
        self.run_action("adopt")
        self.fake.panes["w1:p1"]["agent_session"]["value"] = "ses_replacement"
        for action in ("focus-leader", "brief-leader"):
            with self.assertRaisesRegex(plugin.PluginError, "missing, replaced, or ambiguous"):
                self.run_action(action)
        self.assertFalse(any(c[:2] in (("agent", "focus"), ("agent", "prompt")) for c in self.fake.calls))

    def test_ambiguous_native_session_requires_explicit_re_adoption(self):
        self.run_action("adopt")
        duplicate = copy.deepcopy(self.fake.panes["w1:p1"])
        duplicate.update(pane_id="w1:p2", terminal_id="term_copy")
        self.fake.panes["w1:p2"] = duplicate
        with self.assertRaisesRegex(plugin.PluginError, "ambiguous"):
            self.run_action("focus-leader")

    def test_sessionless_adoption_does_not_claim_safe_focus_or_prompt(self):
        self.fake.panes["w1:p1"].pop("agent_session")
        self.assertIn("identity is unavailable", self.run_action("adopt"))
        for action in ("focus-leader", "brief-leader"):
            with self.assertRaisesRegex(plugin.PluginError, "official Herdr agent integration"):
                self.run_action(action)

    def test_explicit_brief_sends_one_prompt_without_approval(self):
        self.run_action("adopt")
        self.run_action("brief-leader")
        prompts = [c for c in self.fake.calls if c[:2] == ("agent", "prompt")]
        self.assertEqual(len(prompts), 1)
        self.assertEqual(prompts[0][2], "w1:p1")
        self.assertIn(".opencode/agents/leader.md", prompts[0][3])
        self.assertIn("not a feature request, spec approval, auto-mode consent, or merge approval", prompts[0][3])
        self.assertIn("Do not dispatch work or modify files yet", prompts[0][3])

    def test_brief_refuses_working_blocked_and_unknown_states(self):
        self.run_action("adopt")
        for status in ("working", "blocked", "unknown"):
            self.fake.panes["w1:p1"]["agent_status"] = status
            with self.assertRaisesRegex(plugin.PluginError, "not idle"):
                self.run_action("brief-leader")
        self.assertFalse(any(c[:2] == ("agent", "prompt") for c in self.fake.calls))

    def test_claude_and_codex_briefing_reference_their_adapters(self):
        for kind in ("claude", "codex"):
            self.fake.panes["w1:p1"]["agent"] = kind
            if kind == "codex":
                skill = self.project / ".agents/skills/feature/SKILL.md"
                skill.parent.mkdir(parents=True)
                skill.write_text("Codex adapter")
            self.run_action("adopt")
            self.run_action("brief-leader")
            expected = ".agents/skills/feature/SKILL.md" if kind == "codex" else ".claude/commands/feature.md"
            self.assertIn(expected, self.fake.calls[-1][3])

    def test_missing_opencode_adapter_does_not_send_partial_brief(self):
        self.run_action("adopt")
        (self.project / ".opencode/agents/leader.md").unlink()
        with self.assertRaisesRegex(plugin.PluginError, "adapter is missing"):
            self.run_action("brief-leader")
        self.assertFalse(any(c[:2] == ("agent", "prompt") for c in self.fake.calls))

    def test_layout_requires_adoption(self):
        with self.assertRaisesRegex(plugin.PluginError, "run Adopt first"):
            self.run_action("layout")
        self.assertFalse(any(c[:2] == ("pane", "split") for c in self.fake.calls))

    def test_layout_is_idempotent_and_never_runs_commands_in_the_lead(self):
        self.run_action("adopt")
        self.run_action("layout")
        self.run_action("layout")
        self.assertEqual(sum(c[:2] == ("pane", "split") for c in self.fake.calls), 2)
        self.assertEqual(sum(c[:3] == ("plugin", "pane", "open") for c in self.fake.calls), 1)
        self.assertEqual(set(self.binding()["panes"]), {"workers", "server", "board"})
        self.assertFalse(any(c[:2] in (("pane", "run"), ("pane", "close"), ("agent", "start"), ("agent", "prompt")) for c in self.fake.calls))
        opens = [c for c in self.fake.calls if c[:3] == ("plugin", "pane", "open")]
        self.assertIn("AGENT_TOOLKIT_PROJECT=" + str(self.project), opens[0])
        self.assertEqual(self.fake.panes["w1:p1"]["terminal_id"], "term_lead")

    def test_partial_layout_failure_preserves_successful_panes_for_retry(self):
        self.run_action("adopt")
        self.fake.fail_board = True
        with self.assertRaisesRegex(plugin.PluginError, "simulated board failure"):
            self.run_action("layout")
        self.assertEqual(set(self.binding()["panes"]), {"workers", "server"})
        self.fake.fail_board = False
        self.run_action("layout")
        self.assertEqual(sum(c[:2] == ("pane", "split") for c in self.fake.calls), 2)

    def test_closed_support_pane_is_recreated_without_closing_other_panes(self):
        self.run_action("adopt")
        self.run_action("layout")
        worker = self.binding()["panes"]["workers"]["pane_id"]
        self.fake.panes.pop(worker)
        self.run_action("layout")
        self.assertEqual(sum(c[:2] == ("pane", "split") for c in self.fake.calls), 3)

    def test_concurrent_action_fails_cleanly_instead_of_duplicating_layout(self):
        self.run_action("adopt")
        with plugin.locked(self.path):
            with self.assertRaisesRegex(plugin.PluginError, "Another toolkit action"):
                self.run_action("layout")
        self.run_action("layout")

    def test_status_does_not_require_adoption_and_opens_only_the_board(self):
        self.run_action("status")
        self.assertFalse(self.path.exists())
        self.assertEqual(self.fake.calls[-1][:3], ("plugin", "pane", "open"))
        self.assertIn("--focus", self.fake.calls[-1])
        self.assertNotIn("--target-pane", self.fake.calls[-1])

    def test_split_board_keeps_its_explicit_target(self):
        plugin.open_board(self.project, "w1", "w1:p1", "split")
        call = self.fake.calls[-1]
        self.assertEqual(call[call.index("--target-pane") + 1], "w1:p1")

    def test_board_counts_only_ledger_rows_and_never_executes_verifiers(self):
        task = self.project / ".agents/T-001.md"
        task.write_text("""**Status:** blocked:question
**Latest handoff:** tester → needs human → next: lead
**Blocked since:** 2026-10-06 — missing environment
**Review loop count:** 1 / 2
### Acceptance criteria ledger
| AC | Met? | Reviewer evidence | Test evidence |
| AC1 | [x] | Pass 1 | Run 1 |
| AC2 | [ ] | | |
## Test results
| AC1 | [x] | a covering test, not the ledger |
""")
        output = self.run_action("board", "--project", str(self.project), "--once")
        self.assertIn("ledger 1/2 ticked (recorded)", output)
        self.assertIn("Herdr done/idle is NOT acceptance", output)
        self.assertIn("missing environment", output)
        self.assertEqual(self.fake.calls, [])

    def test_board_does_not_render_terminal_controls_or_external_task_links(self):
        (self.project / ".agents/T-001.md").write_text("**Status:** done\x1b]52;c;payload\x07\n")
        external = self.base / "secret.txt"
        external.write_text("do not expose this")
        (self.project / ".agents/T-999.md").symlink_to(external)
        output = plugin.board_text(self.project)
        self.assertNotIn("\x1b", output)
        self.assertNotIn("\x07", output)
        self.assertNotIn("do not expose this", output)
        self.assertIn("external symlink skipped", output)

    def test_empty_header_never_inherits_the_next_lines_value(self):
        text = "**Latest handoff:**\n**Status:** done\n"
        self.assertEqual(plugin.header(text, "Latest handoff"), "not recorded")
        self.assertEqual(plugin.header(text, "Status"), "done")

    def test_dashboard_summary_and_graph_are_model_independent(self):
        for number, status in enumerate(("draft", "testing", "done", "blocked:spec", "invented")):
            (self.project / (".agents/T-{}.md".format(number))).write_text(
                "# Task {}\n**Status:** {}\n**Latest handoff:** needs decision\n".format(number, status))
        output = plugin.board_text(self.project)
        self.assertIn("tasks: 5 | active: 2 | blocked: 1 | done: 1 | unknown: 1", output)
        self.assertIn("PLAN: 1", output)
        self.assertIn("TEST: 1", output)
        self.assertIn("PLAN -> APPROVAL -> BUILD -> REVIEW -> [TEST] -> DONE", output)
        self.assertIn("BLOCKERS / NEEDS ATTENTION", output)
        self.assertIn("! T-3 | blocked:spec", output)
        self.assertIn("? Unknown/unfilled status", output)
        self.assertEqual(self.fake.calls, [])

    def test_graph_does_not_guess_stage_for_blocked_or_unknown_status(self):
        for status in ("blocked:question", "blocked:spec", "not recorded", "draft | done"):
            self.assertNotIn("[", plugin.stage_graph(status))
        self.assertIn("[BUILD]", plugin.stage_graph("changes-requested"))
        self.assertIn("[APPROVAL]", plugin.stage_graph("spec-approved"))

    def test_dashboard_lists_task_state_only_not_artifacts(self):
        (self.project / ".agents/T-023.md").write_text("**Status:** testing\n")
        for relative in ("prompts/T-023/reviewer-1.md", "logs/T-023/T-fake.md",
                         "T-023.review-request.md", "TEAM.md", "TEMPLATE.md"):
            artifact = self.project / ".agents" / relative
            artifact.parent.mkdir(parents=True, exist_ok=True)
            artifact.write_text("**Status:** done\n")
        output = plugin.board_text(self.project)
        self.assertIn("tasks: 1 | active: 1", output)
        self.assertIn("T-023", output)
        self.assertNotIn("reviewer-1", output)
        self.assertNotIn("review-request", output)
        self.assertNotIn("T-fake", output)
        self.assertEqual(self.fake.calls, [])

    def test_dashboard_updates_from_files_and_wraps_for_narrow_panes(self):
        task = self.project / ".agents/T-live.md"
        task.write_text("**Status:** in-review\n")
        self.assertIn("[REVIEW]", plugin.board_text(self.project))
        task.write_text("**Status:** testing\n")
        output = plugin.board_text(self.project, width=40)
        self.assertIn("[TEST]", output)
        self.assertTrue(all(len(line) <= 40 for line in output.splitlines()))
        self.assertEqual(self.fake.calls, [])

    def test_visual_cards_have_stage_boxes_progress_and_semantic_colors(self):
        (self.project / ".agents/T-visual.md").write_text(
            "# T-visual — Example\n**Status:** testing\n**Owner right now:** tester\n"
            "### Acceptance criteria ledger\n| AC1 | [x] | evidence | evidence |\n| AC2 | [ ] | | |\n")
        rows = plugin.visual_lines(self.project, 100)
        output = "\n".join(text for text, _ in rows)
        self.assertIn("+----------+", output)
        self.assertIn("[TEST]", output)
        self.assertIn("Owner: tester", output)
        self.assertIn("1/2 recorded", output)
        self.assertIn("TASK CARDS", output)
        self.assertTrue(any(tone == "heading" for _, tone in rows))
        self.assertEqual(self.fake.calls, [])

    def test_visual_view_filters_blockers_and_fits_narrow_panes(self):
        for name, status in (("blocked", "blocked:question"), ("finished", "done")):
            (self.project / (".agents/T-" + name + ".md")).write_text(
                "**Status:** " + status + "\n**Latest handoff:** human decision needed\n")
        rows = plugin.visual_lines(self.project, 24, blocked_only=True)
        output = "\n".join(text for text, _ in rows)
        self.assertIn("T-blocked", output)
        self.assertNotIn("T-finished", output)
        self.assertTrue(all(len(text) <= 24 for text, _ in rows))
        self.assertTrue(any(tone == "warning" for _, tone in rows))
        self.assertEqual(self.fake.calls, [])

    def test_visual_cards_show_recorded_evidence_and_budget_attention(self):
        (self.project / ".agents/T-evidence.md").write_text(
            "# T-evidence — Useful title\n**Status:** testing\n"
            "**Review loop count:** 2 / 2\n**Test-fix loops:** 0 / 2\n**Spec bounces:** 0 / 1\n"
            "## Review verdicts\n### Pass 1 — date — verdict: CHANGES_REQUESTED\n"
            "### Pass 2 — date — verdict: PASS\n"
            "## Test results\n### Run 1 — date\n- Result: 4 passed\n"
            "### Run 2 — date\n- Result: 5 passed, 1 failed\n")
        rows = plugin.visual_lines(self.project, 100)
        output = "\n".join(text for text, _ in rows)
        self.assertIn("Review: PASS (pass 2)", output)
        self.assertIn("Latest test result: 5 passed, 1 failed", output)
        self.assertNotIn("Latest test result: 4 passed", output)
        self.assertTrue(any("Loops:" in text and tone == "attention" for text, tone in rows))
        self.assertTrue(any("T-evidence / testing" in text and tone == "review" for text, tone in rows))
        self.assertTrue(any("Review: PASS" in text and tone == "success" for text, tone in rows))
        self.assertEqual(self.fake.calls, [])

    def test_visual_cards_prioritize_attention_and_do_not_invent_evidence(self):
        for name, status in (("a-done", "done"), ("b-active", "in-progress"),
                             ("z-blocked", "blocked:question")):
            (self.project / (".agents/T-" + name + ".md")).write_text(
                "**Status:** " + status + "\n**Blocked since:** 2026-10-09 — needs scope\n"
                "## Review verdicts\n### Pass 1 — <date> — verdict: <PASS | CHANGES_REQUESTED>\n"
                "## Test results\n### Run 1 — <date>\n- Result:\n- Command: ignored\n")
        rows = plugin.visual_lines(self.project, 80)
        output = "\n".join(text for text, _ in rows)
        self.assertLess(output.index("T-z-blocked /"), output.index("T-b-active /"))
        self.assertLess(output.index("T-b-active /"), output.index("T-a-done /"))
        self.assertIn("Review: not recorded", output)
        self.assertIn("Latest test result: not recorded", output)
        self.assertIn("Waiting since: 2026-10-09", output)
        self.assertTrue(any("T-b-active /" in text and tone == "active" for text, tone in rows))
        self.assertTrue(any("T-a-done /" in text and tone == "success" for text, tone in rows))
        self.assertEqual(self.fake.calls, [])

    def test_interactive_board_selects_visual_ui_without_model_calls(self):
        with patch.object(plugin.sys.stdout, "isatty", return_value=True), \
                patch.object(plugin.sys.stdin, "isatty", return_value=True), \
                patch.dict(os.environ, {"TERM": "xterm-256color"}), \
                patch.object(plugin, "visual_board") as view:
            plugin.main(["board", "--project", str(self.project)])
        view.assert_called_once_with(self.project)
        self.assertEqual(self.fake.calls, [])

    def test_unreadable_task_does_not_crash_the_entire_board(self):
        (self.project / ".agents/T-001.md").mkdir()
        self.assertIn("unavailable (refresh to retry)", plugin.board_text(self.project))

    def test_invalid_context_and_unknown_binding_version_fail_closed(self):
        os.environ["HERDR_PLUGIN_CONTEXT_JSON"] = "[]"
        with self.assertRaisesRegex(plugin.PluginError, "must be an object"):
            self.run_action("adopt")
        os.environ["HERDR_PLUGIN_CONTEXT_JSON"] = "{}"
        self.run_action("adopt")
        state = self.binding()
        state["version"] = 99
        self.path.write_text(json.dumps(state))
        with self.assertRaisesRegex(plugin.PluginError, "Unsupported leader binding"):
            self.run_action("focus-leader")
        self.run_action("adopt")
        self.assertEqual(self.binding()["version"], 1)


class TransportTests(unittest.TestCase):
    def test_scaffolded_dashboard_is_self_contained_and_upgrade_is_additive(self):
        with tempfile.TemporaryDirectory(prefix="toolkit-dashboard-init-", dir=os.environ.get("TMPDIR")) as tmp:
            project = Path(tmp).resolve()
            init = ["bash", str(ROOT / "bin/init.sh"), "--target", str(project)]
            first = subprocess.run(init + ["--project-name", "dash", "--builder-model", "a/b",
                                           "--reviewer-model", "a/c", "--reviewer-fallback-model", "d/e",
                                           "--tester-model", "a/b"], capture_output=True, text=True, timeout=30)
            self.assertEqual(first.returncode, 0, first.stderr)
            dashboard = project / "scripts/dashboard"
            self.assertTrue(os.access(dashboard, os.X_OK))
            stamp = (project / ".agents/.toolkit-version").read_bytes()
            original = dashboard.read_bytes()
            (project / ".agents/T-001.md").write_text("**Status:** testing\n")
            # This copied artifact has no imports from the checkout or host.
            env = {"PATH": "/nonexistent", "TERM": "dumb"}
            view = subprocess.run([sys.executable, str(dashboard), "--once"], cwd=project,
                                  env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(view.returncode, 0, view.stderr)
            self.assertIn("T-001 — testing", view.stdout)
            dashboard.unlink()
            triage = subprocess.run(init + ["--update", "--only", "scripts/dashboard"],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(triage.returncode, 1, triage.stderr)
            self.assertIn("new      " + str(dashboard), triage.stdout)
            self.assertFalse(dashboard.exists())
            bootstrap = subprocess.run(init, capture_output=True, text=True, timeout=30)
            self.assertEqual(bootstrap.returncode, 0, bootstrap.stderr)
            self.assertEqual(dashboard.read_bytes(), original)
            self.assertEqual((project / ".agents/.toolkit-version").read_bytes(), stamp)
            dashboard.write_bytes(original + b"\n# project customization\n")
            customized = dashboard.read_bytes()
            rerun = subprocess.run(init, capture_output=True, text=True, timeout=30)
            self.assertEqual(rerun.returncode, 0, rerun.stderr)
            self.assertEqual(dashboard.read_bytes(), customized)
            drift = subprocess.run(init + ["--update", "--only", "scripts/dashboard"],
                                   capture_output=True, text=True, timeout=30)
            self.assertEqual(drift.returncode, 1, drift.stderr)
            self.assertIn("differs  " + str(dashboard), drift.stdout)
            self.assertEqual(dashboard.read_bytes(), customized)

    def test_standalone_command_discovers_nested_project_without_herdr(self):
        with tempfile.TemporaryDirectory(prefix="toolkit-dashboard-", dir=os.environ.get("TMPDIR")) as tmp:
            project = Path(tmp).resolve() / "project with spaces"
            (project / ".agents").mkdir(parents=True)
            (project / "src/nested").mkdir(parents=True)
            (project / ".agents/T-001.md").write_text("**Status:** testing\n")
            # No canonical prompts, scaffold template, or Herdr installation
            # is needed for a read-only standalone task viewer.
            env = {"PATH": "/nonexistent", "TERM": "dumb"}
            command = [sys.executable, str(ROOT / "bin/dashboard"), "--once"]
            result = subprocess.run(command, cwd=project / "src/nested", env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(str(project), result.stdout)
            self.assertIn("T-001 — testing", result.stdout)
            self.assertFalse(any(project.rglob("__pycache__")))
            explicit = subprocess.run(command + ["--project", str(project)], cwd=tmp, env=env,
                                      capture_output=True, text=True, timeout=10)
            self.assertEqual(explicit.returncode, 0, explicit.stderr)
            self.assertEqual(result.stdout, explicit.stdout)

    def test_standalone_command_reports_missing_task_directory_without_writes(self):
        with tempfile.TemporaryDirectory(prefix="toolkit-dashboard-empty-", dir=os.environ.get("TMPDIR")) as tmp:
            result = subprocess.run([sys.executable, str(ROOT / "bin/dashboard"), "--project", tmp, "--once"],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 2)
            self.assertIn("No .agents/ directory found", result.stderr)
            self.assertEqual(list(Path(tmp).iterdir()), [])

    def test_standalone_command_works_through_a_symlink(self):
        with tempfile.TemporaryDirectory(prefix="toolkit-dashboard-link-", dir=os.environ.get("TMPDIR")) as tmp:
            root = Path(tmp)
            (root / ".agents").mkdir()
            link = root / "dashboard"
            link.symlink_to(ROOT / "bin/dashboard")
            result = subprocess.run([sys.executable, str(link), "--once"], cwd=root,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("No task records yet", result.stdout)

    def test_uses_injected_binary_argv_and_preserves_literal_prompt(self):
        prompt = "don't execute `echo x` or $(anything)"
        with patch.dict(os.environ, {"HERDR_BIN_PATH": "/path with spaces/herdr"}), \
                patch.object(plugin.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, '{"result":{"type":"ok"}}', "")) as run:
            plugin.herdr("agent", "prompt", "w1:p1", prompt)
        self.assertEqual(run.call_args.args[0], ["/path with spaces/herdr", "agent", "prompt", "w1:p1", prompt])
        self.assertNotIn("shell", run.call_args.kwargs)
        self.assertEqual(run.call_args.kwargs["timeout"], 20)

    def test_timeout_and_json_error_never_trigger_a_retry(self):
        with patch.object(plugin.subprocess, "run", side_effect=subprocess.TimeoutExpired([], 20)) as run:
            with self.assertRaisesRegex(plugin.PluginError, "may have applied"):
                plugin.herdr("agent", "prompt", "w1:p1", "brief")
            self.assertEqual(run.call_count, 1)
        for stdout in ("not JSON", '{"error":{"code":"agent_blocked"}}', '{"result":null}'):
            with patch.object(plugin.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout, "")) as run:
                with self.assertRaises(plugin.PluginError):
                    plugin.herdr("agent", "prompt", "w1:p1", "brief")
                self.assertEqual(run.call_count, 1)

    def test_manifest_has_only_explicit_actions_and_no_automatic_hooks(self):
        try:
            import tomllib
        except ImportError:
            self.skipTest("Python <3.11 has no stdlib TOML parser; validate manifest with Herdr instead")
        manifest = tomllib.loads((PLUGIN_ROOT / "herdr-plugin.toml").read_text())
        self.assertEqual(manifest["id"], plugin.PLUGIN_ID)
        self.assertEqual(manifest["min_herdr_version"], "0.9.1")
        self.assertEqual(manifest["platforms"], ["linux", "macos"])
        self.assertFalse(any(key in manifest for key in ("build", "startup", "events")))
        actions = {action["id"] for action in manifest["actions"]}
        self.assertEqual(actions, {"adopt", "brief-leader", "layout", "status", "focus-leader"})
        for item in manifest["actions"]:
            self.assertEqual(item["command"][:2], ["python3", "plugin.py"])
        self.assertEqual(manifest["panes"][0]["command"][:2], ["python3", "-c"])
        self.assertIn("HERDR_PLUGIN_ROOT", manifest["panes"][0]["command"][2])

    def test_actual_board_entrypoint_runs_from_the_project_not_plugin_directory(self):
        try:
            import tomllib
        except ImportError:
            self.skipTest("Python <3.11 has no stdlib TOML parser")
        manifest = tomllib.loads((PLUGIN_ROOT / "herdr-plugin.toml").read_text())
        with tempfile.TemporaryDirectory(prefix="toolkit-herdr-pane-", dir=os.environ.get("TMPDIR")) as tmp:
            project = Path(tmp).resolve() / "project with spaces"
            (project / ".agents").mkdir(parents=True)
            (project / ".claude/commands").mkdir(parents=True)
            (project / ".agents/TEMPLATE.md").write_text("template")
            (project / ".claude/commands/feature.md").write_text("canonical flow")
            env = os.environ.copy()
            env.update(HERDR_PLUGIN_ROOT=str(PLUGIN_ROOT), AGENT_TOOLKIT_PROJECT=str(project))
            command = manifest["panes"][0]["command"] + ["--once"]
            result = subprocess.run(command, cwd=project, env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("No task records yet", result.stdout)
            self.assertIn(str(project), result.stdout)


if __name__ == "__main__":
    unittest.main()
