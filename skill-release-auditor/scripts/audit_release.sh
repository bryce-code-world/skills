#!/bin/sh

set -u

YQ_VERSION=v4.53.3
AUDIT_TEMP=
YQ_PATH=
TOOL_JSON=

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

test_yq() {
  parser=$1
  parser_dir=$2
  printf '%s\n' 'name: sample-skill' 'description: sample' > "$parser_dir/parser-valid.yaml"
  printf '%s\n' 'name: [broken' > "$parser_dir/parser-invalid.yaml"
  "$parser" eval -e '.name == "sample-skill" and (.description | type == "!!str")' "$parser_dir/parser-valid.yaml" >/dev/null 2>&1 || return 1
  "$parser" eval '.' "$parser_dir/parser-invalid.yaml" >/dev/null 2>&1 && return 1
  return 0
}

install_temp_yq() {
  tool_dir=$1
  os=$(uname -s)
  arch=$(uname -m)
  suffix=
  case "$os:$arch" in
    Darwin:x86_64) asset=yq_darwin_amd64; expected=b4ba1ecce3c47f00803f4f964de38394326c7a32eb6540616e04fb2935a0f08d ;;
    Darwin:arm64|Darwin:aarch64) asset=yq_darwin_arm64; expected=877de31753a4dd2401aa048937aa9a7fc4d5f6ce858cf31508c5802954297213 ;;
    MINGW*:x86_64) asset=yq_windows_amd64.exe; expected=e279bc506a452eeafcdf364f91a025455e402a8001169083caf01f4b64a544e2; suffix=.exe ;;
    MINGW*:arm64|MINGW*:aarch64) asset=yq_windows_arm64.exe; expected=c80ac96ff2a8d77d452d91304e11feef8fb23239900b3d1d88f47c2ec93be970; suffix=.exe ;;
    *) YQ_ERROR="temporary yq is unsupported on $os/$arch"; return 1 ;;
  esac
  command -v curl >/dev/null 2>&1 || { YQ_ERROR='curl is required to acquire temporary yq'; return 1; }
  command -v shasum >/dev/null 2>&1 || command -v certutil.exe >/dev/null 2>&1 || { YQ_ERROR='SHA-256 tool is unavailable'; return 1; }
  url="https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/$asset"
  YQ_PATH=$tool_dir/yq$suffix
  curl -fL --connect-timeout 15 --max-time 90 -o "$YQ_PATH" "$url" >/dev/null 2>&1 || { YQ_ERROR='temporary yq download failed'; return 1; }
  actual=$(sha256_file "$YQ_PATH") || { YQ_ERROR='temporary yq hash could not be calculated'; return 1; }
  if [ "$actual" != "$expected" ]; then
    rm -f "$YQ_PATH"
    YQ_ERROR="temporary yq SHA-256 mismatch for $asset"
    return 1
  fi
  chmod 700 "$YQ_PATH" 2>/dev/null || true
  test_yq "$YQ_PATH" "$tool_dir" || { YQ_ERROR='temporary yq failed self-test'; return 1; }
  TOOL_JSON=$(printf '{"name":"yq","version":"%s","source":"%s","sha256":"%s","hash_verified":true,"temporary":true}' "$YQ_VERSION" "$url" "$expected")
  return 0
}

