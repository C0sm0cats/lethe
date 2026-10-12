#!/usr/bin/env bash
# Test suite: builds throwaway Codex and Claude Code homes with a fake `codex`
# binary and checks lethe against them. Never touches your real sessions.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LETHE=$ROOT/lethe
# Canonical path: macOS has a trailing slash in $TMPDIR and /tmp is a symlink.
WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/lethe-test.XXXXXX")" && pwd -P)
trap 'rm -rf -- "$WORK"' EXIT

export CODEX_HOME=$WORK/codex CLAUDE_CONFIG_DIR=$WORK/claude
export XDG_DATA_HOME=$WORK/data XDG_CACHE_HOME=$WORK/cache NO_COLOR=1
export PATH=$WORK/bin:$PATH
DB=$CODEX_HOME/state_5.sqlite
PROJ=$WORK/proj
CPROJ=$CLAUDE_CONFIG_DIR/projects/-work-proj
export TRASH=$XDG_DATA_HOME/lethe/trash # used inside check expressions
passed=0 failed=0

# Portable `touch -d @EPOCH FILE` (BSD touch has no -d @).
set_mtime() { perl -e 'utime $ARGV[0], $ARGV[0], $ARGV[1] or die' "$1" "$2"; }

# ── Codex fixture ────────────────────────────────────────────────────────────

mkdir -p "$CODEX_HOME/sessions/2026/01/01" "$CODEX_HOME/archived_sessions" "$WORK/bin" "$PROJ/sub" "$WORK/other"
sqlite3 "$DB" "
    CREATE TABLE threads (
        id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL, source TEXT NOT NULL, model_provider TEXT NOT NULL,
        cwd TEXT NOT NULL, title TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0,
        preview TEXT NOT NULL DEFAULT '', recency_at INTEGER NOT NULL DEFAULT 0,
        agent_nickname TEXT);
    ALTER TABLE threads ADD COLUMN has_user_event INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE threads ADD COLUMN tokens_used INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE threads ADD COLUMN first_user_message TEXT NOT NULL DEFAULT '';
    CREATE TABLE thread_spawn_edges (
        parent_thread_id TEXT NOT NULL, child_thread_id TEXT NOT NULL PRIMARY KEY, status TEXT NOT NULL);"

codex_file() {
    if (($2)); then
        printf '%s' "$CODEX_HOME/archived_sessions/rollout-2026-01-01T00-00-00-$1.jsonl"
    else
        printf '%s' "$CODEX_HOME/sessions/2026/01/01/rollout-2026-01-01T00-00-00-$1.jsonl"
    fi
}

# codex_session ID AGE_DAYS ARCHIVED SOURCE PROVIDER CWD TITLE TEXT [nofile]
codex_session() {
    local id=$1 days=$2 archived=$3 source=$4 provider=$5 cwd=$6 title=$7 text=$8 file
    local ts=$(($(date +%s) - days * 86400))
    file=$(codex_file "$id" "$archived")
    if [[ ${9:-} != nofile ]]; then
        {
            printf '{"type":"session_meta","payload":{"id":"%s","cwd":"%s"}}\n' "$id" "$cwd"
            printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>secretword</environment_context>"}]}}\n'
            [[ -z $text ]] ||
                printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"%s"}]}}\n' "$text"
        } >"$file"
        set_mtime "$ts" "$file"
    fi
    sqlite3 "$DB" "INSERT INTO threads (id, rollout_path, created_at, updated_at, source, model_provider, cwd, title, archived, preview, recency_at, agent_nickname) VALUES ('$id', '$file', $ts, $ts, '$source', '$provider',
        '$cwd', '$title', $archived, '$text', $ts, NULL);"
}

A=aaaaaaaa-0000-4000-8000-000000000001 # codex: old cli session in PROJ
B=bbbbbbbb-0000-4000-8000-000000000002 # codex: exec session in PROJ/sub
C=cccccccc-0000-4000-8000-000000000003 # codex: subagent spawned by A
D=dddddddd-0000-4000-8000-000000000004 # codex: archived, other provider
E=eeeeeeee-0000-4000-8000-000000000005 # codex: empty, active right now
F=ffffffff-0000-4000-8000-000000000006 # codex: index entry without transcript
codex_session "$A" 100 0 cli openai "$PROJ" "Refactor parser" "please refactor the Parser"
codex_session "$B" 2 0 exec openai "$PROJ/sub" "Run tests" "run the test suite"
codex_session "$C" 100 0 '{"subagent":{"thread_spawn":{}}}' openai "$PROJ" "" "child work"
codex_session "$D" 40 1 vscode headroom "$WORK/other" "Old idea" "an old idea"
codex_session "$E" 0 0 cli openai "$WORK/other" "" ""
codex_session "$F" 50 0 cli openai "$WORK/other" "Ghost" "" nofile
sqlite3 "$DB" "INSERT INTO thread_spawn_edges VALUES ('$A', '$C', 'closed');
               UPDATE threads SET agent_nickname = 'Kepler', preview = '' WHERE id = '$C';"
