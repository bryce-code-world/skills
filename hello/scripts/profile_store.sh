#!/bin/sh

set -u

COMMAND=${1-}
[ -n "$COMMAND" ] || { printf '%s\n' '{"ok":false,"command":"","error":"Command is required."}'; exit 2; }
shift

ROOT_ARG=
INPUT=
SUMMARY_INPUT=
EXPECTED_VERSION=
KIND=
SOURCE=
CANDIDATE_ID=
CAPTURE_MODE=
NEXT_REVIEW_AT=
REVIEW_STAGE=
CONFIRMED=false

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s//\\r/g; s/	/\\t/g'
}

fail() {
  printf '{"ok":false,"command":"%s","error":"%s"}\n' "$(json_escape "$COMMAND")" "$(json_escape "$1")"
  exit 2
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --confirmed) CONFIRMED=true; shift ;;
    --root|--input|--summary-input|--expected-version|--kind|--source|--id|--capture-mode|--next-review-at|--review-stage)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      case $1 in
        --root) ROOT_ARG=$2 ;;
        --input) INPUT=$2 ;;
        --summary-input) SUMMARY_INPUT=$2 ;;
        --expected-version) EXPECTED_VERSION=$2 ;;
        --kind) KIND=$2 ;;
        --source) SOURCE=$2 ;;
        --id) CANDIDATE_ID=$2 ;;
        --capture-mode) CAPTURE_MODE=$2 ;;
        --next-review-at) NEXT_REVIEW_AT=$2 ;;
        --review-stage) REVIEW_STAGE=$2 ;;
      esac
      shift 2 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

case $COMMAND in
  resolve-root|init|validate|status|configure|diff|stage|apply|withdraw|self-test) ;;
  *) fail "Unknown command: $COMMAND" ;;
esac

utc_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
file_stamp() { date -u '+%Y%m%dT%H%M%SZ'; }

