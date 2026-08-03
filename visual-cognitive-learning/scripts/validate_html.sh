#!/bin/sh

# POSIX adapter for the deterministic offline single-HTML contract.
set -u

VIOLATION_ORDER='missing-doctype
missing-html
missing-head
missing-body
missing-lang
missing-title
missing-viewport
external-resource
css-external-url
network-api
dynamic-code
module-import
duplicate-id
unlabeled-control
missing-reduced-motion
missing-inline-style
missing-static-content'

json_escape() {
    printf '%s' "$1" | awk 'BEGIN { ORS="" }
        {
            if (NR > 1) printf "\\n"
            gsub(/\\/, "\\\\")
            gsub(/"/, "\\\"")
            gsub(/\r/, "\\r")
            gsub(/\t/, "\\t")
            printf "%s", $0
        }'
}

emit_error() {
    command_name=$1
    message=$2
    printf '{"ok":false,"command":"%s","error":"%s"}\n' \
        "$(json_escape "$command_name")" "$(json_escape "$message")"
}

add_violation() {
    code=$1
    case "
$VIOLATIONS
" in
        *"
$code
"*) ;;
        *)
            if [ -n "$VIOLATIONS" ]; then
                VIOLATIONS="$VIOLATIONS
$code"
            else
                VIOLATIONS=$code
            fi
            ;;
    esac
}

has_pattern() {
    pattern=$1
    file=$2
    grep -Eiq "$pattern" "$file"
}

attribute_values() {
    attribute=$1
    file=$2
    grep -Eio "${attribute}[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]" "$file" 2>/dev/null |
        sed "s/^[^=]*=[[:space:]]*['\"]//; s/['\"]$//"
}

