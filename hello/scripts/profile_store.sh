#!/bin/sh

set -u
umask 077

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
SESSION_ID=
TURN_ID=
PROGRESS_INPUT=
EXPECTED_PROGRESS_VERSION=
CONFIRMED=false
SIMULATE_FAILURE=false

json_escape_legacy() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s//\\r/g; s/	/\\t/g'
}

json_escape() {
  printf '%s' "$1" | awk 'BEGIN { first=1 } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\r/, "\\r"); gsub(/\t/, "\\t"); if (!first) printf "\\n"; printf "%s", $0; first=0 }'
}

fail() {
  printf '{"ok":false,"command":"%s","error":"%s"}\n' "$(json_escape "$COMMAND")" "$(json_escape "$1")"
  exit 2
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --confirmed) CONFIRMED=true; shift ;;
    --simulate-failure) SIMULATE_FAILURE=true; shift ;;
    --root|--input|--summary-input|--expected-version|--kind|--source|--id|--capture-mode|--next-review-at|--review-stage|--session-id|--turn-id|--progress-input|--expected-progress-version)
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
        --session-id) SESSION_ID=$2 ;;
        --turn-id) TURN_ID=$2 ;;
        --progress-input) PROGRESS_INPUT=$2 ;;
        --expected-progress-version) EXPECTED_PROGRESS_VERSION=$2 ;;
      esac
      shift 2 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

case $COMMAND in
  resolve-root|init|validate|status|configure|diff|stage|apply|withdraw|record-turn|recover|self-test) ;;
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
  shift 9
  state_progress=${1-1}
  state_session=${2-}
  state_turn=${3-}
  state_temp=$state_path.tmp.$$
  {
    printf 'schema_version=%s\n' "$state_schema"
    printf 'profile_version=%s\n' "$state_version"
    printf 'capture_mode=%s\n' "$state_capture"
    printf 'created_at=%s\n' "$state_created"
    printf 'updated_at=%s\n' "$state_updated"
    printf 'last_confirmed_at=%s\n' "$state_confirmed"
    printf 'next_review_at=%s\n' "$state_review"
    printf 'review_stage=%s\n' "$state_stage"
    printf 'progress_version=%s\n' "$state_progress"
    printf 'last_session_id=%s\n' "$state_session"
    printf 'last_turn_id=%s\n' "$state_turn"
    if [ -f "$state_path" ]; then
      awk -F= '!/^(schema_version|profile_version|capture_mode|created_at|updated_at|last_confirmed_at|next_review_at|review_stage|progress_version|last_session_id|last_turn_id)=/' "$state_path"
    fi
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
  STATE_PROGRESS_PRESENT=true; STATE_PROGRESS=$(state_value "$state_path" progress_version) || { STATE_PROGRESS_PRESENT=false; STATE_PROGRESS=1; }
  STATE_SESSION_PRESENT=true; STATE_SESSION=$(state_value "$state_path" last_session_id) || { STATE_SESSION_PRESENT=false; STATE_SESSION=; }
  STATE_TURN_PRESENT=true; STATE_TURN=$(state_value "$state_path" last_turn_id) || { STATE_TURN_PRESENT=false; STATE_TURN=; }
  return 0
}