resolve_root() {
  raw=$ROOT_ARG
  [ -n "$raw" ] || raw=${HELLO_HOME-}
  [ -n "$raw" ] || fail 'Personal profile root is not configured. Pass --root or set HELLO_HOME.'
  case $raw in
    /*) ROOT=$raw ;;
    *) ROOT=$(pwd)/$raw ;;
  esac
}

require_confirmed() {
  [ "$CONFIRMED" = true ] || fail 'Mutating commands require --confirmed after user authorization.'
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || fail 'Cannot resolve script directory.'
TEMPLATE_DIR=$SCRIPT_DIR/../assets/profile-templates

state_value() {
  awk -F= -v wanted="$2" '$1 == wanted { sub(/^[^=]*=/, ""); print; found=1; exit } END { if (!found) exit 1 }' "$1"
}

write_state() {
  state_path=$1
  state_schema=$2
  state_version=$3
  state_capture=$4
  state_created=$5
  state_updated=$6
  state_confirmed=$7
  state_review=$8
  state_stage=$9
  state_temp=$state_path.tmp.$$
  umask 077
  {
    printf 'schema_version=%s\n' "$state_schema"
    printf 'profile_version=%s\n' "$state_version"
    printf 'capture_mode=%s\n' "$state_capture"
    printf 'created_at=%s\n' "$state_created"
    printf 'updated_at=%s\n' "$state_updated"
    printf 'last_confirmed_at=%s\n' "$state_confirmed"
    printf 'next_review_at=%s\n' "$state_review"
    printf 'review_stage=%s\n' "$state_stage"
  } > "$state_temp" || fail "Cannot write state file: $state_path"
  mv -f "$state_temp" "$state_path" || fail "Cannot replace state file: $state_path"
}

read_state() {
  state_path=$ROOT/.hello-state
  STATE_SCHEMA=$(state_value "$state_path" schema_version) || return 1
  STATE_VERSION=$(state_value "$state_path" profile_version) || return 1
  STATE_CAPTURE=$(state_value "$state_path" capture_mode) || return 1
  STATE_CREATED=$(state_value "$state_path" created_at) || return 1
  STATE_UPDATED=$(state_value "$state_path" updated_at) || return 1
  STATE_CONFIRMED=$(state_value "$state_path" last_confirmed_at) || return 1
  STATE_REVIEW=$(state_value "$state_path" next_review_at) || STATE_REVIEW=
  STATE_STAGE=$(state_value "$state_path" review_stage) || return 1
  return 0
}

validate_space() {
  VALIDATION_ISSUES=
  [ -d "$ROOT" ] || VALIDATION_ISSUES='Root directory does not exist'
  if [ -d "$ROOT" ]; then
    for name in README.md 个人全景档案.md 待确认信息.md 访谈进度.md 资料索引.md 迭代日志.md; do
      [ -f "$ROOT/$name" ] || VALIDATION_ISSUES="$VALIDATION_ISSUES; Missing file: $name"
    done
    for name in 原始访谈 历史版本 .backups .trash; do
      [ -d "$ROOT/$name" ] || VALIDATION_ISSUES="$VALIDATION_ISSUES; Missing directory: $name"
    done
    if [ ! -f "$ROOT/.hello-state" ]; then
      VALIDATION_ISSUES="$VALIDATION_ISSUES; Missing file: .hello-state"
    elif ! read_state; then
      VALIDATION_ISSUES="$VALIDATION_ISSUES; Invalid state file"
    else
      [ "$STATE_SCHEMA" = 1 ] || VALIDATION_ISSUES="$VALIDATION_ISSUES; schema_version must be 1"
      case $STATE_VERSION in ''|*[!0-9]*|0) VALIDATION_ISSUES="$VALIDATION_ISSUES; profile_version must be a positive integer" ;; esac
      case $STATE_CAPTURE in auto-stage|prompt|explicit) ;; *) VALIDATION_ISSUES="$VALIDATION_ISSUES; invalid capture_mode" ;; esac
      case $STATE_STAGE in baseline|first-review|stable) ;; *) VALIDATION_ISSUES="$VALIDATION_ISSUES; invalid review_stage" ;; esac
    fi
  fi
  VALIDATION_ISSUES=$(printf '%s' "$VALIDATION_ISSUES" | sed 's/^; //')
  [ -z "$VALIDATION_ISSUES" ]
}

require_valid() {
  validate_space || fail "Invalid profile space: $VALIDATION_ISSUES"
}

init_space() {
  require_confirmed
  mkdir -p "$ROOT" || fail "Cannot create root: $ROOT"
  created_json=
  add_created() {
    created_item=$(json_escape "$1")
    if [ -n "$created_json" ]; then created_json=$created_json,; fi
    created_json=$created_json\"$created_item\"
  }
  for name in 原始访谈 历史版本 .backups .trash; do
    if [ ! -d "$ROOT/$name" ]; then
      mkdir -p "$ROOT/$name" || fail "Cannot create directory: $name"
      add_created "$name/"
    fi
  done
  for name in README.md 个人全景档案.md 待确认信息.md 访谈进度.md 资料索引.md 迭代日志.md; do
    if [ ! -f "$ROOT/$name" ]; then
      cp "$TEMPLATE_DIR/$name" "$ROOT/$name" || fail "Cannot create file: $name"
      add_created "$name"
    fi
  done
  if [ ! -f "$ROOT/.hello-state" ]; then
    current=$(utc_now)
    write_state "$ROOT/.hello-state" 1 1 auto-stage "$current" "$current" '' '' baseline
    add_created .hello-state
  fi
  printf '{"ok":true,"command":"init","root":"%s","created":[%s]}\n' "$(json_escape "$ROOT")" "$created_json"
}

status_space() {
  if ! validate_space; then
    printf '{"ok":false,"command":"status","root":"%s","issues":["%s"]}\n' "$(json_escape "$ROOT")" "$(json_escape "$VALIDATION_ISSUES")"
    exit 1
  fi
  pending=$(grep -c '^## C-[0-9TZ-][0-9TZ-]*[[:space:]]*$' "$ROOT/待确认信息.md" 2>/dev/null || true)
  printf '{"ok":true,"command":"status","root":"%s","profile_version":%s,"capture_mode":"%s","review_stage":"%s","last_confirmed_at":"%s","next_review_at":"%s","pending_candidates":%s}\n' \
    "$(json_escape "$ROOT")" "$STATE_VERSION" "$(json_escape "$STATE_CAPTURE")" "$(json_escape "$STATE_STAGE")" \
    "$(json_escape "$STATE_CONFIRMED")" "$(json_escape "$STATE_REVIEW")" "$pending"
}

configure_space() {
  require_confirmed
  require_valid
  [ -n "$CAPTURE_MODE$NEXT_REVIEW_AT$REVIEW_STAGE" ] || fail 'configure requires at least one setting.'
  new_capture=$STATE_CAPTURE
  new_review=$STATE_REVIEW
  new_stage=$STATE_STAGE
  if [ -n "$CAPTURE_MODE" ]; then
    case $CAPTURE_MODE in auto-stage|prompt|explicit) new_capture=$CAPTURE_MODE ;; *) fail '--capture-mode must be auto-stage, prompt, or explicit.' ;; esac
  fi
  if [ -n "$REVIEW_STAGE" ]; then
    case $REVIEW_STAGE in baseline|first-review|stable) new_stage=$REVIEW_STAGE ;; *) fail '--review-stage must be baseline, first-review, or stable.' ;; esac
  fi
  if [ -n "$NEXT_REVIEW_AT" ]; then
    if [ "$NEXT_REVIEW_AT" = none ]; then
      new_review=
    else
      printf '%s\n' "$NEXT_REVIEW_AT" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$' || fail '--next-review-at must be ISO 8601 or none.'
      new_review=$NEXT_REVIEW_AT
    fi
  fi
  current=$(utc_now)
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$new_capture" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$new_review" "$new_stage"
  printf '{"ok":true,"command":"configure","root":"%s","capture_mode":"%s","review_stage":"%s","next_review_at":"%s"}\n' \
    "$(json_escape "$ROOT")" "$new_capture" "$new_stage" "$(json_escape "$new_review")"
}

clean_label() {
  value=$1
  fallback=$2
  [ -n "$value" ] || value=$fallback
  printf '%s' "$value" | tr '\r\n\t' '   ' | cut -c 1-200
}

stage_candidate() {
  require_confirmed
  require_valid
  [ -n "$INPUT" ] || fail 'stage requires --input.'
  [ -f "$INPUT" ] || fail "Candidate input does not exist: $INPUT"
  [ -s "$INPUT" ] || fail 'Candidate input is empty.'
  current=$(utc_now)
  candidate_id=C-$(file_stamp)-$$
  pending=$ROOT/待确认信息.md
  temp=$ROOT/.pending.$$.tmp
  sed '/^当前没有待确认信息。$/d' "$pending" > "$temp" || fail 'Cannot prepare pending file.'
  {
    printf '\n## %s\n\n' "$candidate_id"
    printf -- '- 暂存时间：%s\n' "$current"
    printf -- '- 类型：%s\n' "$(clean_label "$KIND" 未分类)"
    printf -- '- 来源：%s\n' "$(clean_label "$SOURCE" 当前会话)"
    printf -- '- 状态：待确认\n\n'
    cat "$INPUT"
    printf '\n'
  } >> "$temp" || fail 'Cannot append candidate.'
  mv -f "$temp" "$pending" || fail 'Cannot replace pending file.'
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$STATE_REVIEW" "$STATE_STAGE"
  printf '{"ok":true,"command":"stage","root":"%s","candidate_id":"%s"}\n' "$(json_escape "$ROOT")" "$candidate_id"
}

unique_target() {
  unique_dir=$1
  unique_name=$2
  UNIQUE_TARGET=$unique_dir/$unique_name
  unique_count=1
  unique_stem=${unique_name%.*}
  unique_ext=.${unique_name##*.}
  while [ -e "$UNIQUE_TARGET" ]; do
    UNIQUE_TARGET=$unique_dir/$unique_stem-$unique_count$unique_ext
    unique_count=$((unique_count + 1))
  done
}

apply_profile() {
  require_confirmed
  require_valid
  [ -n "$INPUT" ] || fail 'apply requires --input.'
  [ -n "$SUMMARY_INPUT" ] || fail 'apply requires --summary-input.'
  [ -n "$EXPECTED_VERSION" ] || fail 'apply requires --expected-version.'
  case $EXPECTED_VERSION in ''|*[!0-9]*) fail '--expected-version must be an integer.' ;; esac
  [ "$EXPECTED_VERSION" = "$STATE_VERSION" ] || fail "Version conflict: expected $EXPECTED_VERSION, current $STATE_VERSION."
  [ -s "$INPUT" ] || fail 'Candidate profile is empty.'
  [ -s "$SUMMARY_INPUT" ] || fail 'Update summary is empty.'
  grep -q '^- 资料版本：' "$INPUT" || fail 'Candidate profile must contain 资料版本 metadata.'
  grep -q '^- 最近确认时间：' "$INPUT" || fail 'Candidate profile must contain 最近确认时间 metadata.'
  current=$(utc_now)
  new_version=$((STATE_VERSION + 1))
  profile=$ROOT/个人全景档案.md
  name=$(file_stamp)-v$STATE_VERSION-个人全景档案.md
  mkdir -p "$ROOT/历史版本" "$ROOT/.backups/profile" || fail 'Cannot create backup directories.'
  unique_target "$ROOT/历史版本" "$name"; history=$UNIQUE_TARGET
  cp "$profile" "$history" || fail 'Cannot create history snapshot.'
  unique_target "$ROOT/.backups/profile" "$name"; backup=$UNIQUE_TARGET
  cp "$profile" "$backup" || fail 'Cannot create backup.'
  temp=$ROOT/.profile.$$.tmp
  sed -e "s/^- 资料版本：.*$/- 资料版本：$new_version/" -e "s/^- 最近确认时间：.*$/- 最近确认时间：$current/" "$INPUT" > "$temp" || fail 'Cannot prepare profile update.'
  mv -f "$temp" "$profile" || fail 'Cannot replace profile.'
  log=$ROOT/迭代日志.md
  log_temp=$ROOT/.log.$$.tmp
  sed '/^当前没有正式迭代。$/d' "$log" > "$log_temp" || fail 'Cannot prepare log.'
  {
    printf '\n## R%s · %s\n\n' "$new_version" "$current"
    printf -- '- 资料版本：%s\n' "$new_version"
    printf -- '- 确认状态：用户已确认\n'
    printf -- '- 历史快照：`历史版本/%s`\n\n' "$(basename "$history")"
    cat "$SUMMARY_INPUT"
    printf '\n'
  } >> "$log_temp" || fail 'Cannot append log.'
  mv -f "$log_temp" "$log" || fail 'Cannot replace log.'
  next_stage=$STATE_STAGE
  [ "$next_stage" = baseline ] && next_stage=first-review
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$new_version" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$current" "$STATE_REVIEW" "$next_stage"
  printf '{"ok":true,"command":"apply","root":"%s","old_version":%s,"profile_version":%s,"history":"%s","backup":"%s"}\n' \
    "$(json_escape "$ROOT")" "$STATE_VERSION" "$new_version" "$(json_escape "$history")" "$(json_escape "$backup")"
}

withdraw_candidate() {
  require_confirmed
  require_valid
  [ -n "$CANDIDATE_ID" ] || fail 'withdraw requires --id.'
  printf '%s\n' "$CANDIDATE_ID" | grep -Eq '^C-[0-9TZ-]+$' || fail 'Invalid candidate id.'
  pending=$ROOT/待确认信息.md
  temp=$ROOT/.withdraw.$$.tmp
  trash_dir=$ROOT/.trash/candidates
  mkdir -p "$trash_dir" || fail 'Cannot create candidate trash.'
  trash=$trash_dir/$CANDIDATE_ID.md
  [ ! -e "$trash" ] || trash=$trash_dir/$CANDIDATE_ID-$(file_stamp).md
  awk -v target="## $CANDIDATE_ID" -v trash="$trash" '
    BEGIN { inside=0; found=0 }
    $0 == target { inside=1; found=1 }
    inside && $0 != target && /^## C-[0-9TZ-]+[[:space:]]*$/ { inside=0 }
    { if (inside) print > trash; else print }
    END { if (!found) exit 3 }
  ' "$pending" > "$temp"
  code=$?
  [ "$code" -eq 0 ] || { rm -f "$temp" "$trash"; fail "Candidate not found: $CANDIDATE_ID"; }
  if ! grep -q '^## C-[0-9TZ-][0-9TZ-]*[[:space:]]*$' "$temp"; then
    printf '\n当前没有待确认信息。\n' >> "$temp"
  fi
  mv -f "$temp" "$pending" || fail 'Cannot replace pending file.'
  current=$(utc_now)
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$STATE_REVIEW" "$STATE_STAGE"
  printf '{"ok":true,"command":"withdraw","root":"%s","candidate_id":"%s","trash":"%s"}\n' \
    "$(json_escape "$ROOT")" "$CANDIDATE_ID" "$(json_escape "$trash")"
}

self_test() {
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/hello-self-test.XXXXXX") || fail 'Cannot create self-test directory.'
  trap 'rm -rf "$temporary"' EXIT HUP INT TERM
  root=$temporary/中文\ 空格
  candidate=$temporary/candidate.md
  profile=$temporary/profile.md
  summary=$temporary/summary.md
  printf '用户完成了一个重要项目。\n' > "$candidate"
  if sh "$0" init --root "$root" >/dev/null 2>&1; then fail 'Confirmation guard did not fail.'; fi
  sh "$0" init --root "$root" --confirmed >/dev/null || fail 'Self-test init failed.'
  second_init=$(sh "$0" init --root "$root" --confirmed) || fail 'Self-test second init failed.'
  printf '%s' "$second_init" | grep -q '"created":\[\]' || fail 'Self-test init overwrote existing space.'
  sh "$0" validate --root "$root" >/dev/null || fail 'Self-test validate failed.'
  staged=$(sh "$0" stage --root "$root" --input "$candidate" --kind 经历 --source 自测 --confirmed) || fail 'Self-test stage failed.'
  staged_id=$(printf '%s' "$staged" | sed -n 's/.*"candidate_id":"\([^"]*\)".*/\1/p')
  [ -n "$staged_id" ] || fail 'Self-test could not read candidate id.'
  sh "$0" configure --root "$root" --capture-mode prompt --next-review-at 2030-01-01T00:00:00Z --confirmed >/dev/null || fail 'Self-test configure failed.'
  cp "$root/个人全景档案.md" "$profile"
  printf '%s\n' '- 自测更新。' > "$summary"
  sh "$0" apply --root "$root" --input "$profile" --summary-input "$summary" --expected-version 1 --confirmed >/dev/null || fail 'Self-test apply failed.'
  if sh "$0" apply --root "$root" --input "$profile" --summary-input "$summary" --expected-version 1 --confirmed >/dev/null 2>&1; then
    fail 'Version conflict did not fail.'
  fi
  sh "$0" withdraw --root "$root" --id "$staged_id" --confirmed >/dev/null || fail 'Self-test withdraw failed.'
  sh "$0" validate --root "$root" >/dev/null || fail 'Self-test final validation failed.'
  rm -rf "$temporary"
  trap - EXIT HUP INT TERM
  printf '%s\n' '{"ok":true,"command":"self-test"}'
}