# Padding (not a message) so that --sort size has a known order.
printf '%05000d\n' 0 >>"$(codex_file "$A" 0)"
printf '%03000d\n' 0 >>"$(codex_file "$B" 0)"
set_mtime "$(($(date +%s) - 100 * 86400))" "$(codex_file "$A" 0)"
set_mtime "$(($(date +%s) - 2 * 86400))" "$(codex_file "$B" 0)"

# Fake codex: applies delete/archive/unarchive to the fixture.
cat >"$WORK/bin/codex" <<EOF
#!/usr/bin/env bash
set -e
echo "\$*" >>"$WORK/codex.log"
id=\${@: -1}
path=\$(sqlite3 "$DB" "SELECT rollout_path FROM threads WHERE id = '\$id';")
[[ -n \$path ]] || { echo "no session \$id" >&2; exit 1; }
case \$1 in
    delete)
        # Test hook: write to another transcript while a deletion runs.
        if [[ -f "$WORK/on-delete" ]]; then echo '{}' >>"\$(cat "$WORK/on-delete")"; rm -f "$WORK/on-delete"; fi
        rm -f -- "\$path"
        sqlite3 "$DB" "DELETE FROM threads WHERE id = '\$id'; DELETE FROM thread_spawn_edges WHERE child_thread_id = '\$id';" ;;
    archive) sqlite3 "$DB" "UPDATE threads SET archived = 1 WHERE id = '\$id';" ;;
    unarchive) sqlite3 "$DB" "UPDATE threads SET archived = 0 WHERE id = '\$id';" ;;
esac
EOF
chmod +x "$WORK/bin/codex"
cp "$WORK/bin/codex" "$WORK/codex.fake"
# Fake claude: records how it was started.
printf '#!/bin/sh\necho "$*" >>"%s/claude.log"\n' "$WORK" >"$WORK/bin/claude"
chmod +x "$WORK/bin/claude"

# ── Claude Code fixture ──────────────────────────────────────────────────────

G=11111111-0000-4000-8000-000000000007 # claude: old session in PROJ, with a bundle
H=22222222-0000-4000-8000-000000000008 # claude: empty session
I=33333333-0000-4000-8000-000000000009 # claude: open in a running Claude Code
mkdir -p "$CPROJ" "$CLAUDE_CONFIG_DIR/sessions"

# claude_session ID AGE_DAYS CWD TITLE PROMPT
claude_session() {
    local id=$1 ts=$(($(date +%s) - $2 * 86400)) file=$CPROJ/$1.jsonl
    {
        printf '{"type":"user","isMeta":true,"cwd":"%s","entrypoint":"cli","timestamp":"2026-01-01T10:00:00.000Z","sessionId":"%s","message":{"role":"user","content":"<command-name>/clear</command-name>"}}\n' "$3" "$id"
        if [[ -n $5 ]]; then
            printf '{"type":"user","cwd":"%s","timestamp":"2026-01-01T10:00:01.000Z","message":{"role":"user","content":"%s"}}\n' "$3" "$5"
            printf '{"type":"assistant","cwd":"%s","timestamp":"2026-01-01T10:00:02.000Z","message":{"model":"claude-test-1","role":"assistant","content":[{"type":"thinking","thinking":"hidden"},{"type":"text","text":"Sure, done."}]}}\n' "$3"
        fi
        [[ -z $4 ]] || printf '{"type":"ai-title","aiTitle":"%s","sessionId":"%s"}\n' "$4" "$id"
    } >"$file"
    set_mtime "$ts" "$file"
}
claude_session "$G" 60 "$PROJ" "Design the cache" "how should we cache the parser output"
claude_session "$H" 30 "$WORK/other" "" ""
claude_session "$I" 20 "$WORK/other" "Live work" "keep going"
mkdir -p "$CPROJ/$G/subagents" "$CLAUDE_CONFIG_DIR/session-env/$G" "$CLAUDE_CONFIG_DIR/file-history/$G"
echo '{}' >"$CPROJ/$G/subagents/agent-x.jsonl"
set_mtime "$(($(date +%s) - 60 * 86400))" "$CPROJ/$G.jsonl"
# I is registered as a running session of this very shell (with its start time on Linux).
start=""
if [[ -r /proc/$$/stat ]]; then
    read -ra stat <<<"$(sed 's/^.*) //' "/proc/$$/stat")"
    start=${stat[19]}
