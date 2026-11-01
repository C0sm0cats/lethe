# Changelog

## 0.7.6 — 2026-11-01

- **A running session could be deleted.** One unreadable file in `sessions/` or `jobs/` (a write cut
  short) hid every running session and job after it, without a word, so a session open for over 10
  minutes could go to the trash. Each file now counts on its own; one that cannot be parsed still
  protects the session it names, and if a live agent's file names none, lethe changes nothing and
  says which file. Update if you use `delete` or `--yes`.
- A transcript lethe cannot read (`chmod 000`, owned by root) no longer counts as empty, so
  `--empty` leaves it alone. It shows as `(unreadable transcript)`.
- Prompts in tags with `-`, `_` or `:` (`<my-button>…</my-button>`) were hidden, and could make a
  session `--empty`. Only tags the agents are known to write now count as injected. An unknown
  agent tag shows as text.
- What you type after a slash command (`/review fix the parser`) now shows in `show`, `export`, the
  title and `--grep`.
- The Claude Code index is rebuilt once, for the three fixes above.
- A too old fzf (Debian 12: 0.38) gave a cryptic error and exit 0. The picker and the installer now
  say that 0.45+ is needed.
- The installer no longer stops when `SHELL` is not set (containers, with dash as `sh`).
- Without `sqlite3`, `--older-than 1d` reported an invalid duration instead of the missing command.
- The plan no longer mentions the Claude Code trash when only Codex sessions are deleted.

## 0.7.5 — 2026-10-31

- The age of a Claude Code session is the date of its **last message** (or of its subagents), not of
  the file: Claude Code appends metadata to old transcripts, which made sessions nobody used look
  recent, in the list, the sort and `--older-than`. Any write still protects a session for 10 minutes.
  The Claude Code index is rebuilt once. Codex sessions keep their date: none was found too recent.

## 0.7.4 — 2026-10-31

- **`--grep` and Ctrl-G could fail and find nothing in 0.7.3** when many sessions matched: parallel
  searches cut each other's output lines. Results now match 0.7.0's on every word compared, on 189
  real sessions. Update if you are on 0.7.3. Nothing was deleted by this: an empty search selects
  nothing.
- `show` no longer ends with an extra blank line when the last message ends with a line break.

## 0.7.3 — 2026-10-31

Finishes what 0.7.1 only started:

- `list` and picker reloads start no process per session, and text with accents no longer costs a
  loop over every character: 2.9 s → 1.1 s for 189 real sessions.
- `--grep` and Ctrl-G: one pass over the transcripts instead of several processes per session found.
  A word found almost everywhere: 19.9 s (0.7.0) → 8.9 s on 1.8 GB (measured on 0.7.4; see below).
- Ctrl-G's preview of a huge transcript reads only the lines holding the text (and says "N messages",
  as it does not count the others). Huge compressed transcripts are sampled like the others.
- `delete` and `archive` compute what they compare in one pass, not per session.
- `show` and Enter render messages as they come, without holding the whole text. The first message
  still waits for the transcript to be read once: which branch is active is known only at its end.
- The project menu searches the whole path of a shortened project, and shows it when there is room.
- At under 60 columns, the picker gives the size column to the title too (the marked size stays).

## 0.7.2 — 2026-10-31

- Picker: `F1` left pieces of the old borders on the screen when the footer changed height, next to
  the preview. It now redraws. The README demo showed them too, and is re-recorded.

## 0.7.1 — 2026-10-31

Security:
- A Codex session title holding the internal field separator (`\x1f`) could shift the fields of its
  row, and on SQLite older than 3.50 reach shell arithmetic: `list` or `stats` could fail, or run a
  command. Titles are flattened, and numeric fields are checked before any arithmetic.
- A subagent transcript whose first `timestamp` was forged could inject SQL into the Claude Code
  index script, and write a file through the `sqlite3` shell. Timestamps and agent ids are validated,
  and index scripts run with `sqlite3 -safe` where it exists.
- Restoring a session printed its title with its terminal control sequences. Outside a UTF-8 locale,
  C1 control characters reached the terminal too.

Wrong selection and data loss:
- `--grep` with `--running`, `--recent` or `--idle` could select **another session** than the one
  containing the text, including for `delete`.
- `trash restore` reported success and erased the entry when the transcript was missing from it, and
  lost the session's prompts when `history.jsonl` could not be written. Both now fail and keep the
  session in the trash.
- A failed move to the trash could erase files when putting them back failed too. They now stay in
  the trash entry, and lethe says where.
- On Alpine (busybox grep), a NUL byte in `history.jsonl` silently kept the prompts of deleted
  sessions. A symlinked `history.jsonl` was replaced by a file, with the prompts left in its target.
  Both are handled, and lethe now says when prompts could not be taken out.
