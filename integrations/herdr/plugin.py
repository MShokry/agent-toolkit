#!/usr/bin/env python3
"""Optional Herdr host adapter. No scaffolding, worker dispatch, or approvals."""

import argparse
import importlib.util
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


PLUGIN_ID = "agent-toolkit"
SOURCE = "plugin:agent-toolkit"
KINDS = {"opencode", "claude", "codex"}


class PluginError(Exception):
    pass


def herdr(*args):
    """Use argv, the invoking server's environment, and bounded calls. No retries."""
    try:
        result = subprocess.run(
            [os.environ.get("HERDR_BIN_PATH", "herdr"), *args],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20,
        )
    except subprocess.TimeoutExpired as exc:
        raise PluginError("Herdr call timed out; inspect before retrying (it may have applied).") from exc
    if result.returncode:
        raise PluginError("Herdr call failed: " + clean(result.stderr or result.stdout)[:500])
    try:
        response = json.loads(result.stdout)
    except ValueError as exc:
        raise PluginError("Herdr returned invalid JSON; no fallback target was selected.") from exc
    if not isinstance(response, dict) or "error" in response:
        raise PluginError("Herdr rejected the request: " + clean(json.dumps(response))[:500])
    if not isinstance(response.get("result"), dict):
        raise PluginError("Herdr response has no result object.")
    return response["result"]


def clean(value):
    # Project text is untrusted terminal output, never terminal control sequences.
    return "".join(c for c in str(value) if c.isprintable() or c == " ")


def object_field(result, key):
    value = result.get(key)
    if not isinstance(value, dict):
        raise PluginError("Herdr response has no " + key + " object.")
    return value


def project_root(start):
    if not start or not Path(start).is_absolute():
        raise PluginError("No absolute project cwd supplied by Herdr; select a project pane.")
    path = Path(start).resolve()
    for root in (path, *path.parents):
        if (root / ".agents/TEMPLATE.md").is_file() and (root / ".claude/commands/feature.md").is_file():
            return root
    raise PluginError("Project is not scaffolded. Run bin/init.sh explicitly first; adoption never scaffolds.")


def invocation(args):
    try:
        context = json.loads(os.environ.get("HERDR_PLUGIN_CONTEXT_JSON", "{}"))
    except ValueError as exc:
        raise PluginError("Invalid HERDR_PLUGIN_CONTEXT_JSON.") from exc
    if not isinstance(context, dict):
        raise PluginError("Herdr invocation context must be an object.")
    pane_id = args.pane or context.get("focused_pane_id") or os.environ.get("HERDR_PANE_ID")
    pane = object_field(herdr("pane", "get", pane_id), "pane") if pane_id else None
    start = args.project or os.environ.get("AGENT_TOOLKIT_PROJECT")
    if not start:
        start = ((pane or {}).get("foreground_cwd") or (pane or {}).get("cwd")
                 or context.get("focused_pane_cwd") or context.get("workspace_cwd"))
    root = project_root(start)
    workspace = ((pane or {}).get("workspace_id") or context.get("workspace_id")
                 or os.environ.get("HERDR_WORKSPACE_ID"))
    if not workspace:
        raise PluginError("No workspace supplied; refusing to use an arbitrary focused workspace.")
    return root, workspace, pane


def require_project(pane, root):
    cwd = pane.get("foreground_cwd") or pane.get("cwd")
    if project_root(cwd) != root:
        raise PluginError("Selected agent belongs to a different project; select its project explicitly.")


def binding_path(root, workspace):
    state_dir = os.environ.get("HERDR_PLUGIN_STATE_DIR")
    if not state_dir:
        raise PluginError("HERDR_PLUGIN_STATE_DIR is required; run through the linked Herdr plugin.")
    # Plugins are global. Pane/workspace ids alone collide across named servers.
    server = os.environ.get("HERDR_SOCKET_PATH") or os.environ.get("HERDR_SESSION", "default")
    key = hashlib.sha256(json.dumps([server, workspace, str(root.resolve())]).encode()).hexdigest()
    return Path(state_dir) / "bindings" / (key + ".json")


