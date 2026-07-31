#!/bin/sh

SCRIPT_PATH=$0

json_escape() {
    printf '%s' "$1" | awk '
        BEGIN { first = 1 }
        {
            gsub(/\\/, "\\\\")
            gsub(/"/, "\\\"")
            gsub(/\r/, "\\r")
            if (!first) printf "\\n"
            printf "%s", $0
            first = 0
        }
    '
}

fail() {
    fail_message=$(json_escape "$1")
    fail_command=$(json_escape "${COMMAND-}")
    printf '{"ok":false,"command":"%s","error":"%s"}\n' "$fail_command" "$fail_message" >&2
    exit 2
}

COMMAND=${1-}
[ "$#" -gt 0 ] && shift
PATH_ARG=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --path)
            [ "$#" -ge 2 ] || fail 'Missing value for --path.'
            PATH_ARG=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

case "$COMMAND" in
    check|self-test) ;;
    *) fail 'Command must be check or self-test.' ;;
esac

absolute_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$PWD" "$1" ;;
    esac
}

append_finding() {
    finding_file=$(json_escape "$1")
    finding_line=$2
    finding_rule=$(json_escape "$3")
    finding_target=$(json_escape "$4")
    finding_message=$(json_escape "$5")
    [ "$FINDING_COUNT" -eq 0 ] || FINDINGS_JSON=$FINDINGS_JSON,
    FINDINGS_JSON=$FINDINGS_JSON'{"file":"'$finding_file'","line":'$finding_line',"rule":"'$finding_rule'","target":"'$finding_target'","message":"'$finding_message'"}'
    FINDING_COUNT=$((FINDING_COUNT + 1))
}

is_relative_local_target() {
    case "$1" in
        ''|\#*|/*|\\*|[A-Za-z]:*|[A-Za-z][A-Za-z0-9+.-]*:*) return 1 ;;
        *) return 0 ;;
    esac
}

