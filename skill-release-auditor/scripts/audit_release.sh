#!/bin/sh

set -u

AUDIT_TEMP=

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

layer_json() {
  target_host=${4:-portable}
  printf '{"status":"%s","rule_id":"%s","source":"skill-release-auditor/validation-contract-v1","host":"%s","evidence":"%s"}' "$1" "$2" "$target_host" "$(json_escape "$3")"
}

assert_equal() {
  [ "$2" = "$3" ] || { printf '%s\n' "self-test failed: $1 expected '$3', got '$2'" >&2; exit 1; }
}

cleanup() {
  if [ -n "$AUDIT_TEMP" ] && [ -d "$AUDIT_TEMP" ]; then
    case "$AUDIT_TEMP" in
      "${TMPDIR:-/tmp}"/skill-release-auditor-*) rm -rf "$AUDIT_TEMP" ;;
      *) return ;;
    esac
  fi
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v certutil.exe >/dev/null 2>&1; then
    certutil.exe -hashfile "$1" SHA256 2>/dev/null | tr -d '\r ' | sed -n '2p' | tr 'A-F' 'a-f'
  else
    return 1
  fi
}

hash_manifest() {
  root=$1
  output=$2
  failure=$AUDIT_TEMP/hash-failed
  rm -f "$failure"
  : > "$output"
  (cd "$root" && find . -type f | sort) | while IFS= read -r file; do
    hash=$(sha256_file "$root/$file") || { : > "$failure"; exit; }
    printf '%s  %s\n' "$hash" "$file" >> "$output"
  done
  [ ! -f "$failure" ]
}

check_structure() {
  skill_file=$1
  STRUCTURE_NAME=
  if [ ! -f "$skill_file" ]; then STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-001 'SKILL.md is missing'); STRUCTURE_STATUS=FAIL; return; fi
  [ "$(sed -n '1p' "$skill_file")" = '---' ] || { STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-002 'frontmatter must start on the first line'); STRUCTURE_STATUS=FAIL; return; }
  closing=$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$skill_file")
  [ -n "$closing" ] && [ "$closing" -ge 3 ] || { STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-002 'frontmatter closing delimiter is missing'); STRUCTURE_STATUS=FAIL; return; }
  [ "$closing" -eq 4 ] || { STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-003 'frontmatter must contain only name and description'); STRUCTURE_STATUS=FAIL; return; }
  if ! STRUCTURE_NAME=$(sed -n '2,3p' "$skill_file" | awk '
    function scalar(value, first, last, inner, i, c) {
      if (value == "" || value ~ /^[[:space:]]/ || value ~ /[[:space:]]$/) return 0
      first = substr(value, 1, 1); last = substr(value, length(value), 1)
      if (first == "\"" || first == "\047") {
        if (length(value) < 2 || last != first) return 0
        inner = substr(value, 2, length(value) - 2)
        return index(inner, first) == 0 && index(inner, "\\") == 0
      }
      if (index(value, "\"") || index(value, "\047") || value ~ /:[[:space:]]/) return 0
      for (i = 1; i <= length(value); i++) {
        c = substr(value, i, 1)
        if (index("[]{}&*!|>@`#", c)) return 0
      }
      return 1
    }
    {
      if ($0 !~ /^(name|description): /) exit 1
      split_at = index($0, ": "); key = substr($0, 1, split_at - 1); value = substr($0, split_at + 2)
      if (seen[key]++ || !scalar(value)) exit 1
      if (substr(value, 1, 1) == "\"" || substr(value, 1, 1) == "\047") value = substr(value, 2, length(value) - 2)
      values[key] = value
    }
    END { if (seen["name"] != 1 || seen["description"] != 1) exit 1; print values["name"] }
  '); then STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-004 'frontmatter is outside the portable two-field subset'); STRUCTURE_STATUS=FAIL; return; fi
  case "$STRUCTURE_NAME" in
    ''|*[!a-z0-9-]*|-*|*-) STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-006 'skill name does not match the portable naming contract'); STRUCTURE_STATUS=FAIL; return ;;
    *--*) STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-006 'skill name does not match the portable naming contract'); STRUCTURE_STATUS=FAIL; return ;;
  esac
  [ "${#STRUCTURE_NAME}" -le 64 ] || { STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-006 'skill name exceeds 64 characters'); STRUCTURE_STATUS=FAIL; return; }
  STRUCTURE_JSON=$(layer_json PASS SRA-STRUCT-005 'frontmatter matches the portable two-field subset')
  STRUCTURE_STATUS=PASS
}