validate_file() {
    input_path=$1
    if [ ! -f "$input_path" ]; then
        VALIDATION_ERROR="Path is not a regular file: $input_path"
        return 2
    fi

    path_dir=$(dirname "$input_path") || return 2
    path_name=$(basename "$input_path") || return 2
    resolved_dir=$(cd "$path_dir" 2>/dev/null && pwd -P) || {
        VALIDATION_ERROR="Cannot resolve path: $input_path"
        return 2
    }
    RESOLVED_PATH=$resolved_dir/$path_name

    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/visual-cognitive-learning.XXXXXX") || {
        VALIDATION_ERROR='Cannot create temporary directory'
        return 2
    }
    one_line=$WORK_DIR/content.html
    lower=$WORK_DIR/content.lower
    tags=$WORK_DIR/tags.txt
    scripts=$WORK_DIR/scripts.txt
    labels=$WORK_DIR/labels.txt

    if ! tr '\r\n\t' '   ' < "$RESOLVED_PATH" > "$one_line"; then
        VALIDATION_ERROR="Cannot read UTF-8 HTML: $RESOLVED_PATH"
        rm -rf "$WORK_DIR"
        return 2
    fi
    tr '[:upper:]' '[:lower:]' < "$one_line" > "$lower"
    sed 's/</\
</g' "$lower" > "$tags"
    sed 's#</script>#</script>\
#g' "$lower" |
        sed -n 's#.*<script[^>]*>\(.*\)</script>.*#\1#p' > "$scripts"

    VIOLATIONS=''
    has_pattern '<!doctype[[:space:]]+html[[:space:]]*>' "$lower" || add_violation 'missing-doctype'
    has_pattern '<html([^>]*)>.*</html[[:space:]]*>' "$lower" || add_violation 'missing-html'
    has_pattern '<head([^>]*)>.*</head[[:space:]]*>' "$lower" || add_violation 'missing-head'
    has_pattern '<body([^>]*)>.*</body[[:space:]]*>' "$lower" || add_violation 'missing-body'
    has_pattern "<html[^>]*lang[[:space:]]*=[[:space:]]*['\"][^'\"]+['\"]" "$lower" || add_violation 'missing-lang'
    has_pattern '<title[^>]*>[^<[:space:]][^<]*</title[[:space:]]*>' "$lower" || add_violation 'missing-title'
    has_pattern "<meta[^>]*name[[:space:]]*=[[:space:]]*['\"]viewport['\"]" "$lower" || add_violation 'missing-viewport'

    grep -Ei '^<(script|img|iframe|source|video|audio|link)([[:space:]>])' "$tags" > "$WORK_DIR/resource-tags.txt" 2>/dev/null || :
    attribute_values '(src|href)' "$WORK_DIR/resource-tags.txt" > "$WORK_DIR/resource-values.txt" || :
    while IFS= read -r value; do
        [ -z "$value" ] && continue
        case "$value" in
            data:*|'#'*) ;;
            *) add_violation 'external-resource'; break ;;
        esac
    done < "$WORK_DIR/resource-values.txt"

    grep -Ei '^<style([[:space:]>])|style[[:space:]]*=' "$tags" > "$WORK_DIR/css-parts.txt" 2>/dev/null || :
    grep -Eio 'url\([[:space:]]*[^)]*\)' "$WORK_DIR/css-parts.txt" 2>/dev/null |
        sed -e 's/^url([[:space:]]*//' -e 's/[[:space:]]*)$//' -e "s/^[\"']//" -e "s/[\"']$//" > "$WORK_DIR/css-values.txt" || :
    while IFS= read -r value; do
        [ -z "$value" ] && continue
        case "$value" in
            data:*|'#'*) ;;
            *) add_violation 'css-external-url'; break ;;
        esac
    done < "$WORK_DIR/css-values.txt"
    has_pattern '(^|[^[:alnum:]_])(fetch|xmlhttprequest|websocket|eventsource)[[:space:]]*\(|navigator[[:space:]]*\.[[:space:]]*sendbeacon[[:space:]]*\(' "$scripts" && add_violation 'network-api'
    has_pattern '(^|[^[:alnum:]_])eval[[:space:]]*\(|new[[:space:]]+function[[:space:]]*\(' "$scripts" && add_violation 'dynamic-code'
    if has_pattern "<script[^>]*type[[:space:]]*=[[:space:]]*['\"]module['\"]" "$lower" ||
       has_pattern "(^|[^[:alnum:]_])import[[:space:]]*(\(|[^;]*from[[:space:]]*['\"])" "$scripts"; then
        add_violation 'module-import'
    fi

    attribute_values 'id' "$tags" | sed '/^[[:space:]]*$/d' | sort | uniq -d > "$WORK_DIR/duplicate-ids.txt"
    [ -s "$WORK_DIR/duplicate-ids.txt" ] && add_violation 'duplicate-id'

    grep -Ei '^<label([[:space:]>])' "$tags" > "$WORK_DIR/label-tags.txt" 2>/dev/null || :
    attribute_values 'for' "$WORK_DIR/label-tags.txt" | sed '/^[[:space:]]*$/d' > "$labels" || :
    grep -Ei '^<(input|select|textarea)([[:space:]>])' "$tags" > "$WORK_DIR/control-tags.txt" 2>/dev/null || :
    while IFS= read -r control; do
        printf '%s\n' "$control" | grep -Eiq "type[[:space:]]*=[[:space:]]*['\"]hidden['\"]" && continue
        printf '%s\n' "$control" | grep -Eiq "aria-(label|labelledby)[[:space:]]*=[[:space:]]*['\"][^'\"]+['\"]" && continue
        control_id=$(printf '%s\n' "$control" | grep -Eio "id[[:space:]]*=[[:space:]]*['\"][^'\"]+['\"]" | sed "s/^[^=]*=[[:space:]]*['\"]//; s/['\"]$//" | sed -n '1p')
        if [ -n "$control_id" ] && awk -v target="$control_id" 'tolower($0) == tolower(target) { found=1 } END { exit !found }' "$labels"; then
            continue
        fi
        add_violation 'unlabeled-control'
        break
    done < "$WORK_DIR/control-tags.txt"

    grep -iq 'prefers-reduced-motion' "$lower" || add_violation 'missing-reduced-motion'
    has_pattern '<style([^>]*)>.*</style[[:space:]]*>' "$lower" || add_violation 'missing-inline-style'

    visible_count=$(sed -E 's#.*<body[^>]*>##; s#</body>.*##; s#<script[^>]*>.*</script># #g; s#<style[^>]*>.*</style># #g; s#<[^>]+># #g' "$lower" |
        tr -d '[:space:]' | wc -c | tr -d '[:space:]')
    [ "${visible_count:-0}" -lt 40 ] && add_violation 'missing-static-content'

    rm -rf "$WORK_DIR"
    WORK_DIR=''
    return 0
}

