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
        # Test hook: remove another transcript while a deletion runs.
        if [[ -f "$WORK/on-delete-rm" ]]; then rm -f -- "\$(cat "$WORK/on-delete-rm")"; rm -f "$WORK/on-delete-rm"; fi
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

# claude_chat ID AGE_DAYS CWD ROLE:TEXT... — a Claude Code transcript of linked messages.
claude_chat() {
    local id=$1 days=$2 cwd=$3 file=$CPROJ/$1.jsonl parent=null n=0 arg
    shift 3
    : >"$file"
    for arg; do
        n=$((n + 1))
        jq -cn --arg role "${arg%%:*}" --arg text "${arg#*:}" --arg uuid "$id-$n" --argjson parent "$parent" \
            --arg cwd "$cwd" '{type: $role, uuid: $uuid, parentUuid: $parent, cwd: $cwd,
              timestamp: "2026-01-01T10:00:00.000Z",
              message: (if $role == "user" then {role: "user", content: $text}
                        else {role: "assistant", model: "claude-test-1", content: [{type: "text", text: $text}]} end)}' \
            >>"$file"
        parent="\"$id-$n\""
    done
    set_mtime "$(($(date +%s) - days * 86400))" "$file"
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
# The top CHANGELOG section is the next or current version, never an older one.
version=$("$LETHE" --version | cut -d' ' -f2)
top=$(grep -m1 '^## ' "$ROOT/CHANGELOG.md" | cut -d' ' -f2)
# Characters, not bytes: macOS awk counts the bytes of ◉ and ◔.
out=$("$LETHE" --help | perl -CSD -ne 'print if length > 81')
check "--help fits 80 columns" '[[ -z $out ]]' "$out"
check "CHANGELOG starts with Unreleased or the current version" '[[ $top == Unreleased || $top == "$version" ]]' \
    "top: $top, version: $version"

echo "filters"
expect_ids "no filter lists both agents" "$A $B $C $D $E $F $G $H $I"
expect_ids "--claude" "$G $H $I" --claude
expect_ids "--agent codex" "$A $B $C $D $E $F" --agent codex
expect_ids "--archived" "$D" --archived
expect_ids "--running: open or active in the last 10 minutes" "$E $I" --running
expect_ids "--idle: neither running nor archived" "$A $B $C $F $G $H" --idle
expect_ids "--unarchived (and its old name --active)" "$A $B $C $E $F $G $H $I" --active
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
expect_ids "--keep spares the latest sessions of each project, both agents together" "$A $D $F $H $I" --keep 1
mv "$WORK/other" "$WORK/other.moved"
expect_ids "--orphans" "$D $E $F $H $I" --orphans
mv "$WORK/other.moved" "$WORK/other"
expect_ids "id prefix" "$G" 11111111
expect_ids "--opt=value syntax" "$B" --mode=exec
expect_status "invalid --sort" 2 list --sort name
check "--sort oldest" '[[ $("$LETHE" list --ids --sort oldest --codex | head -n 1) == "$A" || $("$LETHE" list --ids --sort oldest --codex | head -n 1) == "$C" ]]' "$("$LETHE" list --ids --sort oldest --codex)"

echo "output"
order=$("$LETHE" list --ids --sort size --codex | tr '\n' ' ')
check "--sort size: biggest first, missing last" '[[ $order == "$A $B "* && $order == *" $F " ]]' "$order"
check "list --json" '"$LETHE" list --json | jq -e "length == 9 and (map(select(.open)) | map(.id)) == [\"$I\"]" >/dev/null'
out=$("$LETHE" list --claude)
check "Claude titles come from ai-title" '[[ $out == *"Design the cache"* ]]' "$out"
out=$("$LETHE" list --codex)
check "untitled subagents are named after their nickname" '[[ $out == *"subagent Kepler"* ]]' "$out"
out=$("$LETHE" stats)
check "stats" '[[ $out == *Total*9* && $out == *"2 running session(s), protected"*"list --running"* ]]' "$out"
out=$("$LETHE" show "$E" 2>&1; "$LETHE" show "$A" 2>&1)
check "show: the status reads running or idle" \
    '[[ $out == *"running (active in the last 10 minutes)"* && $out == *"  idle  "* ]]' "$out"
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
expect_status "two statuses at once" 2 list --running --idle
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
    '[[ $(sed -n 3p <<<"$out") == "$PROJ/sub"$'"'"'\t'"'"'* ]]' "$out"