fi
printf '{"pid":%d,"sessionId":"%s","procStart":"%s"}\n' "$$" "$I" "$start" >"$CLAUDE_CONFIG_DIR/sessions/$$.json"
# A stale manifest: dead pid, must not protect anything.
printf '{"pid":999999999,"sessionId":"%s"}\n' "$H" >"$CLAUDE_CONFIG_DIR/sessions/999999999.json"

cp -a "$CODEX_HOME" "$WORK/codex.pristine"
cp -a "$CLAUDE_CONFIG_DIR" "$WORK/claude.pristine"
reset_fixture() {
    rm -rf "$CODEX_HOME" "$CLAUDE_CONFIG_DIR" "$XDG_DATA_HOME"
    cp -a "$WORK/codex.pristine" "$CODEX_HOME"
    cp -a "$WORK/claude.pristine" "$CLAUDE_CONFIG_DIR"
    : >"$WORK/codex.log"
    : >"$WORK/claude.log"
    rm -f "$WORK/on-delete"
    cp "$WORK/codex.fake" "$WORK/bin/codex"
}

# ── Assertions ───────────────────────────────────────────────────────────────

ok() { passed=$((passed + 1)) && printf '  ✓ %s\n' "$1"; }
ko() { failed=$((failed + 1)) && printf '  ✗ %s\n%s\n' "$1" "${2:-}" | sed '2,$s/^/      /'; }
check() { if eval "$2"; then ok "$1"; else ko "$1" "${3:-}"; fi; }

# expect_ids NAME "EXPECTED IDS" ARGS... — `list --ids ARGS` must print exactly EXPECTED.
expect_ids() {
    local name=$1 expected actual
    expected=$(tr ' ' '\n' <<<"$2" | sed '/^$/d' | sort | tr '\n' ' ')
    shift 2
    actual=$("$LETHE" list --ids "$@" | sort | tr '\n' ' ')
    if [[ $actual == "$expected" ]]; then ok "$name"; else ko "$name" "expected: $expected"$'\n'"got:      $actual"; fi
}

# expect_status NAME CODE ARGS...
expect_status() {
    local name=$1 code=$2 status=0
    shift 2
    "$LETHE" "$@" >/dev/null 2>&1 </dev/null || status=$?
    if ((status == code)); then ok "$name"; else ko "$name" "expected exit $code, got $status"; fi
}

codex_exists() { [[ -n $(sqlite3 "$DB" "SELECT id FROM threads WHERE id = '$1';") ]]; }
archived() { [[ $(sqlite3 "$DB" "SELECT archived FROM threads WHERE id = '$1';") == 1 ]]; }

# ── Tests ────────────────────────────────────────────────────────────────────

echo "portability"
# macOS bash reads `$VAR●` as one name under some locales: brace them.
out=$(perl -ne 'print "$.: $_" if /\$[A-Za-z_]\w*[^\x00-\x7f]/' "$LETHE")
check "no unbraced variable before non-ASCII text" '[[ -z $out ]]' "$out"

echo "filters"
expect_ids "no filter lists both agents" "$A $B $C $D $E $F $G $H $I"
expect_ids "--claude" "$G $H $I" --claude
expect_ids "--agent codex" "$A $B $C $D $E $F" --agent codex
expect_ids "--archived" "$D" --archived
expect_ids "--older-than" "$A $C $F $G" --older-than 45d
expect_ids "--newer-than" "$B $E" --newer-than 1w
expect_ids "--dir includes subdirectories, both agents" "$A $B $C $G" --dir "$PROJ"
out=$(cd "$WORK" && "$LETHE" list --ids --dir proj/sub)
check "--dir with a relative path" '[[ $out == "$B" ]]' "$out"
expect_ids "--dir does not match sibling prefixes" "" --dir "${PROJ%/proj}/pro"
expect_ids "--mode subagent" "$C" --mode subagent
expect_ids "--provider" "$G $H $I" --provider anthropic
expect_ids "--empty" "$E $H" --empty
expect_ids "--missing" "$F" --missing
expect_ids "--grep searches both agents, case-insensitive" "$A $G" --grep PARSER
expect_ids "--grep ignores injected context" "" --grep secretword
expect_ids "--grep ignores hidden reasoning" "" --grep hidden
expect_ids "filters combine with AND" "$A $C" --codex --dir "$PROJ" --older-than 30d
expect_ids "--keep spares the latest sessions of each project" "$D $F $H" --keep 1
mv "$WORK/other" "$WORK/other.moved"
expect_ids "--orphans" "$D $E $F $H $I" --orphans
mv "$WORK/other.moved" "$WORK/other"
expect_ids "id prefix" "$G" 11111111
expect_ids "--opt=value syntax" "$B" --mode=exec
expect_status "invalid --sort" 2 list --sort name