violations_json() {
    first=1
    printf '['
    old_ifs=$IFS
    IFS='
'
    for code in $VIOLATIONS; do
        [ -z "$code" ] && continue
        if [ "$first" -eq 0 ]; then printf ','; fi
        printf '"%s"' "$(json_escape "$code")"
        first=0
    done
    IFS=$old_ifs
    printf ']'
}

emit_check() {
    if [ -z "$VIOLATIONS" ]; then ok=true; else ok=false; fi
    printf '{"ok":%s,"command":"check","path":"%s","violations":' "$ok" "$(json_escape "$RESOLVED_PATH")"
    violations_json
    printf '}\n'
}

self_test() {
    root=$(mktemp -d "${TMPDIR:-/tmp}/visual-cognitive-learning-self-test.XXXXXX") || return 1
    case_root=$root/'中文 path'
    mkdir -p "$case_root" || { rm -rf "$root"; return 1; }
    good=$case_root/good.html
    bad=$case_root/bad.html
    printf '%s' '<!doctype html><html lang="zh-CN"><head><meta name="viewport" content="width=device-width"><title>流程学习</title><style>body{color:#111}@media (prefers-reduced-motion: reduce){*{animation:none}}</style></head><body><main><h1>理解交付流程</h1><p>这个页面保留足够的静态说明，让脚本失效时仍能理解阶段、检查、异常处理和最终交付之间的关系。</p><label for="step">选择阶段</label><select id="step"><option>分析</option></select></main><script>document.documentElement.dataset.ready="true";</script></body></html>' > "$good"
    printf '%s' '<script type="module" src="https://example.com/a.js">fetch("https://example.com");eval("1");import("./x.js")</script><img src="https://example.com/x.png"><input id="same"><div id="same" style="background:url(https://example.com/x.png)"></div>' > "$bad"

    if ! validate_file "$good" || [ -n "$VIOLATIONS" ]; then
        rm -rf "$root"
        return 1
    fi
    if ! validate_file "$bad" || [ "$VIOLATIONS" != "$VIOLATION_ORDER" ]; then
        rm -rf "$root"
        return 1
    fi
    if validate_file "$case_root/missing.html"; then
        rm -rf "$root"
        return 1
    fi
    rm -rf "$root"
    return 0
}

command_name=${1:-}
case "$command_name" in
    check)
        if [ "$#" -ne 3 ] || [ "$2" != '--path' ]; then
            emit_error 'check' 'check requires --path <html-file>'
            exit 2
        fi
        if ! validate_file "$3"; then
            emit_error 'check' "$VALIDATION_ERROR"
            exit 2
        fi
        emit_check
        [ -z "$VIOLATIONS" ] && exit 0
        exit 1
        ;;
    self-test)
        if [ "$#" -ne 1 ]; then
            emit_error 'self-test' 'self-test does not accept arguments'
            exit 2
        fi
        if self_test; then
            printf '{"ok":true,"command":"self-test","tests":3}\n'
            exit 0
        fi
        emit_error 'self-test' 'self-test failed'
        exit 2
        ;;
    *)
        emit_error "$command_name" 'Expected: check --path <html-file> | self-test'
        exit 2
        ;;
esac