out=""
for _ in 1 2 3 4; do "$LETHE" __state status && out+="$(<"$LETHE_STATE/status") "; done
check "picker: Ctrl-S cycles running, idle, archived, all" '[[ $out == "running idle archived all " ]]' "$out"
printf 'running\n' >"$LETHE_STATE/status"
check "picker: Ctrl-S running lists the open and recent sessions" '[[ $(picker_ids) == "$I $E " ]]' "$(picker_ids)"
check "picker: the prompt and footer show the status" \
    '[[ $("$LETHE" __state prompt) == *running* && $(NO_COLOR=1 "$LETHE" __state footer) == *"Ctrl-S status: running"* ]]'
printf 'claude\n' >"$LETHE_STATE/agent" && printf 'idle\n' >"$LETHE_STATE/status"
"$LETHE" __state status
check "picker: Ctrl-S skips archived for Claude Code" '[[ $(<"$LETHE_STATE/status") == all ]]'
printf 'all\n' >"$LETHE_STATE/agent"
printf 'full\n' >"$LETHE_STATE/keys" && printf 'size\n' >"$LETHE_STATE/sort"
out=$(NO_COLOR=1 "$LETHE" __state footer)
check "picker: the footer shows where each switch stands" \
    '[[ $out == *"Ctrl-T agent: all"* && $out == *"Ctrl-O sort: size"* && $out == *"Ctrl-G find: off"* ]]' "$out"
check "picker: the prompt shows a non-default sort" '[[ $("$LETHE" __state prompt) == *"by size"* ]]'
printf 'recent\n' >"$LETHE_STATE/sort"
printf 'stats\n' >"$LETHE_STATE/panel" && printf 'codex\n' >"$LETHE_STATE/agent"
out=$(NO_COLOR=1 FZF_PREVIEW_COLUMNS=60 "$LETHE" __preview "$A")
check "picker: Ctrl-B shows the stats of the listed sessions in the panel" \
    '[[ $out == *"Disk usage of the sessions listed"* && $out == *"codex"* && $out != *"claude  "* ]] && perl -CSD -ne "exit 1 if length > 61" <<<"$out"' "$out"
printf 'conversation\n' >"$LETHE_STATE/panel" && printf 'all\n' >"$LETHE_STATE/agent"
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
out=$(NO_COLOR="" "$LETHE" __preview "$A" | perl -pe 's/\e\[[0-9;]*m//g')
check "picker: with Ctrl-G the preview shows the messages that mention the text" \
    '[[ $out == *"1 of 1 messages mention “parser”"* && $out == *"refactor the Parser"* ]]' "$out"
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

echo "regressions"
reset_fixture
# shellcheck disable=SC2034 # used in the check below
ids=$("$LETHE" list --ids | sort | tr '\n' ' ')
out=$(cd "$PROJ" && "$LETHE" list --ids --dir / | sort | tr '\n' ' ')
check "--dir / means every project" '[[ $out == "$ids" ]]' "$out"

Q=44444444-0000-4000-8000-0000000000aa
claude_chat "$Q" 3 "$PROJ" 'user:say "hello" to C:\temp' 'assistant:ok'
expect_ids "--grep finds text with double quotes" "$Q" --grep 'say "hello"'
expect_ids "--grep finds text with backslashes" "$Q" --grep 'C:\temp'

T=55555555-0000-4000-8000-0000000000bb
claude_chat "$T" 3 "$PROJ" 'user:<template> is not rendering'
out=$("$LETHE" export "$T")
check "a prompt starting with < is the user's text" '[[ $out == *"<template> is not rendering"* ]]' "$out"
expect_ids "... and the session is not empty" "$H" --empty --claude
out=$("$LETHE" list --claude --json | jq -r --arg id "$T" '.[] | select(.id == $id) | .title')
check "... and it is the title" '[[ $out == "<template> is not rendering" ]]' "$out"