validate_space() {
  allow_transaction=${1-false}
  VALIDATION_ISSUES=
  add_issue() { VALIDATION_ISSUES="$VALIDATION_ISSUES; $1"; }
  [ -d "$ROOT" ] || VALIDATION_ISSUES='Root directory does not exist'
  if [ -d "$ROOT" ]; then
    for name in README.md 个人全景档案.md 待确认信息.md 访谈进度.md 资料索引.md 迭代日志.md; do
      [ -f "$ROOT/$name" ] || add_issue "Missing file: $name"
    done
    for name in 原始访谈 历史版本 .backups .trash; do
      [ -d "$ROOT/$name" ] || add_issue "Missing directory: $name"
    done
    [ "$allow_transaction" = true ] || [ ! -e "$ROOT/.hello-transaction" ] || add_issue 'Unfinished transaction; run recover.'
    if [ ! -f "$ROOT/.hello-state" ]; then
      add_issue 'Missing file: .hello-state'
    elif ! read_state; then
      add_issue 'Invalid state file'
    else
      case $STATE_SCHEMA in 1|2) ;; *) add_issue 'schema_version must be 1 or 2' ;; esac
      if [ "$STATE_SCHEMA" = 2 ]; then
        [ "$STATE_PROGRESS_PRESENT" = true ] || add_issue 'Missing state key: progress_version'
        [ "$STATE_SESSION_PRESENT" = true ] || add_issue 'Missing state key: last_session_id'
        [ "$STATE_TURN_PRESENT" = true ] || add_issue 'Missing state key: last_turn_id'
      fi
      case $STATE_VERSION in ''|*[!0-9]*|0) add_issue 'profile_version must be a positive integer' ;; esac
      case $STATE_PROGRESS in ''|*[!0-9]*|0) add_issue 'progress_version must be a positive integer' ;; esac
      case $STATE_CAPTURE in auto-stage|prompt|explicit) ;; *) add_issue 'invalid capture_mode' ;; esac
      case $STATE_STAGE in baseline|first-review|stable) ;; *) add_issue 'invalid review_stage' ;; esac
      [ "$STATE_STAGE" != first-review ] || [ -n "$STATE_REVIEW" ] || add_issue 'first-review requires next_review_at'
      profile=$ROOT/个人全景档案.md
      progress=$ROOT/访谈进度.md
      pending=$ROOT/待确认信息.md
      log=$ROOT/迭代日志.md
      if [ -f "$profile" ]; then
        [ "$(tr -d '\r' < "$profile" | sed -n '1p')" = '# 个人全景档案' ] || add_issue 'Profile must start with # 个人全景档案'
        profile_versions=$(tr -d '\r' < "$profile" | grep -Ec '^- 资料版本：[0-9]+$' || true)
        [ "$profile_versions" -eq 1 ] || add_issue '资料版本 metadata must appear exactly once'
        [ "$(tr -d '\r' < "$profile" | sed -n 's/^- 资料版本：\([0-9][0-9]*\)$/\1/p')" = "$STATE_VERSION" ] || add_issue 'Profile version does not match state version'
        [ "$(tr -d '\r' < "$profile" | grep -Ec '^- 最近确认时间：.+$' || true)" -eq 1 ] || add_issue '最近确认时间 metadata must appear exactly once'
        for heading in '## 一、当前起点' '## 二、人生时间线与关键经历' '## 三、能力、经验与证据' '## 四、知识、认知与学习方式' '## 五、健康、精力与可持续边界' '## 六、经济、资源与风险承受能力' '## 七、关系、支持网络与现实责任' '## 八、习惯、行动与决策方式' '## 九、价值观、世界观与人生愿景' '## 十、当前目标与未来设想' '## 十一、AI 协作偏好' '## 十二、未知、冲突与 AI 假设' '## 十三、主要来源'; do
          [ "$(tr -d '\r' < "$profile" | grep -Fxc "$heading" || true)" -eq 1 ] || add_issue "Missing or duplicate profile section: $heading"
        done
      fi
      if [ -f "$progress" ]; then
        [ "$(tr -d '\r' < "$progress" | sed -n '1p')" = '# 访谈进度' ] || add_issue 'Interview progress must start with # 访谈进度'
        for heading in '## 已覆盖主题' '## 待补充主题' '## 暂不收集' '## 下次问题'; do
          [ "$(tr -d '\r' < "$progress" | grep -Fxc "$heading" || true)" -eq 1 ] || add_issue "Missing or duplicate progress section: $heading"
        done
        progress_versions=$(tr -d '\r' < "$progress" | grep -Ec '^- 进度版本：[0-9]+$' || true)
        if [ "$STATE_SCHEMA" = 2 ]; then
          [ "$progress_versions" -eq 1 ] || add_issue 'Missing or duplicate 进度版本 metadata'
          [ "$(tr -d '\r' < "$progress" | sed -n 's/^- 进度版本：\([0-9][0-9]*\)$/\1/p')" = "$STATE_PROGRESS" ] || add_issue 'Progress version does not match state version'
        else
          [ "$progress_versions" -le 1 ] || add_issue '进度版本 metadata must appear at most once'
        fi
      fi
      if [ -f "$pending" ]; then
        duplicates=$(tr -d '\r' < "$pending" | sed -n 's/^## \(C-[0-9TZ-][0-9TZ-]*\)$/\1/p' | sort | uniq -d)
        [ -z "$duplicates" ] || add_issue 'Pending candidates contain duplicate ids'
      fi
      if [ -f "$log" ] && printf '%s\n' "$STATE_VERSION" | grep -Eq '^[0-9]+$' && [ "$STATE_VERSION" -gt 1 ]; then
        grep -q "^## R$STATE_VERSION · " "$log" || add_issue 'Iteration log does not contain the current profile version'
      fi
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
      sed 's/\r$//' "$TEMPLATE_DIR/$name" > "$ROOT/$name" || fail "Cannot create file: $name"
      add_created "$name"
    fi
  done
  if [ ! -f "$ROOT/.hello-state" ]; then
    current=$(utc_now)
    write_state "$ROOT/.hello-state" 2 1 prompt "$current" "$current" '' '' baseline 1 '' ''
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
  printf '{"ok":true,"command":"status","root":"%s","profile_version":%s,"progress_version":%s,"capture_mode":"%s","review_stage":"%s","last_confirmed_at":"%s","next_review_at":"%s","last_session_id":"%s","last_turn_id":"%s","pending_candidates":%s}\n' \
    "$(json_escape "$ROOT")" "$STATE_VERSION" "$STATE_PROGRESS" "$(json_escape "$STATE_CAPTURE")" "$(json_escape "$STATE_STAGE")" \
    "$(json_escape "$STATE_CONFIRMED")" "$(json_escape "$STATE_REVIEW")" "$(json_escape "$STATE_SESSION")" "$(json_escape "$STATE_TURN")" "$pending"
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
  if [ "$new_stage" = first-review ] && [ -z "$new_review" ]; then
    fail 'first-review requires --next-review-at.'
  fi
  current=$(utc_now)
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$new_capture" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$new_review" "$new_stage" "$STATE_PROGRESS" "$STATE_SESSION" "$STATE_TURN"
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
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$STATE_REVIEW" "$STATE_STAGE" "$STATE_PROGRESS" "$STATE_SESSION" "$STATE_TURN"
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

