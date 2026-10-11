# Changelog

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