X=66666666-0000-4000-8000-0000000000cc
claude_chat "$X" 3 "$PROJ" $'user:fix it \e]0;TITLE\a now' $'assistant:done \e]52;c;cHduZWQ=\a \e[2J'
out=$("$LETHE" list; "$LETHE" show "$X"; "$LETHE" export "$X")
check "control characters from transcripts never reach the terminal" \
    '[[ $out != *$'"'"'\e'"'"'* && $out != *$'"'"'\a'"'"'* && $out == *"fix it ]0;TITLE now"* ]]' "$(printf '%q' "$out")"

Z=77777777-0000-4000-8000-0000000000dd
claude_chat "$Z" 3 "$PROJ" 'user:first prompt' 'assistant:first reply'
jq -cn '{type: "user", uuid: "z-sum", parentUuid: null, logicalParentUuid: "'"$Z"'-2", isCompactSummary: true,
         isVisibleInTranscriptOnly: true, cwd: "/x", timestamp: "2026-01-01T10:00:00.000Z",
         message: {role: "user", content: "This session is being continued from a previous conversation"}}' >>"$CPROJ/$Z.jsonl"
jq -cn '{type: "user", uuid: "z-3", parentUuid: "z-sum", cwd: "/x", timestamp: "2026-01-01T10:00:00.000Z",
         message: {role: "user", content: "after compaction"}}' >>"$CPROJ/$Z.jsonl"
set_mtime "$(($(date +%s) - 3 * 86400))" "$CPROJ/$Z.jsonl"
out=$("$LETHE" export "$Z")
check "compaction summaries are not shown as the user's messages" \
    '[[ $out != *"being continued"* && $out == *"first prompt"* && $out == *"after compaction"* ]]' "$out"
expect_ids "... nor searched" "" --grep "being continued"

expect_status "trash empty refuses filters it would ignore" 2 trash empty --newer-than 1d -n
expect_status "... --dir too" 2 trash empty --dir / -n
"$LETHE" delete -y "$G" >/dev/null 2>&1
out=$("$LETHE" trash empty --older-than 1d -n)
check "trash empty --older-than says when nothing is old enough" '[[ $out == *"No session in the trash"*"1 in the trash"* ]]' "$out"

reset_fixture
# A PATH without any codex.
nocodex=""
IFS=: read -ra dirs <<<"$PATH"
for dir in "${dirs[@]}"; do [[ $dir == "$WORK/bin" || -x $dir/codex ]] || nocodex+=${nocodex:+:}$dir; done
mkdir -p "$WORK/bin-nocodex" && cp "$WORK/bin/claude" "$WORK/bin-nocodex/"
out=$(PATH=$WORK/bin-nocodex:$nocodex "$LETHE" delete -n "$G" 2>&1)
check "deleting Claude sessions does not need codex" '[[ $out == *"Delete 1 session"* ]]' "$out"
out=$(PATH=$WORK/bin-nocodex:$nocodex "$LETHE" delete -n "$A" 2>&1) || true
check "... Codex sessions do, with a clear message" '[[ $out == *"codex is not installed"* ]]' "$out"

V1=01a02791-0000-7000-8000-000000000001 V2=01a02791-1111-7000-8000-000000000002
codex_session "$V1" 3 0 cli openai "$PROJ" "First twin" "one"
codex_session "$V2" 3 0 cli openai "$PROJ" "Second twin" "two"
mkdir -p "$WORK/export" && printf 'active\n' >"$WORK/export/branches"
(cd "$WORK/export" && for v in "$V1" "$V2"; do LETHE_STATE=$WORK/export "$LETHE" __export "$v" </dev/null >/dev/null 2>&1; done)
out=$(cd "$WORK/export" && ls lethe-*.md | tr '\n' ' ')
check "Ctrl-E exports sessions whose ids share 8 characters" '[[ $out == "lethe-01a02791-0000.md lethe-01a02791-1111.md " ]]' "$out"
out=$(LETHE_STATE=$WORK/export "$LETHE" __preview "$V2" | sed -n 4p)
check "... and the preview shows an id that can be used" '[[ $out == *"· 01a02791-1111" ]]' "$out"