check_release() {
  skill_root=$1
  RELEASE_JSON=$(layer_json PASS SRA-RELEASE-001 'no deterministic release blocker was found')
  RELEASE_STATUS=PASS
  private_file=$(find "$skill_root" -type f -size -1025k -exec grep -El -- '-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----' {} + 2>/dev/null | sed -n '1p')
  if [ -n "$private_file" ]; then RELEASE_JSON=$(layer_json FAIL SRA-RELEASE-004 "private key material detected in $(basename "$private_file")"); RELEASE_STATUS=FAIL; return; fi
  placeholder_file=$(find "$skill_root" -type f -size -1025k \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.json' -o -name '*.txt' \) -exec grep -Eil -- '<owner>|<repo>|YOUR_GITHUB_USERNAME|TODO:[[:space:]]*replace' {} + 2>/dev/null | sed -n '1p')
  if [ -n "$placeholder_file" ]; then RELEASE_JSON=$(layer_json FAIL SRA-RELEASE-003 "unresolved release placeholder detected in $(basename "$placeholder_file")"); RELEASE_STATUS=FAIL; return; fi
}

check_direct_install() {
  skill_root=$1
  skill_name=$2
  destination=$AUDIT_TEMP/install/.agents/skills/$skill_name
  mkdir -p "$(dirname "$destination")"
  cp -R "$skill_root" "$destination" || { INSTALL_JSON=$(layer_json FAIL SRA-INSTALL-002 'direct install copy failed'); INSTALL_STATUS=FAIL; return; }
  [ -f "$destination/SKILL.md" ] || { INSTALL_JSON=$(layer_json FAIL SRA-INSTALL-002 'direct install did not create SKILL.md'); INSTALL_STATUS=FAIL; return; }
  source_manifest=$AUDIT_TEMP/source.sha256
  installed_manifest=$AUDIT_TEMP/installed.sha256
  hash_manifest "$skill_root" "$source_manifest" || { INSTALL_JSON=$(layer_json BLOCKED SRA-INSTALL-003 'SHA-256 tool is required for install comparison'); INSTALL_STATUS=BLOCKED; return; }
  hash_manifest "$destination" "$installed_manifest" || { INSTALL_JSON=$(layer_json BLOCKED SRA-INSTALL-003 'SHA-256 tool is required for install comparison'); INSTALL_STATUS=BLOCKED; return; }
  cmp -s "$source_manifest" "$installed_manifest" || { INSTALL_JSON=$(layer_json FAIL SRA-INSTALL-003 'direct install content differs from source'); INSTALL_STATUS=FAIL; return; }
  INSTALL_JSON=$(layer_json PASS SRA-INSTALL-001 'direct isolated install matches the checked source')
  INSTALL_STATUS=PASS
}

run_audit() {
  source_path=$1; scope=$2; installer=$3
  [ -d "$source_path" ] || { printf '%s\n' '{"schema_version":1,"overall":"ERROR","error":"only local source paths are implemented"}'; return 3; }
  AUDIT_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/skill-release-auditor-XXXXXX") || return 3
  trap cleanup EXIT HUP INT TERM
  check_structure "$source_path/SKILL.md"
  RELEASE_JSON=$(layer_json NOT_RUN SRA-RELEASE-000 'stopped after structure'); RELEASE_STATUS=NOT_RUN
  INSTALL_JSON=$(layer_json NOT_RUN SRA-INSTALL-000 'stopped after structure'); INSTALL_STATUS=NOT_RUN
  if [ "$STRUCTURE_STATUS" = PASS ]; then
    check_release "$source_path"
    if [ "$RELEASE_STATUS" = PASS ]; then
      if [ "$installer" = direct ]; then check_direct_install "$source_path" "$STRUCTURE_NAME"; else INSTALL_JSON=$(layer_json NOT_RUN SRA-INSTALL-000 'installer disabled by caller'); INSTALL_STATUS=NOT_RUN; fi
    fi
  fi
  DISCOVERY_JSON=$(layer_json NOT_RUN SRA-DISCOVERY-000 'requires observable Codex host evidence' codex)
  BEHAVIOR_JSON=$(layer_json NOT_RUN SRA-BEHAVIOR-000 'requires confirmed behavior samples' codex)
  selected="$STRUCTURE_STATUS $RELEASE_STATUS $INSTALL_STATUS"
  [ "$scope" = full ] && selected="$selected NOT_RUN NOT_RUN"
  case " $selected " in *' FAIL '*) code=1; overall=FAIL ;; *' BLOCKED '*|*' NOT_RUN '*) code=2; overall=INCOMPLETE ;; *) code=0; overall=PASS ;; esac
  cleanup
  if [ -d "$AUDIT_TEMP" ]; then cleanup_json=$(layer_json FAIL SRA-CLEANUP-001 "temporary directory remains: $AUDIT_TEMP"); [ "$code" -eq 0 ] && code=2 && overall=INCOMPLETE; else cleanup_json='{"status":"PASS","residual_path":null}'; fi
  AUDIT_TEMP=
  printf '{"schema_version":1,"target":{"source":"%s","skill":"%s","commit":null},"scope":"%s","overall":"%s","layers":{"remote":%s,"structure":%s,"release":%s,"install":%s,"discovery":%s,"behavior":%s},"cleanup":%s}\n' "$(json_escape "$source_path")" "$(json_escape "$STRUCTURE_NAME")" "$scope" "$overall" "$(layer_json NOT_RUN SRA-REMOTE-000 'local source path')" "$STRUCTURE_JSON" "$RELEASE_JSON" "$INSTALL_JSON" "$DISCOVERY_JSON" "$BEHAVIOR_JSON" "$cleanup_json"
  return "$code"
}