echo "output"
order=$("$LETHE" list --ids --sort size --codex | tr '\n' ' ')
check "--sort size: biggest first, missing last" '[[ $order == "$A $B "* && $order == *" $F " ]]' "$order"
check "list --json" '"$LETHE" list --json | jq -e "length == 9 and (map(select(.open)) | map(.id)) == [\"$I\"]" >/dev/null'
out=$("$LETHE" list --claude)
check "Claude titles come from ai-title" '[[ $out == *"Design the cache"* ]]' "$out"
out=$("$LETHE" list --codex)
check "untitled subagents are named after their nickname" '[[ $out == *"subagent Kepler"* ]]' "$out"
out=$("$LETHE" stats)
check "stats" '[[ $out == *Total*9* && $out == *"1 session(s) open"* ]]' "$out"
out=$("$LETHE" show "$A")
check "show (codex)" '[[ $out == *"please refactor the Parser"* && $out != *secretword* ]]' "$out"
out=$("$LETHE" show "$G")
check "show (claude) counts subagent transcripts" '[[ $out == *"1 subagent ("* ]]' "$out"
check "show (claude) skips reasoning and wrappers" \
    '[[ $out == *"how should we cache"* && $out == *"Sure, done."* && $out != *hidden* && $out != *command-name* ]]' "$out"
perl -pi -e 's/Design the cache/Cache design v2/' "$CPROJ/$G.jsonl" && set_mtime "$(($(date +%s) - 86400))" "$CPROJ/$G.jsonl"
out=$("$LETHE" list --claude)
check "the Claude index picks up modified transcripts" '[[ $out == *"Cache design v2"* ]]' "$out"

echo "safety"
expect_status "unknown option" 2 list --bogus
expect_status "invalid duration" 2 list --older-than 3x
expect_status "delete without filter is refused" 2 delete -y
expect_status "an agent alone is not a filter" 2 delete --claude -y
expect_status "--yes is not a list option" 2 list --yes
expect_status "unknown id" 1 delete -y 99999999
expect_status "non-interactive delete needs --yes" 1 delete "$A"
reset_fixture
"$LETHE" delete --older-than 30d --dry-run >/dev/null
check "--dry-run changes nothing" '[[ ! -s $WORK/codex.log && -f $CPROJ/$G.jsonl ]] && codex_exists "$A"'

reset_fixture
out=$("$LETHE" delete -y "$I" 2>&1)
check "an open Claude session is never deleted" '[[ -f $CPROJ/$I.jsonl && $out == *"open in a running agent"* ]]' "$out"
out=$("$LETHE" delete -y "$E" 2>&1)
check "a session active in the last 10 minutes is skipped" '[[ $out == *"active in the last 10 minutes"* ]] && codex_exists "$E"' "$out"
"$LETHE" delete -y --force "$E" >/dev/null 2>&1
check "--force includes recent sessions" '! codex_exists "$E"'
out=$("$LETHE" delete -y --force "$I" 2>&1)
check "--force never includes open sessions" '[[ -f $CPROJ/$I.jsonl ]]' "$out"

reset_fixture
exec 9<"$(codex_file "$A" 0)" # A is now open, like a running Codex holds its rollout
out=$("$LETHE" delete -y "$C" 2>&1)
check "a subagent of an open Codex session is protected" '[[ $out == *"spawned by a session that is open"* ]] && codex_exists "$C"' "$out"
out=$("$LETHE" delete -y "$A" 2>&1)
check "an open Codex session and its subagents are protected" 'codex_exists "$A" && codex_exists "$C" && [[ ! -s $WORK/codex.log ]]' "$out"
exec 9<&-

echo "actions"
reset_fixture
"$LETHE" delete -y "$A" >"$WORK/out" 2>&1
check "codex delete also removes spawned subagents" '! codex_exists "$A" && ! codex_exists "$C" && codex_exists "$B"' "$(cat "$WORK/out")"
check "children are deleted before parents" '[[ $(head -n 1 "$WORK/codex.log") == "delete --force $C" ]]' "$(cat "$WORK/codex.log")"

reset_fixture
"$LETHE" delete -y "$G" >"$WORK/out" 2>&1
check "claude delete moves the whole session to the trash" \
    '[[ ! -e $CPROJ/$G.jsonl && ! -e $CPROJ/$G && ! -e $CLAUDE_CONFIG_DIR/session-env/$G && ! -e $CLAUDE_CONFIG_DIR/file-history/$G ]]' \
    "$(cat "$WORK/out")"
out=$("$LETHE" trash)
check "trash list" '[[ $out == *"Design the cache"* && $out == *"1 session(s) in the trash"* ]]' "$out"
"$LETHE" trash restore 1111 >/dev/null
check "trash restore puts every file back" \
    '[[ -f $CPROJ/$G.jsonl && -f $CPROJ/$G/subagents/agent-x.jsonl && -d $CLAUDE_CONFIG_DIR/session-env/$G ]] && [[ -z $(ls -A "$TRASH") ]]'
