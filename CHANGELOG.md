# Changelog

## Unreleased

- Ctrl-C (or a kill) while a Claude Code session moves to the trash can no longer leave it half
  moved: the few renames finish first.
- With only Claude Code installed (no Codex), `list`, `stats` and the picker failed with
  "no such column: recency".
- Deleting Claude Code sessions reports "moved N to the trash (size, freed when the trash is
  emptied)" instead of "deleted N (0B freed)".
- `trash restore` names the restored session; `resume` explains a session with no recorded
  directory; `Ctrl-W` does nothing in the trash; options before the command
  (`lethe --dir x list`) get a clear message.

## 0.4.0 — 2026-10-12

- `Ctrl-F` opens a menu of cleanup filters, each with its number of sessions and size, instead of
  cycling through them (the trash was six presses away). The cursor starts on the current filter.
- `Ctrl-W` opens a menu of projects sorted by size, with the current session's project on top
  and "All projects" to go back. A project is selected on its own, as counted in the menu
  (`--dir` on the command line still includes the projects below).
- `Ctrl-S` skips "archived" when showing Claude Code only (only Codex sessions can be archived).

## 0.3.3 — 2026-10-12

- On small terminals (narrow and under 32 lines) the preview starts hidden, so the list shows
  15 sessions instead of 2 on 80×24; `Ctrl-P` shows it.
- While sessions are marked, the list title shows how many and how much space they take
  (`3 marked · 42M · …`): what a deletion would free, before pressing `Ctrl-D`.

## 0.3.2 — 2026-10-12

- Column titles (agent, age, size, project, title) at the top of the picker list.
- On short terminals the footer shows the essential keys on one line; `F1` toggles the full list.
  On a 40-line terminal the list shows 10 sessions instead of 7.
- `Ctrl-Y` copies the command that resumes the selected session (OSC 52, `wl-copy`, `xclip` or `pbcopy`).
- Long messages in the preview are cut at a line break, so `**bold**` and `` `code` `` are never left open.

## 0.3.1 — 2026-10-11

- Alt-B is visible: the prompt shows `⑂ all branches`, and a long preview keeps every abandoned
  message (with the one before it) instead of hiding them in "… more messages …".

## 0.3.0 — 2026-10-11

- Claude Code sessions show the active branch only: prompts edited or rewound (Esc Esc, `/rewind`)
  and their replies are hidden from `show`, the preview, `Enter` and `export`. Parallel tool results
  and compactions are followed.
- `⑂N` badge in the picker and `list` (and `abandoned_branches` in `list --json`) for sessions
  with abandoned branches; computed once a session has been quiet for 10 minutes.
- `show --all-branches`, `export --all-branches` and `Alt-B` in the picker show them, labelled
  `(abandoned)`. `--grep` searches every branch.
- The picker no longer scrolls long rows sideways to show a match, which hid the start of the row.

## 0.2.2 — 2026-10-11

- `list` and the deletion plan use the picker's columns: project name, then title (mode as a tag).
- `stats` (and `Ctrl-B`) draw bars for agents, activity age and the biggest projects.

## 0.2.1 — 2026-10-11

- Picker rows show the project name before the title, so it stays visible on narrow terminals.
- Ages are shaded by how recent they are; the match counter drops fzf's tracking marker.
- The preview wraps on words and renders light Markdown (headings, bold, inline code, code blocks).
- Narrower preview (45%), footer keys that fit the list, shorter preview header.

## 0.2.0 — 2026-10-10

Safety:
- Open sessions are detected when `CODEX_HOME` or `CLAUDE_CONFIG_DIR` goes through a symlink.
- `--empty` no longer matches sessions started by a slash command that got a reply, image-only
  sessions, or Codex sessions with a user event or tokens.
- Each session is checked again right before it is changed, and left alone if it was opened,
  written to or moved since the plan was shown.
- Codex activity also counts the transcript's own modification time, when the index lags behind.
- Nothing is changed when the open files of a running agent cannot be listed.
- A Codex transcript the index lost track of (moved, relative path) is not reported as missing.
- Moving a Claude Code session to the trash is all or nothing; restore only writes inside the
  Claude Code directory.
- `resume` refuses sessions already open in a running agent, and subagent sessions.

Features:
- `lethe fork ID` and `Ctrl-K`: continue in a copy of a session.
- `lethe export ID` and `Ctrl-E`: the conversation as Markdown.
- Codex transcripts without response items (message events, voice transcripts) can be read and searched.
- Codex titles fall back to the first user message.

## 0.1.0 — 2026-10-10

First release.

- One fzf picker for Claude Code and Codex sessions, with a live conversation preview.
- Resume a session in its agent and directory (`Ctrl-R`, `lethe resume`).
- Delete, archive and unarchive from the picker or the command line, with `--dry-run` and `--yes`.
- Sessions open in a running agent, or active in the last 10 minutes, are never modified.
- Restorable trash for Claude Code sessions; Codex changes go through the official `codex` CLI.
- Filters: agent, status, age, project directory (`--dir`, `Ctrl-W`), mode, provider, full-text search
  (`--grep`, `Ctrl-G`), empty, orphaned and missing sessions, `--keep N`.
- `stats`, `list --json`, sort by size, and bash/zsh completion.
