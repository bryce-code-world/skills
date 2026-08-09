#!/bin/sh
set -eu

usage() {
    printf '%s\n' 'Usage: prepare_article.sh --platform <wechat|zhihu|csdn|juejin> --input <article.md> --output <directory>' >&2
    exit 2
}

platform=
input=
output=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --platform) [ "$#" -ge 2 ] || usage; platform=$2; shift 2 ;;
        --input) [ "$#" -ge 2 ] || usage; input=$2; shift 2 ;;
        --output) [ "$#" -ge 2 ] || usage; output=$2; shift 2 ;;
        *) usage ;;
    esac
done

case "$platform" in wechat|zhihu|csdn|juejin) ;; *) usage ;; esac
[ -n "$input" ] && [ -n "$output" ] || usage
[ -f "$input" ] || { printf 'Input file does not exist: %s\n' "$input" >&2; exit 1; }

input_dir=$(CDPATH= cd -- "$(dirname -- "$input")" && pwd -P)
input_abs=$input_dir/$(basename -- "$input")
mkdir -p -- "$output"
output_abs=$(CDPATH= cd -- "$output" && pwd -P)
body_md=$output_abs/body.md
body_html=$output_abs/body.html
manifest=$output_abs/manifest.json

first_line=$(LC_ALL=C sed -n '1p' "$input")
[ "$first_line" = '---' ] || { printf '%s\n' 'Article must start with YAML front matter.' >&2; exit 1; }

front_end=$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$input")
[ -n "$front_end" ] || { printf '%s\n' 'Front matter is not closed.' >&2; exit 1; }

meta_value() {
    key=$1
    awk -v key="$key" -v end="$front_end" '
        NR > 1 && NR < end && index($0, key ":") == 1 {
            value=substr($0, length(key)+2)
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            if ((substr(value,1,1)=="\"" && substr(value,length(value),1)=="\"") ||
                (substr(value,1,1)=="\047" && substr(value,length(value),1)=="\047")) {
                value=substr(value,2,length(value)-2)
            }
            print value
            exit
        }
    ' "$input"
}

article_platform=$(meta_value platform)
title=$(meta_value title)
summary=$(meta_value summary)
cover=$(meta_value cover)
source=$(meta_value source)
[ -n "$article_platform" ] && [ -n "$title" ] || { printf '%s\n' 'Missing front matter field: platform or title' >&2; exit 1; }
[ "$article_platform" = "$platform" ] || { printf 'Platform mismatch: article=%s, requested=%s\n' "$article_platform" "$platform" >&2; exit 1; }

awk -v end="$front_end" '
    NR > end {
        sub(/\r$/, "")
        if (!started && $0 == "") next
        started=1
        lines[++count]=$0
    }
    END {
        while (count > 0 && lines[count] == "") count--
        for (i=1; i<=count; i++) print lines[i]
    }
' "$input" > "$body_md"
[ -s "$body_md" ] || { printf '%s\n' 'Article body is empty.' >&2; exit 1; }

if [ "$platform" = wechat ] || [ "$platform" = zhihu ]; then
    if grep -Eq '^(>|```|\|.*\|[[:space:]]*$)' "$body_md"; then
        printf '%s article contains a structure that is not allowed.\n' "$platform" >&2
        exit 1
    fi
fi

