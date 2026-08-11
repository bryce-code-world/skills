#!/bin/sh
# Native POSIX mechanical guard for Markdown documents.

case "$0" in
    /*) SCRIPT_PATH=$0 ;;
    *) SCRIPT_PATH=$PWD/$0 ;;
esac

SEP=$(printf '\034')

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

require_value() {
    [ "$#" -ge 2 ] || fail "Missing value for $1."
}

COMMAND=${1-}
[ "$#" -gt 0 ] && shift

PATH_ARG=
SOURCE=
OUTPUT=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --path)
            require_value "$@"
            PATH_ARG=$2
            shift 2
            ;;
        --source)
            require_value "$@"
            SOURCE=$2
            shift 2
            ;;
        --output)
            require_value "$@"
            OUTPUT=$2
            shift 2
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

case "$COMMAND" in
    check|readability|compare|self-test) ;;
    *) fail 'Command must be one of: check, readability, compare, self-test.' ;;
esac

absolute_path() {
    absolute_raw=$1
    case "$absolute_raw" in
        '~') absolute_raw=${HOME-} ;;
        '~/'*) absolute_raw=${HOME-}/${absolute_raw#~/} ;;
    esac
    case "$absolute_raw" in
        /*) printf '%s\n' "$absolute_raw" ;;
        *) printf '%s/%s\n' "$PWD" "$absolute_raw" ;;
    esac
}

append_issue() {
    issue_file=$1
    issue_path=$2
    issue_type=$3
    issue_line=$4
    issue_target=$5
    issue_message=$6
    printf '%s%s%s%s%s%s%s%s%s\n' \
        "$issue_path" "$SEP" "$issue_type" "$SEP" "$issue_line" "$SEP" \
        "$issue_target" "$SEP" "$issue_message" >> "$issue_file"
}

scan_structure() {
    scan_file=$1
    scan_safe=$2
    scan_issues=$3
    awk -v file="$scan_file" -v safe="$scan_safe" -v issues="$scan_issues" '
        function emit(type, line, target, message, separator) {
            separator = sprintf("%c", 28)
            print file separator type separator line separator target separator message >> issues
        }
        function marker_length(text, character, count) {
            character = substr(text, 1, 1)
            count = 0
            while (substr(text, count + 1, 1) == character) count++
            return count
        }
        {
            raw = $0
            sub(/\r$/, "", raw)
            trimmed = raw
            sub(/^[ \t]*/, "", trimmed)
            is_marker = (substr(trimmed, 1, 3) == "```" || substr(trimmed, 1, 3) == "~~~")
            if (is_marker) {
                character = substr(trimmed, 1, 1)
                length_now = marker_length(trimmed)
                if (fence_character == "") {
                    fence_character = character
                    fence_length = length_now
                    fence_line = NR
                } else if (character == fence_character && length_now >= fence_length) {
                    fence_character = ""
                    fence_length = 0
                    fence_line = 0
                }
                print "" >> safe
                next
            }
            if (fence_character != "") {
                print "" >> safe
                next
            }
            print raw >> safe

            todo = raw
            sub(/^[ \t]*/, "", todo)
            sub(/^#+[ \t]+/, "", todo)
            sub(/^[-*+][ \t]+/, "", todo)
            if (match(todo, /^TODO-[0-9][0-9]+/)) {
                identifier = substr(todo, RSTART, RLENGTH)
                remainder = substr(todo, RLENGTH + 1)
                if (remainder == "" || remainder ~ /^[ \t]/ || remainder ~ /^[:：]/) {
                    if (todo_line[identifier] > 0) {
                        emit("duplicate-todo", NR, identifier, identifier " is already defined at line " todo_line[identifier] ".")
                    } else {
                        todo_line[identifier] = NR
                    }
                }
            }
        }
        END {
            if (fence_character != "") {
                emit("unclosed-fence", fence_line, "", "Code fence opened at line " fence_line " is not closed.")
            }
        }
    ' "$scan_file" || fail "Cannot inspect Markdown structure: $scan_file"
}