"$LETHE" delete -y "$G" >/dev/null 2>&1
mkdir -p "$CLAUDE_CONFIG_DIR/session-env/$G"
expect_status "restore never overwrites" 1 trash restore "$G"
"$LETHE" trash empty -y >/dev/null
check "trash empty" '[[ -z $(ls -A "$TRASH") ]]'

echo "picker"
reset_fixture
"$LETHE" delete -y "$G" >/dev/null 2>&1
export LETHE_STATE=$WORK/picker LETHE_FILTERS=""
mkdir -p "$LETHE_STATE"
printf '%s\n' all >"$LETHE_STATE/agent"
printf '%s\n' all >"$LETHE_STATE/status"
printf '%s\n' recent >"$LETHE_STATE/sort"
printf '%s\n' all >"$LETHE_STATE/filter"
: >"$LETHE_STATE/grep"
: >"$LETHE_STATE/dir"
picker_ids() { "$LETHE" __rows | cut -f 1 | sort | tr '\n' ' '; }
check "picker: column titles come first when the panel layout is on" \
    '[[ $(LETHE_COLUMNS=1 "$LETHE" __rows | head -n 1) == *"AGENT"*"PROJECT"*"TITLE"* ]]'
"$LETHE" __rows >/dev/null
out=$(FZF_SELECT_COUNT=2 "$LETHE" __marked "$A" "$B")
sum=$("$LETHE" list --json "$A" "$B" | jq '[.[].size] | add / 1024 * 10 | floor / 10')
check "picker: the list label sums the marked sessions" '[[ $out == " 2 marked · ${sum}K ·"* ]]' "$out (expected ${sum}K)"
out=$(REINDEX=0 bash -c 'source <(sed "s/^main \"\$@\"\$//" "$1"); choose_lines filter' _ "$LETHE" | perl -pe 's/\e\[[0-9;]*m//g')
check "picker: Ctrl-F lists filters with their counts" \
    '[[ $(grep "^empty" <<<"$out") =~ [[:space:]]2[[:space:]] && $(grep "^missing" <<<"$out") =~ [[:space:]]1[[:space:]] ]]' "$out"
out=$(REINDEX=0 bash -c 'source <(sed "s/^main \"\$@\"\$//" "$1"); choose_lines dir "$2"' _ "$LETHE" "$B" | perl -pe 's/\e\[[0-9;]*m//g')
printf '=%s' "$PROJ" >"$LETHE_STATE/dir"
check "picker: a project chosen with Ctrl-W excludes the projects below it" '[[ $(picker_ids) == "$A $C " ]]' "$(picker_ids)"
: >"$LETHE_STATE/dir"
check "picker: Ctrl-W lists projects, the current one first" \
    '[[ $(sed -n 2p <<<"$out") == "$PROJ/sub"$'"'"'\t'"'"'* ]]' "$out"
printf 'claude\n' >"$LETHE_STATE/agent" && printf 'active\n' >"$LETHE_STATE/status"
"$LETHE" __state status
check "picker: Ctrl-S skips archived for Claude Code" '[[ $(<"$LETHE_STATE/status") == all ]]'
printf 'all\n' >"$LETHE_STATE/agent"
printf 'full\n' >"$LETHE_STATE/keys"
"$LETHE" __state keys
check "picker: F1 switches to the short key list" '[[ $(<"$LETHE_STATE/keys") == short && $("$LETHE" __state footer) == *"F1 all keys"* ]]'
"$LETHE" __state keys
printf '#!/bin/sh\ncat >"%s/clipboard"\n' "$WORK" >"$WORK/bin/pbcopy" && chmod +x "$WORK/bin/pbcopy"
WAYLAND_DISPLAY="" DISPLAY="" "$LETHE" __copy "$A" </dev/null
check "picker: Ctrl-Y copies the command that resumes the session" \
    '[[ $(<"$WORK/clipboard") == "cd $PROJ && codex resume $A" ]]' "$(cat "$WORK/clipboard" 2>/dev/null)"
"$LETHE" __state filter
check "picker: Ctrl-F shows empty sessions" '[[ $(picker_ids) == "$H $E " ]]' "$(picker_ids)"
check "picker: prompt names the filter" '[[ $("$LETHE" __state prompt) == "all agents · empty ❯ " ]]'
printf '%s\n' trash >"$LETHE_STATE/filter"
check "picker: the trash view has its column titles once" \
    '[[ $(LETHE_COLUMNS=1 "$LETHE" __rows | grep -c AGENT) == 1 ]]' "$(LETHE_COLUMNS=1 "$LETHE" __rows)"
