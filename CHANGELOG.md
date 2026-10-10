# Changelog

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