@contextmanager
def locked(path):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(str(path.with_suffix(".lock")), os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(fd, "w") as lock:
        # Serialize repeated layout actions without blocking a second action forever.
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise PluginError("Another toolkit action is running for this project; try again when it finishes.") from exc
        yield


def load_binding(path, required=True):
    if not path.exists():
        if required:
            raise PluginError("No adopted lead for this project/server. Select the lead pane and run Adopt first.")
        return None
    value = json.loads(path.read_text())
    if not isinstance(value, dict) or value.get("version") != 1:
        if not required:
            return None
        raise PluginError("Unsupported leader binding; explicitly adopt the lead again.")
    return value


def save_binding(path, value):
    # Private, atomic state lives outside the project and managed plugin checkout.
    fd, tmp = tempfile.mkstemp(prefix="binding-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def adopt(root, workspace, pane, path):
    if not pane:
        raise PluginError("Select the running lead pane before adoption.")
    agent = object_field(herdr("agent", "get", pane["pane_id"]), "agent")
    if agent.get("agent") not in KINDS:
        raise PluginError("Adoption requires a recognized OpenCode, Claude, or Codex agent, not a shell.")
    require_project(pane, root)
    previous = load_binding(path, required=False)
    same_terminal = previous and previous.get("terminal_id") == agent["terminal_id"]
    binding = {
        "version": 1, "project": str(root), "workspace_id": workspace,
        "pane_id": agent["pane_id"], "terminal_id": agent["terminal_id"],
        "agent": agent["agent"], "session": agent.get("agent_session"),
        "panes": previous.get("panes", {}) if same_terminal else {},
    }
    save_binding(path, binding)
    # Metadata does not take lifecycle/session authority from Herdr integrations.
    herdr("pane", "report-metadata", agent["pane_id"], "--source", SOURCE,
          "--token", "toolkit_role=lead", "--ttl-ms", "3600000")
    print("Adopted existing " + clean(agent["agent"]) + " lead in " + clean(agent["pane_id"]) + ". No prompt or process launched.")
    if not binding["session"]:
        print("Native session identity is unavailable: focus/brief require the official agent integration and re-adoption.")


def lead(root, workspace, binding, require_session=False):
    if require_session and not binding.get("session"):
        raise PluginError("No recorded native session. Install the official Herdr agent integration, then adopt again.")
    panes = herdr("pane", "list", "--workspace", workspace).get("panes")
    if not isinstance(panes, list):
        raise PluginError("Herdr response has no pane list.")
    matches = []
    for pane in panes:
        if pane.get("agent") != binding["agent"]:
            continue
        if binding.get("session"):
            identity_matches = pane.get("agent_session") == binding["session"]
        else:
            identity_matches = (pane.get("pane_id") == binding["pane_id"]
                                and pane.get("terminal_id") == binding["terminal_id"])
        if identity_matches:
            require_project(pane, root)
            matches.append(pane)
    if len(matches) != 1:
        raise PluginError("Adopted lead is missing, replaced, or ambiguous. Re-adopt explicitly; never select the latest worker.")
    return matches[0]


def brief_leader(root, workspace, binding):
    target = lead(root, workspace, binding, require_session=True)
    agent = object_field(herdr("agent", "get", target["pane_id"]), "agent")
    if agent.get("agent_session") != binding["session"] or agent.get("agent") != binding["agent"]:
        raise PluginError("Lead identity changed before prompting; re-adopt explicitly.")
    if agent.get("agent_status") not in {"idle", "done"}:
        raise PluginError("Lead is not idle. No prompt sent; handle its current work or approval dialog yourself.")
    if binding["agent"] == "opencode":
        adapter = ".opencode/agents/leader.md"
        if not (root / adapter).is_file():
            raise PluginError("OpenCode leader adapter is missing; reconcile/bootstrap the toolkit explicitly first.")
        instruction = "Read " + adapter + " and apply its OpenCode adaptations."
    elif binding["agent"] == "codex":
        instruction = "Load .agents/skills/feature/SKILL.md for its Codex adaptations."
        if not (root / ".agents/skills/feature/SKILL.md").is_file():
            raise PluginError("Codex feature skill is missing; bootstrap it explicitly first.")
    else:
        instruction = "Use .claude/commands/feature.md as the canonical lead workflow."
    prompt = (
        "Act as this project's agent-toolkit lead in this existing session, not as an implementer. "
        "Read the project's AGENTS.md and CLAUDE.md when present. " + instruction + " "
        "Read .claude/commands/feature.md in full; keep the pipeline in .agents/T-<id>.md. "
        "This role briefing is not a feature request, spec approval, auto-mode consent, or merge approval. "
        "Do not dispatch work or modify files yet. Confirm readiness briefly and ask for the task. "
        "Herdr hosts terminals only; keep reviewer independence, loop budgets, permission checks, "
        "and human approval gates unchanged."
    )
    herdr("agent", "prompt", target["pane_id"], prompt)
    print("Leader briefing submitted once. No automatic retry; inspect the agent if completion is uncertain.")


def open_board(root, workspace, target, placement, focus=False):
    args = [
        "plugin", "pane", "open", "--plugin", PLUGIN_ID, "--entrypoint", "board",
        "--placement", placement, "--workspace", workspace,
        "--cwd", str(root), "--env", "AGENT_TOOLKIT_PROJECT=" + str(root),
        "--focus" if focus else "--no-focus",
    ]
    if placement == "split":
        args.extend(["--target-pane", target])
    return herdr(*args)


def layout(root, workspace, binding, path):
    target = lead(root, workspace, binding)
    panes = herdr("pane", "list", "--workspace", workspace)["panes"]
    present = {p["pane_id"]: p for p in panes}
    for role in ("workers", "server", "board"):
        saved = binding["panes"].get(role, {})
        current = present.get(saved.get("pane_id"), {})
        if current and current.get("terminal_id") == saved.get("terminal_id"):
            continue
        if role == "board":
            result = open_board(root, workspace, target["pane_id"], "split")
            pane = object_field(object_field(result, "plugin_pane"), "pane")
        else:
            pane = object_field(herdr("pane", "split", target["pane_id"], "--direction", "right",
                                     "--cwd", str(root), "--no-focus"), "pane")
        binding["panes"][role] = {"pane_id": pane["pane_id"], "terminal_id": pane["terminal_id"]}
        # Save each successful creation: a later API failure must not duplicate it on retry.
        save_binding(path, binding)
        herdr("pane", "rename", pane["pane_id"], "Toolkit " + role)
    print("Support panes ready. Existing lead untouched; worker/server shells are empty. No server or agent launched.")


_view_spec = importlib.util.spec_from_file_location("toolkit_dashboard", Path(__file__).with_name("dashboard.py"))
_view = importlib.util.module_from_spec(_view_spec)
sys.dont_write_bytecode = True
_view_spec.loader.exec_module(_view)
header = _view.header
stage_graph = _view.stage_graph
board_text = _view.board_text
visual_lines = _view.visual_lines
visual_board = _view.visual_board


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("adopt", "brief-leader", "layout", "status", "focus-leader", "board"))
    parser.add_argument("--project", help="Explicit scaffolded project (never the plugin cwd)")
    parser.add_argument("--pane", help="Explicit Herdr pane on the invoking server")
    parser.add_argument("--once", action="store_true", help="Print the board once without terminal refresh")
    args = parser.parse_args(argv)
    if args.action == "board":
        # Pane cwd can vary. Use explicit project context, never assume plugin cwd.
        root = project_root(args.project or os.environ.get("AGENT_TOOLKIT_PROJECT"))
        if args.once or not sys.stdout.isatty() or not sys.stdin.isatty() or os.environ.get("TERM") in (None, "dumb"):
            print(board_text(root))
        else:
            visual_board(root)
        return
    root, workspace, pane = invocation(args)
    if args.action == "status":
        if not pane:
            raise PluginError("Select a project pane before opening the board.")
        open_board(root, workspace, pane["pane_id"], "tab", focus=True)
        print("Opened read-only task board.")
        return
    path = binding_path(root, workspace)
    with locked(path):
        if args.action == "adopt":
            adopt(root, workspace, pane, path)
            return
        binding = load_binding(path)
        if args.action == "brief-leader":
            brief_leader(root, workspace, binding)
        elif args.action == "focus-leader":
            target = lead(root, workspace, binding, require_session=True)
            herdr("agent", "focus", target["pane_id"])
            print("Focused the exact adopted lead session; no new process launched.")
        elif args.action == "layout":
            layout(root, workspace, binding, path)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except (PluginError, OSError, ValueError, KeyError) as error:
        print("agent-toolkit/herdr: " + clean(error), file=sys.stderr)
        sys.exit(1)
