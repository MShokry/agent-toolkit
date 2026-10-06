#!/usr/bin/env python3
"""Read-only toolkit dashboard. No host, agent CLI, or model calls required."""

import argparse
import os
from pathlib import Path
import re
import sys
import textwrap
import time


def clean(value):
    return "".join(c for c in str(value) if c.isprintable() or c == " ")


def header(text, name):
    match = re.search(r"^\*\*" + re.escape(name) + r":\*\*[ \t]*(.*)$", text, re.MULTILINE)
    return (clean(match.group(1)).strip() if match else "") or "not recorded"


STAGES = ("PLAN", "APPROVAL", "BUILD", "REVIEW", "TEST", "DONE")
STATUS_STAGE = {
    "draft": "PLAN", "spec-approved": "APPROVAL", "in-progress": "BUILD",
    "in-review": "REVIEW", "changes-requested": "BUILD", "testing": "TEST", "done": "DONE",
}


def stage_graph(status):
    active = STATUS_STAGE.get(status)
    return " -> ".join("[" + stage + "]" if stage == active else stage for stage in STAGES)


def runtime_dir(root):
    """Task-record directory: `.pipeline/`, or a not-yet-migrated `.agents/` runtime."""
    current = root / ".pipeline"
    if current.is_dir():
        return current
    legacy = root / ".agents"
    # `.agents/` also holds Codex skills in migrated projects, so only treat it
    # as a runtime when it carries task records or the task template.
    if legacy.is_dir() and ((legacy / "TEMPLATE.md").is_file() or any(legacy.glob("T-*.md"))):
        return legacy
    return None


def task_records(root):
    records, warnings = [], []
    directory = runtime_dir(root)
    for task in sorted(directory.glob("T-*.md") if directory else ()):
        if root not in task.resolve().parents:
            warnings.append(clean(task.name) + " — external symlink skipped")
            continue
        try:
            text = task.read_text(encoding="utf-8", errors="replace")
        except OSError:
            warnings.append(clean(task.name) + " — unavailable (refresh to retry)")
            continue
        section = re.search(r"^### Acceptance criteria ledger[ \t]*$([\s\S]*?)(?=^#{1,3} |\Z)", text, re.MULTILINE)
        ledger = re.findall(r"^\|\s*(AC[0-9]+)\s*\|\s*([^|]*)\|", section.group(1) if section else "", re.MULTILINE)
        records.append({"task": task, "text": text, "status": header(text, "Status"),
                        "met": sum("[x]" in outcome.lower() for _, outcome in ledger), "total": len(ledger)})
    return records, warnings


def board_text(root, width=None):
    records, warnings = task_records(root)
    blocked = [r for r in records if r["status"].startswith("blocked:")]
    done = sum(r["status"] == "done" for r in records)
    unknown = sum(r["status"] not in STATUS_STAGE and r not in blocked for r in records)
    lines = ["AGENT TOOLKIT | LIVE DASHBOARD", clean(root),
             "MODEL-INDEPENDENT | local task files | refresh: 2s | read-only",
             "Recorded task state only. Herdr done/idle is NOT acceptance or verification.",
             "No scripts run here; verify-state.sh / verify-spec.sh remain the pipeline gates.", "",
             "SUMMARY | tasks: {} | active: {} | blocked: {} | done: {} | unknown: {}".format(
                 len(records), len(records) - len(blocked) - done - unknown, len(blocked), done, unknown),
             "PIPELINE | " + " -> ".join(STAGES),
             "STAGES   | " + " | ".join(stage + ": " + str(sum(STATUS_STAGE.get(r["status"]) == stage for r in records)) for stage in STAGES),
             "[STAGE] = current recorded state, not proof of passed gates.", ""]
    if blocked:
        lines.append("BLOCKERS / NEEDS ATTENTION")
        for record in blocked:
            lines.extend(["! " + clean(record["task"].stem) + " | " + record["status"],
                          "  since: " + header(record["text"], "Blocked since"),
                          "  handoff: " + header(record["text"], "Latest handoff")])
        lines.append("")
    lines.append("TASK DETAILS")
    if not records and not warnings:
        lines.append("No task records yet. Ask your existing lead for a task/spec; do not invent approval.")
    for record in records:
        text, status = record["text"], record["status"]
        ticks = record["met"] * 10 // record["total"] if record["total"] else 0
        lines.extend([
            clean(record["task"].stem) + " — " + status + " — ledger {}/{} ticked (recorded)".format(record["met"], record["total"]),
            "  " + clean(text.splitlines()[0].lstrip("# ") if text.splitlines() else ""),
            "  " + stage_graph(status),
            "  " + ("! BLOCKED: stage unspecified by status" if status.startswith("blocked:") else
                       "? Unknown/unfilled status" if status not in STATUS_STAGE else "owner: " + header(text, "Owner right now")),
            "  AC [" + "#" * ticks + "." * (10 - ticks) + "] recorded ticks only",
            "  handoff: " + header(text, "Latest handoff"),
            "  review " + header(text, "Review loop count") + "; test-fix " + header(text, "Test-fix loops") + "; spec " + header(text, "Spec bounces"), "",
        ])
    lines.extend(warnings)
    if width:
        lines = [piece for line in lines for piece in (textwrap.wrap(line, width=max(20, width), subsequent_indent="  ") or [""])]
    return "\n".join(lines)