relative_path() {
  case $1 in "$ROOT"/*) printf '%s' "${1#"$ROOT"/}" ;; *) printf '%s' "$1" ;; esac
}

begin_transaction() {
  kind=$1; shift
  marker=$ROOT/.hello-transaction
  [ ! -e "$marker" ] || fail 'Unfinished transaction exists; run recover first.'
  {
    printf 'kind=%s\n' "$kind"
    while [ "$#" -gt 1 ]; do printf '%s=%s\n' "$1" "$(relative_path "$2")"; shift 2; done
  } > "$marker" || fail 'Cannot create transaction marker.'
}

restore_from_marker() {
  marker=$ROOT/.hello-transaction
  [ -f "$marker" ] || return 1
  for pair in profile:profile_backup log:log_backup state:state_backup progress:progress_backup; do
    target_key=${pair%%:*}; backup_key=${pair#*:}
    backup_value=$(state_value "$marker" "$backup_key") || backup_value=
    [ -n "$backup_value" ] || continue
    case $backup_value in /*|../*|*/../*|*/..) return 1 ;; esac
    case $target_key in
      profile) target=$ROOT/个人全景档案.md ;;
      log) target=$ROOT/迭代日志.md ;;
      state) target=$ROOT/.hello-state ;;
      progress) target=$ROOT/访谈进度.md ;;
    esac
    cp "$ROOT/$backup_value" "$target" || return 1
  done
  record_value=$(state_value "$marker" record_path) || record_value=
  case $record_value in /*|../*|*/../*|*/..) return 1 ;; esac
  [ -z "$record_value" ] || rm -f "$ROOT/$record_value" || return 1
  rm -f "$marker" || return 1
  return 0
}

recover_space() {
  require_confirmed
  [ -f "$ROOT/.hello-transaction" ] || fail 'No unfinished transaction exists.'
  restore_from_marker || fail 'Recovery failed; transaction marker was retained.'
  validate_space || fail "Recovery completed but validation failed: $VALIDATION_ISSUES"
  printf '{"ok":true,"command":"recover","root":"%s"}\n' "$(json_escape "$ROOT")"
}