out=$("$LETHE" delete -n "$A" "$E")
check "the plan says when subagents are included, even with a protected session" \
    '[[ $out == *"Includes subagent sessions"* ]]' "$out"
out=$("$LETHE" archive -n "$A" "$H")
check "... and with a Claude session in an archive" '[[ $out == *"Includes subagent sessions"* ]]' "$out"

expect_status "a duration out of range is refused" 2 list --older-than 999999y
out=$(bash -c 'source <(sed "s/^main \"\$@\"\$//" "$1"); fit a "プロジェクト" 16; fit b "日本語のテスト 🚀 emoji long" 20; printf "[%s][%s]" "$a" "$b"' _ "$LETHE")
check "columns count wide characters twice" '[[ $out == "[プロジェクト    ][日本語のテスト 🚀 e…]" ]]' "$out"

if [[ $(uname -s) == Linux ]]; then
    out=$(STAT_KIND=gnu bash -c 'source <(sed "s/^main \"\$@\"\$//" "$1"); STAT_KIND=gnu; file_stats "$2" -name "*.jsonl" | wc -l' _ "$LETHE" "$CPROJ")
    check "file sizes and dates without find -printf (busybox)" '[[ $out == $(find "$CPROJ" -name "*.jsonl" | wc -l) ]]' "$out"
fi

reset_fixture
B_FILE=$(codex_file "$B" 0)
sqlite3 "$DB" "UPDATE threads SET updated_at = recency_at WHERE id = '$B';"
set_mtime "$(($(date +%s) - 7200))" "$B_FILE"
expect_ids "--older-than sees a Codex transcript written after the index" "$A $C $D $F $G $H $I" --older-than 1d
expect_ids "--newer-than too" "$B $E" --newer-than 1d
out=$("$LETHE" show "$B" | sed -n 4p)
listed=$("$LETHE" list --json "$B" | jq -r '.[0].last_activity | fromdate | strflocaltime("%Y-%m-%d %H:%M")')
check "show gives the date of the transcript, like list" '[[ $out == *"→ $listed"* && $listed == "$(date "+%Y-%m-%d")"* ]]' "$out (list: $listed)"
sqlite3 "$DB" "UPDATE threads SET updated_at = $(date +%s) WHERE id = '$B';"
set_mtime "$(date +%s)" "$B_FILE"
expect_ids "a transcript moved by archive/unarchive is not activity" "$E $I" --running

reset_fixture
"$LETHE" archive -y "$A" >/dev/null 2>&1
"$LETHE" unarchive -y "$A" >/dev/null 2>&1
check "archive then unarchive brings the subagents back" '! archived "$A" && ! archived "$C"'

sqlite3 "$DB" "ALTER TABLE threads ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0; UPDATE threads SET is_pinned = 1 WHERE id = '$D';"
out=$("$LETHE" delete -n --older-than 1d --codex)
check "pinned Codex sessions are kept by cleanups" '[[ $out == *"pinned in Codex"* && $(sed -n "/^Delete/,/^Skipped/p" <<<"$out") != *"Old idea"* ]]' "$out"
out=$("$LETHE" delete -n "$D")
check "... and changed when named" '[[ $(sed -n "/^Delete/,/^$/p" <<<"$out") == *"Old idea"* ]]' "$out"
check "... and shown" '"$LETHE" list --json | jq -e "map(select(.id == \"$D\"))[0].pinned" >/dev/null && [[ $("$LETHE" list --archived) == *"pinned · "* ]]'

sqlite3 "$DB" "UPDATE threads SET cwd = '/' WHERE id = '$D';"
out=$("$LETHE" list --archived | sed -n 2p)
check "a session started in / shows / as its project" '[[ $out =~ [0-9BKM]\ +/\ +pinned ]]' "$out"

reset_fixture
printf 'z\n' >"$WORK/on-delete-rm.target"
printf '%s' "$CPROJ/$H.jsonl" >"$WORK/on-delete-rm"
set_mtime "$(($(date +%s) - 30 * 86400))" "$CPROJ/$H.jsonl"
out=$("$LETHE" delete -y "$A" "$H" 2>&1)
check "a session removed by someone else is not reported as trashed" \
    '[[ $out == *"1 session(s) were already deleted"* && $out != *"moved 1 to the trash"* ]]' "$out"

