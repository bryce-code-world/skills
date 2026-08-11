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
body_raw=$(mktemp "${TMPDIR:-/tmp}/distribution-body.XXXXXX")
image_meta=$(mktemp "${TMPDIR:-/tmp}/distribution-images.XXXXXX")
images_json=$(mktemp "${TMPDIR:-/tmp}/distribution-images-json.XXXXXX")
trap 'rm -f -- "$body_raw" "$image_meta" "$images_json"' EXIT HUP INT TERM
caption_prefix=$(printf '\345\233\276\346\263\250\357\274\232')
legacy_caption_prefix=$(printf '\345\233\276\357\274\232')

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
' "$input" > "$body_raw"
[ -s "$body_raw" ] || { printf '%s\n' 'Article body is empty.' >&2; exit 1; }

if [ "$platform" = wechat ] || [ "$platform" = zhihu ]; then
    if grep -Eq '^(>|```|\|.*\|[[:space:]]*$)' "$body_raw"; then
        printf '%s article contains a structure that is not allowed.\n' "$platform" >&2
        exit 1
    fi
fi

awk -v caption_prefix="$caption_prefix" -v legacy_caption_prefix="$legacy_caption_prefix" '
function trim(s) {
    sub(/^[[:space:]]+/, "", s)
    sub(/[[:space:]]+$/, "", s)
    return s
}
function is_caption(s) {
    return index(s, caption_prefix) == 1 || index(s, legacy_caption_prefix) == 1
}
function caption_text(s) {
    if (index(s, caption_prefix) == 1) s=substr(s, length(caption_prefix)+1)
    else s=substr(s, length(legacy_caption_prefix)+1)
    return trim(s)
}
function fail(message) {
    print message > "/dev/stderr"
    failed=1
}
{
    sub(/\r$/, "")
    lines[NR]=$0
    current=trim($0)
    if (substr(current,1,3) == "```") {
        code_line[NR]=1
        in_code=!in_code
    } else if (in_code) {
        code_line[NR]=1
    }
}
END {
    for (i=1; i<=NR; i++) {
        if (i in code_line) continue
        current=trim(lines[i])
        if (current !~ /^!\[[^]]*\]\([^)]+\)$/) continue

        alt=current
        sub(/^!\[/, "", alt)
        sub(/\].*$/, "", alt)
        relative_path=current
        sub(/^!\[[^]]*\]\(/, "", relative_path)
        sub(/\)$/, "", relative_path)

        caption_line=i+1
        while (caption_line<=NR && trim(lines[caption_line]) == "") caption_line++
        has_caption=(caption_line<=NR && is_caption(trim(lines[caption_line])))

        if (alt == "") {
            if (has_caption) fail("Decorative image must not have a caption at body line " caption_line ".")
            record_count++
            image_line[record_count]=i
            caption_line_number[record_count]=0
            image_alt[record_count]=alt
            image_path[record_count]=relative_path
            image_caption[record_count]=""
            image_role[record_count]="decorative"
        } else if (!has_caption || caption_text(trim(lines[caption_line])) == "") {
            fail("Informative image is missing an adjacent caption at body line " i ".")
        } else {
            bound_caption[caption_line]=1
            record_count++
            image_line[record_count]=i
            caption_line_number[record_count]=caption_line
            image_alt[record_count]=alt
            image_path[record_count]=relative_path
            image_caption[record_count]=caption_text(trim(lines[caption_line]))
            image_role[record_count]="informative"
        }
    }

    for (i=1; i<=NR; i++) {
        if (!(i in code_line) && is_caption(trim(lines[i])) && !(i in bound_caption)) fail("Orphan image caption at body line " i ".")
    }
    if (failed) exit 1

    for (i=1; i<=record_count; i++) {
        printf "%s%c%s%c%s%c%s%c%s%c%s\n", image_line[i], 28, caption_line_number[i], 28, image_alt[i], 28, image_path[i], 28, image_caption[i], 28, image_role[i]
    }
}
' "$body_raw" > "$image_meta"

awk -F '\034' -v platform="$platform" -v caption_prefix="$caption_prefix" -v metadata="$image_meta" '
BEGIN {
    while ((getline record < metadata) > 0) {
        split(record, fields, "\034")
        if (fields[2] != "0") caption_by_line[fields[2]]=fields[5]
    }
    close(metadata)
}
{
    if (NR in caption_by_line) {
        line=caption_prefix caption_by_line[NR]
        if (platform == "csdn" || platform == "juejin") line="*" line "*"
        print line
    } else {
        print
    }
}
' "$body_raw" > "$body_md"