check "picker: the trash view lists trashed sessions" '[[ $(picker_ids) == trash:claude-$G.* ]]' "$(picker_ids)"
out=$("$LETHE" __preview "$("$LETHE" __rows | cut -f 1)")
check "picker: trashed sessions can be read" '[[ $out == *"in the trash"* && $out == *"how should we cache"* ]]' "$out"
printf '%s\n' all >"$LETHE_STATE/filter"
"$LETHE" __state dir "$B"
check "picker: Ctrl-W keeps the current project" '[[ $(picker_ids) == "$B " ]]' "$(picker_ids)"
"$LETHE" __state dir "$B"
"$LETHE" __state grep parser
check "picker: Ctrl-G searches the conversations" '[[ $(picker_ids) == "$A " ]]' "$(picker_ids)"
out=$("$LETHE" __preview "$A")
check "picker: an empty open-session list does not break the preview" '[[ $out == *Parser* ]]' "$out"
unset LETHE_STATE LETHE_FILTERS

reset_fixture
"$LETHE" delete --missing -y >/dev/null 2>&1
check "delete --missing" '! codex_exists "$F" && codex_exists "$A"'

reset_fixture
"$LETHE" archive --dir "$PROJ/sub" -y >/dev/null 2>&1
check "archive" 'archived "$B" && ! archived "$A"'
"$LETHE" unarchive "$B" "$D" -y >/dev/null 2>&1
check "unarchive" '! archived "$B" && ! archived "$D"'
out=$("$LETHE" archive "$G" -y 2>&1)
check "Claude sessions cannot be archived" '[[ $out == *"cannot be archived"* && -f $CPROJ/$G.jsonl ]]' "$out"

reset_fixture
printf '#!/bin/sh\nexit 0\n' >"$WORK/bin/codex"
status=0
"$LETHE" delete -y "$B" >"$WORK/out" 2>&1 || status=$?
check "a no-op codex is reported as a failure" '((status == 1)) && grep -q "not updated" "$WORK/out"' "$(cat "$WORK/out")"

echo "hardening"
reset_fixture
ln -s "$CODEX_HOME" "$WORK/codex-link"
exec 9<"$(codex_file "$A" 0)" # A is open, as a running Codex holds its rollout
out=$(CODEX_HOME=$WORK/codex-link "$LETHE" delete -y "$A" 2>&1) || true
exec 9<&-
check "open sessions are seen through a symlinked CODEX_HOME" \
    '[[ $out == *"open in a running agent"* ]] && codex_exists "$A"' "$out"

sqlite3 "$DB" "UPDATE threads SET has_user_event = 1 WHERE id = '$E';"
expect_ids "a Codex session with a user event is not empty" "$H" --empty
sqlite3 "$DB" "UPDATE threads SET first_user_message = 'continue the migration' WHERE id = '$E';"
out=$("$LETHE" list --codex)
check "Codex titles fall back to the first user message" '[[ $out == *"continue the migration"* ]]' "$out"
printf '%s\n' \
    '{"type":"user","cwd":"/w","timestamp":"2026-01-01T10:00:00.000Z","message":{"role":"user","content":"<command-name>/review</command-name>"}}' \
    '{"type":"assistant","cwd":"/w","timestamp":"2026-01-01T10:00:01.000Z","message":{"model":"claude-test-1","role":"assistant","content":[{"type":"text","text":"Reviewed."}]}}' \
    >"$CPROJ/$H.jsonl"
expect_ids "a Claude session started by a command, with a reply, is not empty" "" --empty --claude
printf '%s\n' '{"type":"user","cwd":"/w","timestamp":"2026-01-01T10:00:00.000Z","message":{"role":"user","content":[{"type":"image","source":{}}]}}' \
    >"$CPROJ/$H.jsonl"
expect_ids "an image-only Claude session is not empty" "" --empty --claude

reset_fixture
moved=$(codex_file "$D" 1)
sqlite3 "$DB" "UPDATE threads SET rollout_path = '$CODEX_HOME/sessions/gone/rollout-x-$D.jsonl' WHERE id = '$D';"
expect_ids "a transcript the index lost track of is not missing" "$F" --missing
check "and it can still be read" '"$LETHE" show "$D" | grep -q "an old idea"'
sqlite3 "$DB" "UPDATE threads SET rollout_path = '${moved#"$CODEX_HOME"/}' WHERE id = '$D';"
expect_ids "relative index paths are under CODEX_HOME" "$F" --missing
printf '%s\n' '{"type":"session_meta","payload":{"id":"x"}}' \
    '{"type":"event_msg","payload":{"type":"user_message","message":"event only question"}}' \
    '{"type":"event_msg","payload":{"type":"agent_message","message":"event only answer"}}' >"$moved"
out=$("$LETHE" show "$D")
check "Codex transcripts with only message events can be read" \
    '[[ $out == *"event only question"* && $out == *"event only answer"* ]]' "$out"