- One unreadable trash manifest blocked `trash list` and `trash empty`.
- A whole HTML or XML prompt (`<div>…</div>`) was hidden, and could make its session `--empty`: only
  machine-style tags now count as injected context. `[Request interrupted by user]` no longer counts
  as a message you typed.
- A Claude Code session whose subagent wrote in the last 10 minutes now counts as recent, and is
  protected.
- Selecting more than about 3,300 Codex sessions answered "Nothing to delete".
- A prompt holding `\x1f` shifted the fields of its row in the Claude Code index.

List and picker:
- `lethe list` has an **ID column**, as long as ids need to be unique. Under 100 columns, `list` and
  the deletion plan drop the date instead of wrapping.
- Durations accept `mo` (`--older-than 6mo`), as the AGE column writes months; `m` still means months.
- `stats` suggestions keep your filters: `lethe delete --empty --dir ~/work`.
- The picker stays usable on small terminals: the preview no longer takes every row, `F1` and
  `Ctrl-P` take turns under 32 lines, and at 50 columns the title, menu counts, marked size, `Esc` and
  `F1` stay visible.
- The list label counts apart: `11 session(s) + 3 subagent(s)`.
- The project menu keeps both ends of long paths: they stay distinct, and can be found by what starts them.
- `lethe trash` is aligned. `trash --help`, `trash list --help` and `completion --help` show the help.
- `delete --claude` explains why an agent alone is refused. The stats panel says typed text is not
  applied. Completion offers `--sort` only where it works.
- The agent colors are readable on light terminals too.

Speed:
- `list` and picker reloads: no process per session (8.0 s → about 4 s for 1,000 sessions).
- `--grep` and Ctrl-G: one grep over the plain transcripts first, so that only sessions holding the
  text cost anything more.
- The preview of a transcript over 32 MB reads its start and end, and says so.
- The headers and previews read subagents from the index, not one process per subagent.
- `delete -n` no longer computes what only a real deletion uses.
- `show` no longer copies the whole text at each message.

Tests: 78 new checks, on the fixes above and on behavior nothing covered (resume directory, trash
confirmation and dry run, background jobs, recycled PIDs, read-only access to the Codex database…).

## 0.7.0 — 2026-10-22

Subagents:
- The subagents a session started are shown under it, as a tree: Codex subagent sessions with their
  nickname (`├─ Socrates`), Claude Code subagents as read-only rows (`↳ general-purpose · opus/high
  « Audit eviction »`). **Trees are folded by default**: `list` and the picker no longer show Codex
  subagent sessions flat; `▸ … · 3 subagents` tells there are some. `Alt-S` (and `--subagents` for
  `list`, `show`, `export`, `pick`) unfolds them and adds their conversations to the preview, Enter
  and Ctrl-E. A folded Codex tree shows its total size.
- Claude Code subagents can be read: their task (`● Claude → subagent`) and their answers, in a
  section of their own; where each was started is marked in the conversation
  (`↳ subagent « … »`). A subagent row has its own preview and Ctrl-E export.
- Search (`--grep`, Ctrl-G) finds a session by what its subagents wrote; the preview says how many
  matches are in subagents, folded or not.
- Codex subagents whose tasks are encrypted show the actions (commands, edits, messages to other
  agents) between their answers in clear.
- Trees sort by their most recent member (by date) or their total size (by size). A subagent the
  filters keep without its parent comes with the parent shown dim (`ctx:` row, not selectable).
  A subagent whose parent is gone is tagged `parent gone ·`; cycles of edges lose no session.
- Headers: `· 3 subagents: Arendt, Kepler, Raman (2.4M)` on a session, `spawned by …` on a Codex
  subagent. `list --json` (still flat): `parent`, `subagents: {count, size}`. `stats`: a subagents line.
- `--keep N`: a subagent takes the rank of the session at the top of its tree, whatever its own
  directory (it could be deleted while its session was kept).
- Actions apply to what is selected, never to what is folded: Ctrl-D/Ctrl-X/Ctrl-R on a Claude
  subagent row or a dim context row explain and change nothing.

Status:
- "running" now means open in an agent (`◉`), as the agents and other tools count it. A session
  closed in the last 10 minutes (`◔`, still protected) has a status of its own, **recent**:
  `--recent`, and Ctrl-S cycles all → running → recent → idle → archived. `◔` is cyan, `stats` has
  a line for each.

Fixes:
- A Claude Code session that moved to another directory (a `cd`, `/cd`, or a resume elsewhere)
  belongs to the project it is in now, not the one it started in: list, picker, `--dir`, Ctrl-W,
  `--keep`, `--orphans` and resume (which starts there).
