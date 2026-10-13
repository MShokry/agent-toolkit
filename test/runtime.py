"""Worker lifecycle/catalog regressions. No real agent, daemon, or model calls."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[1]
OPENCODE = '''#!/usr/bin/env python3
import json, os, pathlib, sys
if sys.argv[1:] == ["--version"]:
    print("opencode 2.0.18")
    sys.exit(0)
assert sys.argv[1:4] == ["api", "GET", "/api/model"], sys.argv
assert sys.argv[sys.argv.index("--server") + 1] == os.environ["EXPECT_SERVER"]
assert sys.argv[sys.argv.index("--param") + 1] == "directory=" + os.environ["EXPECT_ROOT"]
assert os.environ.get("OPENCODE_PASSWORD") == os.environ["EXPECT_PASSWORD"]
calls = pathlib.Path(os.environ["CALLS"])
with calls.open("a") as f:
    f.write("call\\n")
if os.environ.get("API_FAIL"):
    sys.exit(1)
if os.environ.get("COLD") and len(calls.read_text().splitlines()) == 1:
    print('{"data": []}')
else:
    print(pathlib.Path(os.environ["MOCK_CATALOG"]).read_text())
'''
WORKER = '''#!/usr/bin/env python3
import pathlib, sys, time
args = sys.argv[1:]
mode = args[args.index("--model") + 1]
raw = pathlib.Path(args[args.index("--raw-out") + 1])
with raw.open("x") as f:
    f.write("retained transcript\\n")
print("oc.sh: session=ses_example", file=sys.stderr, flush=True)
if mode == "slow-fail":
    time.sleep(1)
print("worker reply", flush=True)
if mode != "success":
    print("worker failed", file=sys.stderr)
    sys.exit(7)
'''
CODEX = '''#!/usr/bin/env python3
import os, sys
assert sys.argv[1:] == ["debug", "models"], sys.argv
if not os.environ.get("MOCK_CODEX_MODELS"):
    sys.exit(1)
print(os.environ["MOCK_CODEX_MODELS"])
'''


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="toolkit-runtime-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.project = self.base / "project"
        self.project.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.write_executable(self.bin / "opencode", OPENCODE)
        self.write_executable(self.bin / "codex", CODEX)
        self.write_executable(self.bin / "timeout", '#!/usr/bin/env bash\n[ "$1" = 10 ] || exit 90\nshift\nexec "$@"\n')
        self.catalog = self.base / "catalog.json"
        self.calls = self.base / "calls"
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        EXPECT_SERVER="http://localhost:4567", EXPECT_PASSWORD="local-test-password",
                        EXPECT_ROOT=str(self.project), MOCK_CATALOG=str(self.catalog), CALLS=str(self.calls))
        for key in ("OC_SERVER", "OC_PASSWORD", "OPENCODE_PASSWORD", "API_FAIL", "COLD", "MOCK_CODEX_MODELS"):
            self.env.pop(key, None)
        result = self.run_command("bash", str(ROOT / "bin/init.sh"), "--target", str(self.project),
                                  "--project-name", "runtime", "--builder-model", "a/b",
                                  "--reviewer-model", "a/c", "--reviewer-fallback-model", "d/e",
                                  "--tester-model", "a/b")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.pipeline = self.project / ".agent-pipeline"
        (self.pipeline / ".oc-port").write_text("4567")
        (self.pipeline / ".oc-password").write_text("local-test-password")
        self.rows = [dict(providerID=p, modelID=m, enabled=True, variants=[{"id": "high"}])
                     for p, m in [("a", "b"), ("a", "c"), ("d", "e")]]
        self.save_catalog()

    @staticmethod
    def write_executable(path, text):
        path.write_text(text)
        path.chmod(0o755)

    def run_command(self, *args, cwd=None):
        return subprocess.run(args, cwd=cwd or self.project, env=self.env,
                              capture_output=True, text=True, timeout=15)

    def save_catalog(self):
        self.catalog.write_text(json.dumps({"data": self.rows}))

    def verify(self):
        return self.run_command(".agent-pipeline/bin/verify-models.sh")

    def test_explicitly_disabled_reviewer_fallback_is_not_a_model(self):
        self.change_model("reviewer_fallback_model: d/e", "reviewer_fallback_model: none")
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_shell_completion_keeps_candidates_and_resets_empty_results(self):
        self.write_executable(self.bin / "tmux", '#!/bin/bash\nprintf "team-one\\nteam-two\\n"\n')
        script = '''source "$1"
COMP_WORDS=(team.sh --lead o); COMP_CWORD=2
_team_sh_complete
printf '%s\\n' "${COMPREPLY[@]}"
COMP_WORDS=(team.sh --kill team-); COMP_CWORD=2
_team_sh_complete
printf '%s\\n' "${COMPREPLY[@]}"
COMP_WORDS=(team.sh --fr); COMP_CWORD=1
_team_sh_complete
printf '%s\\n' "${COMPREPLY[@]}"
COMP_WORDS=(team.sh unmatched); COMP_CWORD=1
_team_sh_complete
[ "${#COMPREPLY[@]}" -eq 0 ]
'''
        result = self.run_command("bash", "-c", script, "completion-test",
                                  str(self.pipeline / "bin/team-completion.bash"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["opencode", "team-one", "team-two", "--fresh"])

    def change_model(self, old, new):
        path = self.pipeline / ".toolkit-version"
        path.write_text(path.read_text().replace(old, new))

    def bg(self, operation, label, *args, cwd=None):
        return self.run_command(str(self.project / ".agent-pipeline/bin/bg-dispatch.sh"), operation,
                                "T-001", label, *args, cwd=cwd)

    def start(self, label, model="success", cwd=None):
        self.write_executable(self.project / ".agent-pipeline/bin/oc.sh", WORKER)
        prompts = self.pipeline / "prompts/T-001"
        prompts.mkdir(parents=True, exist_ok=True)
        (prompts / (label + ".md")).write_text("literal task prompt")
        return self.bg("start", label, "--", ".agent-pipeline/bin/oc.sh", "--agent", label.rsplit("-", 1)[0],
                       "--model", model, "--text", "--prompt-file",
                       f".agent-pipeline/prompts/T-001/{label}.md", "--raw-out",
                       f".agent-pipeline/logs/T-001/{label}.jsonl", cwd=cwd)

    def test_catalog_auth_and_all_four_ids(self):
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("4 OpenCode worker ids", result.stdout)
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)

    def install_lead_mock(self):
        self.write_executable(self.bin / "codex", '''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
if sys.argv[1:] == ["resume", "--help"]:
    print("--no-daemon")
    sys.exit(0)
with open(os.environ["CALLS"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
if os.environ.get("LEAD_FAIL"):
    sys.exit(7)
if not os.environ.get("NO_CAPTURE"):
    root = os.environ["TEAM_CODEX_ROOT"]
    session = sys.argv[-1] if sys.argv[1] == "resume" else "lead_exact"
    event = dict(hook_event_name="SessionStart", session_id=session, cwd=root)
    subprocess.run([sys.executable, root + "/.agent-pipeline/bin/codex-session.py"],
                   input=json.dumps(event), text=True, check=True)
''')

    def test_exact_codex_lead_resume_fresh_and_failure(self):
        self.install_lead_mock()
        launch = lambda *args: self.run_command(".agent-pipeline/bin/codex-lead.sh", "my-team", *args)
        self.assertEqual(launch().returncode, 0)
        pin = self.pipeline / ".codex-session-id.my-team"
        self.assertEqual(pin.read_text().strip(), "lead_exact")
        self.assertEqual(launch().returncode, 0)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls, [["--no-daemon"], ["resume", "--no-daemon", "lead_exact"]])
        self.env["LEAD_FAIL"] = "1"
        self.assertEqual(launch().returncode, 7)
        self.assertEqual(pin.read_text().strip(), "lead_exact")
        self.env.pop("LEAD_FAIL")
        self.assertEqual(launch("--fresh").returncode, 0)
        self.assertEqual(json.loads(self.calls.read_text().splitlines()[-1]), ["--no-daemon"])

    def test_missing_codex_capture_blocks_ambiguous_restart(self):
        self.install_lead_mock()
        self.env["NO_CAPTURE"] = "1"
        first = self.run_command(".agent-pipeline/bin/codex-lead.sh", "missing")
        self.assertNotEqual(first.returncode, 0)
        self.assertIn("not captured", first.stderr)
        calls = self.calls.read_bytes()
        second = self.run_command(".agent-pipeline/bin/codex-lead.sh", "missing")
        self.assertIn("prior launch has no captured id", second.stderr)
        self.assertEqual(calls, self.calls.read_bytes())

    def test_codex_capture_cannot_replace_lead_with_worker_or_other_project(self):
        lock = self.pipeline / ".codex-lead-lock.capture"
        lock.mkdir()
        self.env.update(TEAM_CODEX_SESSION="capture", TEAM_CODEX_ROOT=str(self.project))
        def capture(session, cwd=None):
            return subprocess.run(["python3", ".agent-pipeline/bin/codex-session.py"], cwd=self.project,
                                  env=self.env, input=json.dumps(dict(hook_event_name="SessionStart",
                                  session_id=session, cwd=str(cwd or self.project))),
                                  text=True, capture_output=True)
        self.assertEqual(capture("lead_exact").returncode, 0)
        self.assertEqual(capture("lead_exact").returncode, 0)
        self.assertEqual(capture("worker_other").returncode, 2)
        self.assertEqual(capture("lead_exact", self.base).returncode, 2)
        self.assertEqual((self.pipeline / ".codex-session-id.capture").read_text().strip(), "lead_exact")
        lock.rmdir()
        self.assertEqual(capture("lead_exact").returncode, 2)

    def install_claude_review_mock(self):
        result = self.run_command("bash", str(ROOT / "bin/init.sh"), "--target", str(self.project),
                                  "--reviewer-model", "claude/sonnet")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.change_model("a/c", "claude/sonnet")
        self.write_executable(self.bin / "timeout", '#!/usr/bin/env bash\nshift\nexec "$@"\n')
        self.write_executable(self.bin / "claude", '''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
assert args[args.index("--tools") + 1] == "Read,Grep,Glob"
assert args[args.index("--permission-mode") + 1] == "dontAsk"
assert "--strict-mcp-config" in args
assert "--dangerously-skip-permissions" not in args
assert "--continue" not in args
with open(os.environ["CALLS"], "a") as log:
    log.write(json.dumps(args) + "\\n")
print(os.environ.get("CLAUDE_RESULT", json.dumps(dict(type="result", subtype="success",
      is_error=False, session_id=args[args.index("--resume") + 1] if "--resume" in args else args[args.index("--session-id") + 1], result=os.environ.get("CLAUDE_TEXT", "VERDICT: PASS\\nnone")))))
sys.exit(int(os.environ.get("CLAUDE_EXIT", "0")))
''')
        (self.pipeline / "tasks/T-001.md").write_text("**Status:** draft\n**Claude review approved:** on\n")
        prompts = self.pipeline / "prompts/T-001"
        prompts.mkdir(parents=True)
        (prompts / "reviewer-1.md").write_text("Read the task and current linked patch.")

    def claude_review(self, pass_number=1, *extra):
        prompts = self.pipeline / "prompts/T-001"
        (prompts / f"reviewer-{pass_number}.md").write_text("Read the task and current linked patch.")
        return self.run_command(".agent-pipeline/bin/claude-review.sh", "--model", "claude/sonnet",
                                "--prompt-file", f".agent-pipeline/prompts/T-001/reviewer-{pass_number}.md",
                                "--raw-out", f".agent-pipeline/logs/T-001/reviewer-{pass_number}.jsonl", *extra)

    def test_claude_review_consent_and_immutable_artifacts(self):
        self.install_claude_review_mock()
        state = self.pipeline / "tasks/T-001.md"
        state.write_text(state.read_text().replace("on", "off"))
        self.assertIn("requires recorded task approval", self.claude_review().stderr)
        self.assertFalse(self.calls.exists())
        state.write_text(state.read_text().replace("off", "on"))
        result = self.claude_review()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "VERDICT: PASS\nnone")
        raw = self.pipeline / "logs/T-001/reviewer-1.jsonl"
        original = raw.read_bytes()
        self.assertNotEqual(self.claude_review().returncode, 0)
        self.assertEqual(raw.read_bytes(), original)
        session = re.search(r"session=([a-f0-9-]+)", result.stderr)[1]
        self.assertIn("invalid reviewer assignment", self.claude_review(2, "--session", session).stderr)
        state.write_text(state.read_text() + f"**Claude reviewer session id:** {session}\n")
        self.assertEqual(self.claude_review(2, "--session", session).returncode, 0)

    def test_claude_review_failure_and_verdict_validation(self):
        self.install_claude_review_mock()
        for number, payload in enumerate(("not JSON", json.dumps(dict(type="result", subtype="success",
            result="no verdict")), json.dumps(dict(type="result", subtype="error", is_error=True,
            result="VERDICT: PASS"))), 1):
            self.env["CLAUDE_RESULT"] = payload
            self.assertNotEqual(self.claude_review(number).returncode, 0)
            self.assertTrue((self.pipeline / f"logs/T-001/reviewer-{number}.jsonl").exists())
        self.env.pop("CLAUDE_RESULT")
        self.env["CLAUDE_EXIT"] = "7"
        self.assertEqual(self.claude_review(4).returncode, 7)

    def test_claude_changes_requested_is_a_verdict_not_a_dispatch_failure(self):
        self.install_claude_review_mock()
        self.env["CLAUDE_TEXT"] = "VERDICT: CHANGES_REQUESTED\n1. [high] broken requirement"
        result = self.claude_review()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.env["CLAUDE_TEXT"])
        session = re.search(r"session=([a-f0-9-]+)", result.stderr)[1]
        state = self.pipeline / "tasks/T-001.md"
        state.write_text(state.read_text() + f"**Claude reviewer session id:** {session}\n")
        model_record = self.pipeline / f"logs/T-001/claude-review-session.{session}.model"
        model_record.write_text("claude/other-model\n")
        self.assertIn("model changed", self.claude_review(2, "--session", session).stderr)

    def test_codex_stale_lock_and_symlink_pin_fail_before_launch(self):
        self.install_lead_mock()
        lock = self.pipeline / ".codex-lead-lock.locked"
        lock.mkdir()
        result = self.run_command(".agent-pipeline/bin/codex-lead.sh", "locked")
        self.assertIn("stale lock", result.stderr)
        self.assertFalse(self.calls.exists())
        pin = self.pipeline / ".codex-session-id.linked"
        pin.symlink_to(self.catalog)
        result = self.run_command(".agent-pipeline/bin/codex-lead.sh", "linked", "--fresh")
        self.assertIn("must not be a symlink", result.stderr)
        self.assertTrue(pin.is_symlink())
        self.assertFalse(self.calls.exists())

    def test_existing_codex_hooks_are_not_overwritten(self):
        hooks = self.project / ".codex/hooks.json"
        parsed = json.loads(hooks.read_text())
        self.assertEqual(set(parsed["hooks"]), {"SessionStart", "UserPromptSubmit"})
        hooks.write_text('{"hooks":{"Stop":[]},"description":"local"}\n')
        original = hooks.read_bytes()
        rerun = self.run_command("bash", str(ROOT / "bin/init.sh"), "--target", str(self.project))
        self.assertEqual(rerun.returncode, 0)
        preview = self.run_command("bash", str(ROOT / "bin/init.sh"), "--update", "--target", str(self.project))
        self.assertEqual(preview.returncode, 1)
        self.assertIn("hooks.json", preview.stdout)
        self.assertEqual(hooks.read_bytes(), original)

    def install_herdr_mock(self):
        self.env.update(HERDR_BIN_PATH=str(self.bin / "herdr"), HERDR_PANE_ID="w1:p1", HERDR_WORKSPACE_ID="w1")
        self.write_executable(self.bin / "herdr", '''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["CALLS"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
if sys.argv[1:3] == ["pane", "get"]:
    print(json.dumps(dict(result=dict(pane=dict(workspace_id="w1",
          cwd=os.environ.get("MOCK_HERDR_CWD", os.environ["EXPECT_ROOT"]))))))
else:
    print(json.dumps(dict(result=dict(type="started"))))
''')

    def test_herdr_team_launcher_routes_actions_and_workspace_sessions(self):
        self.install_herdr_mock()
        setup = self.run_command(".agent-pipeline/bin/herdr-team.sh")
        self.assertEqual(setup.returncode, 0, setup.stderr)
        self.assertIn("inspect", setup.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls, [["pane", "get", "w1:p1"], ["plugin", "action", "invoke", "agent-toolkit.team"]])
        self.assertEqual(self.run_command(".agent-pipeline/bin/herdr-team.sh", "focus-tools").returncode, 0)
        self.assertEqual(self.run_command(".agent-pipeline/bin/herdr-team.sh", "agents").returncode, 0)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls[-1], ["pane", "list", "--workspace", "w1"])
        for action, expected in (("actions", ["plugin", "action", "list"]),
                                 ("logs", ["plugin", "log", "list", "--plugin", "agent-toolkit"])):
            self.assertEqual(self.run_command(".agent-pipeline/bin/herdr-team.sh", action).returncode, 0)
            self.assertEqual(json.loads(self.calls.read_text().splitlines()[-1]), expected)

    def test_herdr_team_launcher_refuses_missing_context_and_wrong_project(self):
        self.install_herdr_mock()
        self.env.pop("HERDR_PANE_ID")
        result = self.run_command(".agent-pipeline/bin/herdr-team.sh", "setup")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("intended Herdr project pane", result.stderr)
        self.assertFalse(self.calls.exists())
        self.env["HERDR_PANE_ID"] = "w1:p1"
        self.env["MOCK_HERDR_CWD"] = str(self.base)
        result = self.run_command(".agent-pipeline/bin/herdr-team.sh", "setup")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("another project", result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls, [["pane", "get", "w1:p1"]])

    def test_claude_agents_render_and_recover_without_stamp(self):
        target = self.base / "claude-project"
        target.mkdir()
        result = self.run_command("bash", str(ROOT / "bin/init.sh"), "--target", str(target),
                                  "--project-name", "claude-project", "--reviewer-model", "claude/sonnet",
                                  "--reviewer-fallback-model", "claude/opus")
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, model in (("reviewer", "sonnet"), ("reviewer_fallback", "opus")):
            source = (target / f".claude/agents/{name}.md").read_text()
            self.assertIn(f"name: {name}\n", source)
            self.assertIn(f"model: {model}\n", source)
            self.assertNotIn("__CLAUDE_", source)
            self.assertIn("tools: Read, Grep, Glob", source)
        preview = self.run_command("bash", str(ROOT / "bin/init.sh"), "--update", "--target", str(target))
        self.assertEqual(preview.returncode, 0, preview.stdout + preview.stderr)
        stamp = target / ".agent-pipeline/.toolkit-version"
        stamp.unlink()
        recovery = self.run_command("bash", str(ROOT / "bin/init.sh"), "--update", "--target", str(target))
        self.assertEqual(recovery.returncode, 0, recovery.stdout + recovery.stderr)
        self.assertIn("REVIEWER_MODEL: claude/sonnet", recovery.stdout)
        self.assertFalse(stamp.exists())

    def test_first_worker_calls_start_distinct_sessions(self):
        flow = (self.pipeline / "adapters/opencode.md").read_text()
        calls = re.findall(r"\.agent-pipeline/bin/oc\.sh --agent (builder)(.*?)```", flow, re.S)
        self.assertTrue(calls)
        for role, arguments in calls:
            self.assertNotIn("--session", arguments, role)
        self.assertIn("First call omits --session", flow)
        self.assertIn("implementer/reviewer/tester role row", flow)
        state = (self.pipeline / "tasks/TEMPLATE.md").read_text()
        for role in ("implementer", "reviewer", "tester"):
            self.assertIn(f"| {role} | pending |", state)
        self.assertNotIn("**OpenCode session id:**", state)

    def test_environment_overrides_and_nested_cwd(self):
        self.env.update(OC_SERVER="http://localhost:9876", EXPECT_SERVER="http://localhost:9876",
                        OC_PASSWORD="override", EXPECT_PASSWORD="override")
        nested = self.project / "nested"
        nested.mkdir()
        result = self.run_command(str(self.project / ".agent-pipeline/bin/verify-models.sh"), cwd=nested)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_invalid_id_and_disabled_model(self):
        self.change_model("a/c", "a/missing")
        result = self.verify()
        self.assertEqual(result.returncode, 1)
        self.assertIn("reviewer_model does not resolve", result.stderr)
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)
        self.change_model("a/missing", "a/c")
        self.rows[1]["enabled"] = False
        self.save_catalog()
        self.assertIn("is disabled", self.verify().stderr)

    def test_model_variants(self):
        self.change_model("a/c", "a/c#high")
        self.assertEqual(self.verify().returncode, 0)
        self.change_model("a/c#high", "a/c#typo")
        self.assertEqual(self.verify().returncode, 1)
        self.assertIn("unknown variant", self.verify().stderr)

    def test_native_ids_are_explicitly_unchecked(self):
        self.change_model("a/c", "codex/example")
        result = self.verify()
        self.assertEqual(result.returncode, 2)
        self.assertIn("UNCHECKED", result.stderr)
        self.assertNotIn("OK", result.stdout)

    def test_codex_catalog_checks_explicit_native_ids(self):
        self.change_model("a/c", "codex/example")
        self.env["MOCK_CODEX_MODELS"] = json.dumps({"models": [{"slug": "example"}]})
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 Codex worker ids", result.stdout)
        self.change_model("codex/example", "codex/missing")
        result = self.verify()
        self.assertEqual(result.returncode, 1)
        self.assertIn("does not resolve in the Codex catalog", result.stderr)

    def test_malformed_native_catalog_is_not_a_pass(self):
        self.change_model("a/c", "codex/example")
        self.env["MOCK_CODEX_MODELS"] = "{\"models\": [null]}"
        result = self.verify()
        self.assertEqual(result.returncode, 1)
        self.assertIn("malformed Codex catalog", result.stderr)

    def test_default_native_implementer_keeps_explicit_scope(self):
        agent = tomllib.loads((self.project / ".codex/agents/codex-dev.toml").read_text())
        self.assertEqual(agent["name"], "codex-dev")
        self.assertEqual(agent["sandbox_mode"], "workspace-write")
        self.assertNotIn("model", agent)
        self.assertNotIn("approval_policy", agent)
        self.assertIn(".agent-pipeline/roles/implementer.md", agent["developer_instructions"])
        self.assertIn("Never overwrite a prior pass artifact", agent["developer_instructions"])
        for optional in ("reviewer.toml", "reviewer_fallback.toml", "tester.toml"):
            self.assertFalse((self.project / ".codex/agents" / optional).exists())
        self.assertFalse((self.project / ".codex/rules").exists())
        hooks = json.loads((self.project / ".codex/hooks.json").read_text())
        self.assertNotIn("PermissionRequest", hooks["hooks"])

    def test_native_agents_round_trip_without_clobbering(self):
        target = self.base / "native"
        target.mkdir()
        flags = ("--reviewer-model", "codex/primary", "--reviewer-fallback-model",
                 "codex/fallback", "--tester-model", "codex/test-model")
        result = self.run_command("bash", str(ROOT / "bin/init.sh"), "--target", str(target),
                                  "--project-name", "native", *flags)
        self.assertEqual(result.returncode, 0, result.stderr)
        agents = target / ".codex/agents"
        for role in ("reviewer", "tester"):
            source = (target / ".opencode/agent" / (role + ".md")).read_text()
            self.assertNotIn("model: codex/", source)
            self.assertIn("permission:", source)
        for name, model, sandbox in (("reviewer", "primary", "read-only"),
                                     ("reviewer_fallback", "fallback", "read-only"),
                                     ("tester", "test-model", "workspace-write")):
            text = (agents / (name + ".toml")).read_text()
            self.assertNotIn("__CODEX_", text)
            agent = tomllib.loads(text)
            self.assertEqual((agent["name"], agent["model"], agent["sandbox_mode"]),
                             (name, model, sandbox))
            self.assertNotIn("approval_policy", agent)
        preview = self.run_command("bash", str(ROOT / "bin/init.sh"), "--update", "--target", str(target))
        self.assertEqual(preview.returncode, 0, preview.stdout + preview.stderr)
        stamp = target / ".agent-pipeline/.toolkit-version"
        stamped = stamp.read_bytes()
        stamp.unlink()
        unstamped = {str(p.relative_to(target)): p.read_bytes() for p in target.rglob("*") if p.is_file()}
        recovery = self.run_command("bash", str(ROOT / "bin/init.sh"), "--update", "--target", str(target))
        self.assertEqual(recovery.returncode, 0, recovery.stdout + recovery.stderr)
        self.assertIn("REVIEWER_MODEL: codex/primary", recovery.stdout)
        self.assertIn("TESTER_MODEL: codex/test-model", recovery.stdout)
        self.assertEqual(unstamped, {str(p.relative_to(target)): p.read_bytes() for p in target.rglob("*") if p.is_file()})
        stamp.write_bytes(stamped)
        reviewer = agents / "reviewer.toml"
        reviewer.write_text(reviewer.read_text() + "\n# user customization\n")
        before = {str(p.relative_to(target)): p.read_bytes() for p in target.rglob("*") if p.is_file()}
        preview = self.run_command("bash", str(ROOT / "bin/init.sh"), "--update", "--target", str(target))
        self.assertEqual(preview.returncode, 1)
        self.assertEqual(before, {str(p.relative_to(target)): p.read_bytes() for p in target.rglob("*") if p.is_file()})
        rerun = self.run_command("bash", str(ROOT / "bin/init.sh"), "--target", str(target))
        self.assertEqual(rerun.returncode, 0, rerun.stderr)
        self.assertEqual(before, {str(p.relative_to(target)): p.read_bytes() for p in target.rglob("*") if p.is_file()})

    def test_native_agent_validation_happens_before_writes(self):
        for i, value in enumerate(("codex/", 'codex/bad"id', "codex/bad/model", "codex/model#variant")):
            target = self.base / ("invalid-" + str(i))
            target.mkdir()
            result = self.run_command("bash", str(ROOT / "bin/init.sh"), "--target", str(target),
                                      "--project-name", "invalid", "--reviewer-model", value)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(list(target.iterdir()), [])
        stamp = self.pipeline / ".toolkit-version"
        before = stamp.read_bytes()
        refresh = self.run_command("bash", str(ROOT / "bin/init.sh"), "--refresh-stamp",
                                   "--target", str(self.project), "--reviewer-model", 'codex/bad"id')
        self.assertEqual(refresh.returncode, 1)
        self.assertEqual(before, stamp.read_bytes())

    def test_native_aliases_never_reach_opencode(self):
        for model in ("codex/example", "claude/sonnet"):
            result = self.run_command(".agent-pipeline/bin/oc.sh", "--agent", "reviewer", "--model", model)
            self.assertEqual(result.returncode, 1)
            self.assertIn("cannot run through oc.sh", result.stderr)
        self.assertFalse(self.calls.exists())

    def test_native_threads_stay_separate_and_legacy_tasks_pass(self):
        state = self.pipeline / "tasks/T-002.md"
        state.write_text("**Status:** draft\n")
        verify = lambda: self.run_command(".agent-pipeline/bin/verify-state.sh", "T-002")
        self.assertEqual(verify().returncode, 0)
        fields = [f"**Codex {role} thread id:** thread_{role}\n"
                  for role in ("planner", "implementer", "reviewer", "tester")]
        original = "**Status:** draft\n" + "".join(fields)
        state.write_text(original)
        self.assertEqual(verify().returncode, 0)
        state.write_text(original.replace("thread_reviewer", "thread_implementer"))
        self.assertIn("must not share thread ids", verify().stderr)
        state.write_text(original.replace("thread_tester", "ses_wrong_runtime"))
        self.assertIn("not an OpenCode session", verify().stderr)
        state.write_text("**Status:** draft\n" + "".join(fields[:3]))
        self.assertIn("native thread fields are incomplete", verify().stderr)
        state.write_text(original + fields[0])
        self.assertIn("duplicate Codex planner thread id", verify().stderr)

    def test_malformed_catalog_and_api_failure(self):
        self.catalog.write_text("<html>not JSON</html>")
        self.assertIn("malformed catalog", self.verify().stderr)
        self.env["API_FAIL"] = "1"
        result = self.verify()
        self.assertEqual(result.returncode, 1)
        self.assertIn("no ids verified", result.stderr)

    def test_incomplete_catalog_metadata_is_not_success(self):
        del self.rows[0]["enabled"]
        self.save_catalog()
        self.assertEqual(self.verify().returncode, 1)

    def test_duplicate_and_missing_configuration(self):
        stamp = self.pipeline / ".toolkit-version"
        original = stamp.read_text()
        stamp.write_text(original + "builder_model: a/b\n")
        self.assertIn("duplicate model field", self.verify().stderr)
        stamp.write_text("\n".join(line for line in original.splitlines() if not line.startswith("tester_model:")))
        self.assertIn("incomplete worker model", self.verify().stderr)

    def test_cold_catalog_retries_without_false_diagnostics(self):
        self.env["COLD"] = "1"
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(len(self.calls.read_text().splitlines()), 2)

    def test_absent_provider_has_bounded_retries(self):
        self.change_model("a/c", "absent/c")
        result = self.verify()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(self.calls.read_text().splitlines()), 3)
        self.assertIn("absent/c", result.stderr)

    def test_background_success_and_no_overwrite(self):
        result = self.start("builder-1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.bg("wait", "builder-1", "5").returncode, 0)
        directory = self.pipeline / "logs/T-001/builder-1.dispatch"
        before = {p.name: p.read_bytes() for p in directory.iterdir() if p.is_file()}
        self.assertNotEqual(self.start("builder-1").returncode, 0)
        self.assertEqual(before, {p.name: p.read_bytes() for p in directory.iterdir() if p.is_file()})
        self.assertEqual((directory / "exit").read_text().strip(), "0")

    def test_session_receipt_never_proves_completion(self):
        self.assertEqual(self.start("reviewer-1", "slow-fail").returncode, 0)
        directory = self.pipeline / "logs/T-001/reviewer-1.dispatch"
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if "session=" in (directory / "err").read_text():
                break
            time.sleep(0.01)
        else:
            self.fail("mock worker did not emit a receipt")
        pending = self.bg("wait", "reviewer-1", "0")
        self.assertEqual(pending.returncode, 3, pending.stdout + pending.stderr)
        failed = self.bg("wait", "reviewer-1", "5")
        self.assertEqual(failed.returncode, 2)
        self.assertIn("exit=7", failed.stdout)
        self.assertEqual((directory / "exit").read_text().strip(), "7")

    def test_dead_wrapper_without_exit_is_unknown(self):
        directory = self.pipeline / "logs/T-001/tester-1.dispatch"
        directory.mkdir(parents=True)
        (directory / "pid").write_text("99999999")
        (directory / "err").write_text("oc.sh: session=ses_example\n")
        result = self.bg("wait", "tester-1", "0")
        self.assertEqual(result.returncode, 2)
        self.assertIn("unknown:", result.stdout)

    def test_invalid_background_command_and_paths(self):
        for label in ("../builder-1", "builder-0", "reviewer"):
            self.assertNotEqual(self.bg("start", label, "--", ".agent-pipeline/bin/oc.sh").returncode, 0)
        self.assertNotEqual(self.bg("start", "builder-1", "--", "bash", "-c", "true").returncode, 0)
        self.assertNotEqual(self.bg("start", "builder-1", "--", ".agent-pipeline/bin/oc.sh", "--agent", "tester").returncode, 0)
        self.assertFalse((self.pipeline / "logs/T-001").exists())

    def test_wait_bounds_and_startup_record(self):
        directory = self.pipeline / "logs/T-001/builder-1.dispatch"
        directory.mkdir(parents=True)
        self.assertEqual(self.bg("wait", "builder-1", "00").returncode, 3)
        self.assertEqual(self.bg("wait", "builder-1", "1").returncode, 2)
        for bound in ("541", "-1", "not-a-number"):
            self.assertEqual(self.bg("wait", "builder-1", bound).returncode, 1)
        self.assertFalse((directory / "exit").exists())

    def test_concurrent_start_reserves_one_writer(self):
        self.write_executable(self.project / ".agent-pipeline/bin/oc.sh", WORKER)
        prompts = self.pipeline / "prompts/T-001"
        prompts.mkdir(parents=True)
        (prompts / "builder-1.md").write_text("prompt")
        command = [".agent-pipeline/bin/bg-dispatch.sh", "start", "T-001", "builder-1", "--", ".agent-pipeline/bin/oc.sh",
                   "--agent", "builder", "--model", "success", "--prompt-file",
                   ".agent-pipeline/prompts/T-001/builder-1.md", "--raw-out",
                   ".agent-pipeline/logs/T-001/builder-1.jsonl"]
        processes = [subprocess.Popen(command, cwd=self.project, env=self.env,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
        for process in processes:
            process.communicate(timeout=5)
        self.assertEqual(sorted(p.returncode for p in processes), [0, 1])
        self.assertEqual(self.bg("wait", "builder-1", "5").returncode, 0)

    def test_background_paths_resolve_from_nested_cwd(self):
        nested = self.project / "nested"
        nested.mkdir()
        self.assertEqual(self.start("tester-1", cwd=nested).returncode, 0)
        self.assertEqual(self.bg("wait", "tester-1", "5", cwd=nested).returncode, 0)


if __name__ == "__main__":
    unittest.main()
