#!/bin/sh
set -eu

usage() {
  echo 'usage: inspect|check --path <platform-markdown> | self-test' >&2
  exit 2
}

if [ "$#" -lt 1 ]; then usage; fi
command_name=$1
shift

case "$command_name" in
  inspect|check)
    [ "$#" -eq 2 ] && [ "$1" = '--path' ] || usage
    article_path=$2
    [ -f "$article_path" ] || { echo 'path must be a Markdown file' >&2; exit 2; }
    ;;
  self-test)
    [ "$#" -eq 0 ] || usage
    ;;
  *) usage ;;
esac

if command -v locale >/dev/null 2>&1; then
  charset=$(locale charmap 2>/dev/null || true)
  case "$charset" in
    UTF-8|utf8|UTF8) ;;
    *)
      if locale -a 2>/dev/null | grep -Eiq '^en_US\.UTF-?8$'; then
        LC_CTYPE=en_US.UTF-8
        export LC_CTYPE
      fi
      ;;
  esac
fi
charset=$(locale charmap 2>/dev/null || true)
case "$charset" in UTF-8|utf8|UTF8) ;; *) echo 'UTF-8 locale is required' >&2; exit 2 ;; esac
command -v iconv >/dev/null 2>&1 || { echo 'iconv is required' >&2; exit 2; }

count_codepoints() {
  converted_path=$1.utf32
  if ! iconv -f UTF-8 -t UTF-32LE "$1" > "$converted_path" 2>/dev/null; then
    rm -f "$converted_path"
    echo 'invalid UTF-8 input' >&2
    return 1
  fi
  byte_count=$(wc -c < "$converted_path" | tr -d '[:space:]')
  rm -f "$converted_path"
  [ $((byte_count % 4)) -eq 0 ] || { echo 'invalid UTF-8 character count' >&2; exit 2; }
  printf '%d' $((byte_count / 4))
}