reset_fixture
set_mtime "$(date +%s)" "$(codex_file "$B" 0)"
out=$("$LETHE" delete -y "$B" 2>&1)
check "a transcript written after the index counts as recent activity" \
    '[[ $out == *"active in the last 10 minutes"* ]] && codex_exists "$B"' "$out"

reset_fixture
codex_file "$B" 0 >"$WORK/on-delete"
out=$("$LETHE" delete -y "$A" "$B" 2>&1) || true
check "a session written to after the plan is left alone" \
    '[[ $out == *"changed since the plan"* ]] && codex_exists "$B" && ! codex_exists "$A"' "$out"

reset_fixture
chmod a-w "$CLAUDE_CONFIG_DIR/session-env"
out=$("$LETHE" delete -y "$G" 2>&1) || true
chmod u+w "$CLAUDE_CONFIG_DIR/session-env"
# (as root the read-only directory would not stop the move)
((EUID == 0)) || check "a failed move to the trash puts everything back" \
    '[[ -f $CPROJ/$G.jsonl && -d $CPROJ/$G && -d $CLAUDE_CONFIG_DIR/file-history/$G && -z $(ls -A "$TRASH" 2>/dev/null) ]]' "$out"
"$LETHE" delete -y "$G" >/dev/null 2>&1
manifest=$(echo "$TRASH"/*/manifest.json)
jq --arg bad "$WORK/outside.jsonl" '.items[0] = $bad' "$manifest" >"$manifest.new" && mv "$manifest.new" "$manifest"
expect_status "restore refuses manifest paths outside the Claude directory" 1 trash restore "$G"
check "and moves nothing" '[[ ! -e $WORK/outside.jsonl && ! -e $CPROJ/$G.jsonl ]]'

reset_fixture
printf '%s\n' '{"type":"assistant","cwd":"/w","timestamp":"2026-01-01T10:00:01.000Z","message":{"model":"claude-test-1","role":"assistant","content":[{"type":"text","text":"**Done** with `make test`, and here is a fairly long sentence that has to wrap on word boundaries."}]}}' \
    >>"$CPROJ/$G.jsonl"
out=$(NO_COLOR="" FZF_PREVIEW_COLUMNS=30 "$LETHE" __preview "$G" | perl -pe 's/\e\[[0-9;]*m//g')
check "the preview wraps on words and renders light Markdown" \
    '[[ $out == *"Done with make test"* && $out != *"**"* ]] && ! awk "length > 30 { exit 1 }" <<<"$out"' "$out"
out=$(FZF_PREVIEW_COLUMNS=30 PAGER=cat "$LETHE" __page "$G" </dev/null | perl -pe 's/\e\[[0-9;]*m//g')
check "Enter reads the conversation full width, even with the preview shown" \
    '[[ $out == *"here is a fairly long sentence that has to wrap"* ]]' "$out"

reset_fixture
# Ctrl-C while a session moves to the trash (the signal reaches the whole
# process group): the session ends up fully moved, never half.
mkdir -p "$WORK/slow"
printf '#!/bin/sh\nsleep 0.3\nexec /bin/mv "$@"\n' >"$WORK/slow/mv" && chmod +x "$WORK/slow/mv"
PATH=$WORK/slow:$PATH perl -e 'setpgrp; exec @ARGV' "$LETHE" delete -y "$G" >/dev/null 2>&1 &
group=$!
for _ in $(seq 200); do
    [[ -z $(ls "$TRASH"/*/files/file-history 2>/dev/null) ]] || break # one item moved
    sleep 0.05
done
kill -TERM -- "-$group" 2>/dev/null || true
wait "$group" 2>/dev/null || true
sleep 1.5
items=("$CPROJ/$G.jsonl" "$CPROJ/$G" "$CLAUDE_CONFIG_DIR/session-env/$G" "$CLAUDE_CONFIG_DIR/file-history/$G")
present=0
for item in "${items[@]}"; do [[ ! -e $item ]] || present=$((present + 1)); done
check "Ctrl-C during a trash move leaves the session whole" '((present == 0 || present == 4))' "$present of 4 items left"