check_links() {
    link_file=$1
    link_safe=$2
    link_issues=$3
    link_matches=$(mktemp "$WORK_DIR/links.XXXXXX") || fail 'Cannot create link scan file.'
    grep -n -Eo '!?\[[^]]*\]\((<[^>]+>|[^)[:space:]]+)' "$link_safe" > "$link_matches" 2>/dev/null || :
    awk '
        /^[[:space:]]{0,3}\[[^]]+\]:[[:space:]]*/ {
            target = $0
            sub(/^[[:space:]]{0,3}\[[^]]+\]:[[:space:]]*/, "", target)
            if (target ~ /^</) {
                sub(/>.*/, ">", target)
            } else {
                sub(/[[:space:]].*$/, "", target)
            }
            print NR ":[reference](" target
        }
    ' "$link_safe" >> "$link_matches"
    while IFS= read -r link_record; do
        [ -n "$link_record" ] || continue
        link_line=${link_record%%:*}
        link_match=${link_record#*:}
        link_target=${link_match#*(}
        case "$link_target" in
            '<'*) link_target=${link_target#<}; link_target=${link_target%>} ;;
        esac
        case "$link_target" in
            ''|'#'*|'//'*) continue ;;
            [A-Za-z][A-Za-z0-9+.-]*:*) continue ;;
        esac
        link_clean=${link_target%%#*}
        link_clean=${link_clean%%\?*}
        [ -n "$link_clean" ] || continue
        link_clean=$(printf '%s' "$link_clean" | sed 's/%20/ /g')
        case "$link_clean" in
            /*) link_resolved=$link_clean ;;
            *) link_resolved=$(dirname "$link_file")/$link_clean ;;
        esac
        if [ ! -e "$link_resolved" ]; then
            append_issue "$link_issues" "$link_file" missing-link "$link_line" "$link_target" "Local link target does not exist: $link_target"
        fi
    done < "$link_matches"
}

prepare_check() {
    check_path=$1
    CHECK_ISSUES=$(mktemp "$WORK_DIR/issues.XXXXXX") || fail 'Cannot create issue file.'
    CHECK_FILES=$(mktemp "$WORK_DIR/files.XXXXXX") || fail 'Cannot create file list.'
    CHECK_COUNT=0

    if [ -f "$check_path" ]; then
        case "$check_path" in
            *.md) printf '%s\n' "$check_path" > "$CHECK_FILES" ;;
            *) fail "Expected a Markdown file: $check_path" ;;
        esac
    elif [ -d "$check_path" ]; then
        find "$check_path" -type f -name '*.md' -print | sort > "$CHECK_FILES" ||
            fail "Cannot enumerate Markdown files: $check_path"
        [ -s "$CHECK_FILES" ] || fail "No Markdown files found: $check_path"
    else
        fail "Path does not exist: $check_path"
    fi

    while IFS= read -r check_file; do
        [ -n "$check_file" ] || continue
        CHECK_COUNT=$((CHECK_COUNT + 1))
        if [ ! -s "$check_file" ]; then
            append_issue "$CHECK_ISSUES" "$check_file" empty-file 1 '' 'Markdown file is empty.'
            continue
        fi
        check_safe=$(mktemp "$WORK_DIR/safe.XXXXXX") || fail 'Cannot create Markdown scan file.'
        scan_structure "$check_file" "$check_safe" "$CHECK_ISSUES"
        check_links "$check_file" "$check_safe" "$CHECK_ISSUES"
    done < "$CHECK_FILES"
}

issues_json() {
    issues_source=$1
    issues_result=
    issues_count=0
    while IFS="$SEP" read -r issue_path issue_type issue_line issue_target issue_message; do
        [ -n "$issue_path" ] || continue
        [ "$issues_count" -eq 0 ] || issues_result=$issues_result,
        path_json=$(json_escape "$issue_path")
        type_json=$(json_escape "$issue_type")
        target_json=$(json_escape "$issue_target")
        message_json=$(json_escape "$issue_message")
        issues_result=$issues_result'{"file":"'$path_json'","type":"'$type_json'","line":'$issue_line',"message":"'$message_json'","target":"'$target_json'"}'
        issues_count=$((issues_count + 1))
    done < "$issues_source"
    ISSUES_JSON=$issues_result
    ISSUE_COUNT=$issues_count
}

run_check() {
    run_path=$1
    prepare_check "$run_path"
    issues_json "$CHECK_ISSUES"
    path_json=$(json_escape "$run_path")
    if [ "$ISSUE_COUNT" -eq 0 ]; then check_ok=true; check_code=0; else check_ok=false; check_code=1; fi
    printf '{"ok":%s,"command":"check","path":"%s","files_checked":%s,"issues":[%s]}\n' \
        "$check_ok" "$path_json" "$CHECK_COUNT" "$ISSUES_JSON"
    return "$check_code"
}

ensure_utf8_locale() {
    utf8_length=$(printf '中' | awk '{ print length($0) }')
    [ "$utf8_length" = 1 ] && return

    for utf8_locale in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8 zh_CN.UTF-8 zh_CN.utf8; do
        utf8_length=$(LC_ALL=$utf8_locale awk 'BEGIN { print length("中") }' 2>/dev/null) || continue
        if [ "$utf8_length" = 1 ]; then
            LC_ALL=$utf8_locale
            export LC_ALL
            return
        fi
    done
    fail 'readability requires an available UTF-8 locale.'
}

scan_readability_file() {
    readability_file=$1
    readability_warnings=$2
    awk -v file="$readability_file" -v warnings="$readability_warnings" '
        function trim(text) {
            sub(/^[ \t]+/, "", text)
            sub(/[ \t]+$/, "", text)
            return text
        }
        function marker_length(text, character, count) {
            character = substr(text, 1, 1)
            count = 0
            while (substr(text, count + 1, 1) == character) count++
            return count
        }
        function emit(line, characters, separators, text, separator) {
            separator = sprintf("%c", 28)
            print file separator line separator characters separator separators separator text >> warnings
        }
        {
            raw = $0
            sub(/\r$/, "", raw)
            trimmed = raw
            sub(/^[ \t]*/, "", trimmed)
            if (NR == 1 && trimmed == "---") {
                frontmatter = 1
                next
            }
            if (frontmatter) {
                if (trimmed == "---") frontmatter = 0
                next
            }
            is_marker = (substr(trimmed, 1, 3) == "```" || substr(trimmed, 1, 3) == "~~~")
            if (is_marker) {
                character = substr(trimmed, 1, 1)
                length_now = marker_length(trimmed)
                if (fence_character == "") {
                    fence_character = character
                    fence_length = length_now
                } else if (character == fence_character && length_now >= fence_length) {
                    fence_character = ""
                    fence_length = 0
                }
                next
            }
            if (fence_character != "" || trimmed == "" || trimmed ~ /^#/ || trimmed ~ /^\|/) next

            visible = raw
            gsub(/\]\((<[^>]+>|[^)[:space:]]+)\)/, "]", visible)
            gsub(/\]\[[^]]*\]/, "]", visible)
            gsub(/[`*_~]/, "", visible)
            sub(/^[ \t]*([-*+]|[0-9]+[.)])[ \t]+/, "", visible)

            rest = visible
            while (rest != "") {
                if (match(rest, /[。！？!?]/)) {
                    sentence = substr(rest, 1, RSTART)
                    rest = substr(rest, RSTART + RLENGTH)
                } else {
                    sentence = rest
                    rest = ""
                }
                sentence = trim(sentence)
                if (sentence == "") continue
                compact = sentence
                gsub(/[[:space:]]/, "", compact)
                punctuation = sentence
                separators = gsub(/[，；：]/, "", punctuation)
                characters = length(compact)
                if (characters >= 55 || separators >= 3) emit(NR, characters, separators, sentence)
            }
        }
    ' "$readability_file" || fail "Cannot inspect Markdown readability: $readability_file"
}

readability_json() {
    readability_source=$1
    readability_result=
    readability_count=0
    while IFS="$SEP" read -r warning_path warning_line warning_characters warning_separators warning_text; do
        [ -n "$warning_path" ] || continue
        [ "$readability_count" -eq 0 ] || readability_result=$readability_result,
        path_json=$(json_escape "$warning_path")
        text_json=$(json_escape "$warning_text")
        readability_result=$readability_result'{"file":"'$path_json'","line":'$warning_line',"characters":'$warning_characters',"separators":'$warning_separators',"text":"'$text_json'"}'
        readability_count=$((readability_count + 1))
    done < "$readability_source"
    READABILITY_JSON=$readability_result
    READABILITY_COUNT=$readability_count
}

run_readability() {
    readability_path=$1
    ensure_utf8_locale
    readability_files=$(mktemp "$WORK_DIR/readability-files.XXXXXX") || fail 'Cannot create readability file list.'
    readability_warnings=$(mktemp "$WORK_DIR/readability-warnings.XXXXXX") || fail 'Cannot create readability warning file.'
    readability_file_count=0

    if [ -f "$readability_path" ]; then
        case "$readability_path" in
            *.md) printf '%s\n' "$readability_path" > "$readability_files" ;;
            *) fail "Expected a Markdown file: $readability_path" ;;
        esac
    elif [ -d "$readability_path" ]; then
        find "$readability_path" -type f -name '*.md' -print | sort > "$readability_files" ||
            fail "Cannot enumerate Markdown files: $readability_path"
        [ -s "$readability_files" ] || fail "No Markdown files found: $readability_path"
    else
        fail "Path does not exist: $readability_path"
    fi

    while IFS= read -r readability_file; do
        [ -n "$readability_file" ] || continue
        readability_file_count=$((readability_file_count + 1))
        scan_readability_file "$readability_file" "$readability_warnings"
    done < "$readability_files"

    readability_json "$readability_warnings"
    if [ "$READABILITY_COUNT" -gt 0 ]; then review_required=true; else review_required=false; fi
    path_json=$(json_escape "$readability_path")
    printf '{"ok":true,"command":"readability","path":"%s","files_checked":%s,"review_required":%s,"warnings":[%s]}\n' \
        "$path_json" "$readability_file_count" "$review_required" "$READABILITY_JSON"
}

append_literal() {
    literal_file=$1
    literal_kind=$2
    literal_value=$3
    [ -n "$literal_value" ] || return
    printf '%s%s%s\n' "$literal_kind" "$SEP" "$literal_value" >> "$literal_file"
}

extract_literals() {
    literal_source=$1
    literal_target=$2
    [ -f "$literal_source" ] || fail "File does not exist: $literal_source"
    literal_raw=$(mktemp "$WORK_DIR/literals.XXXXXX") || fail 'Cannot create literal file.'

    grep -Eo '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}' "$literal_source" 2>/dev/null |
        tr '[:upper:]' '[:lower:]' |
        while IFS= read -r value; do append_literal "$literal_raw" uuid "$value"; done

    grep -Eo '`[^`]+`' "$literal_source" 2>/dev/null |
        while IFS= read -r value; do
            value=${value#\`}
            value=${value%\`}
            append_literal "$literal_raw" code "$value"
        done

    grep -Eo '[0-9]+([.][0-9]+)?([[:space:]]*[~～—-][[:space:]]*[0-9]+([.][0-9]+)?)?([[:space:]]*(%|％|ms|s|min|h|KB|MB|GB|次|个|天|周|月|年))?' "$literal_source" 2>/dev/null |
        while IFS= read -r value; do append_literal "$literal_raw" number "$value"; done

    grep -Eo '!?\[[^]]*\]\((<[^>]+>|[^)[:space:]]+)' "$literal_source" 2>/dev/null |
        while IFS= read -r value; do
            value=${value#*(}
            case "$value" in '<'*) value=${value#<}; value=${value%>} ;; esac
            case "$value" in
                ''|'#'*|'//'*) continue ;;
                [A-Za-z][A-Za-z0-9+.-]*:*) continue ;;
            esac
            append_literal "$literal_raw" link "$value"
        done

    awk '
        /^[[:space:]]{0,3}\[[^]]+\]:[[:space:]]*/ {
            target = $0
            sub(/^[[:space:]]{0,3}\[[^]]+\]:[[:space:]]*/, "", target)
            if (target ~ /^</) {
                sub(/^</, "", target)
                sub(/>.*/, "", target)
            } else {
                sub(/[[:space:]].*$/, "", target)
            }
            print target
        }
    ' "$literal_source" |
        while IFS= read -r value; do
            case "$value" in
                ''|'#'*|'//'*) continue ;;
                [A-Za-z][A-Za-z0-9+.-]*:*) continue ;;
            esac
            append_literal "$literal_raw" link "$value"
        done

    sort -u "$literal_raw" > "$literal_target"
}

tokens_json() {
    token_source=$1
    token_result=
    token_count=0
    while IFS="$SEP" read -r token_kind token_value; do
        [ -n "$token_kind" ] || continue
        [ "$token_count" -eq 0 ] || token_result=$token_result,
        kind_json=$(json_escape "$token_kind")
        value_json=$(json_escape "$token_value")
        token_result=$token_result'{"kind":"'$kind_json'","value":"'$value_json'"}'
        token_count=$((token_count + 1))
    done < "$token_source"
    TOKENS_JSON=$token_result
    TOKEN_COUNT=$token_count
}

run_compare() {
    compare_source=$1
    compare_output=$2
    [ -f "$compare_source" ] || fail "File does not exist: $compare_source"
    [ -f "$compare_output" ] || fail "File does not exist: $compare_output"

    prepare_check "$compare_output"
    issues_json "$CHECK_ISSUES"
    if [ "$ISSUE_COUNT" -eq 0 ]; then compare_ok=true; compare_code=0; else compare_ok=false; compare_code=1; fi

    source_tokens=$(mktemp "$WORK_DIR/source-tokens.XXXXXX") || fail 'Cannot create source token file.'
    output_tokens=$(mktemp "$WORK_DIR/output-tokens.XXXXXX") || fail 'Cannot create output token file.'
    source_only=$(mktemp "$WORK_DIR/source-only.XXXXXX") || fail 'Cannot create comparison file.'
    output_only=$(mktemp "$WORK_DIR/output-only.XXXXXX") || fail 'Cannot create comparison file.'
    extract_literals "$compare_source" "$source_tokens"
    extract_literals "$compare_output" "$output_tokens"
    comm -23 "$source_tokens" "$output_tokens" > "$source_only"
    comm -13 "$source_tokens" "$output_tokens" > "$output_only"

    tokens_json "$source_only"
    source_only_json=$TOKENS_JSON
    source_only_count=$TOKEN_COUNT
    tokens_json "$output_only"
    output_only_json=$TOKENS_JSON
    output_only_count=$TOKEN_COUNT
    if [ "$source_only_count" -gt 0 ] || [ "$output_only_count" -gt 0 ]; then review_required=true; else review_required=false; fi

    source_json=$(json_escape "$compare_source")
    output_json=$(json_escape "$compare_output")
    printf '{"ok":%s,"command":"compare","source":"%s","output":"%s","review_required":%s,"source_only":[%s],"output_only":[%s],"mechanical_issues":[%s]}\n' \
        "$compare_ok" "$source_json" "$output_json" "$review_required" \
        "$source_only_json" "$output_only_json" "$ISSUES_JSON"
    return "$compare_code"
}

self_test() {
    [ -z "$PATH_ARG$SOURCE$OUTPUT" ] || fail 'self-test does not accept arguments.'
    self_base=$(mktemp -d "${TMPDIR:-/tmp}/lightning-guard.XXXXXX") ||
        fail 'Cannot create self-test directory.'
    cleanup_self_test() {
        rm -rf "$self_base"
    }
    trap cleanup_self_test 0 HUP INT TERM

    self_root=$self_base/护栏测试/文档
    mkdir -p "$self_root" || fail 'Cannot prepare self-test directory.'
    printf '# Target\n' > "$self_root/target file.md"
    {
        printf '# Valid\n\n'
        printf '[目标](<target file.md>) [网页](https://example.com) [锚点](#part)\n'
        printf '[引用][doc]\n'
        printf '[doc]: <target file.md>\n\n'
        printf 'TODO-01：确认范围。\n\n'
        printf '%s\n' '```text' 'ok' '```'
    } > "$self_root/valid.md"
    sh "$SCRIPT_PATH" check --path "$self_root/valid.md" >/dev/null ||
        fail 'Self-test failed: valid file.'

    printf '[missing](missing.md)\n' > "$self_root/broken.md"
    broken_code=0
    broken_json=$(sh "$SCRIPT_PATH" check --path "$self_root/broken.md") || broken_code=$?
    [ "$broken_code" -eq 1 ] && printf '%s' "$broken_json" | grep -q '"type":"missing-link"' ||
        fail 'Self-test failed: missing local link.'

    printf '%s\n' '```text' 'unclosed' > "$self_root/fence.md"
    fence_code=0
    fence_json=$(sh "$SCRIPT_PATH" check --path "$self_root/fence.md") || fence_code=$?
    [ "$fence_code" -eq 1 ] && printf '%s' "$fence_json" | grep -q '"type":"unclosed-fence"' ||
        fail 'Self-test failed: unclosed fence.'

    printf 'TODO-02：first\n\n## TODO-02：second\n' > "$self_root/todo.md"
    todo_code=0
    todo_json=$(sh "$SCRIPT_PATH" check --path "$self_root/todo.md") || todo_code=$?
    [ "$todo_code" -eq 1 ] && printf '%s' "$todo_json" | grep -q '"type":"duplicate-todo"' ||
        fail 'Self-test failed: duplicate todo.'

    printf '版本 `v1`，范围 10～20 个，ID 123e4567-e89b-12d3-a456-426614174000。\n' > "$self_root/source.md"
    printf '版本 `v2`，范围 10 个。\n' > "$self_root/output.md"
    compare_json=$(sh "$SCRIPT_PATH" compare --source "$self_root/source.md" --output "$self_root/output.md") ||
        fail 'Self-test failed: literal comparison.'
    printf '%s' "$compare_json" | grep -q '"review_required":true' ||
        fail 'Self-test failed: literal comparison.'

    {
        printf '%s\n' '---'
        printf '%s\n' 'description: "This intentionally long frontmatter value must not become a readability warning candidate."'
        printf '%s\n\n' '---'
        printf '对象满足条件时，执行动作一，执行动作二；出现异常时，执行联动结果。\n\n'
        printf '| 很长的表格行，包含多个逗号，仍然不进入正文句子告警。 |\n'
    } > "$self_root/readability.md"
    readability_json=$(sh "$SCRIPT_PATH" readability --path "$self_root/readability.md") ||
        fail 'Self-test failed: readability warnings.'
    printf '%s' "$readability_json" | grep -q '"review_required":true' &&
        printf '%s' "$readability_json" | grep -q '"separators":4' ||
        fail 'Self-test failed: readability warnings.'

    recursive_code=0
    recursive_json=$(sh "$SCRIPT_PATH" check --path "$self_root") || recursive_code=$?
    [ "$recursive_code" -eq 1 ] && printf '%s' "$recursive_json" | grep -q '"files_checked":8' ||
        fail 'Self-test failed: unicode directory recursion.'

    runtime=$(uname -s 2>/dev/null || printf unknown)
    runtime_json=$(json_escape "$runtime")
    printf '{"ok":true,"command":"self-test","adapter":"posix-sh","runtime":"%s","checks_passed":7,"checks":[{"name":"valid file","passed":true},{"name":"missing local link","passed":true},{"name":"unclosed fence","passed":true},{"name":"duplicate todo","passed":true},{"name":"literal comparison","passed":true},{"name":"readability warnings","passed":true},{"name":"unicode directory recursion","passed":true}]}\n' "$runtime_json"
}

if [ "$COMMAND" = self-test ]; then
    self_test
    exit 0
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lightning-guard-run.XXXXXX") ||
    fail 'Cannot create working directory.'
cleanup_work() {
    rm -rf "$WORK_DIR"
}
trap cleanup_work 0 HUP INT TERM

case "$COMMAND" in
    check)
        [ -n "$PATH_ARG" ] || fail 'Missing required argument: --path'
        run_check "$(absolute_path "$PATH_ARG")"
        exit $?
        ;;
    readability)
        [ -n "$PATH_ARG" ] || fail 'Missing required argument: --path'
        run_readability "$(absolute_path "$PATH_ARG")"
        exit 0
        ;;
    compare)
        [ -n "$SOURCE" ] || fail 'Missing required argument: --source'
        [ -n "$OUTPUT" ] || fail 'Missing required argument: --output'
        run_compare "$(absolute_path "$SOURCE")" "$(absolute_path "$OUTPUT")"
        exit $?
        ;;
esac