run_check() (
  mode=$1
  path=$2
  work_root=$(mktemp -d "${TMPDIR:-/tmp}/broadcast-length.XXXXXX") || exit 2
  trap 'rm -rf "$work_root"' EXIT HUP INT TERM
  awk -v root="$work_root" '
    function strip_visible(value, token, label) {
      while (match(value, /!\[[^]]*\]\([^)]*\)/)) value = substr(value, 1, RSTART - 1) substr(value, RSTART + RLENGTH)
      while (match(value, /\[[^]]+\]\([^)]*\)/)) {
        token = substr(value, RSTART, RLENGTH)
        label = token
        sub(/^\[/, "", label)
        sub(/\]\([^)]*\)$/, "", label)
        value = substr(value, 1, RSTART - 1) label substr(value, RSTART + RLENGTH)
      }
      gsub(/<[^>]+>/, "", value)
      gsub(/`[^`]*`/, "", value)
      sub(/^[ \t]*######[ \t]+/, "", value)
      sub(/^[ \t]*#####[ \t]+/, "", value)
      sub(/^[ \t]*####[ \t]+/, "", value)
      sub(/^[ \t]*###[ \t]+/, "", value)
      sub(/^[ \t]*##[ \t]+/, "", value)
      sub(/^[ \t]*#[ \t]+/, "", value)
      sub(/^[ \t]*[-+*][ \t]+/, "", value)
      sub(/^[ \t]*[0-9]+[.)][ \t]+/, "", value)
      sub(/^[ \t]*>[ \t]?/, "", value)
      gsub(/[*_~]/, "", value)
      gsub(/[[:space:]]/, "", value)
      return value
    }
    BEGIN { front_closed = 1; current_section = 0; printf "" > root "/visible" }
    {
      sub(/\r$/, "")
      line = $0
      if (NR == 1 && line == "---") { front_closed = 0; next }
      if (!front_closed) { if (line == "---") front_closed = 1; next }
      if (line ~ /^[ \t]*(```|~~~)/) {
        marker = substr(line, match(line, /```|~~~/), 3)
        if (fence == "") fence = marker; else if (marker == fence) fence = ""
        next
      }
      if (fence != "") { if (line !~ /^[[:space:]]*$/) code_lines++; next }
      if (index(line, "全文约 ") == 1) { notice_count++; notice_line = line; next }
      if (line ~ /^[ \t]*##[^#][ \t]*/) {
        title = line
        sub(/^[ \t]*##[ \t]+/, "", title)
        section_count++
        current_section = section_count
        printf "%s", title > root "/title." current_section
        printf "" > root "/section." current_section
      }
      visible = strip_visible(line)
      printf "%s", visible >> root "/visible"
      if (current_section > 0) printf "%s", visible >> root "/section." current_section
    }
    END {
      print code_lines + 0 > root "/code_lines"
      print notice_count + 0 > root "/notice_count"
      printf "%s", notice_line > root "/notice_line"
      print section_count + 0 > root "/section_count"
    }
  ' "$path" || exit 2

  code_lines=$(cat "$work_root/code_lines")
  notice_count=$(cat "$work_root/notice_count")
  notice_line=$(cat "$work_root/notice_line")
  section_count=$(cat "$work_root/section_count")

  visible_chars=$(count_codepoints "$work_root/visible") || exit 2
  display_chars=$(( (visible_chars + 50) / 100 * 100 ))
  estimated_minutes=$(( (visible_chars + 499) / 500 ))
  expected_notice="全文约 $display_chars 字，预计阅读 $estimated_minutes 分钟"
  requires_notice=false
  notice_found=false
  notice_matches=false
  error=''
  if [ "$visible_chars" -gt 3000 ]; then requires_notice=true; fi
  if [ "$notice_count" -gt 0 ]; then notice_found=true; fi
  if [ "$requires_notice" = true ] && [ "$notice_count" -eq 1 ] && [ "$notice_line" = "$expected_notice" ]; then notice_matches=true; fi
  if [ "$requires_notice" = false ] && [ "$notice_count" -eq 0 ]; then notice_matches=true; fi
  if [ "$requires_notice" = true ] && [ "$notice_found" = false ]; then error='long article notice is missing'
  elif [ "$requires_notice" = false ] && [ "$notice_found" = true ]; then error='short article must not contain a long article notice'
  elif [ "$notice_matches" = false ]; then error='long article notice does not match computed values'
  fi
  ok=$notice_matches
  escaped_path=$(printf '%s' "$path" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"ok":%s,"errors":[' "$ok"
  if [ -n "$error" ]; then printf '"%s"' "$error"; fi
  printf '],"path":"%s","visible_chars":%d,"display_chars":%d,"estimated_minutes":%d,"code_lines":%d,"section_count":%d,"sections":[' "$escaped_path" "$visible_chars" "$display_chars" "$estimated_minutes" "$code_lines" "$section_count"
  section_index=1
  while [ "$section_index" -le "$section_count" ]; do
    if [ "$section_index" -gt 1 ]; then printf ','; fi
    title=$(sed 's/\\/\\\\/g; s/"/\\"/g' "$work_root/title.$section_index")
    section_chars=$(count_codepoints "$work_root/section.$section_index") || exit 2
    printf '{"title":"%s","visible_chars":%d}' "$title" "$section_chars"
    section_index=$((section_index + 1))
  done
  printf '],"requires_notice":%s,"notice_found":%s,"notice_matches":%s,"expected_notice":' "$requires_notice" "$notice_found" "$notice_matches"
  if [ "$requires_notice" = true ]; then printf '"%s"' "$expected_notice"; else printf 'null'; fi
  printf '}\n'
  if [ "$mode" = check ] && [ "$ok" = false ]; then exit 1; fi
)

self_test() {
  test_root=${TMPDIR:-/tmp}/broadcast-length-$$
  mkdir "$test_root" || exit 2
  trap 'rm -rf "$test_root"' EXIT HUP INT TERM
  front='---
platform: zhihu
title: test
---
'
  printf '%s' "$front" > "$test_root/short.md"
  awk 'BEGIN { for (i = 0; i < 2999; i++) printf "a" }' >> "$test_root/short.md"
  printf '%s' "$front" > "$test_root/exact.md"
  awk 'BEGIN { for (i = 0; i < 3000; i++) printf "a" }' >> "$test_root/exact.md"
  printf '%s' "$front" > "$test_root/missing.md"
  awk 'BEGIN { for (i = 0; i < 3060; i++) printf "a" }' >> "$test_root/missing.md"
  printf '%s全文约 3000 字，预计阅读 7 分钟\n' "$front" > "$test_root/wrong_chars.md"
  awk 'BEGIN { for (i = 0; i < 3060; i++) printf "a" }' >> "$test_root/wrong_chars.md"
  printf '%s全文约 3100 字，预计阅读 1 分钟\n' "$front" > "$test_root/wrong_time.md"
  awk 'BEGIN { for (i = 0; i < 3060; i++) printf "a" }' >> "$test_root/wrong_time.md"
  printf '%s全文约 3100 字，预计阅读 7 分钟\n' "$front" > "$test_root/correct.md"
  awk 'BEGIN { for (i = 0; i < 3060; i++) printf "a" }' >> "$test_root/correct.md"
  printf '%s## Part\n中文 [link](https://example.com) ![alt](x.png) <b>x</b> `code` 😀\n```text\nignored\n```\n' "$front" > "$test_root/mixed.md"

  passed=0
  failed=0
  for name in short exact correct; do
    if run_check check "$test_root/$name.md" >/dev/null; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
  done
  for name in missing wrong_chars wrong_time; do
    if run_check check "$test_root/$name.md" >/dev/null; then failed=$((failed + 1)); else passed=$((passed + 1)); fi
  done
  mixed_output=$(run_check check "$test_root/mixed.md") || failed=$((failed + 1))
  if printf '%s' "$mixed_output" | grep -q '"visible_chars":12' && printf '%s' "$mixed_output" | grep -q '"code_lines":1' && printf '%s' "$mixed_output" | grep -q '"section_count":1'; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
  if [ "$failed" -eq 0 ]; then
    printf '{"ok":true,"passed":%d,"failed":0}\n' "$passed"
    exit 0
  fi
  printf '{"ok":false,"passed":%d,"failed":%d}\n' "$passed" "$failed"
  exit 1
}

if [ "$command_name" = 'self-test' ]; then
  self_test
else
  run_check "$command_name" "$article_path"
fi