rollback_fail() {
  message=$1
  restore_from_marker || fail "$message; automatic rollback also failed. Run recover."
  fail "$message; transaction rolled back."
}

validate_summary() {
  for label in 触发原因 信息来源 更新类型 更新位置 更新摘要 用户确认状态 执行工具; do
    [ "$(tr -d '\r' < "$SUMMARY_INPUT" | grep -Ec "^- $label：.+$")" -eq 1 ] || fail "Update summary requires exactly one field: $label"
  done
  update_type=$(tr -d '\r' < "$SUMMARY_INPUT" | sed -n 's/^- 更新类型：//p')
  update_type=${update_type%。}; update_type=${update_type%.}; update_type=${update_type%;}; update_type=${update_type%；}
  case $update_type in 新增|状态变化|事实纠正|解释变化|假设验证|撤回隐藏) ;; *) fail 'Invalid 更新类型 in summary.' ;; esac
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
  [ "$(tr -d '\r' < "$INPUT" | sed -n '1p')" = '# 个人全景档案' ] || fail 'Candidate profile must start with # 个人全景档案.'
  [ "$(tr -d '\r' < "$INPUT" | grep -Ec '^- 资料版本：[0-9]+$')" -eq 1 ] || fail 'Candidate profile requires exactly one 资料版本 metadata line.'
  [ "$(tr -d '\r' < "$INPUT" | grep -Ec '^- 最近确认时间：.+$')" -eq 1 ] || fail 'Candidate profile requires exactly one 最近确认时间 metadata line.'
  for heading in '## 一、当前起点' '## 二、人生时间线与关键经历' '## 三、能力、经验与证据' '## 四、知识、认知与学习方式' '## 五、健康、精力与可持续边界' '## 六、经济、资源与风险承受能力' '## 七、关系、支持网络与现实责任' '## 八、习惯、行动与决策方式' '## 九、价值观、世界观与人生愿景' '## 十、当前目标与未来设想' '## 十一、AI 协作偏好' '## 十二、未知、冲突与 AI 假设' '## 十三、主要来源'; do
    [ "$(tr -d '\r' < "$INPUT" | grep -Fxc "$heading")" -eq 1 ] || fail "Candidate profile is missing or duplicates section: $heading"
  done
  validate_summary
  canonical_old=$ROOT/.canonical-old.$$.tmp; canonical_new=$ROOT/.canonical-new.$$.tmp
  sed -e 's/\r$//' -e 's/^- 资料版本：.*$/- 资料版本：<version>/' -e 's/^- 最近确认时间：.*$/- 最近确认时间：<time>/' "$ROOT/个人全景档案.md" > "$canonical_old"
  sed -e 's/\r$//' -e 's/^- 资料版本：.*$/- 资料版本：<version>/' -e 's/^- 最近确认时间：.*$/- 最近确认时间：<time>/' "$INPUT" > "$canonical_new"
  if cmp -s "$canonical_old" "$canonical_new"; then rm -f "$canonical_old" "$canonical_new"; fail 'Candidate profile has no content changes.'; fi
  rm -f "$canonical_old" "$canonical_new"
  current=$(utc_now)
  new_version=$((STATE_VERSION + 1))
  profile=$ROOT/个人全景档案.md
  name=$(file_stamp)-v$STATE_VERSION-个人全景档案.md
  mkdir -p "$ROOT/历史版本" "$ROOT/.backups/profile" || fail 'Cannot create backup directories.'
  unique_target "$ROOT/历史版本" "$name"; history=$UNIQUE_TARGET
  cp "$profile" "$history" || fail 'Cannot create history snapshot.'
  unique_target "$ROOT/.backups/profile" "$name"; backup=$UNIQUE_TARGET
  cp "$profile" "$backup" || fail 'Cannot create backup.'
  mkdir -p "$ROOT/.backups/transactions" || fail 'Cannot create transaction backup directory.'
  unique_target "$ROOT/.backups/transactions" "$(file_stamp)-v$STATE_VERSION-迭代日志.md"; log_backup=$UNIQUE_TARGET
  cp "$ROOT/迭代日志.md" "$log_backup" || fail 'Cannot back up iteration log.'
  unique_target "$ROOT/.backups/transactions" "$(file_stamp)-v$STATE_VERSION-hello-state"; state_backup=$UNIQUE_TARGET
  cp "$ROOT/.hello-state" "$state_backup" || fail 'Cannot back up state.'
  begin_transaction apply profile_backup "$backup" log_backup "$log_backup" state_backup "$state_backup"
  temp=$ROOT/.profile.$$.tmp
  sed -e 's/\r$//' -e "s/^- 资料版本：.*$/- 资料版本：$new_version/" -e "s/^- 最近确认时间：.*$/- 最近确认时间：$current/" "$INPUT" > "$temp" || rollback_fail 'Cannot prepare profile update.'
  mv -f "$temp" "$profile" || rollback_fail 'Cannot replace profile.'
  [ "$SIMULATE_FAILURE" = false ] || rollback_fail 'Simulated failure after profile write.'
  log=$ROOT/迭代日志.md
  log_temp=$ROOT/.log.$$.tmp
  sed '/^当前没有正式迭代。$/d' "$log" > "$log_temp" || rollback_fail 'Cannot prepare log.'
  {
    printf '\n## R%s · %s\n\n' "$new_version" "$current"
    printf -- '- 资料版本：%s\n' "$new_version"
    printf -- '- 确认状态：用户已确认\n'
    printf -- '- 历史快照：`历史版本/%s`\n\n' "$(basename "$history")"
    cat "$SUMMARY_INPUT"
    printf '\n'
  } >> "$log_temp" || rollback_fail 'Cannot append log.'
  mv -f "$log_temp" "$log" || rollback_fail 'Cannot replace log.'
  write_state "$ROOT/.hello-state" 2 "$new_version" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$current" "$STATE_REVIEW" "$STATE_STAGE" "$STATE_PROGRESS" "$STATE_SESSION" "$STATE_TURN"
  if ! validate_space true; then rollback_fail "Post-write validation failed: $VALIDATION_ISSUES"; fi
  rm -f "$ROOT/.hello-transaction" || rollback_fail 'Cannot clear transaction marker.'
  printf '{"ok":true,"command":"apply","root":"%s","old_version":%s,"profile_version":%s,"history":"%s","backup":"%s"}\n' \
    "$(json_escape "$ROOT")" "$STATE_VERSION" "$new_version" "$(json_escape "$history")" "$(json_escape "$backup")"
}