check_file() {
    check_file_path=$1
    check_events=$(mktemp "${TMPDIR:-/tmp}/lightning-events.XXXXXX") ||
        fail 'Cannot create temporary event file.'
    awk '
        function emit_link(line_number, target) {
            if (target ~ /^</) {
                sub(/^</, "", target)
                sub(/>.*/, "", target)
            } else {
                sub(/[[:space:]].*$/, "", target)
            }
            print "LINK\t" line_number "\t" target
        }
        {
            sub(/\r$/, "")
            if (match($0, /^[ ]{0,3}(```+|~~~+)/)) {
                marker = substr($0, RSTART, RLENGTH)
                sub(/^[ ]*/, "", marker)
                character = substr(marker, 1, 1)
                if (!in_fence) {
                    in_fence = 1
                    fence_character = character
                    fence_length = length(marker)
                    fence_line = NR
                } else if (character == fence_character && length(marker) >= fence_length) {
                    in_fence = 0
                }
                next
            }
            if (in_fence) next

            rest = $0
            while (match(rest, /!?\[[^]]*\]\([^)]*\)/)) {
                token = substr(rest, RSTART, RLENGTH)
                sub(/^[^(]*\(/, "", token)
                sub(/\)$/, "", token)
                emit_link(NR, token)
                rest = substr(rest, RSTART + RLENGTH)
            }
            if ($0 ~ /^[ ]{0,3}\[[^]]+\]:[[:space:]]*/) {
                token = $0
                sub(/^[ ]{0,3}\[[^]]+\]:[[:space:]]*/, "", token)
                emit_link(NR, token)
            }
        }
        END {
            if (in_fence) print "FENCE\t" fence_line "\t"
        }
    ' "$check_file_path" > "$check_events" ||
        fail "Cannot inspect Markdown file: $check_file_path"

    while IFS='	' read -r event_rule event_line event_target; do
        case "$event_rule" in
            FENCE)
                append_finding "$check_file_path" "$event_line" 'unclosed-fence' '' 'Code fence is not closed.'
                ;;
            LINK)
                clean_target=$(printf '%s' "$event_target" | sed 's/[?#].*$//; s/%20/ /g')
                if is_relative_local_target "$clean_target"; then
                    target_path=$(dirname "$check_file_path")/$clean_target
                    if [ ! -f "$target_path" ] && [ ! -d "$target_path" ]; then
                        append_finding "$check_file_path" "$event_line" 'missing-local-target' "$clean_target" "Local target does not exist: $clean_target"
                    fi
                fi
                ;;
        esac
    done < "$check_events"
    rm -f "$check_events"
}

check_path() {
    [ -n "$PATH_ARG" ] || fail 'Missing required argument: --path'
    CHECK_PATH=$(absolute_path "$PATH_ARG")
    check_files=$(mktemp "${TMPDIR:-/tmp}/lightning-files.XXXXXX") ||
        fail 'Cannot create temporary file list.'
    if [ -f "$CHECK_PATH" ]; then
        case "$CHECK_PATH" in
            *.md) printf '%s\n' "$CHECK_PATH" > "$check_files" ;;
            *) fail "Expected a Markdown file: $CHECK_PATH" ;;
        esac
    elif [ -d "$CHECK_PATH" ]; then
        find "$CHECK_PATH" -type f -name '*.md' -print | LC_ALL=C sort > "$check_files"
    else
        fail "Path does not exist: $CHECK_PATH"
    fi
    [ -s "$check_files" ] || fail "No Markdown files found: $CHECK_PATH"

    FINDINGS_JSON=
    FINDING_COUNT=0
    FILE_COUNT=0
    while IFS= read -r markdown_file; do
        [ -n "$markdown_file" ] || continue
        FILE_COUNT=$((FILE_COUNT + 1))
        check_file "$markdown_file"
    done < "$check_files"
    rm -f "$check_files"

    if [ "$FINDING_COUNT" -eq 0 ]; then ok=true; result_code=0; else ok=false; result_code=1; fi
    path_json=$(json_escape "$CHECK_PATH")
    printf '{"ok":%s,"command":"check","path":"%s","files_checked":%s,"findings":[%s]}\n' \
        "$ok" "$path_json" "$FILE_COUNT" "$FINDINGS_JSON"
    return "$result_code"
}

self_test() {
    [ -z "$PATH_ARG" ] || fail 'self-test does not accept arguments.'
    self_base=$(mktemp -d "${TMPDIR:-/tmp}/lightning-markdown-中文.XXXXXX") ||
        fail 'Cannot create self-test directory.'
    cleanup_self_test() {
        rm -rf "$self_base"
    }
    trap cleanup_self_test 0 HUP INT TERM

    self_target=$self_base/'中文 file.md'
    printf '# Target\n' > "$self_target"
    self_valid=$self_base/valid.md
    printf '# Valid\n\n[local](<中文 file.md>)\n\n```text\nok\n```\n' > "$self_valid"
    sh "$SCRIPT_PATH" check --path "$self_valid" >/dev/null ||
        fail 'Self-test failed: valid document.'
    sh "$SCRIPT_PATH" check --path "$self_base" >/dev/null ||
        fail 'Self-test failed: directory unicode and spaces.'

    self_broken=$self_base/broken.md
    printf '# Broken\n\n[missing](./missing.md)\n' > "$self_broken"
    broken_code=0
    broken_output=$(sh "$SCRIPT_PATH" check --path "$self_broken") || broken_code=$?
    [ "$broken_code" -eq 1 ] && printf '%s' "$broken_output" | grep -q 'missing-local-target' ||
        fail 'Self-test failed: missing target.'

    self_unclosed=$self_base/unclosed.md
    printf '# Unclosed\n\n```text\ncontent\n' > "$self_unclosed"
    unclosed_code=0
    unclosed_output=$(sh "$SCRIPT_PATH" check --path "$self_unclosed") || unclosed_code=$?
    [ "$unclosed_code" -eq 1 ] && printf '%s' "$unclosed_output" | grep -q 'unclosed-fence' ||
        fail 'Self-test failed: unclosed fence.'

    self_remote=$self_base/remote.md
    printf '# Remote\n\n[web](https://example.com) [anchor](#part)\n' > "$self_remote"
    sh "$SCRIPT_PATH" check --path "$self_remote" >/dev/null ||
        fail 'Self-test failed: remote and fragment ignored.'

    runtime=$(uname -s 2>/dev/null || printf unknown)
    runtime_json=$(json_escape "$runtime")
    printf '{"ok":true,"command":"self-test","adapter":"posix-sh","runtime":"%s","checks_passed":5,"checks":[{"name":"valid document","passed":true},{"name":"directory unicode and spaces","passed":true},{"name":"missing target","passed":true},{"name":"unclosed fence","passed":true},{"name":"remote and fragment ignored","passed":true}]}\n' "$runtime_json"
}

if [ "$COMMAND" = self-test ]; then
    self_test
    exit 0
fi

check_path
exit $?