awk -F '\034' -v platform="$platform" -v metadata="$image_meta" '
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
    while ((getline record < metadata) > 0) {
        split(record, fields, "\034")
        caption_by_image[fields[1]]=fields[5]
        if (fields[2] != "0") bound_caption[fields[2]]=1
    }
    close(metadata)
    pstyle=(platform=="wechat" ? "font-size:16px;line-height:1.85;color:#303030;margin:0 0 20px;text-align:left;letter-spacing:0.02em;" : "")
    h2style=(platform=="wechat" ? "font-size:19px;line-height:1.5;font-weight:700;color:#242424;margin:42px 0 20px;padding-left:10px;border-left:3px solid #c58a45;text-align:left;" : "")
    h3style=(platform=="wechat" ? "font-size:17px;line-height:1.55;font-weight:700;color:#242424;margin:32px 0 16px;text-align:left;" : "")
    lstyle=(platform=="wechat" ? "font-size:16px;line-height:1.85;color:#303030;margin:0 0 14px;text-align:left;padding-left:0;" : "")
    istyle=(platform=="wechat" ? "display:block;width:100%;height:auto;margin:28px auto 8px;" : "max-width:100%;height:auto;")
    image_container_style=(platform=="wechat" ? "margin:0;" : "")
    caption_style=(platform=="wechat" ? "font-size:13px;line-height:1.6;color:#888888;margin:0 0 24px;text-align:center;" : "")
    image_count=0
    print "<section data-distribution-platform=\"" platform "\">"
}
{
    sub(/\r$/, "")
    line=$0
    trimmed=line
    sub(/^[[:space:]]+/, "", trimmed)
    sub(/[[:space:]]+$/, "", trimmed)
    if (NR in bound_caption) next
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
        if (NR in caption_by_image && caption_by_image[NR] != "") {
            caption=inline(caption_by_image[NR])
            if (platform == "wechat") {
                print "<p data-image=\"true\" style=\"" image_container_style "\"><img src=\"" placeholder "\" alt=\"" esc(alt) "\" style=\"" istyle "\" /></p>"
                print "<p data-image-caption=\"true\" style=\"" caption_style "\">" caption "</p>"
            } else {
                print "<figure data-image=\"true\"><img src=\"" placeholder "\" alt=\"" esc(alt) "\" style=\"" istyle "\" /><figcaption>" caption "</figcaption></figure>"
            }
        } else {
            print "<p data-image=\"true\" style=\"" image_container_style "\"><img src=\"" placeholder "\" alt=\"" esc(alt) "\" style=\"" istyle "\" /></p>"
        }
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
' "$body_raw" > "$body_html"

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

image_count=0
: > "$images_json"
field_separator=$(printf '\034')
while IFS="$field_separator" read -r image_line caption_line alt relative_path caption role; do
    [ -n "$image_line" ] || continue
    image_file=$input_dir/$relative_path
    [ -f "$image_file" ] || { printf 'Article image does not exist: %s\n' "$image_file" >&2; exit 1; }
    image_dir=$(dirname -- "$image_file")
    image_name=$(basename -- "$image_file")
    image_abs=$(CDPATH= cd -- "$image_dir" && pwd -P)/$image_name
    image_count=$((image_count + 1))
    placeholder=$(printf '__DISTRIBUTION_IMAGE_%03d__' "$image_count")
    placeholder_json=$(printf '%s' "$placeholder" | json_escape)
    relative_path_json=$(printf '%s' "$relative_path" | json_escape)
    image_abs_json=$(printf '%s' "$image_abs" | json_escape)
    alt_json=$(printf '%s' "$alt" | json_escape)
    caption_json=$(printf '%s' "$caption" | json_escape)
    role_json=$(printf '%s' "$role" | json_escape)
    [ "$image_count" -eq 1 ] || printf ',\n' >> "$images_json"
    printf '    {"placeholder": "%s", "relative_path": "%s", "absolute_path": "%s", "alt": "%s", "caption": "%s", "role": "%s"}' \
        "$placeholder_json" "$relative_path_json" "$image_abs_json" "$alt_json" "$caption_json" "$role_json" >> "$images_json"
done < "$image_meta"
title_json=$(printf '%s' "$title" | json_escape)
summary_json=$(printf '%s' "$summary" | json_escape)
source_json=$(printf '%s' "$source" | json_escape)
input_json=$(printf '%s' "$input_abs" | json_escape)
cover_json=$(printf '%s' "$cover_abs" | json_escape)
body_md_json=$(printf '%s' "$body_md" | json_escape)
body_html_json=$(printf '%s' "$body_html" | json_escape)

{
    printf '{\n'
    printf '  "schema_version": 2,\n'
    printf '  "platform": "%s",\n' "$platform"
    printf '  "title": "%s",\n' "$title_json"
    printf '  "summary": "%s",\n' "$summary_json"
    printf '  "source_article": "%s",\n' "$input_json"
    printf '  "source": "%s",\n' "$source_json"
    printf '  "cover": "%s",\n' "$cover_json"
    printf '  "body_markdown": "%s",\n' "$body_md_json"
    printf '  "body_html": "%s",\n' "$body_html_json"
    printf '  "images": [\n'
    cat "$images_json"
    [ "$image_count" -eq 0 ] || printf '\n'
    printf '  ]\n'
    printf '}\n'
} > "$manifest"

printf '{"ok":true,"platform":"%s","manifest":"%s","body_markdown":"%s","body_html":"%s","image_count":%s}\n' \
    "$platform" "$manifest" "$body_md" "$body_html" "$image_count"