record_turn() {
  require_confirmed
  require_valid
  [ -n "$INPUT" ] || fail 'record-turn requires --input.'
  [ -n "$PROGRESS_INPUT" ] || fail 'record-turn requires --progress-input.'
  [ -n "$SESSION_ID" ] || fail 'record-turn requires --session-id.'
  [ -n "$TURN_ID" ] || fail 'record-turn requires --turn-id.'
  [ -n "$EXPECTED_PROGRESS_VERSION" ] || fail 'record-turn requires --expected-progress-version.'
  printf '%s\n' "$SESSION_ID" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}[A-Za-z0-9._-]*$' || fail 'Invalid session id.'
  printf '%s\n' "$TURN_ID" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || fail 'Invalid turn id.'
  case $EXPECTED_PROGRESS_VERSION in ''|*[!0-9]*) fail '--expected-progress-version must be an integer.' ;; esac
  [ -s "$INPUT" ] || fail 'Turn input is empty.'
  [ -s "$PROGRESS_INPUT" ] || fail 'Progress input is empty.'
  year=$(printf '%s' "$SESSION_ID" | cut -c 1-4)
  record_dir=$ROOT/原始访谈/$year/$SESSION_ID
  record_path=$record_dir/$TURN_ID.md
  if [ "$STATE_SESSION" = "$SESSION_ID" ] && [ "$STATE_TURN" = "$TURN_ID" ] && [ -f "$record_path" ]; then
    retry_temp=$ROOT/.turn-retry.$$.tmp
    sed 's/\r$//' "$INPUT" > "$retry_temp" || fail 'Cannot compare idempotent turn retry.'
    if ! cmp -s "$record_path" "$retry_temp"; then rm -f "$retry_temp"; fail 'Idempotent turn retry has different content.'; fi
    rm -f "$retry_temp"
    printf '{"ok":true,"command":"record-turn","root":"%s","idempotent":true,"progress_version":%s,"record":"%s"}\n' "$(json_escape "$ROOT")" "$STATE_PROGRESS" "$(json_escape "$record_path")"
    return
  fi
  [ "$EXPECTED_PROGRESS_VERSION" = "$STATE_PROGRESS" ] || fail "Progress version conflict: expected $EXPECTED_PROGRESS_VERSION, current $STATE_PROGRESS."
  [ ! -e "$record_path" ] || fail 'Turn record already exists but is not the current idempotency key.'
  [ "$(tr -d '\r' < "$PROGRESS_INPUT" | sed -n '1p')" = '# 访谈进度' ] || fail 'Progress input must start with # 访谈进度.'
  for heading in '## 已覆盖主题' '## 待补充主题' '## 暂不收集' '## 下次问题'; do
    [ "$(tr -d '\r' < "$PROGRESS_INPUT" | grep -Fxc "$heading")" -eq 1 ] || fail "Progress input is missing or duplicates section: $heading"
  done
  mkdir -p "$record_dir" "$ROOT/.backups/transactions" || fail 'Cannot create turn or transaction directories.'
  unique_target "$ROOT/.backups/transactions" "$(file_stamp)-p$STATE_PROGRESS-访谈进度.md"; progress_backup=$UNIQUE_TARGET
  cp "$ROOT/访谈进度.md" "$progress_backup" || fail 'Cannot back up progress.'
  unique_target "$ROOT/.backups/transactions" "$(file_stamp)-p$STATE_PROGRESS-hello-state"; state_backup=$UNIQUE_TARGET
  cp "$ROOT/.hello-state" "$state_backup" || fail 'Cannot back up state.'
  begin_transaction record-turn progress_backup "$progress_backup" state_backup "$state_backup" record_path "$record_path"
  sed 's/\r$//' "$INPUT" > "$record_path" || rollback_fail 'Cannot write turn record.'
  [ "$SIMULATE_FAILURE" = false ] || rollback_fail 'Simulated failure after turn record write.'
  new_progress=$((STATE_PROGRESS + 1))
  progress_temp=$ROOT/.progress.$$.tmp
  if tr -d '\r' < "$PROGRESS_INPUT" | grep -q '^- 进度版本：'; then
    tr -d '\r' < "$PROGRESS_INPUT" | sed "s/^- 进度版本：.*$/- 进度版本：$new_progress/" > "$progress_temp" || rollback_fail 'Cannot prepare progress update.'
  else
    tr -d '\r' < "$PROGRESS_INPUT" | awk -v version="$new_progress" 'NR==1 { print; print ""; print "- 进度版本：" version; next } { print }' > "$progress_temp" || rollback_fail 'Cannot prepare progress update.'
  fi
  mv -f "$progress_temp" "$ROOT/访谈进度.md" || rollback_fail 'Cannot replace progress.'
  current=$(utc_now)
  write_state "$ROOT/.hello-state" 2 "$STATE_VERSION" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$STATE_REVIEW" "$STATE_STAGE" "$new_progress" "$SESSION_ID" "$TURN_ID"
  if ! validate_space true; then rollback_fail "Post-write validation failed: $VALIDATION_ISSUES"; fi
  rm -f "$ROOT/.hello-transaction" || rollback_fail 'Cannot clear transaction marker.'
  printf '{"ok":true,"command":"record-turn","root":"%s","idempotent":false,"progress_version":%s,"record":"%s"}\n' "$(json_escape "$ROOT")" "$new_progress" "$(json_escape "$record_path")"
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
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$STATE_REVIEW" "$STATE_STAGE" "$STATE_PROGRESS" "$STATE_SESSION" "$STATE_TURN"
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
  progress=$temporary/progress.md
  turn=$temporary/turn.md
  printf '用户完成了一个重要项目。\n' > "$candidate"
  if sh "$0" init --root "$root" >/dev/null 2>&1; then fail 'Confirmation guard did not fail.'; fi
  sh "$0" init --root "$root" --confirmed >/dev/null || fail 'Self-test init failed.'
  second_init=$(sh "$0" init --root "$root" --confirmed) || fail 'Self-test second init failed.'
  printf '%s' "$second_init" | grep -q '"created":\[\]' || fail 'Self-test init overwrote existing space.'
  validation=$(sh "$0" validate --root "$root" 2>&1) || fail "Self-test validate failed: $validation"
  staged=$(sh "$0" stage --root "$root" --input "$candidate" --kind 经历 --source 自测 --confirmed) || fail 'Self-test stage failed.'
  staged_id=$(printf '%s' "$staged" | sed -n 's/.*"candidate_id":"\([^"]*\)".*/\1/p')
  [ -n "$staged_id" ] || fail 'Self-test could not read candidate id.'
  sh "$0" configure --root "$root" --capture-mode prompt --next-review-at 2030-01-01T00:00:00Z --confirmed >/dev/null || fail 'Self-test configure failed.'
  cp "$root/个人全景档案.md" "$profile"
  awk 'BEGIN { changed=0 } { print } !changed && $0 == "尚未访谈。" { print ""; print "- 自测更新。"; changed=1 }' "$profile" > "$profile.tmp" && mv "$profile.tmp" "$profile"
  {
    printf '%s\n' '- 触发原因：自测'
    printf '%s\n' '- 信息来源：隔离临时数据'
    printf '%s\n' '- 更新类型：新增'
    printf '%s\n' '- 更新位置：A'
    printf '%s\n' '- 更新摘要：增加自测条目'
    printf '%s\n' '- 用户确认状态：已确认'
    printf '%s\n' '- 执行工具：profile_store.sh'
  } > "$summary"
  if sh "$0" apply --root "$root" --input "$profile" --summary-input "$summary" --expected-version 1 --confirmed --simulate-failure >/dev/null 2>&1; then fail 'Simulated apply failure did not fail.'; fi
  validation=$(sh "$0" validate --root "$root" 2>&1) || fail "Self-test rollback validation failed: $validation"
  applied=$(sh "$0" apply --root "$root" --input "$profile" --summary-input "$summary" --expected-version 1 --confirmed 2>&1) || fail "Self-test apply failed: $applied"
  if sh "$0" apply --root "$root" --input "$profile" --summary-input "$summary" --expected-version 1 --confirmed >/dev/null 2>&1; then
    fail 'Version conflict did not fail.'
  fi
  cp "$root/访谈进度.md" "$progress"
  printf '%s\n' '# 自测访谈轮次' '' '- 仅使用临时数据。' > "$turn"
  sh "$0" record-turn --root "$root" --session-id 2030-01-01-self-test --turn-id Q001 --input "$turn" --progress-input "$progress" --expected-progress-version 1 --confirmed >/dev/null || fail 'Self-test record-turn failed.'
  idempotent=$(sh "$0" record-turn --root "$root" --session-id 2030-01-01-self-test --turn-id Q001 --input "$turn" --progress-input "$progress" --expected-progress-version 1 --confirmed) || fail 'Self-test idempotent record-turn failed.'
  printf '%s' "$idempotent" | grep -q '"idempotent":true' || fail 'Self-test record-turn was not idempotent.'
  sh "$0" configure --root "$root" --review-stage first-review --next-review-at 2030-02-01T00:00:00Z --confirmed >/dev/null || fail 'Self-test explicit baseline completion failed.'
  sh "$0" withdraw --root "$root" --id "$staged_id" --confirmed >/dev/null || fail 'Self-test withdraw failed.'
  validation=$(sh "$0" validate --root "$root" 2>&1) || fail "Self-test final validation failed: $validation"
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
  recover) recover_space ;;
  configure) configure_space ;;
  diff)
    require_valid
    [ -n "$INPUT" ] || fail 'diff requires --input.'
    [ -f "$INPUT" ] || fail "Candidate profile does not exist: $INPUT"
    if cmp -s "$ROOT/个人全景档案.md" "$INPUT"; then printf '%s\n' 'No changes.'; else diff -u "$ROOT/个人全景档案.md" "$INPUT" || [ "$?" -eq 1 ]; fi ;;
  stage) stage_candidate ;;
  apply) apply_profile ;;
  record-turn) record_turn ;;
  withdraw) withdraw_candidate ;;
esac