reset_fixture
mkdir -p "$WORK/st"
printf 'all\n' >"$WORK/st/agent"; printf 'active\n' >"$WORK/st/status"; printf 'recent\n' >"$WORK/st/sort"
printf 'all\n' >"$WORK/st/filter"; : >"$WORK/st/grep"; : >"$WORK/st/dir"; printf 'full\n' >"$WORK/st/keys"
printf 'active\n' >"$WORK/st/branches"; printf 'conversation\n' >"$WORK/st/panel"
st() { LETHE_STATE=$WORK/st LETHE_FILTERS=${2:-} "$LETHE" __state "$1"; }
rows() { LETHE_STATE=$WORK/st LETHE_FILTERS=${1:-} "$LETHE" __rows | cut -f 1 | sort | tr '\n' ' '; }
check "the picker says unarchived, not active" '[[ $(st prompt) == *unarchived* && $(st footer) == *"status: unarchived"* ]]' "$(st prompt)"
printf 'all\n' >"$WORK/st/status"
out=$(st prompt "--dir $(printf %q "$PROJ") --older-than 1y")
check "the prompt shows the filters of the command line" '[[ $out == *proj* && $out == *"idle 1y+"* ]]' "$out"
printf 'idle30\n' >"$WORK/st/filter"
check "Ctrl-F narrows the command line's --older-than" '[[ $(rows "--older-than 1y") == "" ]]' "$(rows "--older-than 1y")"
out=$(LETHE_STATE=$WORK/st LETHE_FILTERS="--older-than 1y" REINDEX=0 bash -c 'source <(sed "s/^main \"\$@\"\$//" "$1"); choose_lines filter' _ "$LETHE" | perl -pe 's/\e\[[0-9;]*m//g')
check "... and its menu counts with it" '[[ $(grep "^all" <<<"$out") =~ [[:space:]]0[[:space:]] ]]' "$out"
check "the menus have their column titles above the columns" '[[ $(head -n 1 <<<"$out") =~ ^$'"'"'\t'"'"'\ {41}sessions\ {5}size$ ]]' "$(head -n 1 <<<"$out")"
printf 'all\n' >"$WORK/st/filter"
printf '=%s' "$PROJ/sub" >"$WORK/st/dir"
check "Ctrl-W narrows the command line's --dir" '[[ $(rows "--dir $(printf %q "$PROJ")") == "$B " ]]' "$(rows "--dir $PROJ")"
printf '=/home/u/my_project' >"$WORK/st/dir"; printf 'snake_case' >"$WORK/st/grep"
check "the footer keeps underscores" '[[ $(st footer) == *"project: my_project"* && $(st footer) == *"find: snake_case"* ]]' "$(st footer)"
: >"$WORK/st/dir"; : >"$WORK/st/grep"
sqlite3 "$DB" "UPDATE threads SET cwd = '' WHERE id = '$F';"
rm -f "$WORK/st/choose-current"
LETHE_STATE=$WORK/st REINDEX=0 bash -c 'source <(sed "s/^main \"\$@\"\$//" "$1"); choose_lines dir "$2"' _ "$LETHE" "$F" >/dev/null
check "Ctrl-W does not preselect a project for a session without one" '[[ ! -e $WORK/st/choose-current ]]'
printf 'm' >"$WORK/st/grep"
claude_chat "$Q" 3 "$PROJ" 'user:make a **summary** of `main`' 'assistant:I made it'
"$LETHE" list >/dev/null
out=$(NO_COLOR="" LETHE_STATE=$WORK/st FZF_PREVIEW_COLUMNS=70 "$LETHE" __preview "$Q")
check "Ctrl-G marks never break color codes" '[[ $out != *$'"'"'\e[1\e'"'"'* && $out != *$'"'"'\e[36\e'"'"'* ]]' "$(printf '%q' "$out")"
: >"$WORK/st/grep"
printf '#!/bin/sh\ncat >/dev/null\nprintf "%%s" "$LESS"\n' >"$WORK/bin/lesspager" && chmod +x "$WORK/bin/lesspager"
out=$(LESS=-i PAGER=lesspager LETHE_STATE=$WORK/st "$LETHE" __page "$A" </dev/null)
check "Enter keeps colors when LESS is set" '[[ $out == "-i -R" ]]' "$out"

