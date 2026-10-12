"""Record the README demo, docs/demo.svg: an animated SVG of the real picker.

Run from the repository root:  uv run --with pyte python docs/make_demo.py
Needs tmux. It builds throwaway Claude Code and Codex homes with demo sessions,
drives the real picker in a detached tmux session, captures the screen after
each step and turns the captures into SVG frames.
"""
import json
import os
import sqlite3
import subprocess
import tempfile
import time
from html import escape

import pyte

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEMO = os.path.join(ROOT, "docs", "demo.svg")
COLUMNS, ROWS = 170, 30
FRAME_SECONDS = 2.6
FAKE_HOME = "/home/you"

# One Dark-like palette for pyte's color names.
PALETTE = {
    "default": "#d7dae0", "black": "#282c34", "red": "#e06c75", "green": "#98c379", "brown": "#e5c07b",
    "yellow": "#e5c07b", "blue": "#61afef", "magenta": "#c678dd", "cyan": "#56b6c2", "white": "#d7dae0",
    "brightblack": "#7f848e", "brightred": "#ff7b86", "brightgreen": "#b5e890", "brightyellow": "#f0d58a",
    "brightblue": "#82c4ff", "brightmagenta": "#de9cf0", "brightcyan": "#7fd3dd", "brightwhite": "#ffffff",
}
BACKGROUND, CELL_W, CELL_H, FONT = "#1e2127", 8.6, 19, 14.2

MIN, HOUR, DAY = 60, 3600, 86400
TOKEN_RACE = [
    ("user", "Users get logged out at random. The access token sometimes expires in the middle of a request."),
    ("assistant", "Two requests can refresh the token at the same time: the second one invalidates the first "
                  "refresh token, so the next call fails with 401.\n\nI'll serialize the refresh behind a single "
                  "in-flight promise in `auth/refresh.ts` and add a test that fires 10 concurrent requests "
                  "with an expired token."),
    ("user", "Go ahead, and keep the retry limit at one."),
    ("assistant", "Done. `refreshToken()` now reuses the pending refresh, requests retry once after it resolves, "
                  "and `auth.concurrency.test.ts` covers the race. All 214 tests pass."),
]
# (agent, age, mode, project, title, size, archived, conversation, open)
SESSIONS = [
    ("claude", 4 * MIN, "cli", "code/api-server", "Fix the token refresh race in auth", 2_100_000, 0, TOKEN_RACE, True),
    ("codex", 3 * HOUR, "cli", "code/web-dashboard", "Add dark mode to the settings page", 640_000, 0, [], False),
    ("claude", 9 * HOUR, "cli", "code/api-server", "Write integration tests for /orders", 3_200_000, 0, [], False),
    ("codex", 1 * DAY, "subagent", "code/api-server", "subagent Kepler", 910_000, 0, [], False),
    ("codex", 3 * DAY, "exec", "code/scripts", "Summarize the changelog for 2.4", 95_000, 0, [], False),
    ("claude", 6 * DAY, "cli", "code/game-engine", "Profile the renderer and cut draw calls", 48_300_000, 0, [], False),
    ("claude", 9 * DAY, "cli", "", "", 4_000, 0, [], False),
    ("codex", 16 * DAY, "exec", "code/web-dashboard", "Generate a commit message", 61_000, 0, [], False),
    ("codex", 23 * DAY, "vscode", "notes", "Plan the Q4 roadmap", 410_000, 1, [], False),
    ("claude", 38 * DAY, "vscode", "code/old-prototype", "Port the prototype to Rust", 12_400_000, 0, [], False),
    ("codex", 64 * DAY, "cli", "code/old-prototype", "Benchmark JSON parsers", 2_250_000, 1, [], False),
    ("claude", 97 * DAY, "cli", "code/website", "Migrate the blog to Astro", 5_600_000, 0, [], False),
]


def compact(value):
    return json.dumps(value, separators=(",", ":"))


def write_padded(path, lines, size):
    body = "".join(compact(line) + "\n" for line in lines)
    padding = max(0, size - len(body) - 60)
    body += compact({"type": "padding", "data": "x" * padding}) + "\n"
    with open(path, "w") as file:
        file.write(body)


def proc_start():
    with open("/proc/self/stat") as file:
        return file.read().rsplit(") ", 1)[1].split()[19]