- A transcript with a NUL byte (a pasted log, for example) was taken for a binary file by `grep`
  and read only in part: one real session exported 162 of its 634 messages.
- Since 0.6.0, deleting a Claude Code session empties `~/.claude/history.jsonl` (the prompt history,
  of every session) when that file holds a NUL byte, for the same reason. It is now read as text,
  and lethe replaces it only if no line was lost.

## 0.6.3 — 2026-10-22

- Codex 0.163 compresses old transcripts (`rollout-*.jsonl.zst`) without updating its index:
  lethe listed them as missing (✗), and `lethe delete --missing` (or the Ctrl-F "Missing" filter)
  would have permanently deleted sessions that still exist. Compressed transcripts are now found,
  sized, protected while open, read (`show`, preview, Enter, `export`) and searched (`--grep`,
  Ctrl-G). Reading them needs `zstd`; without it they are still listed and never taken for
  missing, and `show` says what to install.

## 0.6.2 — 2026-10-14

- Codex subagent sessions are tagged `subagent ·` in the list, the picker and the deletion plan,
  like `exec ·` and `vscode ·`, whatever their title; untitled ones are named after their nickname
  (`subagent · Kepler` instead of `subagent Kepler`).

## 0.6.1 — 2026-10-14

- Codex subagents of the multi-agent mode showed "(no messages)": their messages are encrypted by
  Codex. `show`, the preview, Enter and `export` now show what can be read: who gave them their
  task, the commands they ran, the files they edited and who they reported to.
- README: a new banner, and a shorter introduction under it.

## 0.6.0 — 2026-10-14

A bug hunt: 40 bugs found and fixed, almost all with a regression test.

Safety:
- Age filters (`--older-than`, `--newer-than`, the idle menus), the sort and `--keep` use the date of
  the Codex transcript when it was written after the index, as the list did: a session used today
  can no longer be selected as "idle for a month".
- Archiving or unarchiving a Codex session is no longer taken for activity (it showed as "0m",
  running and protected for 10 minutes).
- Sessions pinned in Codex are skipped by filters; naming them (id, picker) still changes them.
- `--orphans` no longer takes an unmounted disk or an unreadable parent for a deleted project.
- `trash empty` refuses filters other than `--older-than` instead of ignoring them and emptying
  the whole trash.
- A restore that fails halfway puts everything back in the trash, so it can be retried; a
  Ctrl-C cannot interrupt it.
- Text from transcripts can no longer send control sequences to the terminal (clipboard, title,
  clear screen).
- In the picker, Ctrl-F and Ctrl-W narrow the command line's `--older-than` and `--dir` instead of
  replacing or widening them; the prompt shows the command line's filters, and `--grep` becomes the
  Ctrl-G search.
- `--keep N` keeps N sessions of each project, both agents together, as documented.
- Deleting a Claude Code session also takes its prompts out of `~/.claude/history.jsonl` (they are
  restored with it).

Correctness:
- `--grep` and Ctrl-G find text with `"` or `\`.
- Prompts that start with `<` (HTML, JSX…) are shown, exported, searched and used as titles; such a
  session is no longer "empty".
- Compaction summaries are no longer shown as messages typed by the user.
- `--dir /` means every project; `--dir` through a symlink matches the sessions of its target.
- Codex ids that share their first 8 characters: the preview shows a unique prefix, and Ctrl-E
  exports both.
- `show`, the preview and Enter give the same date and status as the list.
- Deleting Claude Code sessions no longer needs the `codex` command; a session removed meanwhile
  by something else is reported as such, not as moved to the trash.
- Unarchiving a Codex session brings back the subagents archived with it.
- The plan always says when it includes subagent sessions.
- Durations out of range are refused instead of failing in SQL.
- `trash empty --older-than` says when nothing is old enough instead of "The trash is empty".
- Each Claude Code directory (`CLAUDE_CONFIG_DIR`) has its own index: switching profiles no longer
  reindexes everything.

Platforms:
- macOS with the system bash first in the `PATH`: the picker works (its subcommands use
  Homebrew's bash too).
- Alpine Linux (busybox): sessions are listed and open sessions detected.
- Installer: zsh with `ZDOTDIR` gets the `PATH` line in the right file, and a startup file that
  merely mentions the directory no longer prevents it.

Display:
- Wide characters (CJK, emoji) keep the columns aligned; `lethe list` fits 80 columns; a session
  started in `/` shows `/`.
- Ctrl-G highlighting no longer breaks colors; Enter keeps colors with a custom `LESS`; the footer
  keeps `_`; the picker says "unarchived" instead of "active"; Ctrl-W no longer preselects an
  unrelated project; the menus' column titles sit above their columns.
- Completion offers `--all-branches`, the options of each command, and trashed ids for
  `trash restore`.

## 0.5.3 — 2026-10-13

- "active" meant "not archived", and read as "running". `Ctrl-S` now cycles all → running → idle
  → archived: running is the sessions open in an agent or active in the last 10 minutes (◉ ◔),
  idle the others that are not archived (●). On the command line: `--running`, `--idle`,
  `--archived`, and `--unarchived` (the former `--active`, still accepted). Two of them at once
  is an error instead of the last one winning.
- The header of a conversation (`show`, preview, `Enter`) says running or idle the same way.
  `list --json` keeps its `status` field (`active` / `archived`) for scripts.
- Colors follow the status: running sessions (`◉` `◔`) are green, idle ones (`●`) grey. Idle
  sessions were green, which read as "running".
- `stats` (and `Ctrl-B`), the `list` summary and the picker's list title count the running
  sessions (◉ and ◔), not only the open ones; `stats` points to `lethe list --running`.

## 0.5.2 — 2026-10-13

- One-line installer: `curl -fsSL https://raw.githubusercontent.com/C0sm0cats/lethe/main/install.sh | sh`
  downloads lethe, adds `~/.local/bin` to the `PATH` in the right file for zsh, bash (Linux and
  macOS) or fish, and prints the exact command to install missing dependencies for the system
  (Homebrew, apt, dnf, pacman, zypper, apk). Tested in CI on Linux and on macOS.