if [ "$COMMAND" = self-test ]; then
  self_test
  exit 0
fi

resolve_root

case $COMMAND in
  resolve-root)
    printf '{"ok":true,"command":"resolve-root","root":"%s"}\n' "$(json_escape "$ROOT")" ;;
  init) init_space ;;
  validate)
    if validate_space; then
      printf '{"ok":true,"command":"validate","root":"%s","issues":[]}\n' "$(json_escape "$ROOT")"
    else
      printf '{"ok":false,"command":"validate","root":"%s","issues":["%s"]}\n' "$(json_escape "$ROOT")" "$(json_escape "$VALIDATION_ISSUES")"
      exit 1
    fi ;;
  status) status_space ;;
  configure) configure_space ;;
  diff)
    require_valid
    [ -n "$INPUT" ] || fail 'diff requires --input.'
    [ -f "$INPUT" ] || fail "Candidate profile does not exist: $INPUT"
    if cmp -s "$ROOT/个人全景档案.md" "$INPUT"; then printf '%s\n' 'No changes.'; else diff -u "$ROOT/个人全景档案.md" "$INPUT" || [ "$?" -eq 1 ]; fi ;;
  stage) stage_candidate ;;
  apply) apply_profile ;;
  withdraw) withdraw_candidate ;;
esac