def build_demo(root):
    now = int(time.time())
    codex, claude = os.path.join(root, "codex"), os.path.join(root, "claude")
    os.makedirs(os.path.join(codex, "sessions", "2026", "01", "01"))
    os.makedirs(os.path.join(codex, "archived_sessions"))
    os.makedirs(os.path.join(claude, "sessions"))
    db = sqlite3.connect(os.path.join(codex, "state_5.sqlite"))
    db.execute("""CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT, created_at INTEGER,
        updated_at INTEGER, recency_at INTEGER, source TEXT, model_provider TEXT, cwd TEXT, title TEXT,
        preview TEXT, archived INTEGER, model TEXT, tokens_used INTEGER)""")
    for i, (agent, age, mode, project, title, size, archived, conversation, is_open) in enumerate(SESSIONS):
        session_id = f"019a{i:04x}-5c2e-7d41-9b6a-{0x3f8e21c4d7a0 + i * 0x1111:012x}"
        cwd = os.path.join(FAKE_HOME, project) if project else FAKE_HOME
        stamp = now - age
        conversation = conversation or ([("user", title)] if title else [])
        if agent == "codex":
            folder = "archived_sessions" if archived else os.path.join("sessions", "2026", "01", "01")
            path = os.path.join(codex, folder, f"rollout-2026-01-01T00-00-00-{session_id}.jsonl")
            write_padded(path, [{"type": "response_item", "payload": {"type": "message", "role": role, "content": [
                {"type": "input_text" if role == "user" else "output_text", "text": text}]}}
                for role, text in conversation], size)
            os.utime(path, (stamp, stamp))
            source = '{"subagent":{}}' if mode == "subagent" else mode
            db.execute("INSERT INTO threads VALUES (?, ?, ?, ?, ?, ?, 'openai', ?, ?, ?, ?, 'gpt-5.5', ?)",
                       (session_id, path, stamp - 1800, stamp, stamp, source, cwd, title, title, archived,
                        18_400 * (i + 3)))
        else:
            project_dir = os.path.join(claude, "projects", cwd.replace("/", "-"))
            os.makedirs(project_dir, exist_ok=True)
            path = os.path.join(project_dir, f"{session_id}.jsonl")
            entry = "claude-vscode" if mode == "vscode" else "cli"
            started = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(stamp - 1800))
            lines = [{"type": "user" if role == "user" else "assistant", "cwd": cwd, "entrypoint": entry,
                      "timestamp": started, "sessionId": session_id,
                      "message": {"role": role, "model": "claude-opus-5-5",
                                  "content": text if role == "user" else [{"type": "text", "text": text}]}}
                     for role, text in conversation]
            if title:
                lines.append({"type": "ai-title", "aiTitle": title, "sessionId": session_id})
            write_padded(path, lines, size)
            os.utime(path, (stamp, stamp))
            if is_open:
                with open(os.path.join(claude, "sessions", f"{os.getpid()}.json"), "w") as file:
                    json.dump({"pid": os.getpid(), "sessionId": session_id, "procStart": proc_start()}, file)
    db.commit()
    return codex, claude


def tmux(*args):
    return subprocess.run(["tmux", "-L", "lethe-demo", *args], check=True, capture_output=True,
                          text=True).stdout


def keys(*names, wait=1.2):
    for name in names:
        if name.startswith("sleep:"):
            time.sleep(float(name[6:]))
            continue
        if name.startswith("text:"):
            tmux("send-keys", "-t", "demo", "-l", name[5:])
        else:
            tmux("send-keys", "-t", "demo", name)
        time.sleep(0.25)
    time.sleep(wait)


def screen():
    ansi = tmux("capture-pane", "-p", "-e", "-t", "demo")
    term = pyte.Screen(COLUMNS, ROWS)
    pyte.Stream(term).feed("\r\n".join(ansi.split("\n")[:ROWS]))
    return term


# (caption, keys to press before the capture)
STORY = [
    ("Every Claude Code and Codex session, in one list", []),
    ("Ctrl-T: one agent at a time", ["C-t"]),
    ("Ctrl-O: biggest sessions first", ["C-o", *["Up"] * 8]),
    ("Tab marks, Ctrl-D deletes, and open sessions are always skipped",
     ["Down", "Tab", "Down", "Down", "Tab", "C-d"]),
    ("Deleted Claude Code sessions go to a restorable trash", ["text:y", "Enter"]),
    ("Ctrl-F: empty, orphaned, idle sessions, and the trash", ["Enter", "sleep:2", *[k for _ in range(6) for k in ("C-f", "sleep:0.6")]]),
    ("Ctrl-R puts it back, exactly where it was", ["C-r"]),
]