audit_fixture() {
  kind=$1
  fixture=$(mktemp -d "${TMPDIR:-/tmp}/skill-release-auditor-test.XXXXXX") || exit 3
  case "$kind" in
    valid) printf '%s\n' '---' 'name: sample-skill' 'description: Sample skill for tests.' '---' > "$fixture/SKILL.md" ;;
    duplicate-name) printf '%s\n' '---' 'name: sample-skill' 'name: other-skill' 'description: Sample skill for tests.' '---' > "$fixture/SKILL.md" ;;
    complex-yaml) printf '%s\n' '---' 'name: sample-skill' 'description: >' '  Multiline descriptions are outside the portable subset.' '---' > "$fixture/SKILL.md" ;;
  esac
  set +e; output=$(run_audit "$fixture" static direct); code=$?; set -e
  rm -rf "$fixture"
  structure=$(printf '%s\n' "$output" | sed -n 's/.*"structure":{"status":"\([A-Z_]*\)".*/\1/p')
  printf '%s|%s\n' "$code" "$structure"
}

self_test() {
  assert_equal missing-skill "$(audit_fixture missing-skill)" '1|FAIL'
  assert_equal native-frontmatter "$(audit_fixture valid)" '0|PASS'
  assert_equal duplicate-name "$(audit_fixture duplicate-name)" '1|FAIL'
  assert_equal complex-yaml "$(audit_fixture complex-yaml)" '1|FAIL'
  contract=$(mktemp -d "${TMPDIR:-/tmp}/skill-release-auditor-contract.XXXXXX") || exit 3
  skill_root=$contract/sample-skill
  mkdir -p "$skill_root"
  printf '%s\n' '---' 'name: sample-skill' 'description: Sample skill for tests.' '---' > "$skill_root/SKILL.md"
  AUDIT_TEMP=$contract
  check_release "$skill_root"; assert_equal release-pass "$RELEASE_STATUS" PASS
  check_direct_install "$skill_root" sample-skill; assert_equal direct-install "$INSTALL_STATUS" PASS
  printf '%s\n' 'Install from https://github.com/<owner>/<repo>.' > "$skill_root/notes.md"
  check_release "$skill_root"; assert_equal release-placeholder "$RELEASE_STATUS" FAIL
  rm -rf "$contract"; AUDIT_TEMP=
  auditor_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
  check_release "$auditor_root"; assert_equal auditor-release-scan "$RELEASE_STATUS" PASS
  printf '%s\n' '{"self_test":"PASS"}'
}

command=${1:-audit}
case "$command" in
  self-test) self_test; exit 0 ;;
  audit) shift ;;
  *) printf '%s\n' "unknown command: $command" >&2; exit 3 ;;
esac

source_path=; scope=full; installer=direct
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source) shift; [ "$#" -gt 0 ] || { printf '%s\n' '--source requires a value' >&2; exit 3; }; source_path=$1 ;;
    --scope) shift; [ "$#" -gt 0 ] || exit 3; scope=$1; [ "$scope" = static ] || [ "$scope" = full ] || exit 3 ;;
    --installer) shift; [ "$#" -gt 0 ] || exit 3; installer=$1; [ "$installer" = direct ] || [ "$installer" = none ] || exit 3 ;;
    *) printf '%s\n' "unknown argument: $1" >&2; exit 3 ;;
  esac
  shift
done
[ -n "$source_path" ] || { printf '%s\n' '--source is required' >&2; exit 3; }
run_audit "$source_path" "$scope" "$installer"
exit $?
