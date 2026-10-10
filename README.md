# lethe

**Browse, resume and forget your Claude Code and Codex sessions.** One picker for every conversation your AI coding agents left on disk. It never touches a session that is still running.

[![tests](https://github.com/C0sm0cats/lethe/actions/workflows/test.yml/badge.svg)](https://github.com/C0sm0cats/lethe/actions/workflows/test.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![single bash script](https://img.shields.io/badge/single%20file-bash-4EAA25?logo=gnubash&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude%20Code-supported-D97757)
![Codex](https://img.shields.io/badge/Codex-supported-10A37F)
![Linux | macOS](https://img.shields.io/badge/Linux%20%7C%20macOS-lightgrey)

![lethe demo: every session in one list, filter by agent, sort by size, delete with open sessions skipped, then restore from the trash](docs/demo.svg)

In Greek myth, Lethe is the river of forgetting. Your agents never forget: after a few weeks you have hundreds of sessions spread over `~/.claude` and `~/.codex`. There are one-shot runs, abandoned subagents, sessions you opened and closed, and transcripts of several hundred megabytes. Neither agent lets you see them all, let alone clean them up.

```sh
curl -fsSL -o ~/.local/bin/lethe https://raw.githubusercontent.com/C0sm0cats/lethe/main/lethe && chmod +x ~/.local/bin/lethe
lethe
```

One Bash file. No runtime, no daemon, no install step.

## Features

- **Every session, one list.** Claude Code and Codex side by side, with age, size, project and title, and a live preview of the conversation.
- **Resume anything.** `Ctrl-R` reopens a session in its agent, in the directory it was started from.
- **Clean up in seconds.** Mark with `Tab`, delete with `Ctrl-D`. Or `lethe delete --older-than 1m --keep 3`.
- **Running sessions are untouchable.** Sessions open in a running agent, or active in the last 10 minutes, are detected and skipped. Always, even with `--yes`.
- **Undo.** Deleted Claude Code sessions go to a trash and can be restored. Codex sessions can be archived instead of deleted.
- **Find what to clean.** Empty sessions, sessions whose project folder is gone, idle ones, the biggest ones, or full-text search in your conversations.
- **Scriptable.** `list --json`, `stats`, `--dry-run`, `--yes` for cron, and tab completion.

## Install

```sh
curl -fsSL -o ~/.local/bin/lethe https://raw.githubusercontent.com/C0sm0cats/lethe/main/lethe
chmod +x ~/.local/bin/lethe
```

Requirements: bash 4.4+ (on macOS: `brew install bash`), `sqlite3`, `jq`, and `fzf` 0.45+ for the picker (0.63+ for the panel layout). It works with whichever agents you have; you don't need both.

Tab completion: add `source <(lethe completion zsh)` to `~/.zshrc`, or `source <(lethe completion bash)` to `~/.bashrc`.

## Usage

```sh
lethe                          # the picker
lethe stats                    # what takes space, with cleanup suggestions
lethe list --claude --sort size
lethe resume 01a11ee1          # unique id prefixes work everywhere
```

### Picker keys

Everything the command line can do, the picker can do too.

| Key | Action |
| --- | --- |
| `Tab` | mark / unmark |
| `Ctrl-A` | mark / unmark all visible sessions |
| `Ctrl-D` | delete the marked sessions (or the current one) |
| `Ctrl-X` | archive / unarchive (Codex) |
| `Ctrl-R` | resume the session in its agent |
| `Enter` | read the whole conversation in your pager |
| `Ctrl-T` | show all agents, Claude Code only, or Codex only |
| `Ctrl-S` | show all, active or archived sessions |
| `Ctrl-F` | cleanup filter: empty → orphans → missing → idle 30d+ → idle 90d+ → trash |
| `Ctrl-W` | only the project of the current session (press again for all projects) |
| `Ctrl-G` | find the text you typed inside the conversations (press again to clear) |
| `Ctrl-O` | sort by date or by size |
| `Ctrl-P` | show / hide the conversation preview |
| `Ctrl-B` | disk usage and cleanup stats |
| `Esc` | quit |

In the trash view, `Ctrl-R` restores a session and `Ctrl-D` deletes it for good. Typing filters the list by title, project, agent or mode. Command-line filters apply too: `lethe --dir ~/work --older-than 2w`.

| Icon | Meaning |
| --- | --- |
| `●` | active session |
| `◌` | archived session (Codex) |
| `◉` | open in a running agent: protected |
| `◔` | active in the last 10 minutes: protected |
| `✗` | indexed by Codex, but the transcript file is gone |
| `↺` | in the trash, restorable |

Sizes over 10 MB are yellow, over 50 MB red.

### Cleaning up from the command line

```sh
lethe delete --empty                       # sessions without a single message
lethe delete --orphans                     # projects you have deleted or moved
lethe delete --older-than 1m --keep 3      # idle for a month, but keep the last 3 of each project
lethe delete --codex --mode exec --older-than 1w
lethe delete --grep "api key" --dry-run    # preview what would be deleted
lethe archive --dir ~/old-project          # hide a finished project from codex resume
lethe delete --older-than 6m --yes         # no prompt, e.g. from cron
```

Destructive commands show the sessions they will change and ask for confirmation. Without a terminal they require `--yes`. With no filter at all they require `--all`.

### Trash (Claude Code)

```sh
lethe trash                    # list trashed sessions
lethe trash restore 7f3a       # put a session back, exactly where it was
lethe trash empty --older-than 30d
```

The trash lives in `~/.local/share/lethe/trash`. Restoring never overwrites existing files.

### Filters

| Filter | Matches |
| --- | --- |
| `--claude`, `--codex` | one agent |
| `--active`, `--archived` | session status |
| `--older-than D`, `--newer-than D` | last activity; `D` is `12h`, `30d`, `8w`, `6m`, `1y` |
| `--dir PATH` | sessions started in `PATH` or below it (repeatable) |
| `--mode MODE` | `cli`, `exec`, `vscode`, `subagent`, … |
| `--provider NAME` | `anthropic`, `openai`, … |
| `--grep TEXT` | your messages or the agent's replies contain `TEXT` (case-insensitive) |
| `--empty` | sessions without any message |
| `--orphans` | sessions whose project directory no longer exists |
| `--missing` | Codex index entries whose transcript is gone |
| `--keep N` | spares the `N` most recent sessions of each project |
| `ID…` | session ids or unique prefixes |

```sh
lethe list --json | jq -r '.[] | select(.size > 50000000) | "\(.agent) \(.id) \(.title)"'
```

## How it stays safe

- **Running sessions.** A session is protected when:
  - a running process holds its transcript open (this is how Codex works);
  - Claude Code lists it in `~/.claude/sessions/` with a live process, checked against the process start time so that a recycled PID doesn't count;
  - it is an unfinished Claude Code background job;
  - it was active in the last 10 minutes.

  Protection is checked when the plan is shown, and again right before each change. `--force` lifts only the 10-minute rule.
- **Subagents.** Deleting a Codex session also deletes the subagent sessions it spawned, children first. A subagent whose parent is running is protected, and so is the whole tree of any protected session. Claude Code subagent transcripts live inside their session and go with it.
- **Codex** is changed only through its own CLI (`codex delete`, `codex archive`, `codex unarchive`). Every change is checked in its database afterwards.
- **Claude Code** has no delete command. lethe moves the transcript and everything Claude Code keeps for that session (subagent transcripts, tool results, file history, session environment) to the trash, with a manifest to restore it.
- **Read-only by default.** Listing, searching and previewing never write to the agents' data. The Claude Code index is a cache in `~/.cache/lethe`.

## Configuration

| Variable | Default |
| --- | --- |
| `CLAUDE_CONFIG_DIR` | `~/.claude` |
| `CODEX_HOME` | `~/.codex` |
| `XDG_DATA_HOME` | `~/.local/share` (trash) |
| `XDG_CACHE_HOME` | `~/.cache` (Claude Code index) |
| `NO_COLOR` | colors on |
| `PAGER` | `less -R` |

## Development

```sh
tests/run.sh                                  # throwaway homes, fake codex: never touches your sessions
uv run --with pyte python docs/make_demo.py   # re-record the README demo (needs tmux)
```

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

Built with ❤️ by C0sm0cats