awk -v platform="$platform" '
function esc(s) {
    gsub(/&/, "\\&amp;", s)
    gsub(/</, "\\&lt;", s)
    gsub(/>/, "\\&gt;", s)
    gsub(/"/, "\\&quot;", s)
    return s
}
function pair(s, token, open_tag, close_tag,    a, rest, b) {
    while ((a=index(s,token)) > 0) {
        rest=substr(s,a+length(token))
        b=index(rest,token)
        if (b == 0) break
        s=substr(s,1,a-1) open_tag substr(rest,1,b-1) close_tag substr(rest,b+length(token))
    }
    return s
}
function inline(s,    strong, code) {
    s=esc(s)
    strong=(platform=="wechat" ? "<strong style=\"font-weight:700;color:#242424;\">" : "<strong style=\"font-weight:700;\">")
    code=(platform=="wechat" ? "<code style=\"font-family:Consolas,Menlo,monospace;font-size:0.94em;background:#f5f5f5;padding:1px 4px;border-radius:3px;\">" : "<code style=\"font-family:monospace;\">")
    s=pair(s,"**",strong,"</strong>")
    s=pair(s,"`",code,"</code>")
    return s
}
function flush_paragraph() {
    if (paragraph != "") {
        print "<p style=\"" pstyle "\">" inline(paragraph) "</p>"
        paragraph=""
    }
}
function flush_list() {
    if (list_type != "") print list_html "</" list_type ">"
    list_type=""
    list_html=""
}
function flush_all() { flush_paragraph(); flush_list() }
BEGIN {
    pstyle=(platform=="wechat" ? "font-size:16px;line-height:1.85;color:#303030;margin:0 0 20px;text-align:left;letter-spacing:0.02em;" : "")
    h2style=(platform=="wechat" ? "font-size:19px;line-height:1.5;font-weight:700;color:#242424;margin:42px 0 20px;padding-left:10px;border-left:3px solid #c58a45;text-align:left;" : "")
    h3style=(platform=="wechat" ? "font-size:17px;line-height:1.55;font-weight:700;color:#242424;margin:32px 0 16px;text-align:left;" : "")
    lstyle=(platform=="wechat" ? "font-size:16px;line-height:1.85;color:#303030;margin:0 0 14px;text-align:left;padding-left:0;" : "")
    istyle=(platform=="wechat" ? "display:block;width:100%;height:auto;margin:28px auto 10px;" : "max-width:100%;height:auto;")
    image_count=0
    print "<section data-distribution-platform=\"" platform "\">"
}
{
    sub(/\r$/, "")
    line=$0
    trimmed=line
    sub(/^[[:space:]]+/, "", trimmed)
    sub(/[[:space:]]+$/, "", trimmed)
    if (in_code) {
        if (substr(trimmed,1,3) == "```") {
            print "<pre><code class=\"language-" esc(code_language) "\">" esc(code_content) "</code></pre>"
            in_code=0
            code_language=""
            code_content=""
        } else {
            code_content=(code_content=="" ? line : code_content "\n" line)
        }
        next
    }
    if (trimmed == "") { flush_all(); next }
    if (substr(trimmed,1,3) == "## ") {
        flush_all(); print "<h2 style=\"" h2style "\">" inline(substr(trimmed,4)) "</h2>"; next
    }
    if (substr(trimmed,1,4) == "### ") {
        flush_all(); print "<h3 style=\"" h3style "\">" inline(substr(trimmed,5)) "</h3>"; next
    }
    if (substr(trimmed,1,3) == "```") {
        flush_all(); in_code=1; code_language=substr(trimmed,4); sub(/^[[:space:]]+/, "", code_language); next
    }
    if (substr(trimmed,1,2) == "- ") {
        flush_paragraph()
        item=inline(substr(trimmed,3))
        if (platform == "wechat") {
            flush_list(); print "<p data-list-item=\"bullet\" style=\"" lstyle "\"><strong style=\"font-weight:700;color:#242424;\">&#8226;</strong>&nbsp;&nbsp;" item "</p>"
        } else {
            if (list_type != "ul") { flush_list(); list_type="ul"; list_html="<ul>" }
            list_html=list_html "<li>" item "</li>"
        }
        next
    }
    if (trimmed ~ /^[0-9]+\.[[:space:]]+/) {
        flush_paragraph()
        number=trimmed; sub(/\..*$/, "", number)
        item=trimmed; sub(/^[0-9]+\.[[:space:]]+/, "", item); item=inline(item)
        if (platform == "wechat") {
            flush_list(); print "<p data-list-item=\"ordered\" style=\"" lstyle "\"><strong style=\"font-weight:700;color:#242424;\">" number ".</strong>&nbsp;&nbsp;" item "</p>"
        } else {
            if (list_type != "ol") { flush_list(); list_type="ol"; list_html="<ol>" }
            list_html=list_html "<li>" item "</li>"
        }
        next
    }
    if (trimmed ~ /^!\[[^]]*\]\([^)]+\)$/) {
        flush_all()
        alt=trimmed; sub(/^!\[/,"",alt); sub(/\].*$/,"",alt)
        image_count++
        placeholder=sprintf("__DISTRIBUTION_IMAGE_%03d__",image_count)
        print "<p style=\"" pstyle "\"><img src=\"" placeholder "\" alt=\"" esc(alt) "\" style=\"" istyle "\" /></p>"
        next
    }
    flush_list()
    paragraph=(paragraph=="" ? trimmed : paragraph " " trimmed)
}
END {
    if (in_code) exit 1
    flush_all()
    print "</section>"
}
' "$body_md" > "$body_html"

json_escape() {
    awk 'BEGIN { ORS="" } { if (NR > 1) printf "\\n"; gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\r/, "\\r"); gsub(/\t/, "\\t"); printf "%s", $0 }'
}

cover_abs=
if [ -n "$cover" ]; then
    cover_dir=$(dirname -- "$input_dir/$cover")
    cover_name=$(basename -- "$cover")
    [ -f "$input_dir/$cover" ] || { printf 'Cover image does not exist: %s\n' "$input_dir/$cover" >&2; exit 1; }
    cover_abs=$(CDPATH= cd -- "$cover_dir" && pwd -P)/$cover_name
fi

image_count=$(grep -Ec '^!\[[^]]*\]\([^)]+\)[[:space:]]*$' "$body_md" || true)
title_json=$(printf '%s' "$title" | json_escape)
summary_json=$(printf '%s' "$summary" | json_escape)
source_json=$(printf '%s' "$source" | json_escape)
input_json=$(printf '%s' "$input_abs" | json_escape)
cover_json=$(printf '%s' "$cover_abs" | json_escape)
body_md_json=$(printf '%s' "$body_md" | json_escape)
body_html_json=$(printf '%s' "$body_html" | json_escape)

{
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "platform": "%s",\n' "$platform"
    printf '  "title": "%s",\n' "$title_json"
    printf '  "summary": "%s",\n' "$summary_json"
    printf '  "source_article": "%s",\n' "$input_json"
    printf '  "source": "%s",\n' "$source_json"
    printf '  "cover": "%s",\n' "$cover_json"
    printf '  "body_markdown": "%s",\n' "$body_md_json"
    printf '  "body_html": "%s",\n' "$body_html_json"
    printf '  "image_count": %s\n' "$image_count"
    printf '}\n'
} > "$manifest"

printf '{"ok":true,"platform":"%s","manifest":"%s","body_markdown":"%s","body_html":"%s","image_count":%s}\n' \
    "$platform" "$manifest" "$body_md" "$body_html" "$image_count"