check_structure() {
  skill_file=$1
  allow_temp=$2
  STRUCTURE_AUTH=false
  STRUCTURE_NAME=
  TOOL_JSON=
  if [ ! -f "$skill_file" ]; then STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-001 'SKILL.md is missing'); STRUCTURE_STATUS=FAIL; return; fi
  [ "$(sed -n '1p' "$skill_file")" = '---' ] || { STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-002 'frontmatter must start on the first line'); STRUCTURE_STATUS=FAIL; return; }
  closing=$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$skill_file")
  [ -n "$closing" ] && [ "$closing" -ge 3 ] || { STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-002 'frontmatter closing delimiter is missing'); STRUCTURE_STATUS=FAIL; return; }
  yaml_dir=$AUDIT_TEMP/yaml
  mkdir -p "$yaml_dir"
  sed -n "2,$((closing - 1))p" "$skill_file" > "$yaml_dir/frontmatter.yaml"
  name_count=$(grep -c '^name[[:space:]]*:' "$yaml_dir/frontmatter.yaml")
  description_count=$(grep -c '^description[[:space:]]*:' "$yaml_dir/frontmatter.yaml")
  if [ "$name_count" -ne 1 ] || [ "$description_count" -ne 1 ]; then STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-003 'frontmatter must contain exactly one name and one description'); STRUCTURE_STATUS=FAIL; return; fi
  if command -v yq >/dev/null 2>&1 && test_yq "$(command -v yq)" "$yaml_dir"; then
    YQ_PATH=$(command -v yq)
  elif [ "$allow_temp" = true ]; then
    install_temp_yq "$yaml_dir" || { STRUCTURE_JSON=$(layer_json BLOCKED SRA-STRUCT-004 "$YQ_ERROR"); STRUCTURE_STATUS=BLOCKED; return; }
  else
    STRUCTURE_JSON=$(layer_json BLOCKED SRA-STRUCT-004 'strict YAML parser is unavailable or failed self-test')
    STRUCTURE_STATUS=BLOCKED
    STRUCTURE_AUTH=true
    return
  fi
  if ! "$YQ_PATH" eval -e 'type == "!!map" and (.name | type == "!!str") and (.description | type == "!!str")' "$yaml_dir/frontmatter.yaml" >/dev/null 2>&1; then STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-005 'frontmatter is not valid strict YAML metadata'); STRUCTURE_STATUS=FAIL; return; fi
  STRUCTURE_NAME=$("$YQ_PATH" eval -r '.name' "$yaml_dir/frontmatter.yaml")
  case "$STRUCTURE_NAME" in
    ''|*[!a-z0-9-]*|-*|*-) STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-006 'skill name does not match the portable naming contract'); STRUCTURE_STATUS=FAIL; return ;;
    *--*) STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-006 'skill name does not match the portable naming contract'); STRUCTURE_STATUS=FAIL; return ;;
  esac
  [ "${#STRUCTURE_NAME}" -le 64 ] || { STRUCTURE_JSON=$(layer_json FAIL SRA-STRUCT-006 'skill name exceeds 64 characters'); STRUCTURE_STATUS=FAIL; return; }
  STRUCTURE_JSON=$(layer_json PASS SRA-STRUCT-005 'frontmatter passed strict YAML validation')
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
  source_path=$1; allow_temp=$2; scope=$3; installer=$4
  [ -d "$source_path" ] || { printf '%s\n' '{"schema_version":1,"overall":"ERROR","error":"only local source paths are implemented"}'; return 3; }
  AUDIT_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/skill-release-auditor-XXXXXX") || return 3
  trap cleanup EXIT HUP INT TERM
  check_structure "$source_path/SKILL.md" "$allow_temp"
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
  tools="[]"; [ -n "$TOOL_JSON" ] && tools="[$TOOL_JSON]"
  cleanup
  if [ -d "$AUDIT_TEMP" ]; then cleanup_json=$(layer_json FAIL SRA-CLEANUP-001 "temporary directory remains: $AUDIT_TEMP"); [ "$code" -eq 0 ] && code=2 && overall=INCOMPLETE; else cleanup_json='{"status":"PASS","residual_path":null}'; fi
  AUDIT_TEMP=
  printf '{"schema_version":1,"target":{"source":"%s","skill":"%s","commit":null},"scope":"%s","overall":"%s","authorization_required":%s,"layers":{"remote":%s,"structure":%s,"release":%s,"install":%s,"discovery":%s,"behavior":%s},"tools":%s,"cleanup":%s}\n' "$(json_escape "$source_path")" "$(json_escape "$STRUCTURE_NAME")" "$scope" "$overall" "$STRUCTURE_AUTH" "$(layer_json NOT_RUN SRA-REMOTE-000 'local source path')" "$STRUCTURE_JSON" "$RELEASE_JSON" "$INSTALL_JSON" "$DISCOVERY_JSON" "$BEHAVIOR_JSON" "$tools" "$cleanup_json"
  return "$code"
}

audit_fixture() {
  kind=$1
  fixture=$(mktemp -d "${TMPDIR:-/tmp}/skill-release-auditor-test.XXXXXX") || exit 3
  case "$kind" in
    valid) printf '%s\n' '---' 'name: sample-skill' 'description: Sample skill for tests.' '---' > "$fixture/SKILL.md" ;;
    duplicate-name) printf '%s\n' '---' 'name: sample-skill' 'name: other-skill' 'description: Sample skill for tests.' '---' > "$fixture/SKILL.md" ;;
  esac
  set +e; output=$(run_audit "$fixture" false full direct); code=$?; set -e
  rm -rf "$fixture"
  structure=$(printf '%s\n' "$output" | sed -n 's/.*"structure":{"status":"\([A-Z_]*\)".*/\1/p')
  authorization=$(printf '%s\n' "$output" | sed -n 's/.*"authorization_required":\(true\|false\).*/\1/p')
  [ "$kind" = missing-skill ] && printf '%s|%s\n' "$code" "$structure" || printf '%s|%s|%s\n' "$code" "$structure" "$authorization"
}

self_test() {
  assert_equal missing-skill "$(audit_fixture missing-skill)" '1|FAIL'
  assert_equal missing-yq "$(audit_fixture valid)" '2|BLOCKED|true'
  assert_equal duplicate-name "$(audit_fixture duplicate-name)" '1|FAIL|false'
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

integration_test() {
  fixture=$(mktemp -d "${TMPDIR:-/tmp}/skill-release-auditor-integration.XXXXXX") || exit 3
  printf '%s\n' '---' 'name: sample-skill' 'description: Sample skill for tests.' '---' > "$fixture/SKILL.md"
  set +e; output=$(run_audit "$fixture" true static direct); code=$?; set -e
  rm -rf "$fixture"
  assert_equal integration-exit "$code" 0
  printf '%s\n' '{"integration_test":"PASS"}'
}

command=${1:-audit}
case "$command" in
  self-test) self_test; exit 0 ;;
  integration-test) integration_test; exit 0 ;;
  audit) shift ;;
  *) printf '%s\n' "unknown command: $command" >&2; exit 3 ;;
esac

source_path=; allow_temp=false; scope=full; installer=direct
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source) shift; [ "$#" -gt 0 ] || { printf '%s\n' '--source requires a value' >&2; exit 3; }; source_path=$1 ;;
    --allow-temp-yaml-parser) allow_temp=true ;;
    --scope) shift; [ "$#" -gt 0 ] || exit 3; scope=$1; [ "$scope" = static ] || [ "$scope" = full ] || exit 3 ;;
    --installer) shift; [ "$#" -gt 0 ] || exit 3; installer=$1; [ "$installer" = direct ] || [ "$installer" = none ] || exit 3 ;;
    *) printf '%s\n' "unknown argument: $1" >&2; exit 3 ;;
  esac
  shift
done
[ -n "$source_path" ] || { printf '%s\n' '--source is required' >&2; exit 3; }
run_audit "$source_path" "$allow_temp" "$scope" "$installer"
exit $?