- README: install section rewritten around the installer, with the manual steps as an alternative.
- On macOS, lethe runs with Homebrew's bash even when `/usr/bin` (bash 3.2) comes first in the
  `PATH`, instead of stopping with "bash >= 4.4 is required".

## 0.5.1 — 2026-10-13

- `--help` is up to date (the cycles of `Ctrl-T`, `Ctrl-S`, `Ctrl-O`, the menus, `Ctrl-Y`, `F1`) and
  fits 80 columns.
- README: the key table no longer breaks `Ctrl-A` over two lines on GitHub (shorter descriptions,
  non-breaking hyphens), and `Ctrl-G` has its own short section.

## 0.5.0 — 2026-10-13
- `Ctrl-G` (and `--grep`) search the transcripts in parallel: twice as fast. While a search is
  active, the preview shows only the messages that mention the text, highlighted, with a count
  ("8 of 22 messages mention …"), and `Enter` opens the conversation on the first occurrence.
- `Ctrl-O` cycles by date → by size → oldest first; `--sort oldest` on the command line.
- Every key that switches a view shows where it stands in the footer (`Ctrl-T agent: claude`,
  `Ctrl-O sort: size`, `Ctrl-G find: off`, `Alt-B abandoned branches: shown`…), and the prompt
  now includes the sort when it is not by date. `Ctrl-O` and `Alt-B` update both at once.
- `Ctrl-B` shows the disk usage in the preview panel instead of a pager page ending in `(END)`:
  it follows the agent, filter and project shown, and pressing it again brings the conversation
  back. `lethe stats` fits the terminal width (bars, paths, cleanup commands on their own line).

## 0.4.2 — 2026-10-13

- Enter reads the conversation on the full width of the terminal. With the preview shown, the
  text was wrapped to the preview's width.

## 0.4.1 — 2026-10-12

- Ctrl-C (or a kill) while a Claude Code session moves to the trash can no longer leave it half
  moved: the few renames finish first.
- With only Claude Code installed (no Codex), `list`, `stats` and the picker failed with
  "no such column: recency".
- Deleting Claude Code sessions reports "moved N to the trash (size, freed when the trash is
  emptied)" instead of "deleted N (0B freed)".
- `trash restore` names the restored session; `resume` explains a session with no recorded
  directory; `Ctrl-W` does nothing in the trash; options before the command
  (`lethe --dir x list`) get a clear message.
- Indexing is 2 to 5 times faster: one jq per transcript instead of five, run in parallel (one job
  per CPU). 500 new Claude Code sessions: 13 s → 2.6 s; on a real 640 MB home: 5.5 s → 2.2 s.
- `--grep` on Claude Code sessions reads the texts with one jq instead of three (1.4 to 2 times faster).
- The project column widens on terminals of 180 columns or more.
- `NO_COLOR` also turns off the picker's colors; the selected row follows fzf's color scheme, so
  `--color=light` in `FZF_DEFAULT_OPTS` gives a readable light theme.
- fzf before 0.63 works again (an `F1` binding needed a newer fzf). Checked with fzf 0.45 and bash 4.4.
- README: dependencies per system, `~/.local/bin` created by the install line, the `Ctrl-F` and
  `Ctrl-W` menus in the features.
- `packaging/`: a Homebrew formula and an AUR `PKGBUILD` (built and checked with makepkg), and
  `docs/social-preview.png` for the repository's social preview.

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