def visual_lines(root, width, blocked_only=False):
    width = max(16, width)
    records, warnings = task_records(root)
    blocked = [r for r in records if r["status"].startswith("blocked:")]
    done = sum(r["status"] == "done" for r in records)
    unknown = sum(r["status"] not in STATUS_STAGE and r not in blocked for r in records)
    rows = []

    def line(text, tone="normal"):
        rows.extend((piece, tone) for piece in textwrap.wrap(clean(text), width=width) or [""])

    def card(title, body, tone="normal"):
        inner = width - 4
        rows.append(("+" + "-" * (width - 2) + "+", tone))
        for text in [title, *body]:
            for piece in textwrap.wrap(clean(text), width=inner) or [""]:
                rows.append(("| " + piece.ljust(inner) + " |", tone))
        rows.extend([("+" + "-" * (width - 2) + "+", tone), ("", "normal")])

    line("AGENT TOOLKIT / VISUAL DASHBOARD", "heading")
    line(str(root), "muted")
    line("Local files / no model calls / read-only / refresh every 2s", "muted")
    line("")
    card("PROJECT SUMMARY", [
        "Tasks {}   Active {}   Blocked {}   Done {}   Unknown {}".format(
            len(records), len(records) - len(blocked) - done - unknown, len(blocked), done, unknown),
        "Herdr done/idle is NOT acceptance. Ticks are recorded, not verified.",
    ], "heading")
    line("PIPELINE / recorded stage counts", "heading")
    per_row = max(1, (width + 4) // 16)
    for start in range(0, len(STAGES), per_row):
        group = STAGES[start:start + per_row]
        for part in range(3):
            cells = []
            for stage in group:
                count = sum(STATUS_STAGE.get(r["status"]) == stage for r in records)
                cells.append("+----------+" if part != 1 else "|" + (stage + " " + str(count)).center(10) + "|")
            line((" -> " if part == 1 else "    ").join(cells), "heading")
    line("Blocked/unknown stages are not guessed. Earlier gates are not implied.", "muted")
    line("")
    line("BLOCKERS: {} / b toggles blocked-only view".format(len(blocked)), "warning" if blocked else "muted")
    for record in blocked:
        line("! " + clean(record["task"].stem) + ": " + header(record["text"], "Latest handoff"), "warning")
        line("  Since " + header(record["text"], "Blocked since"), "warning")
    line("")
    line("TASK CARDS" + (" / BLOCKED ONLY" if blocked_only else ""), "heading")
    visible = blocked if blocked_only else records
    if not visible:
        line("No blocked tasks." if blocked_only else "No task records yet. Ask the lead for a task/spec.", "muted")
    for record in sorted(visible, key=lambda r: (not r["status"].startswith("blocked:"), r["task"].name)):
        text, status = record["text"], record["status"]
        bar_width = min(24, width - 6)
        ticks = record["met"] * bar_width // record["total"] if record["total"] else 0
        tone = ("warning" if status.startswith("blocked:") else "success" if status == "done"
                else "muted" if status not in STATUS_STAGE else "normal")
        card(clean(record["task"].stem) + " / " + status, [
            text.splitlines()[0].lstrip("# ") if text.splitlines() else "",
            stage_graph(status), "Owner: " + header(text, "Owner right now"),
            "AC [" + "#" * ticks + "." * (bar_width - ticks) + "] {}/{} recorded".format(record["met"], record["total"]),
            "Handoff: " + header(text, "Latest handoff"),
            "Loops: review " + header(text, "Review loop count") + " / test-fix " + header(text, "Test-fix loops") + " / spec " + header(text, "Spec bounces"),
        ], tone)
    for warning in warnings:
        line(warning, "warning")
    return rows


def visual_board(root):
    import curses

    def run(screen):
        try:
            curses.curs_set(0)
        except curses.error:
            pass
        screen.keypad(True)
        screen.timeout(200)
        colors = {}
        if curses.has_colors():
            curses.start_color()
            background = curses.COLOR_BLACK
            try:
                curses.use_default_colors()
                background = -1
            except curses.error:
                pass
            for index, (name, color) in enumerate((
                    ("heading", curses.COLOR_CYAN), ("warning", curses.COLOR_YELLOW),
                    ("success", curses.COLOR_GREEN), ("muted", curses.COLOR_WHITE)), 1):
                if index < curses.COLOR_PAIRS:
                    curses.init_pair(index, color, background)
                    colors[name] = curses.color_pair(index)
        offset, blocked_only, updated, rows, last_width = 0, False, 0, [], None
        while True:
            height, width = screen.getmaxyx()
            if time.monotonic() - updated >= 2 or width != last_width:
                rows = visual_lines(root, max(16, width - 1), blocked_only)
                updated, last_width = time.monotonic(), width
            available = max(1, height - 2)
            offset = max(0, min(offset, max(0, len(rows) - available)))
            screen.erase()
            for y, (text, tone) in enumerate(rows[offset:offset + available]):
                attr = colors.get(tone, 0) | (curses.A_BOLD if tone == "heading" else 0)
                try:
                    screen.addnstr(y, 0, text, max(0, width - 1), attr)
                except curses.error:
                    pass
            footer = "Up/Down j/k scroll | PgUp/PgDn | b blockers | r refresh | q close | {}/{}".format(offset + 1, len(rows))
            try:
                screen.addnstr(max(0, height - 1), 0, footer, max(0, width - 1), curses.A_REVERSE)
            except curses.error:
                pass
            screen.refresh()
            key = screen.getch()
            if key in (ord("q"), 27):
                return
            if key in (curses.KEY_DOWN, ord("j")):
                offset += 1
            elif key in (curses.KEY_UP, ord("k")):
                offset -= 1
            elif key == curses.KEY_NPAGE:
                offset += available
            elif key == curses.KEY_PPAGE:
                offset -= available
            elif key == curses.KEY_HOME:
                offset = 0
            elif key == curses.KEY_END:
                offset = len(rows)
            elif key == ord("b"):
                blocked_only, offset, updated = not blocked_only, 0, 0
            elif key in (ord("r"), curses.KEY_RESIZE):
                updated = 0

    curses.wrapper(run)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".", help="Project or nested directory (default: cwd)")
    parser.add_argument("--once", action="store_true", help="Print a plain-text snapshot")
    args = parser.parse_args(argv)
    start = Path(args.project).expanduser().resolve()
    root = next((p for p in (start, *start.parents) if runtime_dir(p)), None)
    if root is None:
        parser.error("No .pipeline/ directory found. Run inside a toolkit project or pass --project.")
    if args.once or not sys.stdout.isatty() or not sys.stdin.isatty() or os.environ.get("TERM") in (None, "dumb"):
        print(board_text(root))
    else:
        visual_board(root)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except (OSError, ValueError) as error:
        print("dashboard: " + clean(error), file=sys.stderr)
        sys.exit(1)