echo "branches"
reset_fixture
# A rewind (the second prompt was edited), parallel tool results (one with a
# queued note) and a compaction whose logical parent is written after it.
{
    entry() { printf '{"type":"%s","uuid":"%s","parentUuid":%s,"cwd":"%s","timestamp":"2026-01-01T10:00:00.000Z","message":{"role":"%s","model":"claude-test-1","content":%s}}\n' "$1" "$2" "$3" "$PROJ" "$1" "$4"; }
    entry user u1 null '"first question"'
    entry assistant a1 '"u1"' '[{"type":"text","text":"first answer"}]'
    entry user u2 '"a1"' '"abandoned prompt"'
    entry assistant a2 '"u2"' '[{"type":"text","text":"abandoned reply"}]'
    entry user u2b '"a1"' '"kept prompt"'
    entry assistant t1 '"u2b"' '[{"type":"tool_use","id":"x","name":"Read","input":{}}]'
    entry user r1 '"t1"' '[{"type":"tool_result","tool_use_id":"x","content":"ok"}]'
    entry user r2 '"t1"' '[{"type":"tool_result","tool_use_id":"y","content":"ok"},{"type":"text","text":"queued note"}]'
    entry assistant a3 '"r1"' '[{"type":"text","text":"after tools"}]'
    printf '{"type":"system","subtype":"compact_boundary","uuid":"cb","parentUuid":null,"logicalParentUuid":"late"}\n'
    printf '{"type":"attachment","uuid":"late","parentUuid":"a3"}\n'
    entry user u3 '"cb"' '"after compaction"'
    entry assistant a5 '"u3"' '[{"type":"text","text":"final answer"}]'
    printf '{"type":"ai-title","aiTitle":"Branchy","sessionId":"%s"}\n' "$G"
} >"$CPROJ/$G.jsonl"
set_mtime "$(($(date +%s) - 3600))" "$CPROJ/$G.jsonl"
out=$("$LETHE" show "$G")
check "show follows the active branch only" \
    '[[ $out == *"kept prompt"* && $out == *"queued note"* && $out == *"after tools"* && $out == *"final answer"* && $out != *"abandoned prompt"* && $out != *"abandoned reply"* ]]' "$out"
check "and says how many branches are hidden" '[[ $out == *"1 abandoned branch(es) hidden"* ]]' "$out"
out=$("$LETHE" export "$G" --all-branches)
check "export --all-branches labels abandoned messages" \
    '[[ $out == *$'"'"'## You (abandoned)\n\nabandoned prompt'"'"'* && $out == *"## Claude (abandoned)"* && $out == *$'"'"'## You\n\nkept prompt'"'"'* ]]' "$out"
out=$("$LETHE" export "$G")
check "export keeps the active branch by default" '[[ $out != *"abandoned"* && $out == *"final answer"* ]]' "$out"
expect_ids "--grep searches abandoned branches too" "$G" --grep "abandoned reply"
out=$("$LETHE" list --claude)
check "list shows the abandoned-branch badge" '[[ $out == *"⑂1 Branchy"* ]]' "$out"
mkdir -p "$WORK/branches" && printf 'all\n' >"$WORK/branches/branches"
out=$(LETHE_STATE=$WORK/branches "$LETHE" __preview "$G")
check "picker: Alt-B state shows abandoned branches in the preview" \
    '[[ $out == *"You (abandoned)"* && $out == *"abandoned reply"* ]]' "$out"
printf 'all\n' >"$WORK/branches/filter" && : >"$WORK/branches/grep" && : >"$WORK/branches/dir"
printf 'all\n' >"$WORK/branches/agent" && printf 'all\n' >"$WORK/branches/status"
check "picker: the prompt says when all branches are shown" \
    '[[ $(LETHE_STATE=$WORK/branches "$LETHE" __state prompt) == *"⑂ all branches"* ]]'
parent=a5
for n in $(seq 1 30); do
    printf '{"type":"user","uuid":"m%d","parentUuid":"%s","message":{"role":"user","content":"more %d"}}\n' "$n" "$parent" "$n"
    parent=m$n
done >>"$CPROJ/$G.jsonl"
set_mtime "$(($(date +%s) - 3600))" "$CPROJ/$G.jsonl"
out=$(LETHE_STATE=$WORK/branches "$LETHE" __preview "$G")
check "picker: a long preview keeps the abandoned messages" \
    '[[ $out == *"abandoned prompt"* && $out == *"more messages"* && $out == *"more 30"* ]]' "$out"
check "list --json counts abandoned branches" \
    '"$LETHE" list --json --claude | jq -e "map(select(.id == \"$G\"))[0].abandoned_branches == 1" >/dev/null'

reset_fixture
out=$("$LETHE" resume "$I" 2>&1) || true
check "resume refuses a session that is already open" '[[ $out == *"already open"* && ! -s $WORK/claude.log ]]' "$out"
expect_status "resume refuses subagent sessions" 1 resume "$C"
"$LETHE" fork "$I" >/dev/null 2>&1
check "fork opens a copy of a Claude session" '[[ $(cat "$WORK/claude.log") == "--resume $I --fork-session" ]]' \
    "$(cat "$WORK/claude.log")"
"$LETHE" fork "$A" >/dev/null 2>&1
check "fork uses codex fork" 'grep -qx "fork $A" "$WORK/codex.log"' "$(cat "$WORK/codex.log")"
out=$("$LETHE" export "$A")
check "export writes the conversation as Markdown" \
    '[[ $out == "# Refactor parser"* && $out == *"## You"* && $out == *"please refactor the Parser"* && $out != *secretword* ]]' "$out"

echo
printf '%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
