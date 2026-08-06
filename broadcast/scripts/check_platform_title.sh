#!/bin/sh
# Checks that platform Markdown keeps its title in front matter and not in the body.

fail() {
    printf 'Cannot check platform Markdown: %s\n' "$1" >&2
    exit 2
}

check_file() {
    awk '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function unquote(value, first, last) {
            value = trim(value)
            first = substr(value, 1, 1)
            last = substr(value, length(value), 1)
            if (length(value) >= 2 && ((first == "\"" && last == "\"") || (first == "\047" && last == "\047")))
                return substr(value, 2, length(value) - 2)
            return value
        }
        NR == 1 {
            sub(/^\xef\xbb\xbf/, "", $0)
            if ($0 != "---") exit 0
            frontmatter = 1
            next
        }
        frontmatter {
            if ($0 == "---") {
                frontmatter = 0
                body = 1
                next
            }
            if ($0 ~ /^platform:[[:space:]]*/) {
                value = $0
                sub(/^platform:[[:space:]]*/, "", value)
                platform = unquote(value)
            }
            if ($0 ~ /^title:[[:space:]]*/) {
                value = $0
                sub(/^title:[[:space:]]*/, "", value)
                title = unquote(value)
            }
            next
        }
        body {
            line = $0
            sub(/\r$/, "", line)
            if (line ~ /^[[:space:]]*(```|~~~)/) {
                marker = line
                sub(/^[[:space:]]*/, "", marker)
                marker = substr(marker, 1, 3)
                if (!fence) {
                    fence = 1
                    fence_marker = marker
                } else if (marker == fence_marker) {
                    fence = 0
                    fence_marker = ""
                }
                next
            }
            if (fence || trim(line) == "") next
            if (!first_body_seen) {
                first_body_seen = 1
                first_body = trim(line)
                first_body_line = NR
            }
            if (line ~ /^#[[:space:]]+/) {
                printf "%s:%d: platform body must not contain an H1\n", FILENAME, NR > "/dev/stderr"
                failed = 1
            }
        }
        END {
            supported = platform == "wechat" || platform == "zhihu" || platform == "csdn" || platform == "juejin"
            if (!supported) exit 0
            if (title == "") {
                printf "%s: front matter requires a non-empty title\n", FILENAME > "/dev/stderr"
                failed = 1
            }
            if (!first_body_seen) {
                printf "%s: platform body is empty\n", FILENAME > "/dev/stderr"
                failed = 1
            } else if (title != "" && first_body == title) {
                printf "%s:%d: first body line repeats front matter title\n", FILENAME, first_body_line > "/dev/stderr"
                failed = 1
            }
            if (!failed) printf "[PASS] %s\n", FILENAME
            exit failed ? 1 : 0
        }
    ' "$1"
}

target=${1-}
[ -n "$target" ] || fail 'missing Markdown file or directory path'
[ -e "$target" ] || fail "path does not exist: $target"

status=0
checked=0
if [ -d "$target" ]; then
    while IFS= read -r file; do
        checked=$((checked + 1))
        check_file "$file" || status=1
    done <<EOF
$(find "$target" -type f -name '*.md')
EOF
else
    checked=1
    check_file "$target" || status=1
fi

[ "$status" -eq 0 ] || exit 1
printf 'platform title check completed: %d Markdown file(s) scanned\n' "$checked"