def record(root, codex, claude):
    env = (f"CODEX_HOME={codex} CLAUDE_CONFIG_DIR={claude} XDG_CACHE_HOME={root}/cache "
           f"XDG_DATA_HOME={root}/data HOME={FAKE_HOME} TERM=xterm-256color")
    command = f"env {env} {os.path.join(ROOT, 'lethe')} pick; sleep 30"
    tmux("-f", "/dev/null", "new-session", "-d", "-s", "demo", "-x", str(COLUMNS), "-y", str(ROWS), command)
    frames = []
    try:
        time.sleep(4.0)
        for caption, steps in STORY:
            keys(*steps, wait=2.5)
            frames.append((caption, screen()))
    finally:
        tmux("kill-server")
    return frames


def color(name, default):
    if name == "default":
        return default
    return PALETTE.get(name, f"#{name}" if len(name) == 6 else default)


def cell_style(cell):
    fill, back = color(cell.fg, PALETTE["default"]), color(cell.bg, None)
    if cell.reverse:
        fill, back = color(cell.bg, BACKGROUND), color(cell.fg, PALETTE["default"])
    return fill, back, cell.bold


def frame_body(term, top):
    """SVG elements for one screen: background runs, then text runs."""
    out = []
    for y in range(ROWS):
        row = [term.buffer[y][x] for x in range(COLUMNS)]
        line_top = top + y * CELL_H
        baseline = line_top + CELL_H * 0.75
        x = 0
        while x < COLUMNS:
            fill, back, bold = cell_style(row[x])
            start = x
            while x < COLUMNS and cell_style(row[x]) == (fill, back, bold):
                x += 1
            text = "".join(cell.data or " " for cell in row[start:x])
            left, width = PAD_X + start * CELL_W, (x - start) * CELL_W
            if back:
                out.append(f'<rect x="{left:.1f}" y="{line_top:.1f}" width="{width:.1f}" height="{CELL_H}" '
                           f'fill="{back}"/>')
            stripped = text.rstrip()
            if stripped.strip():
                lead = len(stripped) - len(stripped.lstrip())
                stripped = stripped.lstrip()
                weight = ' font-weight="bold"' if bold else ""
                out.append(f'<text x="{left + lead * CELL_W:.1f}" y="{baseline:.1f}" fill="{fill}"{weight} '
                           f'textLength="{len(stripped) * CELL_W:.1f}" lengthAdjust="spacingAndGlyphs">'
                           f'{escape(stripped)}</text>')
    return out


PAD_X, PAD_TOP, TITLE_H = 18, 14, 34


def svg(frames):
    width = PAD_X * 2 + COLUMNS * CELL_W
    height = TITLE_H + PAD_TOP * 2 + ROWS * CELL_H
    total = FRAME_SECONDS * len(frames)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:.0f}" height="{height:.0f}" '
           f'viewBox="0 0 {width:.0f} {height:.0f}" font-family="\'JetBrains Mono\', \'DejaVu Sans Mono\', Menlo, '
           f'Consolas, monospace" font-size="{FONT}" xml:space="preserve">',
           f'<rect width="100%" height="100%" rx="10" fill="{BACKGROUND}"/>',
           f'<rect width="100%" height="{TITLE_H}" rx="10" fill="#2c313a"/>',
           f'<rect y="{TITLE_H - 10}" width="100%" height="10" fill="#2c313a"/>']
    for i, dot in enumerate(("#ff5f57", "#febc2e", "#28c840")):
        out.append(f'<circle cx="{20 + i * 20}" cy="{TITLE_H / 2}" r="6" fill="{dot}"/>')
    css = []
    for i in range(len(frames)):
        start, end = 100 * i / len(frames), 100 * (i + 1) / len(frames)
        css.append(f"@keyframes f{i}{{0%{{opacity:{1 if i == 0 else 0}}}"
                   f"{start:.3f}%{{opacity:1}}{end:.3f}%{{opacity:0}}100%{{opacity:0}}}}"
                   f".f{i}{{opacity:{1 if i == 0 else 0};animation:f{i} {total}s step-end infinite}}")
    out.append("<style>" + "".join(css) + "</style>")
    for i, (caption, term) in enumerate(frames):
        out.append(f'<g class="f{i}">')
        out.append(f'<text x="{width / 2:.0f}" y="{TITLE_H / 2 + 5}" fill="#9da5b4" text-anchor="middle" '
                   f'font-size="13">lethe · {escape(caption)}</text>')
        out.extend(frame_body(term, TITLE_H + PAD_TOP))
        out.append("</g>")
    out.append("</svg>")
    return "\n".join(out)


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as root:
        codex, claude = build_demo(root)
        frames = record(root, codex, claude)
    with open(DEMO, "w") as file:
        file.write(svg(frames))
    print(f"wrote {os.path.relpath(DEMO, ROOT)} ({os.path.getsize(DEMO) // 1024} KB)")