reset_fixture
ln -s "$PROJ" "$WORK/link"
expect_ids "--dir through a symlink" "$A $B $C $G" --dir "$WORK/link"
if ((EUID != 0)); then
    sqlite3 "$DB" "UPDATE threads SET cwd = '$WORK/locked/inner' WHERE id = '$B';"
    mkdir -p "$WORK/locked/inner" && chmod 000 "$WORK/locked"
    expect_ids "an unreachable project is not an orphan" "" --orphans --codex
    chmod 755 "$WORK/locked"
fi
mkdir -p "$WORK/claude2/projects/-p"
cp "$CPROJ/$G.jsonl" "$WORK/claude2/projects/-p/"
CLAUDE_CONFIG_DIR=$WORK/claude2 "$LETHE" list >/dev/null
"$LETHE" list >/dev/null
check "one index per Claude Code directory" '[[ $(ls "$XDG_CACHE_HOME"/lethe/claude-v4-*.sqlite | wc -l) -eq 2 ]]'

printf '{"display":"secret prompt","sessionId":"%s"}\n{"display":"other","sessionId":"%s"}\n' "$G" "$H" \
    >"$CLAUDE_CONFIG_DIR/history.jsonl"
"$LETHE" delete -y "$G" >/dev/null 2>&1
check "deleting a Claude session takes its prompts out of the history" \
    '! grep -q "secret prompt" "$CLAUDE_CONFIG_DIR/history.jsonl" && grep -q other "$CLAUDE_CONFIG_DIR/history.jsonl"'
if ((EUID != 0)); then
    chmod 555 "$CLAUDE_CONFIG_DIR/session-env"
    "$LETHE" trash restore "${G:0:8}" >/dev/null 2>&1 || true
    chmod 755 "$CLAUDE_CONFIG_DIR/session-env"
    check "a failed restore leaves the session whole in the trash" '[[ ! -e $CPROJ/$G.jsonl ]]'
fi
"$LETHE" trash restore "${G:0:8}" >/dev/null 2>&1
check "... and it can be restored afterwards, prompts included" \
    '[[ -f $CPROJ/$G.jsonl && -d $CLAUDE_CONFIG_DIR/session-env/$G ]] && grep -q "secret prompt" "$CLAUDE_CONFIG_DIR/history.jsonl"'

out=$(bash -c 'source <("$1" completion bash); COMP_WORDS=(lethe export 1234 --all); COMP_CWORD=3; _lethe; echo "${COMPREPLY[*]}"' _ "$LETHE")
check "completion offers --all-branches" '[[ $out == --all-branches ]]' "$out"

H2=$WORK/home-zdot
mkdir -p "$H2/.config/zsh" "$WORK/fakecurl"
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do case $1 in -o) out=$2; shift;; esac; shift; done\necho "#!/bin/sh" > "$out"\n' \
    >"$WORK/fakecurl/curl" && chmod +x "$WORK/fakecurl/curl"
printf '# tools in %s/.local/bin/old\n' "$H2" >"$H2/.bashrc"
env -i HOME="$H2" PATH="$WORK/fakecurl:/usr/bin:/bin" SHELL=/bin/bash sh "$ROOT/install.sh" >/dev/null 2>&1
check "installer: a startup file that only mentions the directory gets the PATH line" \
    'grep -qF "export PATH=\"$H2/.local/bin:\$PATH\"" "$H2/.bashrc"'
if command -v zsh >/dev/null 2>&1; then
    printf 'export ZDOTDIR=$HOME/.config/zsh\n' >"$H2/.zshenv"
    env -i HOME="$H2" PATH="$WORK/fakecurl:/usr/bin:/bin" SHELL=/bin/zsh sh "$ROOT/install.sh" >/dev/null 2>&1
    check "installer: zsh with ZDOTDIR" 'grep -qF "$H2/.local/bin" "$H2/.config/zsh/.zshrc"'
fi

echo
printf '%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
