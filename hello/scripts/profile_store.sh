#!/bin/sh

set -u
umask 077

COMMAND=${1-}
[ -n "$COMMAND" ] || { printf '%s\n' '{"ok":false,"command":"","error":"Command is required."}'; exit 2; }
shift

# A self-test invokes this script through `sh "$0" ...` while its parent
# owns an EXIT cleanup trap.  Bash may reuse the inherited trap in that child
# shell, so clear it before any non-self-test command can run.  The marker is
# exported only by self-test and is never part of normal adapter state.
if [ "$COMMAND" != self-test ] && [ "${HELLO_SELF_TEST_ACTIVE-}" = 1 ]; then
  trap - EXIT HUP INT TERM
  unset HELLO_SELF_TEST_ACTIVE
fi

ROOT_ARG=
ROOT_ARG_SET=false
INPUT=
SUMMARY_INPUT=
EXPECTED_VERSION=
KIND=
SOURCE=
CANDIDATE_ID=
CAPTURE_MODE=
CAPTURE_MODE_SET=false
NEXT_REVIEW_AT=
NEXT_REVIEW_AT_SET=false
REVIEW_STAGE=
REVIEW_STAGE_SET=false
SESSION_ID=
TURN_ID=
PROGRESS_INPUT=
EXPECTED_PROGRESS_VERSION=
TARGET_ARG=
TARGET_ARG_SET=false
DESTINATION_ARG=
DESTINATION_ARG_SET=false
MIGRATION_ID=
CONFIRMED=false
SIMULATE_FAILURE=false
CONFIRMED_SEEN=false
SIMULATE_FAILURE_SEEN=false
SEEN_VALUE_OPTIONS=
OPTION_NAMES=
STATE_PARSE_ERROR=
VALIDATION_ISSUES_JSON=[]
STORE_LOCK_HELD=false
STORE_LOCK_PATH=
STORE_LOCK_PID=
STORE_LOCK_SHELL_ID=
EXTRA_LOCK_PATHS=
RESTORED_JSON=[]

json_escape() {
  # JSON permits UTF-8 as-is, but every U+0000..U+001F byte must be escaped.
  # Shell arguments cannot contain NUL; the remaining control bytes are
  # handled explicitly so POSIX output has the same validity guarantees as
  # Python's json.dumps and PowerShell's ConvertTo-Json.
  printf '%s' "$1" | awk '
    BEGIN { first=1 }
    {
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      gsub(/\001/, "\\u0001"); gsub(/\002/, "\\u0002"); gsub(/\003/, "\\u0003")
      gsub(/\004/, "\\u0004"); gsub(/\005/, "\\u0005"); gsub(/\006/, "\\u0006")
      gsub(/\007/, "\\u0007"); gsub(/\010/, "\\b");    gsub(/\011/, "\\t")
      gsub(/\012/, "\\n");  gsub(/\013/, "\\u000b"); gsub(/\014/, "\\f")
      gsub(/\015/, "\\r");  gsub(/\016/, "\\u000e"); gsub(/\017/, "\\u000f")
      gsub(/\020/, "\\u0010"); gsub(/\021/, "\\u0011"); gsub(/\022/, "\\u0012")
      gsub(/\023/, "\\u0013"); gsub(/\024/, "\\u0014"); gsub(/\025/, "\\u0015")
      gsub(/\026/, "\\u0016"); gsub(/\027/, "\\u0017"); gsub(/\030/, "\\u0018")
      gsub(/\031/, "\\u0019"); gsub(/\032/, "\\u001a"); gsub(/\033/, "\\u001b")
      gsub(/\034/, "\\u001c"); gsub(/\035/, "\\u001d"); gsub(/\036/, "\\u001e")
      gsub(/\037/, "\\u001f")
      if (!first) printf "\\n"
      printf "%s", $0
      first=0
    }
  '
}

fail() {
  printf '{"ok":false,"command":"%s","error":"%s"}\n' "$(json_escape "$COMMAND")" "$(json_escape "$1")"
  exit 2
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --confirmed) [ "$CONFIRMED_SEEN" = false ] || fail 'Duplicate option: --confirmed'; OPTION_NAMES="$OPTION_NAMES confirmed"; CONFIRMED=true; CONFIRMED_SEEN=true; shift ;;
    --simulate-failure) [ "$SIMULATE_FAILURE_SEEN" = false ] || fail 'Duplicate option: --simulate-failure'; OPTION_NAMES="$OPTION_NAMES simulate-failure"; SIMULATE_FAILURE=true; SIMULATE_FAILURE_SEEN=true; shift ;;
    --root|--input|--summary-input|--expected-version|--kind|--source|--id|--capture-mode|--next-review-at|--review-stage|--session-id|--turn-id|--progress-input|--expected-progress-version|--target|--destination|--migration-id)
      [ "$#" -ge 2 ] || fail "Missing value for $1"
      case $2 in
        --*) fail "Missing value for $1" ;;
      esac
      option_name=${1#--}
      case "|$SEEN_VALUE_OPTIONS|" in *"|$option_name|"*) fail "Duplicate option: --$option_name" ;; esac
      SEEN_VALUE_OPTIONS="$SEEN_VALUE_OPTIONS|$option_name"
      OPTION_NAMES="$OPTION_NAMES $option_name"
      case $1 in
        --root) ROOT_ARG=$2; ROOT_ARG_SET=true ;;
        --input) INPUT=$2 ;;
        --summary-input) SUMMARY_INPUT=$2 ;;
        --expected-version) EXPECTED_VERSION=$2 ;;
        --kind) KIND=$2 ;;
        --source) SOURCE=$2 ;;
        --id) CANDIDATE_ID=$2 ;;
        --capture-mode) CAPTURE_MODE=$2; CAPTURE_MODE_SET=true ;;
        --next-review-at) NEXT_REVIEW_AT=$2; NEXT_REVIEW_AT_SET=true ;;
        --review-stage) REVIEW_STAGE=$2; REVIEW_STAGE_SET=true ;;
        --session-id) SESSION_ID=$2 ;;
        --turn-id) TURN_ID=$2 ;;
        --progress-input) PROGRESS_INPUT=$2 ;;
        --expected-progress-version) EXPECTED_PROGRESS_VERSION=$2 ;;
        --target) TARGET_ARG=$2; TARGET_ARG_SET=true ;;
        --destination) DESTINATION_ARG=$2; DESTINATION_ARG_SET=true ;;
        --migration-id) MIGRATION_ID=$2 ;;
      esac
      shift 2 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

case $COMMAND in
  resolve-root|init|validate|status|configure|record-disclosure|diff|stage|apply|withdraw|record-turn|recover|self-test|target-validate|migrate-plan|migrate-apply|rebuild-index|switch-layout|rollback-layout) ;;
  *) fail "Unknown command: $COMMAND" ;;
esac

validate_command_arguments() {
  for option in $OPTION_NAMES; do
    case "$COMMAND:$option" in
      resolve-root:root|init:root|validate:root|status:root) ;;
      configure:root|configure:capture-mode|configure:next-review-at|configure:review-stage) ;;
      record-disclosure:root|record-disclosure:capture-mode) ;;
      diff:root|diff:input) ;;
      stage:root|stage:input|stage:kind|stage:source) ;;
      apply:root|apply:input|apply:summary-input|apply:expected-version|apply:simulate-failure) ;;
      record-turn:root|record-turn:input|record-turn:progress-input|record-turn:session-id|record-turn:turn-id|record-turn:expected-progress-version|record-turn:simulate-failure) ;;
      withdraw:root|withdraw:id) ;;
      recover:root) ;;
      target-validate:root) ;;
      migrate-plan:root|migrate-plan:target|migrate-plan:migration-id|migrate-plan:confirmed) ;;
      migrate-apply:root|migrate-apply:target|migrate-apply:destination|migrate-apply:expected-version|migrate-apply:expected-progress-version|migrate-apply:confirmed|migrate-apply:simulate-failure) ;;
      rebuild-index:root|rebuild-index:confirmed) ;;
      switch-layout:root|switch-layout:target|switch-layout:expected-version|switch-layout:expected-progress-version|switch-layout:migration-id|switch-layout:confirmed|switch-layout:simulate-failure) ;;
      rollback-layout:root|rollback-layout:migration-id|rollback-layout:confirmed) ;;
      init:confirmed|configure:confirmed|record-disclosure:confirmed|stage:confirmed|apply:confirmed|record-turn:confirmed|withdraw:confirmed|recover:confirmed) ;;
      *) fail "Option --$option is not valid for $COMMAND." ;;
    esac
  done
  case $COMMAND in
    resolve-root|validate|status|diff|self-test|target-validate)
      [ "$CONFIRMED" = false ] || fail "Option --confirmed is not valid for $COMMAND." ;;
  esac
  case $COMMAND in
    apply|record-turn|migrate-apply|switch-layout) ;;
    *) [ "$SIMULATE_FAILURE" = false ] || fail "Option --simulate-failure is not valid for $COMMAND." ;;
  esac
  case $COMMAND in
    init|configure|record-disclosure|stage|apply|record-turn|withdraw|recover|migrate-apply|rebuild-index|switch-layout|rollback-layout)
      [ "$ROOT_ARG_SET" = true ] || fail 'Mutating commands require an explicit --root.' ;;
  esac
  if [ "$COMMAND" = migrate-plan ] && [ "$CONFIRMED" = true ] && [ "$ROOT_ARG_SET" != true ]; then
    fail 'Confirmed migrate-plan requires an explicit --root.'
  fi
  case $COMMAND in
    target-validate) [ "$ROOT_ARG_SET" = true ] || fail 'target-validate requires an explicit --root.' ;;
    migrate-plan) [ "$TARGET_ARG_SET" = true ] || fail 'migrate-plan requires --target.' ;;
    migrate-apply) [ "$TARGET_ARG_SET" = true ] || fail 'migrate-apply requires --target.'; [ "$DESTINATION_ARG_SET" = true ] || fail 'migrate-apply requires --destination.'; [ -n "$EXPECTED_VERSION" ] || fail 'migrate-apply requires --expected-version.'; [ -n "$EXPECTED_PROGRESS_VERSION" ] || fail 'migrate-apply requires --expected-progress-version.' ;;
    rebuild-index) ;;
    switch-layout) [ "$TARGET_ARG_SET" = true ] || fail 'switch-layout requires --target.'; [ -n "$EXPECTED_VERSION" ] || fail 'switch-layout requires --expected-version.'; [ -n "$EXPECTED_PROGRESS_VERSION" ] || fail 'switch-layout requires --expected-progress-version.' ;;
    rollback-layout) [ -n "$MIGRATION_ID" ] || fail 'rollback-layout requires --migration-id.' ;;
  esac
}

validate_command_arguments

utc_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
file_stamp() { date -u '+%Y%m%dT%H%M%SZ'; }

is_positive_decimal() {
  case $1 in
    ''|0*|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

digit_rank() {
  case $1 in
    0) DIGIT_RANK=0 ;;
    1) DIGIT_RANK=1 ;;
    2) DIGIT_RANK=2 ;;
    3) DIGIT_RANK=3 ;;
    4) DIGIT_RANK=4 ;;
    5) DIGIT_RANK=5 ;;
    6) DIGIT_RANK=6 ;;
    7) DIGIT_RANK=7 ;;
    8) DIGIT_RANK=8 ;;
    9) DIGIT_RANK=9 ;;
    *) return 1 ;;
  esac
}

# Compare canonical positive decimal strings without converting the version
# itself to a host integer.  Return 0 for equal, 1 for left < right, 2 for
# left > right; only the single-digit rank uses shell arithmetic-safe values.
decimal_compare() {
  decimal_left=$1
  decimal_right=$2
  is_positive_decimal "$decimal_left" || return 3
  is_positive_decimal "$decimal_right" || return 3
  decimal_left_length=$(printf '%s' "$decimal_left" | LC_ALL=C wc -c | tr -d '[:space:]')
  decimal_right_length=$(printf '%s' "$decimal_right" | LC_ALL=C wc -c | tr -d '[:space:]')
  if [ "$decimal_left_length" -lt "$decimal_right_length" ]; then return 1; fi
  if [ "$decimal_left_length" -gt "$decimal_right_length" ]; then return 2; fi
  while [ -n "$decimal_left" ]; do
    decimal_left_rest=${decimal_left#?}
    decimal_right_rest=${decimal_right#?}
    decimal_left_digit=${decimal_left%"$decimal_left_rest"}
    decimal_right_digit=${decimal_right%"$decimal_right_rest"}
    digit_rank "$decimal_left_digit" || return 3
    decimal_left_rank=$DIGIT_RANK
    digit_rank "$decimal_right_digit" || return 3
    decimal_right_rank=$DIGIT_RANK
    if [ "$decimal_left_rank" -lt "$decimal_right_rank" ]; then return 1; fi
    if [ "$decimal_left_rank" -gt "$decimal_right_rank" ]; then return 2; fi
    decimal_left=$decimal_left_rest
    decimal_right=$decimal_right_rest
  done
  return 0
}

decimal_increment() {
  increment_input=$1
  is_positive_decimal "$increment_input" || return 1
  increment_output=
  while [ -n "$increment_input" ]; do
    case $increment_input in
      *0) increment_output="1$increment_output"; increment_input=${increment_input%?}; printf '%s\n' "${increment_input}${increment_output}"; return 0 ;;
      *1) increment_output="2$increment_output"; increment_input=${increment_input%?}; printf '%s\n' "${increment_input}${increment_output}"; return 0 ;;
      *2) increment_output="3$increment_output"; increment_input=${increment_input%?}; printf '%s\n' "${increment_input}${increment_output}"; return 0 ;;
      *3) increment_output="4$increment_output"; increment_input=${increment_input%?}; printf '%s\n' "${increment_input}${increment_output}"; return 0 ;;
      *4) increment_output="5$increment_output"; increment_input=${increment_input%?}; printf '%s\n' "${increment_input}${increment_output}"; return 0 ;;
      *5) increment_output="6$increment_output"; increment_input=${increment_input%?}; printf '%s\n' "${increment_input}${increment_output}"; return 0 ;;
      *6) increment_output="7$increment_output"; increment_input=${increment_input%?}; printf '%s\n' "${increment_input}${increment_output}"; return 0 ;;
      *7) increment_output="8$increment_output"; increment_input=${increment_input%?}; printf '%s\n' "${increment_input}${increment_output}"; return 0 ;;
      *8) increment_output="9$increment_output"; increment_input=${increment_input%?}; printf '%s\n' "${increment_input}${increment_output}"; return 0 ;;
      *9) increment_output="0$increment_output"; increment_input=${increment_input%?} ;;
    esac
  done
  printf '1%s\n' "$increment_output"
}

# Validate the canonical UTC timestamp used by the state contract.  Keeping
# calendar validation here (rather than only checking the character shape)
# makes the POSIX adapter reject the same impossible dates as Python and
# PowerShell.
is_iso_utc() {
  printf '%s\n' "$1" | awk '
    length($0) != 20 || $0 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ { exit 1 }
    {
      y = substr($0, 1, 4) + 0
      m = substr($0, 6, 2) + 0
      d = substr($0, 9, 2) + 0
      h = substr($0, 12, 2) + 0
      n = substr($0, 15, 2) + 0
      s = substr($0, 18, 2) + 0
      if (y < 1 || m < 1 || m > 12 || h > 23 || n > 59 || s > 59 || d < 1) exit 1
      max = 31
      if (m == 4 || m == 6 || m == 9 || m == 11) max = 30
      if (m == 2) max = 28 + ((y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 1 : 0)
      if (d > max) exit 1
    }
  '
}

# Normalize a text payload the same way as Python/PowerShell adapters:
# normalize CRLF to LF, trim surrounding Unicode/ASCII whitespace that the
# POSIX tools can recognize, and leave internal lines untouched.
trim_text_file() {
  TRIMMED_TEXT=$(sed 's/\r$//' "$1" | awk '
    NR == 1 { sub(/^\357\273\277/, "", $0) }
    { if (NR > 1) text = text "\n"; text = text $0 }
    END {
      # Python str.strip()/PowerShell Trim() treat NBSP as whitespace; the
      # explicit UTF-8 bytes keep the POSIX adapter aligned under C locales.
      gsub(/^[[:space:]\302\240]+/, "", text)
      gsub(/[[:space:]\302\240]+$/, "", text)
      printf "%s", text
    }
  ')
}

resolve_root() {
  if [ "$ROOT_ARG_SET" = true ]; then raw=$ROOT_ARG; else raw=${HELLO_HOME-}; fi
  # An all-whitespace value is an omitted/invalid root, not a directory name.
  # Reject it before normalization so a dropped argument can never resolve to
  # the current directory or a whitespace-only path.
  if ! printf '%s' "$raw" | awk '
    {
      gsub(/[[:space:]]/, "", $0)
      gsub(/\302\240/, "", $0)
      if (length($0) > 0) found = 1
    }
    END { exit(found ? 0 : 1) }
  '; then
    fail 'Personal profile root is not configured. Pass --root or set HELLO_HOME.'
  fi
  # Match the native adapters for the common user-relative forms.  Do not
  # evaluate arbitrary shell text: only expand the current user's `~` prefix.
  case $raw in
    '~') [ -n "${HOME-}" ] && raw=$HOME ;;
    '~/'*) [ -n "${HOME-}" ] && raw=$HOME/${raw#~/} ;;
  esac
  case $raw in
    /*) candidate=$raw ;;
    *) candidate=$(pwd -P)/$raw ;;
  esac
  # Resolve existing directories through the filesystem (including symlinks),
  # then lexically normalize a not-yet-created root so `.`/`..` behave like
  # Python Path.resolve(strict=False) and PowerShell GetFullPath.
  normalized=
  if [ -d "$candidate" ]; then
    normalized=$(CDPATH= cd "$candidate" 2>/dev/null && pwd -P) || normalized=
  fi
  if [ -z "$normalized" ]; then
    normalized=$(printf '%s\n' "$candidate" | awk -F/ '
      {
        count = 0
        for (i = 1; i <= NF; i++) {
          part = $i
          if (part == "" || part == ".") continue
          if (part == "..") { if (count > 0) count--; continue }
          parts[++count] = part
        }
      }
      END {
        if (count == 0) {
          print "/"
        } else {
          result = ""
          for (i = 1; i <= count; i++) result = result "/" parts[i]
          print result
        }
      }
    ')
  fi
  [ -n "$normalized" ] || fail 'Cannot normalize profile root.'
  ROOT=$normalized
}

# Resolve an explicitly supplied secondary root without ever falling back to
# HELLO_HOME.  Target-layout operations deliberately require two independent
# roots; accepting an omitted/relative fallback here would make it possible to
# accidentally migrate or replace the canonical profile space.
resolve_explicit_path() {
  explicit_value=$1
  explicit_label=$2
  if ! printf '%s' "$explicit_value" | awk '
    { gsub(/[[:space:]]/, "", $0); gsub(/\302\240/, "", $0); if (length($0) > 0) found=1 }
    END { exit(found ? 0 : 1) }
  '; then
    fail "$explicit_label must not be empty or whitespace-only."
  fi
  raw_secondary=$explicit_value
  case $raw_secondary in
    '~') [ -n "${HOME-}" ] && raw_secondary=$HOME ;;
    '~/'*) [ -n "${HOME-}" ] && raw_secondary=$HOME/${raw_secondary#~/} ;;
  esac
  case $raw_secondary in
    /*) candidate_secondary=$raw_secondary ;;
    *) candidate_secondary=$(pwd -P)/$raw_secondary ;;
  esac
  normalized_secondary=
  if [ -d "$candidate_secondary" ]; then
    normalized_secondary=$(CDPATH= cd "$candidate_secondary" 2>/dev/null && pwd -P) || normalized_secondary=
  fi
  if [ -z "$normalized_secondary" ]; then
    normalized_secondary=$(printf '%s\n' "$candidate_secondary" | awk -F/ '
      { count=0; for (i=1;i<=NF;i++) { part=$i; if (part=="" || part==".") continue; if (part=="..") { if (count>0) count--; continue } parts[++count]=part } }
      END { if (count==0) print "/"; else { result=""; for (i=1;i<=count;i++) result=result "/" parts[i]; print result } }
    ')
  fi
  [ -n "$normalized_secondary" ] || fail "Cannot normalize $explicit_label."
  SECONDARY_PATH=$normalized_secondary
}

path_is_same_or_nested() {
  path_a=$1
  path_b=$2
  [ "$path_a" = "$path_b" ] && return 0
  case "$path_a/" in "$path_b/"*) return 0 ;; esac
  case "$path_b/" in "$path_a/"*) return 0 ;; esac
  return 1
}

assert_independent_roots() {
  independent_a=$1
  independent_b=$2
  path_is_same_or_nested "$independent_a" "$independent_b" && fail 'Source and target roots must be independent directories (neither may contain the other).'
}

sha256_file() {
  hash_file=$1
  [ -f "$hash_file" ] || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$hash_file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$hash_file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$hash_file" | awk '{print $NF}'
  else
    return 1
  fi
}

safe_migration_id() {
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'
}

target_marker_value() {
  marker_value_path=$1
  marker_value_key=$2
  state_value "$marker_value_path" "$marker_value_key" 2>/dev/null
}

target_issue_add() {
  target_issue=$1
  if [ -n "${TARGET_VALIDATION_ISSUES-}" ]; then
    TARGET_VALIDATION_ISSUES="$TARGET_VALIDATION_ISSUES; $target_issue"
  else
    TARGET_VALIDATION_ISSUES=$target_issue
  fi
  target_issue_json=$(json_escape "$target_issue")
  if [ "${TARGET_VALIDATION_ISSUES_JSON-[]}" = '[]' ]; then
    TARGET_VALIDATION_ISSUES_JSON="[\"$target_issue_json\"]"
  else
    TARGET_VALIDATION_ISSUES_JSON="${TARGET_VALIDATION_ISSUES_JSON%]},\"$target_issue_json\"]"
  fi
}

# Validate the machine marker and metadata-only manifest of the target
# directory.  This intentionally does not inspect claim/event bodies: target
# validation is a layout/safety check, while content review remains an owner
# decision.  `schema_version=3` is the formal target protocol; the historical
# draft marker is accepted only for migration-plan/migrate-apply input.
validate_target_space() {
  target_root=$1
  TARGET_VALIDATION_ISSUES=
  TARGET_VALIDATION_ISSUES_JSON=[]
  [ -d "$target_root" ] || target_issue_add 'Target root directory does not exist'
  if [ -d "$target_root" ]; then
    marker=$target_root/.hello-state
    manifest=$target_root/manifest.json
    [ -f "$marker" ] || target_issue_add 'Missing target marker: .hello-state'
    if [ -f "$marker" ]; then
      validate_marker_syntax "$marker" || target_issue_add 'Invalid target marker syntax'
      target_layout=$(target_marker_value "$marker" layout) || target_layout=
      target_layout_version=$(target_marker_value "$marker" layout_version) || target_layout_version=
      target_schema=$(target_marker_value "$marker" schema_version) || target_schema=
      target_migration=$(target_marker_value "$marker" migration_id) || target_migration=
      case $target_layout in target-draft|target) ;; *) target_issue_add 'layout must be target-draft or target' ;; esac
      [ "$target_layout_version" = 1 ] || target_issue_add 'layout_version must be 1'
      case $target_layout:$target_schema in
        target:3|target-draft:target-draft-0.1|target-draft:3) ;;
        *) target_issue_add 'schema_version is incompatible with target layout' ;;
      esac
      safe_migration_id "$target_migration" || target_issue_add 'migration_id has invalid characters'
      for target_identity_key in package_id subject_id; do
        target_identity_value=$(target_marker_value "$marker" "$target_identity_key") || target_identity_value=
        [ -n "$target_identity_value" ] || target_issue_add "Missing target marker field: $target_identity_key"
        safe_migration_id "$target_identity_value" || target_issue_add "$target_identity_key has invalid characters"
      done
      if [ "$target_layout" = target ]; then
        for target_compat_key in profile_version progress_version capture_mode created_at updated_at last_confirmed_at next_review_at review_stage last_interview_at last_session_id last_turn_id last_capture_disclosed_at last_capture_disclosed_mode; do
          # Formal schema 3 keeps the complete compatibility cursor so every
          # adapter can resume interviews without reconstructing legacy state.
          target_compat_value=$(target_marker_value "$marker" "$target_compat_key") || target_compat_value=
          [ -n "$target_compat_value" ] || {
            case $target_compat_key in
              next_review_at|last_confirmed_at|last_interview_at|last_session_id|last_turn_id|last_capture_disclosed_at|last_capture_disclosed_mode) [ -e "$marker" ] && grep -q "^$target_compat_key=" "$marker" || target_issue_add "Formal target marker is missing compatibility field: $target_compat_key" ;;
              *) target_issue_add "Formal target marker is missing compatibility field: $target_compat_key" ;;
            esac
          }
        done
        [ "$target_schema" = 3 ] || target_issue_add 'Formal target marker schema_version must be 3'
      fi
    fi
    [ -f "$manifest" ] || target_issue_add 'Missing target manifest: manifest.json'
    if [ -f "$manifest" ]; then
      # The manifest is metadata-only. These checks reject a missing or
      # mismatched identity without parsing or echoing personal body text.
      manifest_layout=$(target_manifest_field "$manifest" layout) || manifest_layout=
      manifest_migration=$(target_manifest_field "$manifest" migration_id) || manifest_migration=
      manifest_package=$(target_manifest_field "$manifest" package_id) || manifest_package=
      manifest_subject=$(target_manifest_field "$manifest" subject_id) || manifest_subject=
      manifest_owner=$(target_manifest_field "$manifest" owner) || manifest_owner=
      manifest_audience=$(target_manifest_field "$manifest" audience) || manifest_audience=
      [ "$manifest_layout" = "$target_layout" ] || target_issue_add 'Target marker and manifest layout do not match'
      [ "$(target_manifest_field "$manifest" layout_version)" = 1 ] || target_issue_add 'Manifest layout_version must be 1'
      [ "$manifest_migration" = "$target_migration" ] || target_issue_add 'Target marker and manifest migration_id do not match'
      [ -n "$manifest_package" ] || target_issue_add 'Missing target manifest field: package_id'
      [ "$manifest_package" = "$(target_marker_value "$marker" package_id)" ] || target_issue_add 'Target marker and manifest package_id do not match'
      [ -n "$manifest_subject" ] || target_issue_add 'Missing target manifest field: subject_id'
      [ "$manifest_subject" = "$(target_marker_value "$marker" subject_id)" ] || target_issue_add 'Target marker and manifest subject_id do not match'
      [ -n "$manifest_owner" ] || target_issue_add 'Missing target manifest field: owner'
      [ -n "$manifest_audience" ] || target_issue_add 'Missing target manifest field: audience'
      manifest_schema=$(target_manifest_field "$manifest" schema_version) || manifest_schema=
      [ "$manifest_schema" = "$target_schema" ] || target_issue_add 'Target marker and manifest schema_version do not match'
      if [ -f "$marker" ]; then
        marker_profile_hash=$(target_marker_value "$marker" source_profile_sha256) || marker_profile_hash=
        marker_progress_hash=$(target_marker_value "$marker" source_progress_sha256) || marker_progress_hash=
        marker_pending_hash=$(target_marker_value "$marker" source_pending_sha256) || marker_pending_hash=
        manifest_profile_hash=$(target_manifest_source_value "$manifest" profile sha256) || manifest_profile_hash=
        manifest_progress_hash=$(target_manifest_source_value "$manifest" progress sha256) || manifest_progress_hash=
        manifest_pending_hash=$(target_manifest_source_value "$manifest" pending sha256) || manifest_pending_hash=
        [ -z "$marker_profile_hash" ] || [ "$marker_profile_hash" = "$manifest_profile_hash" ] || target_issue_add 'Marker/manifest profile hash mismatch'
        [ -z "$marker_progress_hash" ] || [ "$marker_progress_hash" = "$manifest_progress_hash" ] || target_issue_add 'Marker/manifest progress hash mismatch'
        [ -z "$marker_pending_hash" ] || [ "$marker_pending_hash" = "$manifest_pending_hash" ] || target_issue_add 'Marker/manifest pending hash mismatch'
      fi
    fi
    for required_target_file in README.md 个人全景档案.md 主题覆盖矩阵.md 待确认信息.md 访谈进度.md 资料索引.md 迭代日志.md; do
      [ -f "$target_root/$required_target_file" ] || target_issue_add "Missing target file: $required_target_file"
    done
    for required_target_dir in 原始访谈 来源 权威 派生 历史版本 .backups .trash; do
      [ -d "$target_root/$required_target_dir" ] || target_issue_add "Missing target directory: $required_target_dir"
    done
    # Symlinks are not accepted in a migration package.  They could point
    # outside the authorized root and would defeat the independent-root check.
    if find "$target_root" -type l -print -quit 2>/dev/null | grep -q .; then
      target_issue_add 'Target package must not contain symbolic links'
    fi
    if [ -f "$marker" ]; then
      for target_hash_key in source_profile_sha256 source_progress_sha256 source_pending_sha256; do
        target_hash_value=$(target_marker_value "$marker" "$target_hash_key") || target_hash_value=
        [ -z "$target_hash_value" ] || printf '%s\n' "$target_hash_value" | grep -Eq '^[0-9a-fA-F]{64}$' || target_issue_add "$target_hash_key must be a SHA-256 value"
      done
    fi
  fi
  [ -z "$TARGET_VALIDATION_ISSUES" ]
}

write_target_manifest() {
  target_manifest_root=$1
  target_manifest_layout=$2
  target_manifest_migration=$3
  target_manifest_package=${4-pkg-local}
  target_manifest_subject=${5-subject-local}
  target_manifest_source_profile=${6-}
  target_manifest_source_progress=${7-}
  target_manifest_source_pending=${8-}
  target_manifest_generated=${9-}
  target_manifest_profile_version=${10-}
  target_manifest_progress_version=${11-}
  target_manifest_index_hash=${12-}
  target_manifest_index_generated=${13-}
  target_manifest_index_matrix=${14-}
  [ -n "$target_manifest_generated" ] || target_manifest_generated=$(utc_now)
  manifest_temp=$target_manifest_root/.manifest.$$.tmp
  {
    printf '{\n'
    printf '  "layout": "%s",\n' "$(json_escape "$target_manifest_layout")"
    printf '  "layout_version": 1,\n'
    printf '  "schema_version": %s,\n' "$([ "$target_manifest_layout" = target ] && printf 3 || printf '"target-draft-0.1"')"
    printf '  "migration_id": "%s",\n' "$(json_escape "$target_manifest_migration")"
    printf '  "package_id": "%s",\n' "$(json_escape "$target_manifest_package")"
    printf '  "subject_id": "%s",\n' "$(json_escape "$target_manifest_subject")"
    printf '  "owner": "local-owner",\n'
    printf '  "audience": "owner-and-authorized-ai",\n'
    printf '  "language": "zh-CN",\n'
    if [ -n "$target_manifest_source_profile" ] || [ -n "$target_manifest_source_progress" ] || [ -n "$target_manifest_source_pending" ]; then
      printf '  "generated_at": "%s",\n' "$(json_escape "$target_manifest_generated")"
    else
      printf '  "generated_at": "%s"' "$(json_escape "$target_manifest_generated")"
    fi
    if [ -n "$target_manifest_source_profile" ] || [ -n "$target_manifest_source_progress" ] || [ -n "$target_manifest_source_pending" ]; then
      printf '\n  "source": {\n'
      printf '    "profile": {"version": "%s", "sha256": "%s"},\n' "$(json_escape "$target_manifest_profile_version")" "$(json_escape "$target_manifest_source_profile")"
      printf '    "progress": {"version": "%s", "sha256": "%s"},\n' "$(json_escape "$target_manifest_progress_version")" "$(json_escape "$target_manifest_source_progress")"
      printf '    "pending": {"sha256": "%s"}\n' "$(json_escape "$target_manifest_source_pending")"
      printf '  }'
    fi
    if [ -n "$target_manifest_index_hash" ]; then
      printf ',\n  "index_source_hash": "%s",\n  "index_generated_at": "%s"' "$(json_escape "$target_manifest_index_hash")" "$(json_escape "$target_manifest_index_generated")"
      [ -z "$target_manifest_index_matrix" ] || printf ',\n  "index_source_matrix_version": "%s"' "$(json_escape "$target_manifest_index_matrix")"
    fi
    printf '\n}\n'
  } > "$manifest_temp" || { rm -f "$manifest_temp"; return 1; }
  mv -f "$manifest_temp" "$target_manifest_root/manifest.json"
}

write_target_marker() {
  target_marker_root=$1
  target_marker_layout=$2
  target_marker_migration=$3
  target_marker_package=${4-pkg-local}
  target_marker_subject=${5-subject-local}
  target_marker_profile_version=${6-}
  target_marker_progress_version=${7-}
  target_marker_profile_hash=${8-}
  target_marker_progress_hash=${9-}
  target_marker_pending_hash=${10-}
  target_marker_generated=${11-}
  [ -n "$target_marker_generated" ] || target_marker_generated=$(utc_now)
  marker_temp=$target_marker_root/.hello-state.$$.tmp
  {
    printf 'layout=%s\n' "$target_marker_layout"
    printf 'layout_version=1\n'
    if [ "$target_marker_layout" = target ]; then printf 'schema_version=3\n'; else printf 'schema_version=target-draft-0.1\n'; fi
    printf 'migration_id=%s\n' "$target_marker_migration"
    printf 'package_id=%s\n' "$target_marker_package"
    printf 'subject_id=%s\n' "$target_marker_subject"
    [ -n "$target_marker_profile_version" ] && printf 'source_profile_version=%s\n' "$target_marker_profile_version"
    [ -n "$target_marker_progress_version" ] && printf 'source_progress_version=%s\n' "$target_marker_progress_version"
    [ -n "$target_marker_profile_hash" ] && printf 'source_profile_sha256=%s\n' "$target_marker_profile_hash"
    [ -n "$target_marker_progress_hash" ] && printf 'source_progress_sha256=%s\n' "$target_marker_progress_hash"
    [ -n "$target_marker_pending_hash" ] && printf 'source_pending_sha256=%s\n' "$target_marker_pending_hash"
    printf 'generated_at=%s\n' "$target_marker_generated"
    if [ "$target_marker_layout" = target ]; then printf 'authority_status=active\n'; else printf 'authority_status=non-authoritative-needs-user-confirmation\n'; fi
  } > "$marker_temp" || { rm -f "$marker_temp"; return 1; }
  mv -f "$marker_temp" "$target_marker_root/.hello-state"
}

sync_target_compat_state() {
  target_compat_root=$1
  # Formal targets retain the cursor/policy fields required by record-turn and
  # candidate staging.  The caller has already read the source state into the
  # STATE_* variables; unknown target marker fields are preserved by
  # write_state.
  [ -n "${STATE_VERSION-}" ] || return 0
  write_state "$target_compat_root/.hello-state" 3 "$STATE_VERSION" "${STATE_CAPTURE-}" "${STATE_CREATED-}" "$(utc_now)" "${STATE_CONFIRMED-}" "${STATE_REVIEW-}" "${STATE_STAGE-}" "${STATE_INTERVIEW-}" "${STATE_PROGRESS-1}" "${STATE_SESSION-}" "${STATE_TURN-}" "${STATE_DISCLOSED-}" "${STATE_DISCLOSED_MODE-}"
}

copy_target_tree() {
  copy_source=$1
  copy_destination=$2
  [ -d "$copy_source" ] || return 1
  mkdir -p "$copy_destination" || return 1
  # Refuse links before copying. `cp -R` then preserves filenames (including
  # spaces and UTF-8) without unsafe word splitting.
  if find "$copy_source" -type l -print -quit 2>/dev/null | grep -q .; then return 1; fi
  cp -R "$copy_source"/. "$copy_destination"/ || return 1
  # Locks belong to the live source/draft process and must never become part
  # of an installed target package.  The draft is locked while it is copied.
  rm -rf "$copy_destination/.hello-lock" 2>/dev/null || return 1
  return 0
}

target_required_source_hashes() {
  target_source_root=$1
  [ -f "$target_source_root/个人全景档案.md" ] || return 1
  [ -f "$target_source_root/访谈进度.md" ] || return 1
  [ -f "$target_source_root/待确认信息.md" ] || return 1
  TARGET_SOURCE_PROFILE_HASH=$(sha256_file "$target_source_root/个人全景档案.md") || return 1
  TARGET_SOURCE_PROGRESS_HASH=$(sha256_file "$target_source_root/访谈进度.md") || return 1
  TARGET_SOURCE_PENDING_HASH=$(sha256_file "$target_source_root/待确认信息.md") || return 1
}

target_manifest_source_value() {
  target_manifest_file=$1
  target_manifest_section=$2
  target_manifest_key=$3
  [ -f "$target_manifest_file" ] || return 1
  target_manifest_compact=$(tr -d '\r\n' < "$target_manifest_file")
  # Frozen protocol form: source.profile/progress/pending objects.  The flat
  # keys are accepted for drafts produced by the first migration prototype.
  target_manifest_value_result=$(printf '%s' "$target_manifest_compact" | sed -n \
    's/.*"'"$target_manifest_section"'"[[:space:]]*:[[:space:]]*{[^}]*"'"$target_manifest_key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [ -n "$target_manifest_value_result" ]; then
    printf '%s\n' "$target_manifest_value_result"
    return 0
  fi
  case $target_manifest_section:$target_manifest_key in
    profile:sha256) printf '%s' "$target_manifest_compact" | sed -n 's/.*"profile_sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' ;;
    progress:sha256) printf '%s' "$target_manifest_compact" | sed -n 's/.*"progress_sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' ;;
    pending:sha256) printf '%s' "$target_manifest_compact" | sed -n 's/.*"pending_sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' ;;
    profile:version) printf '%s' "$target_manifest_compact" | sed -n 's/.*"profile_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' ;;
    progress:version) printf '%s' "$target_manifest_compact" | sed -n 's/.*"progress_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' ;;
    *) return 1 ;;
  esac
}

target_manifest_field() {
  target_manifest_field_file=$1
  target_manifest_field_name=$2
  [ -f "$target_manifest_field_file" ] || return 1
  target_manifest_field_compact=$(tr -d '\r\n' < "$target_manifest_field_file")
  target_manifest_field_result=$(printf '%s' "$target_manifest_field_compact" | sed -n 's/.*"'"$target_manifest_field_name"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [ -n "$target_manifest_field_result" ]; then printf '%s\n' "$target_manifest_field_result"; return 0; fi
  printf '%s' "$target_manifest_field_compact" | sed -n 's/.*"'"$target_manifest_field_name"'"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p'
}

target_frontmatter_tokens() {
  tfm_file=$1
  shift
  [ -f "$tfm_file" ] || return 1
  tfm_keys=$(printf '%s|' "$@" | sed 's/|$//')
  # Target entities use ordinary YAML frontmatter.  A few early drafts used
  # Markdown-list metadata (`- key:`), so accept that prefix as a compatibility
  # form while keeping the key/value grammar identical.  If delimiters are
  # absent, parse the whole file for backwards-compatible fixtures.
  tr -d '\r' < "$tfm_file" | awk -v wanted="$tfm_keys" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function emit_scalar(value, quote) {
      value = trim(value)
      if (value == "") return
      # Strip an inline YAML comment only when it is separated by whitespace;
      # URI fragments and IDs containing # remain intact.
      sub(/[[:space:]]+#.*$/, "", value)
      value = trim(value)
      quote = sprintf("%c", 34)
      if (length(value) >= 2 && substr(value, 1, 1) == quote && substr(value, length(value), 1) == quote) {
        value = substr(value, 2, length(value) - 2)
      } else {
        quote = sprintf("%c", 39)
        if (length(value) >= 2 && substr(value, 1, 1) == quote && substr(value, length(value), 1) == quote) {
          value = substr(value, 2, length(value) - 2)
        } else if (length(value) >= 2 && substr(value, 1, 1) == "`" && substr(value, length(value), 1) == "`") {
          value = substr(value, 2, length(value) - 2)
        }
      }
      value = trim(value)
      if (value != "") print value
    }
    function emit_value(value, count, i, item, values) {
      value = trim(value)
      if (value == "") return
      # Inline YAML/JSON arrays and comma-separated scalar compatibility forms
      # both become one token per array member.
      if (substr(value, 1, 1) == "[" && substr(value, length(value), 1) == "]") {
        value = substr(value, 2, length(value) - 2)
      }
      if (index(value, ",") > 0) {
        count = split(value, values, ",")
        for (i = 1; i <= count; i++) emit_scalar(values[i])
      } else {
        emit_scalar(value)
      }
    }
    BEGIN {
      key_count = split(wanted, key_list, /\|/)
      has_frontmatter = 0
      in_frontmatter = 0
      active_key = ""
    }
    {
      line = $0
      # Treat only a leading delimiter as an opening marker.  A horizontal
      # rule in the body must not truncate metadata parsing.
      if (NR == 1 && line ~ /^[[:space:]]*---[[:space:]]*$/) {
        has_frontmatter = 1
        in_frontmatter = 1
        next
      }
      if (has_frontmatter && line ~ /^[[:space:]]*---[[:space:]]*$/) exit
      if (has_frontmatter && !in_frontmatter) next
      matched = 0
      for (i = 1; i <= key_count; i++) {
        prefix = "^[[:space:]]*-?[[:space:]]*" key_list[i] "[[:space:]]*:[[:space:]]*"
        if (line ~ prefix) {
          value = line
          sub(prefix, "", value)
          emit_value(value)
          active_key = key_list[i]
          if (trim(value) != "") active_key = ""
          matched = 1
          break
        }
      }
      if (matched) next
      # Also accept a conventional multiline YAML list (`key:` followed by
      # indented `- value`) for the array-valued metadata fields.
      if (active_key != "" && line ~ /^[[:space:]]+-[[:space:]]+/) {
        value = line
        sub(/^[[:space:]]+-[[:space:]]+/, "", value)
        emit_value(value)
        next
      }
      if (line !~ /^[[:space:]]*$/ && line !~ /^[[:space:]]*#/) active_key = ""
    }
  '
}

target_frontmatter_value() {
  target_frontmatter_tokens "$1" "$2" | head -n 1
}

target_frontmatter_array_json() {
  tfm_array_file=$1
  shift
  tfm_array_values=$(target_frontmatter_tokens "$tfm_array_file" "$@") || return 1
  tfm_array_json='['
  tfm_array_first=true
  tfm_array_seen=
  while IFS= read -r tfm_array_value; do
    [ -n "$tfm_array_value" ] || continue
    # Preserve source order while avoiding duplicate aliases such as a
    # `topic_id` repeated in `cross_topic_ids`.
    if [ -n "$tfm_array_seen" ] && printf '%s\n' "$tfm_array_seen" | grep -Fqx -- "$tfm_array_value"; then
      continue
    fi
    if [ "$tfm_array_first" = true ]; then
      tfm_array_first=false
    else
      tfm_array_json=$tfm_array_json,
    fi
    tfm_array_json=$tfm_array_json\"$(json_escape "$tfm_array_value")\"
    if [ -n "$tfm_array_seen" ]; then
      tfm_array_seen=$(printf '%s\n%s' "$tfm_array_seen" "$tfm_array_value")
    else
      tfm_array_seen=$tfm_array_value
    fi
  done <<EOF
$tfm_array_values
EOF
  printf '%s]\n' "$tfm_array_json"
}

update_target_marker_keys() {
  update_marker_root=$1
  shift
  update_marker_temp=$update_marker_root/.hello-state.$$.update
  update_marker_pairs=
  while [ "$#" -gt 1 ]; do
    update_marker_pairs="$update_marker_pairs|$1=$2"
    shift 2
  done
  tr -d '\r' < "$update_marker_root/.hello-state" | awk -v pairs="$update_marker_pairs" '
    BEGIN { n=split(pairs, a, "|"); for (i=1;i<=n;i++) { if (a[i]=="") continue; p=index(a[i], "="); if (p>1) { k=substr(a[i],1,p-1); v=substr(a[i],p+1); values[k]=v; order[++count]=k } } }
    /^$/ { print; next }
    /^#/ { print; next }
    { p=index($0,"="); if (p>1) { k=substr($0,1,p-1); if (k in values) { print k "=" values[k]; seen[k]=1; next } } print }
    END { for (i=1;i<=count;i++) { k=order[i]; if (!seen[k]) print k "=" values[k] } }
  ' > "$update_marker_temp" || { rm -f "$update_marker_temp"; return 1; }
  mv -f "$update_marker_temp" "$update_marker_root/.hello-state"
}

require_confirmed() {
  [ "$CONFIRMED" = true ] || fail 'Mutating commands require --confirmed after user authorization.'
}

release_store_lock() {
  # In Bash, a command-substitution subshell inherits shell variables and
  # traps but has a different BASHPID.  Only the shell that created the lock
  # may release it; an external `sh "$0" ...` child has no exported marker and
  # therefore still cleans up its own lock normally.  Native POSIX shells
  # without BASHPID retain the historical single-shell behavior.
  if [ "${BASH_SUBSHELL-0}" -gt 0 ] && [ -n "${STORE_LOCK_SHELL_ID-}" ] && [ -n "${BASHPID-}" ] && [ "${BASHPID}" != "$STORE_LOCK_SHELL_ID" ]; then
    return 0
  fi
  [ "${STORE_LOCK_HELD-}" = true ] || return 0
  STORE_LOCK_HELD=false
  # Never remove a lock that no longer carries this process's owner marker.
  if [ ! -e "$STORE_LOCK_PATH/owner" ] || { [ -f "$STORE_LOCK_PATH/owner" ] && [ "$(sed -n 's/^pid=//p' "$STORE_LOCK_PATH/owner" | head -n 1)" = "$STORE_LOCK_PID" ]; }; then
    rm -f "$STORE_LOCK_PATH/owner" 2>/dev/null || true
    rmdir "$STORE_LOCK_PATH" 2>/dev/null || true
  fi
}

release_extra_locks() {
  if [ "${BASH_SUBSHELL-0}" -gt 0 ] && [ -n "${STORE_LOCK_SHELL_ID-}" ] && [ -n "${BASHPID-}" ] && [ "${BASHPID}" != "$STORE_LOCK_SHELL_ID" ]; then
    return 0
  fi
  # Secondary roots are tab-delimited explicit paths; tabs are not valid in
  # the CLI path grammar used by the adapters. Cleanup only removes an owner
  # marker bearing this PID.
  printf '%s\n' "$EXTRA_LOCK_PATHS" | tr '\t' '\n' | while IFS= read -r extra_path; do
    [ -n "$extra_path" ] || continue
    extra_lock=$extra_path/.hello-lock
    if [ ! -e "$extra_lock/owner" ] || { [ -f "$extra_lock/owner" ] && [ "$(sed -n 's/^pid=//p' "$extra_lock/owner" | head -n 1)" = "$$" ]; }; then
      rm -f "$extra_lock/owner" 2>/dev/null || true
      rmdir "$extra_lock" 2>/dev/null || true
    fi
  done
}

acquire_extra_lock() {
  extra_root=$1
  [ -d "$extra_root" ] || return 0
  [ "$extra_root" = "$ROOT" ] && return 0
  extra_lock=$extra_root/.hello-lock
  if ! mkdir "$extra_lock" 2>/dev/null; then
    fail 'Profile space is busy; retry after the active operation finishes.'
  fi
  extra_started=$(utc_now)
  extra_owner_temp=$(mktemp "$extra_lock/.owner.XXXXXX") || { rmdir "$extra_lock" 2>/dev/null || true; fail 'Cannot create profile lock owner.'; }
  if ! printf 'pid=%s\nstarted_at=%s\n' "$$" "$extra_started" > "$extra_owner_temp"; then
    rm -f "$extra_owner_temp" 2>/dev/null || true
    rmdir "$extra_lock" 2>/dev/null || true
    fail 'Cannot write profile lock owner.'
  fi
  mv "$extra_owner_temp" "$extra_lock/owner" || { rm -f "$extra_owner_temp" 2>/dev/null || true; rmdir "$extra_lock" 2>/dev/null || true; fail 'Cannot finalize profile lock owner.'; }
  if [ -n "$EXTRA_LOCK_PATHS" ]; then EXTRA_LOCK_PATHS=$(printf '%s\t%s' "$EXTRA_LOCK_PATHS" "$extra_root"); else EXTRA_LOCK_PATHS=$extra_root; fi
  trap 'release_store_lock; release_extra_locks' 0 1 2 3 15
}

acquire_store_lock() {
  [ -d "$ROOT" ] || return 0
  STORE_LOCK_PATH=$ROOT/.hello-lock
  STORE_LOCK_PID=$$
  STORE_LOCK_SHELL_ID=${BASHPID-}
  if ! mkdir "$STORE_LOCK_PATH" 2>/dev/null; then
    fail 'Profile space is busy; retry after the active operation finishes.'
  fi
  STORE_LOCK_HELD=true
  trap 'release_store_lock; release_extra_locks' 0 1 2 3 15
  lock_started=$(utc_now)
  lock_owner_temp=$(mktemp "$STORE_LOCK_PATH/.owner.XXXXXX") || { release_store_lock; fail 'Cannot create profile lock owner.'; }
  if ! printf 'pid=%s\nstarted_at=%s\n' "$STORE_LOCK_PID" "$lock_started" > "$lock_owner_temp"; then
    rm -f "$lock_owner_temp" 2>/dev/null || true
    release_store_lock
    fail 'Cannot write profile lock owner.'
  fi
  mv -f "$lock_owner_temp" "$STORE_LOCK_PATH/owner" || {
    rm -f "$lock_owner_temp" 2>/dev/null || true
    release_store_lock
    fail 'Cannot finalize profile lock owner.'
  }
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || fail 'Cannot resolve script directory.'
TEMPLATE_DIR=$SCRIPT_DIR/../assets/profile-templates

validate_state_file_syntax() {
  # Keep comment/blank-line recognition identical to Python and PowerShell:
  # only an actually empty line or a line whose first byte is `#` is ignored.
  # Keys are compared case-insensitively for duplicate detection across all
  # adapters; otherwise a case variant of a reserved key would be ambiguous.
  tr -d '\r' < "$1" | awk '
    /^$/ || /^#/ { next }
    {
      separator = index($0, "=")
      if (separator < 2) exit 1
      key = substr($0, 1, separator - 1)
      normalized = tolower(key)
      if (seen[normalized]++) exit 1
    }
  '
}

state_value() {
  tr -d '\r' < "$1" | awk -v wanted="$2" '
    /^$/ || /^#/ { next }
    {
      separator = index($0, "=")
      if (separator < 2) { invalid = 1; next }
      key = substr($0, 1, separator - 1)
      normalized = tolower(key)
      if (key == wanted) { count++; value = substr($0, separator + 1) }
      if (seen[normalized]++) { duplicate = 1 }
    }
    END {
      if (invalid) exit 2
      if (duplicate) exit 2
      if (count != 1) exit 1
      print value
    }
  '
}

# A malformed transaction marker must never be interpreted as an absent
# optional field.  Validate the whole marker before individual lookups so
# duplicate keys and stray lines fail closed like the Python/PowerShell
# adapters.
validate_marker_syntax() {
  tr -d '\r' < "$1" | awk '
    /^$/ || /^#/ { next }
    {
      separator = index($0, "=")
      if (separator < 2) exit 1
      key = substr($0, 1, separator - 1)
      normalized = tolower(key)
      if (seen[normalized]++) exit 1
    }
  '
}

# A transaction marker is a typed recovery record.  Do not treat required
# backup fields as optional: restoring an incomplete marker could silently
# commit only part of the interrupted operation.  This check runs before any
# target is copied and leaves the marker untouched on failure.
validate_transaction_requirements() {
  marker=$1
  marker_schema=$(state_value "$marker" schema_version) || return 1
  [ "$marker_schema" = 1 ] || return 1
  marker_kind=$(state_value "$marker" kind) || return 1
  case $marker_kind in
    apply) required_fields='profile_backup log_backup state_backup' ;;
    record-turn) required_fields='progress_backup state_backup record_path record_created' ;;
    *) return 1 ;;
  esac
  for required_field in $required_fields; do
    required_value=$(state_value "$marker" "$required_field") || return 1
    [ -n "$required_value" ] || return 1
    if [ "$required_field" = record_created ]; then
      case $required_value in true|false) ;; *) return 1 ;; esac
    fi
  done
  return 0
}

# Return the first actionable state-file parse error without writing anything
# to the command's output stream.  `read_state` captures this text and
# `validate`/`status` expose it as an issue; transaction-marker callers keep
# using the silent validator above.
state_parse_error() {
  state_file_name=$(basename "$1")
  tr -d '\r' < "$1" | awk -v file="$state_file_name" '
    /^$/ || /^#/ { next }
    {
      separator = index($0, "=")
      if (separator < 2) {
        printf "Invalid key=value line %d in %s.", NR, file
        exit
      }
      key = substr($0, 1, separator - 1)
      normalized = tolower(key)
      if (seen[normalized]++) {
        printf "Invalid or duplicate key on line %d in %s.", NR, file
        exit
      }
    }
  '
}

read_required_state_value() {
  STATE_REQUIRED_VALUE=$(state_value "$1" "$2") || {
    STATE_PARSE_ERROR="Missing state key: $2"
    return 1
  }
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
  state_interview=${1-}
  state_progress=${2-1}
  state_session=${3-}
  state_turn=${4-}
  state_disclosed=${5-}
  state_disclosed_mode=${6-}
  state_interview_present=false
  state_progress_present=false
  state_session_present=false
  state_turn_present=false
  state_disclosed_present=false
  state_disclosed_mode_present=false
  if [ -f "$state_path" ]; then
    tr -d '\r' < "$state_path" | grep -q '^last_interview_at=' && state_interview_present=true || true
    tr -d '\r' < "$state_path" | grep -q '^progress_version=' && state_progress_present=true || true
    tr -d '\r' < "$state_path" | grep -q '^last_session_id=' && state_session_present=true || true
    tr -d '\r' < "$state_path" | grep -q '^last_turn_id=' && state_turn_present=true || true
    tr -d '\r' < "$state_path" | grep -q '^last_capture_disclosed_at=' && state_disclosed_present=true || true
    tr -d '\r' < "$state_path" | grep -q '^last_capture_disclosed_mode=' && state_disclosed_mode_present=true || true
  fi
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
    if [ "$state_schema" = 2 ] || [ "$state_schema" = 3 ] || [ "$state_interview_present" = true ] || [ -n "$state_interview" ]; then
      printf 'last_interview_at=%s\n' "$state_interview"
    fi
    if [ "$state_schema" = 2 ] || [ "$state_schema" = 3 ] || [ "$state_progress_present" = true ]; then printf 'progress_version=%s\n' "$state_progress"; fi
    if [ "$state_schema" = 2 ] || [ "$state_schema" = 3 ] || [ "$state_session_present" = true ]; then printf 'last_session_id=%s\n' "$state_session"; fi
    if [ "$state_schema" = 2 ] || [ "$state_schema" = 3 ] || [ "$state_turn_present" = true ]; then printf 'last_turn_id=%s\n' "$state_turn"; fi
    if [ "$state_schema" = 2 ] || [ "$state_schema" = 3 ] || [ "$state_disclosed_present" = true ] || [ -n "${state_disclosed-}" ]; then
      printf 'last_capture_disclosed_at=%s\n' "${state_disclosed-}"
    fi
    if [ "$state_schema" = 2 ] || [ "$state_schema" = 3 ] || [ "$state_disclosed_mode_present" = true ] || [ -n "${state_disclosed_mode-}" ]; then
      printf 'last_capture_disclosed_mode=%s\n' "${state_disclosed_mode-}"
    fi
    if [ -f "$state_path" ]; then
      tr -d '\r' < "$state_path" | awk -F= '
        BEGIN { reserved["schema_version"]=1; reserved["profile_version"]=1; reserved["capture_mode"]=1; reserved["created_at"]=1; reserved["updated_at"]=1; reserved["last_confirmed_at"]=1; reserved["next_review_at"]=1; reserved["review_stage"]=1; reserved["last_interview_at"]=1; reserved["progress_version"]=1; reserved["last_session_id"]=1; reserved["last_turn_id"]=1; reserved["last_capture_disclosed_at"]=1; reserved["last_capture_disclosed_mode"]=1 }
        { key=tolower($1); if (!reserved[key]) print }
      '
    fi
  } > "$state_temp" || { rm -f "$state_temp"; return 1; }
  mv -f "$state_temp" "$state_path" || { rm -f "$state_temp"; return 1; }
}

read_state() {
  state_path=$ROOT/.hello-state
  STATE_PARSE_ERROR=
  parse_issue=$(state_parse_error "$state_path")
  if [ -n "$parse_issue" ]; then
    STATE_PARSE_ERROR=$parse_issue
    return 1
  fi
  validate_state_file_syntax "$state_path" || return 1
  read_required_state_value "$state_path" schema_version || return 1; STATE_SCHEMA=$STATE_REQUIRED_VALUE
  read_required_state_value "$state_path" profile_version || return 1; STATE_VERSION=$STATE_REQUIRED_VALUE
  read_required_state_value "$state_path" capture_mode || return 1; STATE_CAPTURE=$STATE_REQUIRED_VALUE
  read_required_state_value "$state_path" created_at || return 1; STATE_CREATED=$STATE_REQUIRED_VALUE
  read_required_state_value "$state_path" updated_at || return 1; STATE_UPDATED=$STATE_REQUIRED_VALUE
  read_required_state_value "$state_path" last_confirmed_at || return 1; STATE_CONFIRMED=$STATE_REQUIRED_VALUE
  read_required_state_value "$state_path" next_review_at || return 1; STATE_REVIEW=$STATE_REQUIRED_VALUE
  read_required_state_value "$state_path" review_stage || return 1; STATE_STAGE=$STATE_REQUIRED_VALUE
  STATE_INTERVIEW=$(state_value "$state_path" last_interview_at) || STATE_INTERVIEW=
  STATE_PROGRESS_PRESENT=true; STATE_PROGRESS=$(state_value "$state_path" progress_version) || { STATE_PROGRESS_PRESENT=false; STATE_PROGRESS=1; }
  if [ "$STATE_PROGRESS_PRESENT" = false ] && [ -f "$ROOT/访谈进度.md" ]; then
    legacy_progress=$(tr -d '\r' < "$ROOT/访谈进度.md" | sed -n 's/^- 进度版本：\([1-9][0-9]*\)$/\1/p' | head -n 1)
    if is_positive_decimal "$legacy_progress"; then STATE_PROGRESS=$legacy_progress; fi
  fi
  STATE_SESSION_PRESENT=true; STATE_SESSION=$(state_value "$state_path" last_session_id) || { STATE_SESSION_PRESENT=false; STATE_SESSION=; }
  STATE_TURN_PRESENT=true; STATE_TURN=$(state_value "$state_path" last_turn_id) || { STATE_TURN_PRESENT=false; STATE_TURN=; }
  STATE_DISCLOSED=$(state_value "$state_path" last_capture_disclosed_at) || STATE_DISCLOSED=
  STATE_DISCLOSED_MODE=$(state_value "$state_path" last_capture_disclosed_mode) || STATE_DISCLOSED_MODE=
  return 0
}

validate_log_versions() {
  log_path=$1
  LOG_DUPLICATE=false
  LOG_DESCENDING=false
  log_versions=$(tr -d '\r' < "$log_path" | sed -n 's/^## R\([1-9][0-9]*\) · .*/\1/p')
  log_previous=
  log_seen=
  while IFS= read -r log_version; do
    [ -n "$log_version" ] || continue
    case "|$log_seen|" in *"|$log_version|"*) LOG_DUPLICATE=true ;; esac
    if [ -n "$log_previous" ]; then
      decimal_compare "$log_version" "$log_previous"
      log_comparison=$?
      [ "$log_comparison" -eq 1 ] && LOG_DESCENDING=true
    fi
    log_seen=${log_seen}${log_version}'|'
    log_previous=$log_version
  done <<EOF
$log_versions
EOF
}

validate_space() {
  allow_transaction=${1-false}
  VALIDATION_ISSUES=
  VALIDATION_ISSUES_JSON=[]
  add_issue() {
    validation_issue=$1
    if [ -n "$VALIDATION_ISSUES" ]; then
      VALIDATION_ISSUES="$VALIDATION_ISSUES; $validation_issue"
    else
      VALIDATION_ISSUES=$validation_issue
    fi
    validation_issue_json=$(json_escape "$validation_issue")
    if [ "$VALIDATION_ISSUES_JSON" = '[]' ]; then
      VALIDATION_ISSUES_JSON="[\"$validation_issue_json\"]"
    else
      VALIDATION_ISSUES_JSON="${VALIDATION_ISSUES_JSON%]},\"$validation_issue_json\"]"
    fi
  }
  [ -d "$ROOT" ] || add_issue 'Root directory does not exist'
  # Once a formal target layout is active, validate its own package contract
  # instead of applying the legacy schema-2 heading checks to the aggregate
  # index.  The compatibility root files remain available to record-turn,
  # stage, and withdraw, while target-specific integrity is checked here.
  if [ -d "$ROOT" ] && [ -f "$ROOT/.hello-state" ] && grep -q '^layout=target$' "$ROOT/.hello-state" 2>/dev/null; then
    if validate_target_space "$ROOT"; then
      VALIDATION_ISSUES=
      VALIDATION_ISSUES_JSON=[]
      return 0
    fi
    VALIDATION_ISSUES=${TARGET_VALIDATION_ISSUES-Invalid target profile space}
    VALIDATION_ISSUES_JSON=${TARGET_VALIDATION_ISSUES_JSON-'["Invalid target profile space"]'}
    return 1
  fi
  if [ -d "$ROOT" ]; then
    for name in README.md 个人全景档案.md 待确认信息.md 访谈进度.md 资料索引.md 迭代日志.md; do
      [ -f "$ROOT/$name" ] || add_issue "Missing file: $name"
    done
    for name in 原始访谈 历史版本 .backups .trash; do
      [ -d "$ROOT/$name" ] || add_issue "Missing directory: $name"
    done
    [ "$allow_transaction" = true ] || [ ! -e "$ROOT/.hello-transaction" ] || add_issue 'Unfinished transaction; run recover --confirmed --root <authorized-root>.'
    if [ ! -f "$ROOT/.hello-state" ]; then
      add_issue 'Missing file: .hello-state'
    elif ! read_state; then
      add_issue "${STATE_PARSE_ERROR:-Invalid state file}"
    else
      case $STATE_SCHEMA in 1|2) ;; *) add_issue 'schema_version must be 1 or 2' ;; esac
      if [ "$STATE_SCHEMA" = 2 ]; then
        [ "$STATE_PROGRESS_PRESENT" = true ] || add_issue 'Missing state key: progress_version'
        [ "$STATE_SESSION_PRESENT" = true ] || add_issue 'Missing state key: last_session_id'
        [ "$STATE_TURN_PRESENT" = true ] || add_issue 'Missing state key: last_turn_id'
      fi
      is_positive_decimal "$STATE_VERSION" || add_issue 'profile_version must be a positive integer'
      is_positive_decimal "$STATE_PROGRESS" || add_issue 'progress_version must be a positive integer'
      case $STATE_CAPTURE in auto-stage|prompt|explicit) ;; *) add_issue 'invalid capture_mode' ;; esac
      case $STATE_STAGE in baseline|first-review|stable) ;; *) add_issue 'invalid review_stage' ;; esac
      [ "$STATE_STAGE" != first-review ] || [ -n "$STATE_REVIEW" ] || add_issue 'first-review requires next_review_at'
      is_iso_utc "$STATE_CREATED" || add_issue 'created_at must be ISO 8601 UTC'
      is_iso_utc "$STATE_UPDATED" || add_issue 'updated_at must be ISO 8601 UTC'
      [ -z "$STATE_CONFIRMED" ] || is_iso_utc "$STATE_CONFIRMED" || add_issue 'last_confirmed_at must be empty or ISO 8601 UTC'
      [ -z "$STATE_REVIEW" ] || is_iso_utc "$STATE_REVIEW" || add_issue 'next_review_at must be empty or ISO 8601 UTC'
      [ -z "$STATE_INTERVIEW" ] || is_iso_utc "$STATE_INTERVIEW" || add_issue 'last_interview_at must be empty or ISO 8601 UTC'
      [ -z "$STATE_DISCLOSED" ] || is_iso_utc "$STATE_DISCLOSED" || add_issue 'last_capture_disclosed_at must be empty or ISO 8601 UTC'
      case $STATE_DISCLOSED_MODE in ''|auto-stage|prompt|explicit) ;; *) add_issue 'last_capture_disclosed_mode must be empty or a capture mode' ;; esac
      profile=$ROOT/个人全景档案.md
      progress=$ROOT/访谈进度.md
      pending=$ROOT/待确认信息.md
      log=$ROOT/迭代日志.md
      if [ -f "$profile" ]; then
        [ "$(tr -d '\r' < "$profile" | sed -n '1p')" = '# 个人全景档案' ] || add_issue 'Profile must start with # 个人全景档案'
        profile_versions=$(tr -d '\r' < "$profile" | grep -Ec '^- 资料版本：[1-9][0-9]*$' || true)
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
        progress_header_count=$(tr -d '\r' < "$progress" | grep -Ec '^- 进度版本：' || true)
        progress_versions=$(tr -d '\r' < "$progress" | grep -Ec '^- 进度版本：[1-9][0-9]*$' || true)
        if [ "$progress_header_count" -gt 1 ]; then
          add_issue '进度版本 metadata must appear at most once'
        elif [ "$progress_header_count" -eq 1 ] && [ "$progress_versions" -eq 0 ]; then
          add_issue '进度版本 metadata must be a positive integer'
        fi
        if [ "$STATE_SCHEMA" = 2 ]; then
          [ "$progress_versions" -eq 1 ] || add_issue 'Missing or duplicate 进度版本 metadata'
          [ "$(tr -d '\r' < "$progress" | sed -n 's/^- 进度版本：\([0-9][0-9]*\)$/\1/p')" = "$STATE_PROGRESS" ] || add_issue 'Progress version does not match state version'
        else
          [ "$progress_versions" -le 1 ] || add_issue '进度版本 metadata must appear at most once'
        fi
        if [ "$progress_versions" -eq 1 ]; then
          legacy_progress_value=$(tr -d '\r' < "$progress" | sed -n 's/^- 进度版本：\([0-9][0-9]*\)$/\1/p')
          is_positive_decimal "$legacy_progress_value" || add_issue '进度版本 metadata must be positive'
        fi
      fi
      if [ -f "$pending" ]; then
        duplicates=$(tr -d '\r' < "$pending" | sed -n 's/^## \(C-[0-9TZ-][0-9TZ-]*\)$/\1/p' | sort | uniq -d)
        [ -z "$duplicates" ] || add_issue 'Pending candidates contain duplicate ids'
      fi
      if [ -f "$log" ] && is_positive_decimal "$STATE_VERSION" && [ "$STATE_VERSION" != 1 ]; then
        grep -q "^## R$STATE_VERSION · " "$log" || add_issue 'Iteration log does not contain the current profile version'
      fi
      if [ -f "$log" ]; then
        validate_log_versions "$log"
        if [ "$LOG_DUPLICATE" = true ]; then
          add_issue 'Iteration log contains duplicate version headings'
        fi
        if [ "$LOG_DESCENDING" = true ]; then
          add_issue 'Iteration log versions must be ascending'
        fi
      fi
    fi
  fi
  VALIDATION_ISSUES=$(printf '%s' "$VALIDATION_ISSUES" | sed 's/^; //')
  [ -z "$VALIDATION_ISSUES" ]
}

require_valid() {
  validate_space || fail "Invalid profile space: $VALIDATION_ISSUES"
  # A formal target keeps the compatibility cursor in its schema-3 marker.
  # `validate_space` intentionally validates the target package without
  # populating the legacy STATE_* variables, so load that marker before any
  # compatibility bridge (configure/stage/record-turn/withdraw) uses them.
  if [ -f "$ROOT/.hello-state" ] && grep -q '^layout=target$' "$ROOT/.hello-state" 2>/dev/null; then
    read_state || fail "Invalid target compatibility state: ${STATE_PARSE_ERROR:-cannot parse .hello-state}"
  fi
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
    state_disclosed=
    write_state "$ROOT/.hello-state" 2 1 prompt "$current" "$current" '' '' baseline '' 1 '' '' '' '' || fail 'Cannot write state file.'
    add_created .hello-state
  fi
  printf '{"ok":true,"command":"init","root":"%s","created":[%s]}\n' "$(json_escape "$ROOT")" "$created_json"
}

target_status_space() {
  if ! validate_target_space "$ROOT"; then
    printf '{"ok":false,"command":"status","root":"%s","layout":"target","issues":%s}\n' "$(json_escape "$ROOT")" "${TARGET_VALIDATION_ISSUES_JSON-[\"Invalid target profile space\"]}"
    exit 1
  fi
  marker=$ROOT/.hello-state
  target_layout=$(target_marker_value "$marker" layout)
  target_migration=$(target_marker_value "$marker" migration_id)
  target_package=$(target_marker_value "$marker" package_id)
  target_subject=$(target_marker_value "$marker" subject_id)
  # Target roots use the same progress/pending projections as the compatibility
  # adapter, so status remains useful immediately after a layout switch.
  pending=0
  [ -f "$ROOT/待确认信息.md" ] && pending=$(grep -c '^## C-[0-9TZ-][0-9TZ-]*[[:space:]]*$' "$ROOT/待确认信息.md" 2>/dev/null || true)
  progress_stage=
  progress_last=
  progress_next=
  # Target status is metadata-only; never expose the interview's next
  # question (or other progress body text) in an implicit status probe.
  progress_next=
  progress_stage='目标资料包'
  # read_state is deliberately used only after target validation; schema 3
  # keeps the legacy cursor keys so record-turn can continue across the switch.
  read_state || fail "Invalid target state: ${STATE_PARSE_ERROR:-cannot parse .hello-state}"
  case $STATE_CAPTURE in auto-stage) capture_strategy=自动暂存 ;; prompt) capture_strategy=提示确认 ;; explicit) capture_strategy=仅显式 ;; *) capture_strategy= ;; esac
  [ -n "$progress_stage" ] || case $STATE_STAGE in baseline) progress_stage=基线访谈 ;; first-review) progress_stage=首次回访 ;; stable) progress_stage=稳定维护 ;; esac
  progress_last=$STATE_INTERVIEW
  # Target coverage is owned by the matrix, not by the compatibility
  # progress projection.  Parse only topic IDs, priority and state so status
  # remains metadata-only and agrees with the Python/PowerShell adapters.
  baseline_json='[]'; long_json='[]'; baseline_split_unknown=true; baseline_blocked=true
  matrix_path=$ROOT/主题覆盖矩阵.md
  if [ -f "$matrix_path" ]; then
    matrix_result=$(tr -d '\r' < "$matrix_path" | awk -F'|' '
      function clean(v){gsub(/[[:space:]`]/,"",v); return v}
      function add(which,id,state,    escaped){gsub(/\\/,"\\\\",id); gsub(/"/,"\\\"",id); escaped=id "（" state "）"; if(which=="b"){if(bfirst){b="[\"" escaped "\""; bfirst=0}else{b=b ",\"" escaped "\""}} else {if(lfirst){l="[\"" escaped "\""; lfirst=0}else{l=l ",\"" escaped "\""}}}
      BEGIN{b="[";l="[";bfirst=1;lfirst=1;found=0}
      /^\|/ {
        id=clean($2); priority=clean($4); state=clean($5)
        if(id=="" || id=="主题ID" || id=="topic_id" || id ~ /^[-:]+$/){next}
        if(priority=="基线必答" || priority=="baseline" || priority=="基线"){found=1; if(state!="confirmed_minimum" && state!="deepened" && state!="declined" && state!="not_applicable") add("b",id,state)}
        else if(priority=="可长期补充" || priority=="long-term" || priority=="long"){found=1; if(state!="confirmed_minimum" && state!="deepened" && state!="declined" && state!="not_applicable") add("l",id,state)}
      }
      END{print b "]\t" l "]\t" (found ? "false" : "true")}
    ')
    baseline_json=${matrix_result%%$'\t'*}; matrix_rest=${matrix_result#*$'\t'}
    long_json=${matrix_rest%%$'\t'*}; baseline_split_unknown=${matrix_rest#*$'\t'}
  fi
  if [ "$baseline_split_unknown" = true ]; then
    baseline_json='["legacy-unclassified（需先完成基线/长期分组）"]'
  fi
  authority_status=$(target_marker_value "$ROOT/.hello-state" authority_status) || authority_status=
  case $authority_status in
    non-authoritative-needs-user-confirmation|active-layout-needs-review)
      if [ "$baseline_json" = '[]' ]; then baseline_json='["migration-review（需用户确认目录化切换）"]'; else baseline_json="${baseline_json%]},\"migration-review（需用户确认目录化切换）\"]"; fi
      ;;
  esac
  [ "$baseline_json" = '[]' ] && [ "$baseline_split_unknown" = false ] && baseline_blocked=false
  authority_entry_count=0
  [ -d "$ROOT/权威" ] && authority_entry_count=$(find "$ROOT/权威" -type f -name '*.md' ! -name 'README.md' -print 2>/dev/null | wc -l | tr -d '[:space:]')
  file_count=0
  [ -d "$ROOT" ] && file_count=$(find "$ROOT" -type f -print 2>/dev/null | wc -l | tr -d '[:space:]')
  printf '{"ok":true,"command":"status","root":"%s","layout":"%s","layout_version":"1","schema_version":"3","migration_id":"%s","package_id":"%s","subject_id":"%s","profile_version":"%s","progress_version":"%s","capture_mode":"%s","capture_strategy":"%s","last_capture_disclosed_at":"%s","last_capture_disclosed_mode":"%s","review_stage":"%s","last_confirmed_at":"%s","next_review_at":"%s","last_session_id":"%s","last_turn_id":"%s","pending_candidates":%s,"authority_entry_count":%s,"file_count":%s,"baseline_required_remaining":%s,"baseline_closure_blocked":%s,"baseline_split_unknown":%s,"long_term_backlog":%s,"progress":{"current_stage":"%s","last_interview_at":"%s","next_question":"%s"}}\n' \
    "$(json_escape "$ROOT")" "$(json_escape "$target_layout")" "$(json_escape "$target_migration")" "$(json_escape "$target_package")" "$(json_escape "$target_subject")" "$STATE_VERSION" "$STATE_PROGRESS" "$(json_escape "$STATE_CAPTURE")" "$(json_escape "$capture_strategy")" "$(json_escape "$STATE_DISCLOSED")" "$(json_escape "$STATE_DISCLOSED_MODE")" "$(json_escape "$STATE_STAGE")" "$(json_escape "$STATE_CONFIRMED")" "$(json_escape "$STATE_REVIEW")" "$(json_escape "$STATE_SESSION")" "$(json_escape "$STATE_TURN")" "$pending" "$authority_entry_count" "$file_count" "$baseline_json" "$baseline_blocked" "$baseline_split_unknown" "$long_json" "$(json_escape "$progress_stage")" "$(json_escape "$progress_last")" "$(json_escape "$progress_next")"
}

status_space() {
  if [ -f "$ROOT/.hello-state" ] && grep -q '^layout=target$' "$ROOT/.hello-state" 2>/dev/null; then
    target_status_space
    return
  fi
  if ! validate_space; then
    printf '{"ok":false,"command":"status","root":"%s","issues":%s}\n' "$(json_escape "$ROOT")" "$VALIDATION_ISSUES_JSON"
    exit 1
  fi
  pending=$(grep -c '^## C-[0-9TZ-][0-9TZ-]*[[:space:]]*$' "$ROOT/待确认信息.md" 2>/dev/null || true)
  progress_stage=$(tr -d '\r' < "$ROOT/访谈进度.md" | sed -n 's/^- 当前阶段：//p' | head -n 1)
  progress_last=$(tr -d '\r' < "$ROOT/访谈进度.md" | sed -n 's/^- 最近正式访谈时间：//p' | head -n 1)
  progress_next=$(tr -d '\r' < "$ROOT/访谈进度.md" | awk 'BEGIN{inside=0} /^## 下次问题[[:space:]]*$/{inside=1; next} /^## /{if(inside) exit} inside && NF{print; exit}')
  baseline_json=$(tr -d '\r' < "$ROOT/访谈进度.md" | awk 'BEGIN{b=0;first=1;out="["} /^### 基线必答（阻塞基线收口）/{b=1;next} /^### |^## /{if(b) exit} b && /^- /{v=substr($0,3); gsub(/\\/,"\\\\",v); gsub(/"/,"\\\"",v); if(!first) out=out ","; out=out "\"" v "\""; first=0} END{print out "]"}')
  long_json=$(tr -d '\r' < "$ROOT/访谈进度.md" | awk 'BEGIN{b=0;first=1;out="["} /^### 可长期补充（不阻塞基线收口）/{b=1;next} /^### |^## /{if(b) exit} b && /^- /{v=substr($0,3); gsub(/\\/,"\\\\",v); gsub(/"/,"\\\"",v); if(!first) out=out ","; out=out "\"" v "\""; first=0} END{print out "]"}')
  baseline_split_unknown=false
  [ "$STATE_SCHEMA" = 2 ] || baseline_split_unknown=true
  for bucket_heading in '### 基线必答（阻塞基线收口）' '### 可长期补充（不阻塞基线收口）'; do
    [ "$(tr -d '\r' < "$ROOT/访谈进度.md" | grep -Fxc "$bucket_heading" || true)" -eq 1 ] || baseline_split_unknown=true
  done
  if [ "$baseline_split_unknown" = true ]; then
    baseline_json='["legacy-unclassified（需先完成基线/长期分组）"]'
  fi
  baseline_blocked=true; [ "$baseline_json" = '[]' ] && [ "$baseline_split_unknown" = false ] && baseline_blocked=false
  case $STATE_CAPTURE in auto-stage) capture_strategy=自动暂存 ;; prompt) capture_strategy=提示确认 ;; explicit) capture_strategy=仅显式 ;; esac
  [ -n "$progress_stage" ] || case $STATE_STAGE in baseline) progress_stage=基线访谈 ;; first-review) progress_stage=首次回访 ;; stable) progress_stage=稳定维护 ;; esac
  [ -n "$progress_last" ] || progress_last=$STATE_INTERVIEW
  [ -n "$progress_last" ] || [ -z "$STATE_TURN" ] || progress_last=$STATE_UPDATED
  printf '{"ok":true,"command":"status","root":"%s","profile_version":"%s","progress_version":"%s","capture_mode":"%s","capture_strategy":"%s","last_capture_disclosed_at":"%s","last_capture_disclosed_mode":"%s","review_stage":"%s","last_confirmed_at":"%s","next_review_at":"%s","last_session_id":"%s","last_turn_id":"%s","pending_candidates":%s,"baseline_required_remaining":%s,"baseline_closure_blocked":%s,"baseline_split_unknown":%s,"long_term_backlog":%s,"progress":{"current_stage":"%s","last_interview_at":"%s","next_question":"%s"}}\n' \
    "$(json_escape "$ROOT")" "$STATE_VERSION" "$STATE_PROGRESS" "$(json_escape "$STATE_CAPTURE")" "$(json_escape "$capture_strategy")" "$(json_escape "$STATE_DISCLOSED")" \
    "$(json_escape "$STATE_DISCLOSED_MODE")" "$(json_escape "$STATE_STAGE")" "$(json_escape "$STATE_CONFIRMED")" "$(json_escape "$STATE_REVIEW")" "$(json_escape "$STATE_SESSION")" "$(json_escape "$STATE_TURN")" "$pending" "$baseline_json" "$baseline_blocked" "$baseline_split_unknown" "$long_json" \
    "$(json_escape "$progress_stage")" "$(json_escape "$progress_last")" "$(json_escape "$progress_next")"
}

configure_space() {
  require_confirmed
  require_valid
  [ "$CAPTURE_MODE_SET" = true ] || [ "$NEXT_REVIEW_AT_SET" = true ] || [ "$REVIEW_STAGE_SET" = true ] || fail 'configure requires at least one setting.'
  new_capture=$STATE_CAPTURE
  new_review=$STATE_REVIEW
  new_stage=$STATE_STAGE
  if [ "$CAPTURE_MODE_SET" = true ]; then
    case $CAPTURE_MODE in auto-stage|prompt|explicit) new_capture=$CAPTURE_MODE ;; *) fail '--capture-mode must be auto-stage, prompt, or explicit.' ;; esac
  fi
  if [ "$REVIEW_STAGE_SET" = true ]; then
    case $REVIEW_STAGE in baseline|first-review|stable) new_stage=$REVIEW_STAGE ;; *) fail '--review-stage must be baseline, first-review, or stable.' ;; esac
  fi
  if [ "$NEXT_REVIEW_AT_SET" = true ]; then
    if [ "$NEXT_REVIEW_AT" = none ] || [ -z "$NEXT_REVIEW_AT" ]; then
      new_review=
    else
      is_iso_utc "$NEXT_REVIEW_AT" || fail '--next-review-at must be ISO 8601 UTC or none.'
      new_review=$NEXT_REVIEW_AT
    fi
  fi
  if [ "$new_stage" = first-review ] && [ -z "$new_review" ]; then
    fail 'first-review requires --next-review-at.'
  fi
  current=$(utc_now)
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$new_capture" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$new_review" "$new_stage" "$STATE_INTERVIEW" "$STATE_PROGRESS" "$STATE_SESSION" "$STATE_TURN" "$STATE_DISCLOSED" "$STATE_DISCLOSED_MODE" || fail 'Cannot write state file.'
  printf '{"ok":true,"command":"configure","root":"%s","capture_mode":"%s","review_stage":"%s","next_review_at":"%s"}\n' \
    "$(json_escape "$ROOT")" "$new_capture" "$new_stage" "$(json_escape "$new_review")"
}

record_disclosure() {
  require_confirmed
  require_valid
  if [ "$CAPTURE_MODE_SET" = true ]; then
    case $CAPTURE_MODE in auto-stage|prompt|explicit) ;; *) fail '--capture-mode must be auto-stage, prompt, or explicit.' ;; esac
    [ "$CAPTURE_MODE" = "$STATE_CAPTURE" ] || fail '--capture-mode does not match the current capture policy.'
  fi
  current=$(utc_now)
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$STATE_REVIEW" "$STATE_STAGE" "$STATE_INTERVIEW" "$STATE_PROGRESS" "$STATE_SESSION" "$STATE_TURN" "$current" "$STATE_CAPTURE" || fail 'Cannot write state file.'
  case $STATE_CAPTURE in auto-stage) capture_strategy=自动暂存 ;; prompt) capture_strategy=提示确认 ;; explicit) capture_strategy=仅显式 ;; esac
  printf '{"ok":true,"command":"record-disclosure","root":"%s","capture_mode":"%s","capture_strategy":"%s","last_capture_disclosed_at":"%s","last_capture_disclosed_mode":"%s"}\n' \
    "$(json_escape "$ROOT")" "$(json_escape "$STATE_CAPTURE")" "$(json_escape "$capture_strategy")" "$(json_escape "$current")" "$(json_escape "$STATE_CAPTURE")"
}

clean_label() {
  # Match Python/PowerShell: collapse all whitespace (including newlines),
  # trim both ends, use the fallback for an all-whitespace value, and cap the
  # resulting label at 200 characters.
  printf '%s' "$1" | awk -v fallback="$2" '
    {
      if (NR > 1) text = text " "
      text = text $0
    }
    END {
      gsub(/[[:space:]]+/, " ", text)
      sub(/^ +/, "", text)
      sub(/ +$/, "", text)
      if (text == "") text = fallback
      if (length(text) > 200) text = substr(text, 1, 200)
      printf "%s", text
    }
  '
}

stage_candidate() {
  require_confirmed
  require_valid
  if [ "$STATE_CAPTURE" != explicit ]; then
    [ -n "$STATE_DISCLOSED" ] && [ "$STATE_DISCLOSED_MODE" = "$STATE_CAPTURE" ] || fail 'Capture policy must be disclosed (with matching mode) before staging candidates.'
  fi
  [ -n "$INPUT" ] || fail 'stage requires --input.'
  [ -f "$INPUT" ] || fail "Candidate input does not exist: $INPUT"
  [ -s "$INPUT" ] || fail 'Candidate input is empty.'
  trim_text_file "$INPUT"
  candidate_body=$TRIMMED_TEXT
  [ -n "$candidate_body" ] || fail 'Candidate input is empty.'
  current=$(utc_now)
  candidate_id=C-$(file_stamp)-$$
  pending=$ROOT/待确认信息.md
  temp=$ROOT/.pending.$$.tmp
  tr -d '\r' < "$pending" | sed '/^当前没有待确认信息。$/d' > "$temp" || fail 'Cannot prepare pending file.'
  {
    printf '\n## %s\n\n' "$candidate_id"
    printf -- '- 暂存时间：%s\n' "$current"
    printf -- '- 类型：%s\n' "$(clean_label "$KIND" 未分类)"
    printf -- '- 来源：%s\n' "$(clean_label "$SOURCE" 当前会话)"
    printf -- '- 状态：待确认\n\n'
    printf '%s\n' "$candidate_body"
  } >> "$temp" || fail 'Cannot append candidate.'
  mv -f "$temp" "$pending" || fail 'Cannot replace pending file.'
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$STATE_REVIEW" "$STATE_STAGE" "$STATE_INTERVIEW" "$STATE_PROGRESS" "$STATE_SESSION" "$STATE_TURN" "$STATE_DISCLOSED" "$STATE_DISCLOSED_MODE" || fail 'Cannot write state file.'
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
  [ ! -e "$marker" ] || fail 'Unfinished transaction exists; run recover --confirmed --root <authorized-root> first.'
  marker_temp=$(mktemp "$ROOT/.hello-transaction.XXXXXX") || fail 'Cannot create transaction marker temporary file.'
  if ! {
    printf 'schema_version=1\n'
    printf 'kind=%s\n' "$kind"
    while [ "$#" -gt 1 ]; do printf '%s=%s\n' "$1" "$(relative_path "$2")"; shift 2; done
  } > "$marker_temp"; then
    rm -f "$marker_temp" 2>/dev/null || true
    fail 'Cannot create transaction marker.'
  fi
  # A completed temporary file is linked into place atomically; ln refuses to
  # replace a marker created by another writer, preserving the old marker.
  if ln "$marker_temp" "$marker" 2>/dev/null; then
    rm -f "$marker_temp" 2>/dev/null || true
  else
    rm -f "$marker_temp" 2>/dev/null || true
    [ -e "$marker" ] && fail 'Unfinished transaction exists; run recover --confirmed --root <authorized-root> first.'
    fail 'Cannot create transaction marker.'
  fi
}

restore_from_marker() {
  marker=$ROOT/.hello-transaction
  [ -f "$marker" ] || return 1
  validate_marker_syntax "$marker" || return 1
  validate_transaction_requirements "$marker" || return 1
  RESTORED_JSON=[]
  # Preflight every referenced backup and path before copying any target.  A
  # malformed/incomplete marker must not leave a half-restored tree.
  for pair in profile:profile_backup log:log_backup state:state_backup progress:progress_backup; do
    backup_key=${pair#*:}
    backup_value=$(state_value "$marker" "$backup_key") || backup_value=
    [ -n "$backup_value" ] || continue
    case $backup_value in /*|../*|*/../*|*/..) return 1 ;; esac
    [ -f "$ROOT/$backup_value" ] || return 1
  done
  record_value=$(state_value "$marker" record_path) || record_value=
  case $record_value in /*|../*|*/../*|*/..) return 1 ;; esac
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
    target_name=$(basename "$target")
    target_name_json=$(json_escape "$target_name")
    if [ "$RESTORED_JSON" = '[]' ]; then
      RESTORED_JSON="[\"$target_name_json\"]"
    else
      RESTORED_JSON="${RESTORED_JSON%]},\"$target_name_json\"]"
    fi
  done
  if [ -n "$record_value" ]; then
    record_created=$(state_value "$marker" record_created) || return 1
    if [ "$record_created" = true ]; then
      rm -f "$ROOT/$record_value" || return 1
    fi
  fi
  return 0
}

cleanup_transaction_backups() {
  validate_marker_syntax "$ROOT/.hello-transaction" || return 1
  for backup_key in profile_backup log_backup state_backup progress_backup; do
    backup_value=$(state_value "$ROOT/.hello-transaction" "$backup_key") || backup_value=
    [ -n "$backup_value" ] || continue
    case $backup_value in /*|../*|*/../*|*/..) return 1 ;; esac
    rm -f "$ROOT/$backup_value" || return 1
  done
  return 0
}

recover_space() {
  require_confirmed
  [ -f "$ROOT/.hello-transaction" ] || fail 'No unfinished transaction exists.'
  restore_from_marker || fail 'Recovery failed; transaction marker was retained.'
  validate_space true || fail "Recovery completed but profile space is invalid: $VALIDATION_ISSUES"
  cleanup_transaction_backups || fail 'Recovery validation passed but transaction backups could not be cleared; marker retained.'
  rm -f "$ROOT/.hello-transaction" || fail 'Recovery validation passed but transaction marker could not be cleared.'
  printf '{"ok":true,"command":"recover","root":"%s","restored":%s}\n' "$(json_escape "$ROOT")" "$RESTORED_JSON"
}

rollback_fail() {
  message=$1
  [ -z "${progress_migration_temp-}" ] || rm -f "$progress_migration_temp"
  restore_from_marker || fail "$message; automatic rollback also failed. Run recover --confirmed --root <authorized-root>."
  validate_space true || fail "$message; automatic rollback validation failed: $VALIDATION_ISSUES. Run recover --confirmed --root <authorized-root>."
  cleanup_transaction_backups || fail "$message; rollback validation passed but transaction backups could not be cleared. Run recover --confirmed --root <authorized-root>."
  rm -f "$ROOT/.hello-transaction" || fail "$message; rollback validation passed but transaction marker could not be cleared. Run recover --confirmed --root <authorized-root>."
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
  # The monolithic schema-2 apply protocol must never overwrite a directoryized
  # target package (formal or draft).  Target entities are changed through the
  # target protocol, which preserves the aggregate index/authority split.
  if [ -f "$ROOT/.hello-state" ]; then
    apply_layout=$(sed -n 's/^layout=//p' "$ROOT/.hello-state" | head -n 1)
    case $apply_layout in
      target|target-draft) fail 'apply is not available for a formal target layout; use target protocol commands.' ;;
    esac
  fi
  require_valid
  [ -n "$INPUT" ] || fail 'apply requires --input.'
  [ -n "$SUMMARY_INPUT" ] || fail 'apply requires --summary-input.'
  [ -n "$EXPECTED_VERSION" ] || fail 'apply requires --expected-version.'
  is_positive_decimal "$EXPECTED_VERSION" || fail '--expected-version must be a positive decimal integer.'
  [ "$EXPECTED_VERSION" = "$STATE_VERSION" ] || fail "Version conflict: expected $EXPECTED_VERSION, current $STATE_VERSION."
  [ -s "$INPUT" ] || fail 'Candidate profile is empty.'
  [ -s "$SUMMARY_INPUT" ] || fail 'Update summary is empty.'
  trim_text_file "$INPUT"
  candidate_content=$TRIMMED_TEXT
  [ -n "$candidate_content" ] || fail 'Candidate profile is empty.'
  [ "$(printf '%s\n' "$candidate_content" | sed -n '1p')" = '# 个人全景档案' ] || fail 'Candidate profile must start with # 个人全景档案.'
  [ "$(printf '%s\n' "$candidate_content" | grep -Ec '^- 资料版本：[1-9][0-9]*$')" -eq 1 ] || fail 'Candidate profile requires exactly one positive 资料版本 metadata line.'
  [ "$(printf '%s\n' "$candidate_content" | grep -Ec '^- 最近确认时间：.+$')" -eq 1 ] || fail 'Candidate profile requires exactly one 最近确认时间 metadata line.'
  for heading in '## 一、当前起点' '## 二、人生时间线与关键经历' '## 三、能力、经验与证据' '## 四、知识、认知与学习方式' '## 五、健康、精力与可持续边界' '## 六、经济、资源与风险承受能力' '## 七、关系、支持网络与现实责任' '## 八、习惯、行动与决策方式' '## 九、价值观、世界观与人生愿景' '## 十、当前目标与未来设想' '## 十一、AI 协作偏好' '## 十二、未知、冲突与 AI 假设' '## 十三、主要来源'; do
    [ "$(printf '%s\n' "$candidate_content" | grep -Fxc "$heading")" -eq 1 ] || fail "Candidate profile is missing or duplicates section: $heading"
  done
  validate_summary
  canonical_old=$ROOT/.canonical-old.$$.tmp; canonical_new=$ROOT/.canonical-new.$$.tmp
  sed -e 's/\r$//' -e 's/^- 资料版本：.*$/- 资料版本：<version>/' -e 's/^- 最近确认时间：.*$/- 最近确认时间：<time>/' "$ROOT/个人全景档案.md" > "$canonical_old"
  printf '%s\n' "$candidate_content" | sed -e 's/^- 资料版本：.*$/- 资料版本：<version>/' -e 's/^- 最近确认时间：.*$/- 最近确认时间：<time>/' > "$canonical_new"
  if cmp -s "$canonical_old" "$canonical_new"; then rm -f "$canonical_old" "$canonical_new"; fail 'Candidate profile has no content changes.'; fi
  rm -f "$canonical_old" "$canonical_new"
  current=$(utc_now)
  new_version=$(decimal_increment "$STATE_VERSION") || fail 'Cannot increment profile version.'
  profile=$ROOT/个人全景档案.md
  progress_path=$ROOT/访谈进度.md
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
  migration_progress=$STATE_PROGRESS
  progress_migration_temp=
  progress_backup=
  if [ "$STATE_SCHEMA" != 2 ]; then
    progress_header_count=$(tr -d '\r' < "$progress_path" | grep -Ec '^- 进度版本：' || true)
    [ "$progress_header_count" -le 1 ] || fail 'Invalid legacy progress metadata: duplicate 进度版本 metadata.'
    progress_version_in_file=$(tr -d '\r' < "$progress_path" | sed -n 's/^- 进度版本：\([0-9][0-9]*\)$/\1/p' | head -n 1)
    if [ "$progress_header_count" -eq 1 ] && [ -z "$progress_version_in_file" ]; then
      fail 'Invalid legacy progress metadata: 进度版本 must be a positive integer.'
    fi
    if [ "$progress_header_count" -eq 1 ]; then
      if [ "$STATE_PROGRESS_PRESENT" != true ]; then migration_progress=$progress_version_in_file; fi
    else
      progress_migration_temp=$ROOT/.progress-migration.$$.tmp
      tr -d '\r' < "$progress_path" | awk -v version="$migration_progress" 'NR==1 { print; print ""; print "- 进度版本：" version; next } { print }' > "$progress_migration_temp" || fail 'Cannot prepare progress migration.'
      unique_target "$ROOT/.backups/transactions" "$(file_stamp)-v$STATE_VERSION-访谈进度.md"; progress_backup=$UNIQUE_TARGET
      cp "$progress_path" "$progress_backup" || fail 'Cannot back up progress.'
    fi
  fi
  if [ -n "$progress_backup" ]; then
    begin_transaction apply profile_backup "$backup" log_backup "$log_backup" state_backup "$state_backup" progress_backup "$progress_backup"
  else
    begin_transaction apply profile_backup "$backup" log_backup "$log_backup" state_backup "$state_backup"
  fi
  temp=$ROOT/.profile.$$.tmp
  printf '%s\n' "$candidate_content" | sed -e "s/^- 资料版本：.*$/- 资料版本：$new_version/" -e "s/^- 最近确认时间：.*$/- 最近确认时间：$current/" > "$temp" || rollback_fail 'Cannot prepare profile update.'
  mv -f "$temp" "$profile" || rollback_fail 'Cannot replace profile.'
  log=$ROOT/迭代日志.md
  log_temp=$ROOT/.log.$$.tmp
  tr -d '\r' < "$log" | sed '/^当前没有正式迭代。$/d' > "$log_temp" || rollback_fail 'Cannot prepare log.'
  {
    printf '\n## R%s · %s\n\n' "$new_version" "$current"
    printf -- '- 资料版本：%s\n' "$new_version"
    printf -- '- 确认状态：用户已确认\n'
    printf -- '- 历史快照：`历史版本/%s`\n\n' "$(basename "$history")"
    cat "$SUMMARY_INPUT"
    printf '\n'
  } >> "$log_temp" || rollback_fail 'Cannot append log.'
  mv -f "$log_temp" "$log" || rollback_fail 'Cannot replace log.'
  if [ -n "${progress_migration_temp-}" ]; then
    mv -f "$progress_migration_temp" "$progress_path" || rollback_fail 'Cannot replace migrated progress.'
    progress_migration_temp=
  fi
  write_state "$ROOT/.hello-state" 2 "$new_version" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$current" "$STATE_REVIEW" "$STATE_STAGE" "$STATE_INTERVIEW" "$migration_progress" "$STATE_SESSION" "$STATE_TURN" "$STATE_DISCLOSED" "$STATE_DISCLOSED_MODE" || rollback_fail 'Cannot write state.'
  [ "$SIMULATE_FAILURE" = false ] || rollback_fail 'Simulated failure after state write.'
  if ! validate_space true; then rollback_fail "Post-write validation failed: $VALIDATION_ISSUES"; fi
  cleanup_transaction_backups || rollback_fail 'Cannot clear transaction backups.'
  rm -f "$ROOT/.hello-transaction" || rollback_fail 'Cannot clear transaction marker.'
  printf '{"ok":true,"command":"apply","root":"%s","old_version":"%s","profile_version":"%s","history":"%s","backup":"%s"}\n' \
    "$(json_escape "$ROOT")" "$STATE_VERSION" "$new_version" "$(json_escape "$history")" "$(json_escape "$backup")"
}

session_termination_json() {
  session_id=$1
  reasons_json=[]
  reason_count=0
  today=$(date -u +%Y-%m-%d)
  session_date=$(printf '%s' "$session_id" | cut -c1-10)
  if [ "$session_date" != "$today" ]; then reasons_json='["cross-natural-day"]'; reason_count=1; fi
  session_dir="$ROOT/原始访谈/$(printf '%s' "$session_id" | cut -c1-4)/$session_id"
  turn_count=0
  [ -d "$session_dir" ] && turn_count=$(find "$session_dir" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
  if [ "$turn_count" -gt 50 ]; then
    [ "$reason_count" -eq 0 ] && reasons_json='["over-50-turns"]' || reasons_json='["cross-natural-day","over-50-turns"]'
    reason_count=$((reason_count + 1))
  fi
  [ "$reason_count" -gt 0 ] && notice='请开启新会话' || notice=
  # Return an object-member fragment: callers merge it into their response
  # object, so emitting braces here would create invalid JSON after a comma.
  printf '"new_session_required":%s,"session_termination_reasons":%s,"session_termination_notice":"%s"' \
    "$([ "$reason_count" -gt 0 ] && echo true || echo false)" "$reasons_json" "$(json_escape "$notice")"
}

record_turn() {
  require_confirmed
  require_valid
  [ -n "$INPUT" ] || fail 'record-turn requires --input.'
  [ -n "$PROGRESS_INPUT" ] || fail 'record-turn requires --progress-input.'
  [ -n "$SESSION_ID" ] || fail 'record-turn requires --session-id.'
  [ -n "$TURN_ID" ] || fail 'record-turn requires --turn-id.'
  [ -n "$EXPECTED_PROGRESS_VERSION" ] || fail 'record-turn requires --expected-progress-version.'
  printf '%s\n' "$SESSION_ID" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}[A-Za-z0-9._-]{0,117}$' || fail 'Invalid session id.'
  printf '%s\n' "$TURN_ID" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' || fail 'Invalid turn id.'
  is_positive_decimal "$EXPECTED_PROGRESS_VERSION" || fail '--expected-progress-version must be a positive decimal integer.'
  [ -s "$INPUT" ] || fail 'Turn input is empty.'
  trim_text_file "$INPUT"
  turn_body=$TRIMMED_TEXT
  [ -n "$turn_body" ] || fail 'Turn input is empty.'
  year=$(printf '%s' "$SESSION_ID" | cut -c 1-4)
  record_dir=$ROOT/原始访谈/$year/$SESSION_ID
  record_path=$record_dir/$TURN_ID.md
  # The immutable turn file is the durable idempotency key, not the mutable
  # last-session/last-turn cursor. A retry may arrive after later turns have
  # advanced that cursor, so consult the original file first.
  if [ -f "$record_path" ]; then
    # Python and PowerShell compare trimmed, newline-normalized text. Read the
    # existing record through the same helper so a legacy CRLF file does not
    # turn an otherwise identical retry into a false collision.
    trim_text_file "$record_path"
    retry_body=$TRIMMED_TEXT
    [ "$retry_body" = "$turn_body" ] || fail 'Idempotent turn retry has different content.'
    printf '{"ok":true,"command":"record-turn","root":"%s","session_id":"%s","turn_id":"%s","record":"%s","created":false,"idempotent":true,"progress_version":"%s",%s}\n' \
      "$(json_escape "$ROOT")" "$(json_escape "$SESSION_ID")" "$(json_escape "$TURN_ID")" "$(json_escape "$record_path")" "$STATE_PROGRESS" "$(session_termination_json "$SESSION_ID")"
    return
  fi
  [ "$EXPECTED_PROGRESS_VERSION" = "$STATE_PROGRESS" ] || fail "Progress version conflict: expected $EXPECTED_PROGRESS_VERSION, current $STATE_PROGRESS."
  [ ! -e "$record_path" ] || fail 'Turn record already exists with different content.'
  [ -s "$PROGRESS_INPUT" ] || fail 'Progress input is empty.'
  trim_text_file "$PROGRESS_INPUT"
  progress_body=$TRIMMED_TEXT
  [ -n "$progress_body" ] || fail 'Progress input is empty.'
  [ "$(printf '%s\n' "$progress_body" | sed -n '1p')" = '# 访谈进度' ] || fail 'Progress input must start with # 访谈进度.'
  for heading in '## 已覆盖主题' '## 待补充主题' '## 暂不收集' '## 下次问题'; do
    [ "$(printf '%s\n' "$progress_body" | grep -Fxc "$heading")" -eq 1 ] || fail "Progress input is missing or duplicates section: $heading"
  done
  # Keep the progress-version grammar aligned with Python/PowerShell.  A
  # malformed or duplicate header must fail closed; only a missing header is
  # eligible for insertion below.
  progress_header_count=$(printf '%s\n' "$progress_body" | grep -Ec '^- 进度版本：' || true)
  progress_versions=$(printf '%s\n' "$progress_body" | grep -Ec '^- 进度版本：[1-9][0-9]*$' || true)
  [ "$progress_header_count" -le 1 ] || fail 'Progress input contains duplicate 进度版本 metadata.'
  if [ "$progress_header_count" -eq 1 ] && [ "$progress_versions" -eq 0 ]; then
    fail 'Progress input 进度版本 must be a positive integer.'
  fi
  if [ "$progress_versions" -eq 1 ]; then
    progress_version_in_input=$(printf '%s\n' "$progress_body" | sed -n 's/^- 进度版本：\([1-9][0-9]*\)$/\1/p')
    is_positive_decimal "$progress_version_in_input" || fail 'Progress input 进度版本 must be a positive integer.'
  fi
  mkdir -p "$record_dir" "$ROOT/.backups/transactions" || fail 'Cannot create turn or transaction directories.'
  unique_target "$ROOT/.backups/transactions" "$(file_stamp)-p$STATE_PROGRESS-访谈进度.md"; progress_backup=$UNIQUE_TARGET
  cp "$ROOT/访谈进度.md" "$progress_backup" || fail 'Cannot back up progress.'
  unique_target "$ROOT/.backups/transactions" "$(file_stamp)-p$STATE_PROGRESS-hello-state"; state_backup=$UNIQUE_TARGET
  cp "$ROOT/.hello-state" "$state_backup" || fail 'Cannot back up state.'
  begin_transaction record-turn progress_backup "$progress_backup" state_backup "$state_backup" record_path "$record_path" record_created true
  printf '%s\n' "$turn_body" > "$record_path" || rollback_fail 'Cannot write turn record.'
  new_progress=$(decimal_increment "$STATE_PROGRESS") || rollback_fail 'Cannot increment progress version.'
  progress_temp=$ROOT/.progress.$$.tmp
  if printf '%s\n' "$progress_body" | grep -q '^- 进度版本：'; then
    printf '%s\n' "$progress_body" | sed "s/^- 进度版本：.*$/- 进度版本：$new_progress/" > "$progress_temp" || rollback_fail 'Cannot prepare progress update.'
  else
    printf '%s\n' "$progress_body" | awk -v version="$new_progress" 'NR==1 { print; print ""; print "- 进度版本：" version; next } { print }' > "$progress_temp" || rollback_fail 'Cannot prepare progress update.'
  fi
  mv -f "$progress_temp" "$ROOT/访谈进度.md" || rollback_fail 'Cannot replace progress.'
  current=$(utc_now)
  record_state_schema=$STATE_SCHEMA
  [ "$record_state_schema" = 1 ] && record_state_schema=2
  write_state "$ROOT/.hello-state" "$record_state_schema" "$STATE_VERSION" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$STATE_REVIEW" "$STATE_STAGE" "$current" "$new_progress" "$SESSION_ID" "$TURN_ID" "$STATE_DISCLOSED" "$STATE_DISCLOSED_MODE" || rollback_fail 'Cannot write state.'
  [ "$SIMULATE_FAILURE" = false ] || rollback_fail 'Simulated failure after state write.'
  if ! validate_space true; then rollback_fail "Post-write validation failed: $VALIDATION_ISSUES"; fi
  cleanup_transaction_backups || rollback_fail 'Cannot clear transaction backups.'
  rm -f "$ROOT/.hello-transaction" || rollback_fail 'Cannot clear transaction marker.'
  printf '{"ok":true,"command":"record-turn","root":"%s","session_id":"%s","turn_id":"%s","record":"%s","created":true,"idempotent":false,"progress_version":"%s",%s}\n' \
    "$(json_escape "$ROOT")" "$(json_escape "$SESSION_ID")" "$(json_escape "$TURN_ID")" "$(json_escape "$record_path")" "$new_progress" "$(session_termination_json "$SESSION_ID")"
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
  tr -d '\r' < "$pending" | awk -v target="## $CANDIDATE_ID" -v trash="$trash" '
    BEGIN { inside=0; found=0 }
    $0 == target { inside=1; found=1 }
    inside && $0 != target && /^## C-[0-9TZ-]+[[:space:]]*$/ { inside=0 }
    { if (inside) print > trash; else print }
    END { if (!found) exit 3 }
  ' > "$temp"
  code=$?
  [ "$code" -eq 0 ] || { rm -f "$temp" "$trash"; fail "Candidate not found: $CANDIDATE_ID"; }
  if ! grep -q '^## C-[0-9TZ-][0-9TZ-]*[[:space:]]*$' "$temp"; then
    printf '\n当前没有待确认信息。\n' >> "$temp"
  fi
  mv -f "$temp" "$pending" || fail 'Cannot replace pending file.'
  current=$(utc_now)
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$STATE_REVIEW" "$STATE_STAGE" "$STATE_INTERVIEW" "$STATE_PROGRESS" "$STATE_SESSION" "$STATE_TURN" "$STATE_DISCLOSED" "$STATE_DISCLOSED_MODE" || fail 'Cannot write state file.'
  printf '{"ok":true,"command":"withdraw","root":"%s","candidate_id":"%s","trash":"%s"}\n' \
    "$(json_escape "$ROOT")" "$CANDIDATE_ID" "$(json_escape "$trash")"
}

target_prepare_dirs() {
  target_prepare_root=$1
  mkdir -p "$target_prepare_root/权威/声明" "$target_prepare_root/权威/事件" "$target_prepare_root/权威/决策" \
    "$target_prepare_root/来源" "$target_prepare_root/派生" "$target_prepare_root/原始访谈" \
    "$target_prepare_root/历史版本" "$target_prepare_root/.backups" "$target_prepare_root/.trash" || return 1
}

target_copy_compatibility_projection() {
  target_projection_source=$1
  target_projection_root=$2
  for projection_name in 访谈进度.md 待确认信息.md; do
    [ -f "$target_projection_source/$projection_name" ] || return 1
    cp "$target_projection_source/$projection_name" "$target_projection_root/$projection_name" || return 1
  done
  # The target's aggregate is an index, not a second authoritative profile.
  # Preserve the exact legacy profile under history for traceability instead
  # of silently replacing the target overview with the monolith.
  mkdir -p "$target_projection_root/历史版本/compatibility" || return 1
  cp "$target_projection_source/个人全景档案.md" "$target_projection_root/历史版本/compatibility/个人全景档案.md" || return 1
  return 0
}

target_init_draft() {
  target_init_root=$1
  target_init_migration=$2
  target_init_profile_version=$3
  target_init_progress_version=$4
  target_init_profile_hash=$5
  target_init_progress_hash=$6
  target_init_pending_hash=$7
  target_init_generated=$8
  target_init_package=${9-pkg-local}
  target_init_subject=${10-subject-local}
  if [ -e "$target_init_root" ]; then
    [ -d "$target_init_root" ] || return 1
    # An existing target is safe only when it carries the same migration id;
    # never merge an unrelated package into a user-selected destination.
    if [ -f "$target_init_root/.hello-state" ]; then
      existing_target_migration=$(target_marker_value "$target_init_root/.hello-state" migration_id) || existing_target_migration=
      [ "$existing_target_migration" = "$target_init_migration" ] || return 1
    else
      find "$target_init_root" -mindepth 1 -print -quit 2>/dev/null | grep -q . && return 1
    fi
  else
    mkdir -p "$target_init_root" || return 1
  fi
  target_prepare_dirs "$target_init_root" || return 1
  # Reuse the checked-in target templates where available.  Existing files in
  # an owner-created draft are never overwritten by plan generation.
  for template_name in README.md 个人全景档案.md 主题覆盖矩阵.md; do
    if [ ! -f "$target_init_root/$template_name" ] && [ -f "$TEMPLATE_DIR/target-package/$template_name" ]; then
      sed 's/\r$//' "$TEMPLATE_DIR/target-package/$template_name" > "$target_init_root/$template_name" || return 1
    fi
  done
  [ -f "$target_init_root/README.md" ] || printf '%s\n' '# 个人资料目标包' > "$target_init_root/README.md"
  [ -f "$target_init_root/个人全景档案.md" ] || printf '%s\n' '# 个人全景档案' > "$target_init_root/个人全景档案.md"
  [ -f "$target_init_root/主题覆盖矩阵.md" ] || printf '%s\n' '# 主题覆盖矩阵' > "$target_init_root/主题覆盖矩阵.md"
  [ -f "$target_init_root/资料索引.md" ] || printf '%s\n' '# 资料索引' > "$target_init_root/资料索引.md"
  [ -f "$target_init_root/迭代日志.md" ] || printf '%s\n' '# 迭代日志' > "$target_init_root/迭代日志.md"
  target_copy_compatibility_projection "$ROOT" "$target_init_root" || return 1
  if [ ! -f "$target_init_root/迁移映射.md" ]; then
    {
      printf '# 迁移映射\n\n'
      printf -- '- 迁移 ID：%s\n' "$target_init_migration"
      printf -- '- 来源资料版本：%s\n' "$target_init_profile_version"
      printf -- '- 来源进度版本：%s\n' "$target_init_progress_version"
      printf -- '- 来源档案 SHA-256：%s\n' "$target_init_profile_hash"
      printf -- '- 来源进度 SHA-256：%s\n' "$target_init_progress_hash"
      printf -- '- 来源待确认信息 SHA-256：%s\n\n' "$target_init_pending_hash"
      printf '## 来源完整性\n\n保留来源文件与哈希；实体草稿须经用户确认后才可成为权威。\n'
    } > "$target_init_root/迁移映射.md" || return 1
  fi
  write_target_marker "$target_init_root" target-draft "$target_init_migration" "$target_init_package" "$target_init_subject" \
    "$target_init_profile_version" "$target_init_progress_version" "$target_init_profile_hash" "$target_init_progress_hash" "$target_init_pending_hash" "$target_init_generated" || return 1
  write_target_manifest "$target_init_root" target-draft "$target_init_migration" "$target_init_package" "$target_init_subject" \
    "$target_init_profile_hash" "$target_init_progress_hash" "$target_init_pending_hash" "$target_init_generated" "$target_init_profile_version" "$target_init_progress_version" || return 1
  return 0
}

target_validate_command() {
  # `ROOT` is the explicitly supplied target root for this command.
  if validate_target_space "$ROOT"; then
    marker=$ROOT/.hello-state
    printf '{"ok":true,"command":"target-validate","root":"%s","layout":"%s","layout_version":"%s","schema_version":"%s","migration_id":"%s","issues":[]}\n' \
      "$(json_escape "$ROOT")" "$(json_escape "$(target_marker_value "$marker" layout)")" "$(json_escape "$(target_marker_value "$marker" layout_version)")" \
      "$(json_escape "$(target_marker_value "$marker" schema_version)")" "$(json_escape "$(target_marker_value "$marker" migration_id)")"
  else
    printf '{"ok":false,"command":"target-validate","root":"%s","issues":%s}\n' "$(json_escape "$ROOT")" "${TARGET_VALIDATION_ISSUES_JSON-[\"Invalid target profile space\"]}"
    exit 1
  fi
}

migrate_plan_command() {
  # Planning is a read-only comparison.  It must never create a target root or
  # copy source body; migrate-apply is the explicit, confirmed write step.
  # ROOT is the source; TARGET_PATH is the explicitly supplied draft root.
  require_valid
  assert_independent_roots "$ROOT" "$TARGET_PATH"
  target_required_source_hashes "$ROOT" || fail 'Cannot hash source profile files.'
  read_state || fail "Cannot read source state: ${STATE_PARSE_ERROR:-invalid state}"
  is_positive_decimal "$STATE_VERSION" || fail 'Source profile version is invalid.'
  is_positive_decimal "$STATE_PROGRESS" || fail 'Source progress version is invalid.'
  plan_migration=$MIGRATION_ID
  [ -n "$plan_migration" ] || plan_migration=hello-migration-$(file_stamp)-$$
  safe_migration_id "$plan_migration" || fail 'Invalid migration id.'
  target_exists=false
  target_layout=
  target_issues_json='[]'
  mapping_ready=false
  if [ -e "$TARGET_PATH" ]; then
    target_exists=true
    [ -d "$TARGET_PATH" ] || fail 'Target path exists and is not a directory.'
    acquire_extra_lock "$TARGET_PATH"
    if validate_target_space "$TARGET_PATH"; then
      target_layout=$(target_marker_value "$TARGET_PATH/.hello-state" layout)
      target_migration=$(target_marker_value "$TARGET_PATH/.hello-state" migration_id) || target_migration=
      [ "$target_migration" = "$plan_migration" ] || fail 'Target migration id does not match the requested migration.'
      target_manifest_profile=$(target_manifest_source_value "$TARGET_PATH/manifest.json" profile sha256) || target_manifest_profile=
      target_manifest_progress=$(target_manifest_source_value "$TARGET_PATH/manifest.json" progress sha256) || target_manifest_progress=
      target_manifest_pending=$(target_manifest_source_value "$TARGET_PATH/manifest.json" pending sha256) || target_manifest_pending=
      [ "$target_manifest_profile" = "$TARGET_SOURCE_PROFILE_HASH" ] || fail 'Target manifest profile hash does not match source.'
      [ "$target_manifest_progress" = "$TARGET_SOURCE_PROGRESS_HASH" ] || fail 'Target manifest progress hash does not match source.'
      [ "$target_manifest_pending" = "$TARGET_SOURCE_PENDING_HASH" ] || fail 'Target manifest pending hash does not match source.'
      mapping_ready=true
    else
      target_issues_json=${TARGET_VALIDATION_ISSUES_JSON-'["Invalid target package"]'}
    fi
  elif [ "$CONFIRMED" = true ]; then
    # An explicitly confirmed plan may materialize the deterministic draft
    # skeleton; an unconfirmed probe remains strictly read-only.
    # Let target_init_draft create the root after the independent-root check.
    # Creating it before acquiring the secondary lock would leave `.hello-lock`
    # in an otherwise empty directory, which the draft initializer correctly
    # rejects as unexpected user content.
    acquire_extra_lock "$TARGET_PATH"
    target_init_draft "$TARGET_PATH" "$plan_migration" "$STATE_VERSION" "$STATE_PROGRESS" \
      "$TARGET_SOURCE_PROFILE_HASH" "$TARGET_SOURCE_PROGRESS_HASH" "$TARGET_SOURCE_PENDING_HASH" "$(utc_now)" pkg-$plan_migration subject-local || fail 'Cannot initialize confirmed target draft.'
    target_exists=true
    target_layout=target-draft
    mapping_ready=true
    target_issues_json='[]'
  fi
  printf '{"ok":true,"command":"migrate-plan","source_root":"%s","target_root":"%s","migration_id":"%s","source_profile_version":"%s","source_progress_version":"%s","source_profile_sha256":"%s","source_progress_sha256":"%s","source_pending_sha256":"%s","target_exists":%s,"target_layout":"%s","mapping_ready":%s,"target_issues":%s}\n' \
    "$(json_escape "$ROOT")" "$(json_escape "$TARGET_PATH")" "$(json_escape "$plan_migration")" "$STATE_VERSION" "$STATE_PROGRESS" \
    "$TARGET_SOURCE_PROFILE_HASH" "$TARGET_SOURCE_PROGRESS_HASH" "$TARGET_SOURCE_PENDING_HASH" "$target_exists" "$(json_escape "$target_layout")" "$mapping_ready" "$target_issues_json"
  # Release secondary and primary locks before returning to a caller that may
  # capture this command's output in a command substitution.  The explicit
  # cleanup complements the EXIT trap and avoids leaving a target busy marker
  # on shells that do not run inherited traps for nested invocations.
  release_extra_locks
  release_store_lock
}

promote_target_in_place() {
  promote_root=$1
  promote_migration=$2
  promote_profile_version=$3
  promote_progress_version=$4
  promote_profile_hash=$5
  promote_progress_hash=$6
  promote_pending_hash=$7
  promote_package=${8-pkg-local}
  promote_subject=${9-subject-local}
  validate_target_space "$promote_root" || return 1
  current_promote_migration=$(target_marker_value "$promote_root/.hello-state" migration_id) || current_promote_migration=
  [ "$current_promote_migration" = "$promote_migration" ] || return 1
  write_target_marker "$promote_root" target "$promote_migration" "$promote_package" "$promote_subject" \
    "$promote_profile_version" "$promote_progress_version" "$promote_profile_hash" "$promote_progress_hash" "$promote_pending_hash" "$(utc_now)" || return 1
  sync_target_compat_state "$promote_root" || return 1
  write_target_manifest "$promote_root" target "$promote_migration" "$promote_package" "$promote_subject" \
    "$promote_profile_hash" "$promote_progress_hash" "$promote_pending_hash" "$(utc_now)" "$promote_profile_version" "$promote_progress_version" || return 1
  validate_target_space "$promote_root"
}

migrate_apply_command() {
  require_confirmed
  require_valid
  assert_independent_roots "$ROOT" "$TARGET_PATH"
  assert_independent_roots "$ROOT" "$DESTINATION_PATH"
  # Target and destination may intentionally be identical for an in-place
  # promotion.  Distinct roots must also be independent of each other.
  if [ "$TARGET_PATH" != "$DESTINATION_PATH" ]; then
    assert_independent_roots "$TARGET_PATH" "$DESTINATION_PATH"
  fi
  is_positive_decimal "$EXPECTED_VERSION" || fail '--expected-version must be a positive decimal integer.'
  is_positive_decimal "$EXPECTED_PROGRESS_VERSION" || fail '--expected-progress-version must be a positive decimal integer.'
  read_state || fail "Cannot read source state: ${STATE_PARSE_ERROR:-invalid state}"
  [ "$EXPECTED_VERSION" = "$STATE_VERSION" ] || fail "Version conflict: expected $EXPECTED_VERSION, current $STATE_VERSION."
  [ "$EXPECTED_PROGRESS_VERSION" = "$STATE_PROGRESS" ] || fail "Progress version conflict: expected $EXPECTED_PROGRESS_VERSION, current $STATE_PROGRESS."
  acquire_extra_lock "$TARGET_PATH"
  [ "$TARGET_PATH" = "$DESTINATION_PATH" ] || acquire_extra_lock "$DESTINATION_PATH"
  target_required_source_hashes "$ROOT" || fail 'Cannot hash source profile files.'
  validate_target_space "$TARGET_PATH" || fail "Target draft is invalid: $TARGET_VALIDATION_ISSUES"
  draft_marker=$TARGET_PATH/.hello-state
  draft_migration=$(target_marker_value "$draft_marker" migration_id) || draft_migration=
  [ -n "$draft_migration" ] || fail 'Target draft has no migration id.'
  [ -n "$MIGRATION_ID" ] && [ "$MIGRATION_ID" != "$draft_migration" ] && fail 'Migration id does not match target draft.'
  draft_profile_hash=$(target_marker_value "$draft_marker" source_profile_sha256) || draft_profile_hash=
  draft_progress_hash=$(target_marker_value "$draft_marker" source_progress_sha256) || draft_progress_hash=
  draft_pending_hash=$(target_marker_value "$draft_marker" source_pending_sha256) || draft_pending_hash=
  [ -z "$draft_profile_hash" ] || [ "$draft_profile_hash" = "$TARGET_SOURCE_PROFILE_HASH" ] || fail 'Target draft source profile hash is stale.'
  [ -z "$draft_progress_hash" ] || [ "$draft_progress_hash" = "$TARGET_SOURCE_PROGRESS_HASH" ] || fail 'Target draft source progress hash is stale.'
  [ -z "$draft_pending_hash" ] || [ "$draft_pending_hash" = "$TARGET_SOURCE_PENDING_HASH" ] || fail 'Target draft source pending hash is stale.'
  draft_package=$(target_marker_value "$draft_marker" package_id) || draft_package=pkg-local
  draft_subject=$(target_marker_value "$draft_marker" subject_id) || draft_subject=subject-local
  if [ "$TARGET_PATH" = "$DESTINATION_PATH" ]; then
    promote_target_in_place "$TARGET_PATH" "$draft_migration" "$STATE_VERSION" "$STATE_PROGRESS" \
      "$TARGET_SOURCE_PROFILE_HASH" "$TARGET_SOURCE_PROGRESS_HASH" "$TARGET_SOURCE_PENDING_HASH" "$draft_package" "$draft_subject" || fail 'Cannot promote target draft in place.'
    printf '{"ok":true,"command":"migrate-apply","source_root":"%s","target_root":"%s","destination_root":"%s","migration_id":"%s","promoted_in_place":true}\n' \
      "$(json_escape "$ROOT")" "$(json_escape "$TARGET_PATH")" "$(json_escape "$DESTINATION_PATH")" "$(json_escape "$draft_migration")"
    return
  fi
  if [ -e "$DESTINATION_PATH" ]; then
    [ -d "$DESTINATION_PATH" ] || fail 'Destination exists and is not a directory.'
    find "$DESTINATION_PATH" -mindepth 1 -print -quit 2>/dev/null | grep -q . && fail 'Destination must be absent or empty.'
  else
    parent_destination=$(dirname "$DESTINATION_PATH")
    mkdir -p "$parent_destination" || fail 'Cannot create destination parent.'
  fi
  staging_parent=$(dirname "$DESTINATION_PATH")
  staging_path=$staging_parent/.hello-target-stage-$$
  [ ! -e "$staging_path" ] || fail 'Target staging path already exists.'
  mkdir -p "$staging_path" || fail 'Cannot create target staging directory.'
  if ! copy_target_tree "$TARGET_PATH" "$staging_path"; then
    rm -rf "$staging_path" 2>/dev/null || true
    fail 'Cannot copy target draft to destination.'
  fi
  promote_target_in_place "$staging_path" "$draft_migration" "$STATE_VERSION" "$STATE_PROGRESS" \
    "$TARGET_SOURCE_PROFILE_HASH" "$TARGET_SOURCE_PROGRESS_HASH" "$TARGET_SOURCE_PENDING_HASH" "$draft_package" "$draft_subject" || {
      rm -rf "$staging_path" 2>/dev/null || true
      fail 'Cannot finalize target destination.'
    }
  [ "$SIMULATE_FAILURE" = false ] || { rm -rf "$staging_path" 2>/dev/null || true; fail 'Simulated migration failure; source and destination remain unchanged.'; }
  mv "$staging_path" "$DESTINATION_PATH" || { rm -rf "$staging_path" 2>/dev/null || true; fail 'Cannot atomically install target destination.'; }
  validate_target_space "$DESTINATION_PATH" || fail "Installed target destination is invalid: $TARGET_VALIDATION_ISSUES"
  printf '{"ok":true,"command":"migrate-apply","source_root":"%s","target_root":"%s","destination_root":"%s","migration_id":"%s","promoted_in_place":false}\n' \
    "$(json_escape "$ROOT")" "$(json_escape "$TARGET_PATH")" "$(json_escape "$DESTINATION_PATH")" "$(json_escape "$draft_migration")"
}

rebuild_index_command() {
  require_confirmed
  validate_target_space "$ROOT" || fail "Target package is invalid: $TARGET_VALIDATION_ISSUES"
  authority_dir=$ROOT/权威
  mkdir -p "$authority_dir" || fail 'Cannot create authority index directory.'
  authority_list=$ROOT/.authority-files.$$.tmp
  authority_hash_parts=$ROOT/.authority-hashes.$$.tmp
  authority_index_temp=$authority_dir/.声明索引.$$.tmp
  index_temp=$ROOT/.资料索引.$$.tmp
  (cd "$authority_dir" && find . -type f -name '*.md' ! -name 'README.md' ! -name '声明索引.md' -print | LC_ALL=C sort) | sed 's#^./##' > "$authority_list" || fail 'Cannot enumerate authority entries.'
  : > "$authority_hash_parts" || fail 'Cannot prepare authority hash input.'
  while IFS= read -r authority_rel; do
    [ -n "$authority_rel" ] || continue
    authority_file=$authority_dir/$authority_rel
    authority_hash=$(sha256_file "$authority_file") || { rm -f "$authority_list" "$authority_hash_parts" "$authority_index_temp"; fail 'Cannot hash authority entry.'; }
    printf '%s:%s\n' "权威/$authority_rel" "$authority_hash" >> "$authority_hash_parts" || fail 'Cannot write authority hash input.'
  done < "$authority_list"
  # Match the Python/PowerShell freshness contract: hash sorted
  # `path:sha256` lines joined by LF, without a trailing LF.
  index_source_hash=$(awk '{if (NR > 1) printf "\n"; printf "%s", $0}' "$authority_hash_parts" | sha256sum | awk '{print $1}') || { rm -f "$authority_list" "$authority_hash_parts"; fail 'Cannot hash authority index input.'; }
  index_source_matrix_version=$(sha256_file "$ROOT/主题覆盖矩阵.md") || { rm -f "$authority_list" "$authority_hash_parts"; fail 'Cannot hash topic matrix.'; }
  generated_at=$(utc_now)
  {
    printf '{\n'
    printf '  "layout": "target",\n'
    printf '  "layout_version": 1,\n'
    printf '  "generated_at": "%s",\n' "$(json_escape "$generated_at")"
    printf '  "index_source_hash": "%s",\n' "$index_source_hash"
    printf '  "index_source_version": "%s",\n' "$(json_escape "$(target_marker_value "$ROOT/.hello-state" profile_version)")"
    printf '  "index_source_progress_version": "%s",\n' "$(json_escape "$(target_marker_value "$ROOT/.hello-state" progress_version)")"
    printf '  "index_source_matrix_version": "%s",\n' "$index_source_matrix_version"
    printf '  "entries": ['
    authority_first=true
    while IFS= read -r authority_rel; do
      [ -n "$authority_rel" ] || continue
      authority_file=$authority_dir/$authority_rel
      authority_kind=Claim
      case $authority_rel in 事件/*) authority_kind=Event ;; 决策/*) authority_kind=Decision ;; esac
      authority_id=$(target_frontmatter_value "$authority_file" claim_id); [ -n "$authority_id" ] || authority_id=$(target_frontmatter_value "$authority_file" event_id); [ -n "$authority_id" ] || authority_id=$(target_frontmatter_value "$authority_file" decision_id); [ -n "$authority_id" ] || authority_id=$(target_frontmatter_value "$authority_file" draft_id); [ -n "$authority_id" ] || authority_id=$(target_frontmatter_value "$authority_file" id); [ -n "$authority_id" ] || authority_id=${authority_rel##*/}; authority_id=${authority_id%.md}
      authority_topics=$(target_frontmatter_array_json "$authority_file" topic_id topic_ids cross_topic_ids) || authority_topics='[]'
      authority_status=$(target_frontmatter_value "$authority_file" status); [ -n "$authority_status" ] || authority_status=unknown
      authority_sensitivity=$(target_frontmatter_value "$authority_file" sensitivity); [ -n "$authority_sensitivity" ] || authority_sensitivity=unknown
      authority_sources=$(target_frontmatter_array_json "$authority_file" source_ref source_refs) || authority_sources='[]'
      authority_allowed_uses=$(target_frontmatter_array_json "$authority_file" allowed_use allowed_uses) || authority_allowed_uses='[]'
      authority_hash=$(sha256_file "$authority_file") || fail 'Cannot hash authority entry.'
      [ "$authority_first" = true ] || printf ','
      authority_first=false
      printf '{"id":"%s","topic_ids":%s,"kind":"%s","status":"%s","source_refs":%s,"sensitivity":"%s","allowed_uses":%s,"path":"%s","sha256":"%s"}' \
        "$(json_escape "$authority_id")" "$authority_topics" "$(json_escape "$authority_kind")" "$(json_escape "$authority_status")" "$authority_sources" "$(json_escape "$authority_sensitivity")" "$authority_allowed_uses" "$(json_escape "权威/$authority_rel")" "$authority_hash"
    done < "$authority_list"
    printf ']\n}\n'
  } > "$authority_index_temp" || { rm -f "$authority_list" "$authority_hash_parts" "$authority_index_temp"; fail 'Cannot build authority index.'; }
  mv -f "$authority_index_temp" "$authority_dir/声明索引.json" || fail 'Cannot finalize authority index.'
  update_target_marker_keys "$ROOT" index_source_hash "$index_source_hash" index_generated_at "$generated_at" index_source_matrix_version "$index_source_matrix_version" || fail 'Cannot update target index freshness metadata.'
  rebuild_migration=$(target_marker_value "$ROOT/.hello-state" migration_id) || rebuild_migration=local
  rebuild_package=$(target_marker_value "$ROOT/.hello-state" package_id) || rebuild_package=pkg-local
  rebuild_subject=$(target_marker_value "$ROOT/.hello-state" subject_id) || rebuild_subject=subject-local
  rebuild_profile_hash=$(target_marker_value "$ROOT/.hello-state" source_profile_sha256) || rebuild_profile_hash=
  rebuild_progress_hash=$(target_marker_value "$ROOT/.hello-state" source_progress_sha256) || rebuild_progress_hash=
  rebuild_pending_hash=$(target_marker_value "$ROOT/.hello-state" source_pending_sha256) || rebuild_pending_hash=
  rebuild_profile_version=$(target_marker_value "$ROOT/.hello-state" profile_version) || rebuild_profile_version=$(target_marker_value "$ROOT/.hello-state" source_profile_version)
  rebuild_progress_version=$(target_marker_value "$ROOT/.hello-state" progress_version) || rebuild_progress_version=$(target_marker_value "$ROOT/.hello-state" source_progress_version)
  write_target_manifest "$ROOT" target "$rebuild_migration" "$rebuild_package" "$rebuild_subject" "$rebuild_profile_hash" "$rebuild_progress_hash" "$rebuild_pending_hash" "$generated_at" "$rebuild_profile_version" "$rebuild_progress_version" "$index_source_hash" "$generated_at" "$index_source_matrix_version" || fail 'Cannot update target manifest freshness metadata.'
  {
    printf '# 资料索引\n\n'
    printf -- '- 布局：target\n'
    printf -- '- 权威条目数：%s\n' "$(grep -o '"id"' "$authority_dir/声明索引.json" | wc -l | tr -d '[:space:]')"
    printf -- '- 索引源哈希：%s\n' "$index_source_hash"
    printf -- '- 索引源矩阵版本：%s\n' "$index_source_matrix_version"
    printf -- '- 生成时间：%s\n' "$generated_at"
  } > "$index_temp" || fail 'Cannot build target index summary.'
  mv -f "$index_temp" "$ROOT/资料索引.md" || fail 'Cannot finalize target index summary.'
  rm -f "$authority_list" "$authority_hash_parts"
  printf '{"ok":true,"command":"rebuild-index","root":"%s","layout":"target","entry_count":"%s","index_source_hash":"%s","index_source_matrix_version":"%s","generated_at":"%s"}\n' \
    "$(json_escape "$ROOT")" "$(grep -o '"id"' "$authority_dir/声明索引.json" | wc -l | tr -d '[:space:]')" "$index_source_hash" "$index_source_matrix_version" "$(json_escape "$generated_at")"
}

copy_target_content_for_switch() {
  switch_source=$1
  switch_destination=$2
  mkdir -p "$switch_destination" || return 1
  # Keep the canonical compatibility/history stores intact.  The target's
  # authoritative/derived/index files are copied; raw interviews, backups,
  # trash, and old history remain owned by the canonical root and are covered
  # by the pre-switch snapshot.
  for switch_item in "$switch_source"/* "$switch_source"/.[!.]* "$switch_source"/..?*; do
    [ -e "$switch_item" ] || continue
    switch_name=$(basename "$switch_item")
    case $switch_name in
      .hello-state|.hello-lock|.hello-transaction|.hello-layout-transaction|历史版本|原始访谈|.backups|.trash) continue ;;
    esac
    cp -R "$switch_item" "$switch_destination"/ || return 1
  done
  return 0
}

create_layout_snapshot() {
  snapshot_source=$1
  snapshot_id=$2
  snapshot_version=${3-1}
  snapshot_parent=$snapshot_source/历史版本
  snapshot_path=$snapshot_parent/compat-v$snapshot_version-$snapshot_id
  [ ! -e "$snapshot_path" ] || { SNAPSHOT_PATH=$snapshot_path; return 0; }
  mkdir -p "$snapshot_parent" || return 1
  snapshot_tmp_parent=$(mktemp -d "${TMPDIR:-/tmp}/hello-layout-snapshot.XXXXXX") || return 1
  snapshot_tmp=$snapshot_tmp_parent/canonical
  if ! copy_target_tree "$snapshot_source" "$snapshot_tmp"; then
    rm -rf "$snapshot_tmp_parent" 2>/dev/null || true
    return 1
  fi
  rm -rf "$snapshot_tmp/.hello-lock" "$snapshot_tmp/.hello-transaction" "$snapshot_tmp/.hello-layout-transaction" 2>/dev/null || true
  if ! mv "$snapshot_tmp" "$snapshot_path"; then
    rm -rf "$snapshot_tmp_parent" 2>/dev/null || true
    return 1
  fi
  rmdir "$snapshot_tmp_parent" 2>/dev/null || true
  snapshot_meta_temp=$(mktemp "$snapshot_path/.snapshot.XXXXXX") || return 1
  {
    printf '{"layout_snapshot":true,"migration_id":"%s","profile_version":"%s","created_at":"%s"}\n' \
      "$(json_escape "$snapshot_id")" "$(json_escape "$snapshot_version")" "$(utc_now)"
  } > "$snapshot_meta_temp" || { rm -f "$snapshot_meta_temp"; return 1; }
  mv -f "$snapshot_meta_temp" "$snapshot_path/snapshot.json" || { rm -f "$snapshot_meta_temp"; return 1; }
  SNAPSHOT_PATH=$snapshot_path
  return 0
}

write_layout_transaction() {
  layout_transaction_root=$1
  layout_transaction_id=$2
  layout_transaction_snapshot=$3
  layout_transaction_target=$4
  layout_transaction_temp=$layout_transaction_root/.hello-layout-transaction.$$
  {
    printf 'schema_version=1\n'
    printf 'kind=switch-layout\n'
    printf 'migration_id=%s\n' "$layout_transaction_id"
    printf 'snapshot=%s\n' "${layout_transaction_snapshot#"$layout_transaction_root"/}"
    printf 'target=%s\n' "$layout_transaction_target"
  } > "$layout_transaction_temp" || return 1
  if ! ln "$layout_transaction_temp" "$layout_transaction_root/.hello-layout-transaction" 2>/dev/null; then
    rm -f "$layout_transaction_temp" 2>/dev/null || true
    return 1
  fi
  rm -f "$layout_transaction_temp" 2>/dev/null || true
  return 0
}

remove_layout_transaction() {
  [ ! -e "$1/.hello-layout-transaction" ] || rm -f "$1/.hello-layout-transaction"
}

restore_layout_snapshot_internal() {
  restore_root=$1
  restore_snapshot=$2
  restore_id=$3
  [ -d "$restore_snapshot" ] || return 1
  # Move current non-history content to a recoverable trash area before
  # restoring.  This makes rollback exact while retaining the post-switch
  # target package for forensic recovery.
  restore_trash=$restore_root/.trash/layout-switch-$restore_id-current
  [ ! -e "$restore_trash" ] || restore_trash=$restore_root/.trash/layout-switch-$restore_id-current-$(file_stamp)
  mkdir -p "$restore_trash" || return 1
  for restore_item in "$restore_root"/* "$restore_root"/.[!.]* "$restore_root"/..?*; do
    [ -e "$restore_item" ] || continue
    restore_name=$(basename "$restore_item")
    case $restore_name in
      .hello-lock|.hello-layout-transaction|.hello-transaction|.trash|历史版本) continue ;;
    esac
    mv "$restore_item" "$restore_trash"/ || return 1
  done
  # Copy the snapshot back, preserving all pre-existing canonical files.  A
  # snapshot created by this adapter never contains its own lock/transaction.
  for restore_item in "$restore_snapshot"/* "$restore_snapshot"/.[!.]* "$restore_snapshot"/..?*; do
    [ -e "$restore_item" ] || continue
    restore_name=$(basename "$restore_item")
    case $restore_name in .hello-lock|.hello-layout-transaction|.hello-transaction|snapshot.json) continue ;; esac
    cp -R "$restore_item" "$restore_root"/ || return 1
  done
  rm -f "$restore_root/.hello-layout-transaction" 2>/dev/null || true
  RESTORED_LAYOUT_TRASH=$restore_trash
  return 0
}

switch_layout_command() {
  require_confirmed
  # ROOT is canonical; TARGET_PATH is the formal target package.
  require_valid
  assert_independent_roots "$ROOT" "$TARGET_PATH"
  is_positive_decimal "$EXPECTED_VERSION" || fail '--expected-version must be a positive decimal integer.'
  is_positive_decimal "$EXPECTED_PROGRESS_VERSION" || fail '--expected-progress-version must be a positive decimal integer.'
  read_state || fail "Cannot read canonical state: ${STATE_PARSE_ERROR:-invalid state}"
  [ "$EXPECTED_VERSION" = "$STATE_VERSION" ] || fail "Version conflict: expected $EXPECTED_VERSION, current $STATE_VERSION."
  [ "$EXPECTED_PROGRESS_VERSION" = "$STATE_PROGRESS" ] || fail "Progress version conflict: expected $EXPECTED_PROGRESS_VERSION, current $STATE_PROGRESS."
  acquire_extra_lock "$TARGET_PATH"
  validate_target_space "$TARGET_PATH" || fail "Formal target is invalid: $TARGET_VALIDATION_ISSUES"
  target_marker=$TARGET_PATH/.hello-state
  formal_layout=$(target_marker_value "$target_marker" layout) || formal_layout=
  [ "$formal_layout" = target ] || fail 'switch-layout requires a formal target with layout=target.'
  switch_id=$(target_marker_value "$target_marker" migration_id) || switch_id=
  [ -n "$switch_id" ] || fail 'Formal target has no migration id.'
  [ -n "$MIGRATION_ID" ] && [ "$MIGRATION_ID" != "$switch_id" ] && fail 'Migration id does not match formal target.'
  target_profile_hash=$(target_marker_value "$target_marker" source_profile_sha256) || target_profile_hash=
  target_progress_hash=$(target_marker_value "$target_marker" source_progress_sha256) || target_progress_hash=
  target_pending_hash=$(target_marker_value "$target_marker" source_pending_sha256) || target_pending_hash=
  target_required_source_hashes "$ROOT" || fail 'Cannot hash canonical profile files.'
  [ -z "$target_profile_hash" ] || [ "$target_profile_hash" = "$TARGET_SOURCE_PROFILE_HASH" ] || fail 'Formal target was built from a different profile version.'
  [ -z "$target_progress_hash" ] || [ "$target_progress_hash" = "$TARGET_SOURCE_PROGRESS_HASH" ] || fail 'Formal target was built from a different progress version.'
  [ -z "$target_pending_hash" ] || [ "$target_pending_hash" = "$TARGET_SOURCE_PENDING_HASH" ] || fail 'Formal target was built from different pending information.'
  # If already active with this migration, make the command idempotent.
  if [ -f "$ROOT/.hello-state" ] && grep -q '^layout=target$' "$ROOT/.hello-state" 2>/dev/null; then
    active_id=$(target_marker_value "$ROOT/.hello-state" migration_id) || active_id=
    if [ "$active_id" = "$switch_id" ]; then
      validate_target_space "$ROOT" || fail "Active target is invalid: $TARGET_VALIDATION_ISSUES"
      printf '{"ok":true,"command":"switch-layout","root":"%s","target_root":"%s","migration_id":"%s","idempotent":true}\n' \
        "$(json_escape "$ROOT")" "$(json_escape "$TARGET_PATH")" "$(json_escape "$switch_id")"
      return
    fi
    fail 'Canonical root already uses a different target migration.'
  fi
  create_layout_snapshot "$ROOT" "$switch_id" "$EXPECTED_VERSION" || fail 'Cannot create canonical rollback snapshot.'
  switch_snapshot=$SNAPSHOT_PATH
  write_layout_transaction "$ROOT" "$switch_id" "$switch_snapshot" "$TARGET_PATH" || fail 'Cannot create layout transaction marker.'
  if ! copy_target_content_for_switch "$TARGET_PATH" "$ROOT"; then
    restore_layout_snapshot_internal "$ROOT" "$switch_snapshot" "$switch_id" >/dev/null 2>&1 || true
    fail 'Cannot copy formal target into canonical root; snapshot retained for rollback.'
  fi
  target_package=$(target_marker_value "$target_marker" package_id) || target_package=pkg-local
  target_subject=$(target_marker_value "$target_marker" subject_id) || target_subject=subject-local
  if ! write_target_marker "$ROOT" target "$switch_id" "$target_package" "$target_subject" "$STATE_VERSION" "$STATE_PROGRESS" \
      "$TARGET_SOURCE_PROFILE_HASH" "$TARGET_SOURCE_PROGRESS_HASH" "$TARGET_SOURCE_PENDING_HASH" "$(utc_now)"; then
    restore_layout_snapshot_internal "$ROOT" "$switch_snapshot" "$switch_id" >/dev/null 2>&1 || true
    fail 'Cannot write active target marker; snapshot retained for rollback.'
  fi
  if ! sync_target_compat_state "$ROOT"; then
    restore_layout_snapshot_internal "$ROOT" "$switch_snapshot" "$switch_id" >/dev/null 2>&1 || true
    fail 'Cannot write active target compatibility state; snapshot retained for rollback.'
  fi
  write_target_manifest "$ROOT" target "$switch_id" "$target_package" "$target_subject" "$TARGET_SOURCE_PROFILE_HASH" "$TARGET_SOURCE_PROGRESS_HASH" "$TARGET_SOURCE_PENDING_HASH" "$(utc_now)" "$STATE_VERSION" "$STATE_PROGRESS" || {
    restore_layout_snapshot_internal "$ROOT" "$switch_snapshot" "$switch_id" >/dev/null 2>&1 || true
    fail 'Cannot write active target manifest; snapshot retained for rollback.'
  }
  [ "$SIMULATE_FAILURE" = false ] || fail 'Simulated layout switch failure; run rollback-layout with the migration id.'
  if ! validate_target_space "$ROOT"; then
    fail "Switched canonical target is invalid: $TARGET_VALIDATION_ISSUES"
  fi
  remove_layout_transaction "$ROOT"
  printf '{"ok":true,"command":"switch-layout","root":"%s","target_root":"%s","migration_id":"%s","snapshot":"%s","idempotent":false}\n' \
    "$(json_escape "$ROOT")" "$(json_escape "$TARGET_PATH")" "$(json_escape "$switch_id")" "$(json_escape "$switch_snapshot")"
}

rollback_layout_command() {
  require_confirmed
  [ -n "$MIGRATION_ID" ] || fail 'rollback-layout requires --migration-id.'
  safe_migration_id "$MIGRATION_ID" || fail 'Invalid migration id.'
  snapshot_candidate=
  if [ -f "$ROOT/.hello-layout-transaction" ]; then
    validate_marker_syntax "$ROOT/.hello-layout-transaction" || fail 'Invalid layout transaction marker.'
    transaction_id=$(state_value "$ROOT/.hello-layout-transaction" migration_id) || transaction_id=
    [ "$transaction_id" = "$MIGRATION_ID" ] || fail 'Interrupted transaction migration_id does not match.'
    transaction_snapshot=$(state_value "$ROOT/.hello-layout-transaction" snapshot) || transaction_snapshot=
    case $transaction_snapshot in ''|/*|../*|*/../*|*/..) fail 'Layout transaction snapshot path is unsafe.' ;; esac
    snapshot_candidate=$ROOT/$transaction_snapshot
  else
    # Snapshot names include the guarded compatibility version. Resolve a
    # single matching directory without accepting a user-controlled glob/path.
    for rollback_candidate in "$ROOT"/历史版本/compat-v*-$MIGRATION_ID; do
      [ -d "$rollback_candidate" ] || continue
      if [ -n "$snapshot_candidate" ]; then fail 'Multiple rollback snapshots found for migration id.'; fi
      snapshot_candidate=$rollback_candidate
    done
  fi
  [ -d "$snapshot_candidate" ] || fail 'Rollback snapshot not found.'
  [ -f "$snapshot_candidate/snapshot.json" ] || fail 'Rollback snapshot metadata is missing.'
  snapshot_metadata_compact=$(tr -d '\r\n' < "$snapshot_candidate/snapshot.json")
  snapshot_metadata_migration=$(printf '%s' "$snapshot_metadata_compact" | sed -n 's/.*"migration_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [ "$snapshot_metadata_migration" = "$MIGRATION_ID" ] || fail 'Rollback snapshot migration_id does not match.'
  snapshot_metadata_version=$(printf '%s' "$snapshot_metadata_compact" | sed -n 's/.*"profile_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  is_positive_decimal "$snapshot_metadata_version" || fail 'Rollback snapshot profile_version is invalid.'
  [ -f "$snapshot_candidate/.hello-state" ] || fail 'Rollback snapshot state is missing.'
  snapshot_schema=$(state_value "$snapshot_candidate/.hello-state" schema_version) || snapshot_schema=
  case $snapshot_schema in 1|2) ;; *) fail 'Rollback snapshot must contain a compatibility schema-1/2 state.' ;; esac
  if ! restore_layout_snapshot_internal "$ROOT" "$snapshot_candidate" "$MIGRATION_ID"; then
    fail 'Rollback failed; snapshot and current files were retained.'
  fi
  if ! validate_space true; then
    fail "Rollback restored files but canonical validation failed: $VALIDATION_ISSUES"
  fi
  printf '{"ok":true,"command":"rollback-layout","root":"%s","migration_id":"%s","snapshot":"%s","recovery_trash":"%s"}\n' \
    "$(json_escape "$ROOT")" "$(json_escape "$MIGRATION_ID")" "$(json_escape "$snapshot_candidate")" "$(json_escape "$RESTORED_LAYOUT_TRASH")"
}

assert_cli_parser_error() {
  expected_command=$1
  shift
  parser_output=$(sh "$0" "$@" 2>/dev/null)
  parser_code=$?
  [ "$parser_code" -eq 2 ] || fail 'Self-test parser probe returned a non-2 exit code.'
  printf '%s' "$parser_output" | grep -q '"ok":false' || fail 'Self-test parser probe did not return JSON failure.'
  printf '%s' "$parser_output" | grep -q "\"command\":\"$expected_command\"" || fail 'Self-test parser command field mismatch.'
  printf '%s' "$parser_output" | grep -q '"error":"[^"]' || fail 'Self-test parser error field missing.'
}

assert_explicit_root_guard() {
  state_before=$(cksum "$1/.hello-state") || fail 'Self-test could not snapshot state for root guard.'
  guard_output=$(HELLO_HOME="$1" sh "$0" record-disclosure --confirmed 2>/dev/null)
  guard_code=$?
  [ "$guard_code" -eq 2 ] || fail 'Self-test mutation without explicit root did not fail.'
  printf '%s' "$guard_output" | grep -q '"ok":false' || fail 'Self-test root-guard probe did not return JSON failure.'
  printf '%s' "$guard_output" | grep -q -- '--root' || fail 'Self-test root-guard error did not mention --root.'
  state_after=$(cksum "$1/.hello-state") || fail 'Self-test could not re-read state for root guard.'
  [ "$state_before" = "$state_after" ] || fail 'Self-test root-guard probe changed state.'
}

self_test() {
  assert_cli_parser_error not-a-command not-a-command
  assert_cli_parser_error status status --unknown-option
  assert_cli_parser_error status status --simulate-failure
  assert_cli_parser_error status status --root --confirmed
  assert_cli_parser_error status status --confirmed
  assert_cli_parser_error status status --r /tmp/hello-no-root
  assert_cli_parser_error status status --root=/tmp/hello-no-root
  assert_cli_parser_error status status --root /tmp/hello-one --root /tmp/hello-two
  assert_cli_parser_error status status --
  assert_cli_parser_error init init --confirmed
  assert_cli_parser_error target-validate target-validate
  assert_cli_parser_error migrate-plan migrate-plan --root /tmp/hello-source --confirmed
  assert_cli_parser_error migrate-apply migrate-apply --root /tmp/hello-source --target /tmp/hello-draft --confirmed
  assert_cli_parser_error switch-layout switch-layout --root /tmp/hello-source --target /tmp/hello-formal --confirmed
  assert_cli_parser_error rollback-layout rollback-layout --root /tmp/hello-source --confirmed
  export HELLO_SELF_TEST_ACTIVE=1
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/hello-self-test.XXXXXX") || fail 'Cannot create self-test directory.'
  # Keep cleanup owned by the top-level self-test shell.  Bash runs EXIT traps
  # in command-substitution subshells; without this guard a nested probe such
  # as `status=$(sh "$0" ...)` can remove the fixture while the parent is still
  # using it.  `BASHPID` is optional so native POSIX shells retain the same
  # behavior when they do not expose it.
  self_test_main_bashpid=${BASHPID-}
  self_test_cleanup() {
    # Bash command substitutions increment BASH_SUBSHELL even when the
    # compatibility `sh` wrapper reports the same BASHPID.  Use that stable
    # signal first; otherwise a nested probe such as `status=$(sh "$0" ...)`
    # can run the parent EXIT trap and remove the fixture mid-test.
    if [ "${BASH_SUBSHELL-0}" -ne 0 ]; then
      return 0
    fi
    if [ -n "${self_test_main_bashpid-}" ] && [ "${BASHPID-}" != "$self_test_main_bashpid" ]; then
      return 0
    fi
    rm -rf "$temporary"
  }
  trap 'self_test_cleanup' EXIT
  if is_iso_utc '2030-01-01T00:00:00+08:00'; then fail 'Self-test accepted a non-UTC timestamp.'; fi
  if is_iso_utc '2030-02-30T00:00:00Z'; then fail 'Self-test accepted an invalid calendar timestamp.'; fi
  if is_iso_utc '0000-01-01T00:00:00Z'; then fail 'Self-test accepted year zero.'; fi
  if is_iso_utc '2030-01-01T00:00:00z'; then fail 'Self-test accepted a lowercase UTC marker.'; fi
  root=$temporary/中文\ 空格
  candidate=$temporary/candidate.md
  profile=$temporary/profile.md
  summary=$temporary/summary.md
  progress=$temporary/progress.md
  turn=$temporary/turn.md
  printf '用户完成了一个重要项目。\n' > "$candidate"
  if sh "$0" init --root "$root" >/dev/null 2>&1; then fail 'Confirmation guard did not fail.'; fi
  sh "$0" init --root "$root" --confirmed >/dev/null || fail 'Self-test init failed.'
  assert_explicit_root_guard "$root"
  second_init=$(sh "$0" init --root "$root" --confirmed) || fail 'Self-test second init failed.'
  printf '%s' "$second_init" | grep -q '"created":\[\]' || fail 'Self-test init overwrote existing space.'
  if HELLO_HOME="$root" sh "$0" status --root '' >/dev/null 2>&1; then fail 'Self-test explicit empty root fell back to HELLO_HOME.'; fi
  if HELLO_HOME="$root" sh "$0" status --root '   ' >/dev/null 2>&1; then fail 'Self-test whitespace root fell back to HELLO_HOME.'; fi
  validation=$(sh "$0" validate --root "$root" 2>&1) || fail "Self-test validate failed: $validation"
  long_version=$(awk 'BEGIN { for (i = 1; i <= 40; i++) printf "9" }')
  long_zeros=$(awk 'BEGIN { for (i = 1; i <= 40; i++) printf "0" }')
  expected_long_increment="1$long_zeros"
  [ "$(decimal_increment "$long_version")" = "$expected_long_increment" ] || fail 'Self-test long decimal version handling failed.'
  [ "$(decimal_increment 1)" = 2 ] || fail 'Self-test single-digit decimal increment failed.'
  [ "$(decimal_increment 19)" = 20 ] || fail 'Self-test carry decimal increment failed.'
  decimal_compare 9 10; [ "$?" -eq 1 ] || fail 'Self-test decimal comparison failed.'
  decimal_compare 10 9; [ "$?" -eq 2 ] || fail 'Self-test decimal comparison failed.'
  for name in README.md 个人全景档案.md 待确认信息.md 访谈进度.md 资料索引.md 迭代日志.md; do
    cr_count=$(LC_ALL=C tr -cd '\r' < "$root/$name" | wc -c | tr -d ' ')
    [ "$cr_count" -eq 0 ] || fail "Self-test init left CR in $name."
  done
  {
    printf '%s\n' 'schema_version=1' 'kind=record-turn' 'duplicate=x' 'duplicate=y'
  } > "$root/.hello-transaction"
  if sh "$0" recover --root "$root" --confirmed >/dev/null 2>&1; then fail 'Self-test accepted a malformed transaction marker.'; fi
  [ -f "$root/.hello-transaction" ] || fail 'Self-test removed a malformed transaction marker.'
  rm -f "$root/.hello-transaction"
  {
    printf '%s\n' 'schema_version=1' 'PROFILE_VERSION=shadow' 'profile_version=1'
  } > "$root/.hello-transaction"
  if sh "$0" recover --root "$root" --confirmed >/dev/null 2>&1; then fail 'Self-test accepted case-variant transaction keys.'; fi
  [ -f "$root/.hello-transaction" ] || fail 'Self-test removed a case-variant transaction marker.'
  rm -f "$root/.hello-transaction"
  cp "$root/个人全景档案.md" "$temporary/profile.before-missing"
  printf '%s\n' 'schema_version=1' 'kind=apply' 'profile_backup=.backups/transactions/missing-profile.md' > "$root/.hello-transaction"
  if sh "$0" recover --root "$root" --confirmed >/dev/null 2>&1; then fail 'Self-test accepted a missing transaction backup.'; fi
  [ -f "$root/.hello-transaction" ] || fail 'Self-test removed a missing-backup marker.'
  cmp -s "$temporary/profile.before-missing" "$root/个人全景档案.md" || fail 'Self-test changed a target before missing-backup failure.'
  rm -f "$root/.hello-transaction"
  for incomplete_marker in 'schema_version=1
kind=apply' 'schema_version=1
kind=record-turn'; do
    printf '%b\n' "$incomplete_marker" > "$root/.hello-transaction"
    if sh "$0" recover --root "$root" --confirmed >/dev/null 2>&1; then fail 'Self-test accepted an incomplete transaction marker.'; fi
    [ -f "$root/.hello-transaction" ] || fail 'Self-test removed an incomplete transaction marker.'
    rm -f "$root/.hello-transaction"
  done
  blank=$temporary/blank.md
  printf ' \t\n' > "$blank"
  if sh "$0" stage --root "$root" --input "$blank" --confirmed >/dev/null 2>&1; then fail 'Self-test accepted a whitespace-only candidate.'; fi
  state_snapshot=$temporary/state.v2
  cp "$root/.hello-state" "$state_snapshot"
  sed 's/^created_at=.*/created_at=2030-02-30T00:00:00Z/' "$state_snapshot" > "$root/.hello-state.invalid"
  mv "$root/.hello-state.invalid" "$root/.hello-state"
  if sh "$0" validate --root "$root" >/dev/null 2>&1; then fail 'Self-test accepted an invalid created_at date.'; fi
  cp "$state_snapshot" "$root/.hello-state"
  sed '/^next_review_at=/d' "$state_snapshot" > "$root/.hello-state.invalid"
  mv "$root/.hello-state.invalid" "$root/.hello-state"
  if sh "$0" validate --root "$root" >/dev/null 2>&1; then fail 'Self-test accepted a state without next_review_at.'; fi
  cp "$state_snapshot" "$root/.hello-state"
  sed '1a schema_version=2' "$state_snapshot" > "$root/.hello-state.invalid"
  mv "$root/.hello-state.invalid" "$root/.hello-state"
  if sh "$0" validate --root "$root" >/dev/null 2>&1; then fail 'Self-test accepted a duplicate state key.'; fi
  cp "$state_snapshot" "$root/.hello-state"
  sed '1i malformed-state-line' "$state_snapshot" > "$root/.hello-state.invalid"
  mv "$root/.hello-state.invalid" "$root/.hello-state"
  if sh "$0" validate --root "$root" >/dev/null 2>&1; then fail 'Self-test accepted a malformed state line.'; fi
  cp "$state_snapshot" "$root/.hello-state"
  sed 's/^profile_version=1$/profile_version=01/' "$state_snapshot" > "$root/.hello-state.invalid"
  mv "$root/.hello-state.invalid" "$root/.hello-state"
  if sh "$0" validate --root "$root" >/dev/null 2>&1; then fail 'Self-test accepted a leading-zero state version.'; fi
  cp "$state_snapshot" "$root/.hello-state"
  cp "$root/个人全景档案.md" "$temporary/profile.canonical"
  sed 's/^- 资料版本：1$/- 资料版本：01/' "$temporary/profile.canonical" > "$root/个人全景档案.md"
  if sh "$0" validate --root "$root" >/dev/null 2>&1; then fail 'Self-test accepted a leading-zero profile version.'; fi
  cp "$temporary/profile.canonical" "$root/个人全景档案.md"
  cp "$root/访谈进度.md" "$temporary/progress.canonical"
  sed 's/^- 进度版本：1$/- 进度版本：01/' "$temporary/progress.canonical" > "$root/访谈进度.md"
  if sh "$0" validate --root "$root" >/dev/null 2>&1; then fail 'Self-test accepted a leading-zero progress version.'; fi
  cp "$temporary/progress.canonical" "$root/访谈进度.md"
  sed -e 's/^schema_version=2$/schema_version=1/' -e '/^progress_version=/d' -e '/^last_session_id=/d' -e '/^last_turn_id=/d' "$state_snapshot" > "$root/.hello-state.legacy"
  mv "$root/.hello-state.legacy" "$root/.hello-state"
  legacy_status=$(sh "$0" status --root "$root") || fail 'Self-test legacy schema status failed.'
  printf '%s' "$legacy_status" | grep -q '"baseline_split_unknown":true' || fail 'Self-test legacy schema status did not block baseline.'
  legacy_disclosure=$(sh "$0" record-disclosure --root "$root" --capture-mode prompt --confirmed) || fail 'Self-test legacy record-disclosure failed.'
  grep -q '^schema_version=1$' "$root/.hello-state" || fail 'Self-test legacy record-disclosure changed schema.'
  if grep -q '^progress_version=' "$root/.hello-state" || grep -q '^last_session_id=' "$root/.hello-state" || grep -q '^last_turn_id=' "$root/.hello-state"; then fail 'Self-test legacy record-disclosure added schema-2 cursor fields.'; fi
  cp "$state_snapshot" "$root/.hello-state"
  mkdir "$root/.hello-lock" || fail 'Self-test could not create profile lock.'
  if sh "$0" stage --root "$root" --input "$candidate" --kind 经历 --source 自测 --confirmed >/dev/null 2>&1; then
    rm -rf "$root/.hello-lock"
    fail 'Self-test stage ignored an active profile lock.'
  fi
  rmdir "$root/.hello-lock" || fail 'Self-test could not remove profile lock.'
  sh "$0" record-disclosure --root "$root" --capture-mode prompt --confirmed >/dev/null || fail 'Self-test disclosure before stage failed.'
  bom_candidate=$temporary/bom.md
  nbsp_candidate=$temporary/nbsp.md
  printf '\357\273\277' > "$bom_candidate"
  printf '\302\240' > "$nbsp_candidate"
  if sh "$0" stage --root "$root" --input "$bom_candidate" --confirmed >/dev/null 2>&1; then fail 'Self-test accepted a BOM-only candidate.'; fi
  if sh "$0" stage --root "$root" --input "$nbsp_candidate" --confirmed >/dev/null 2>&1; then fail 'Self-test accepted an NBSP-only candidate.'; fi
  staged=$(sh "$0" stage --root "$root" --input "$candidate" --kind 经历 --source 自测 --confirmed) || fail 'Self-test stage failed.'
  staged_id=$(printf '%s' "$staged" | sed -n 's/.*"candidate_id":"\([^"]*\)".*/\1/p')
  [ -n "$staged_id" ] || fail 'Self-test could not read candidate id.'
  { tr -d '\r' < "$root/.hello-state"; printf 'legacy_crlf=keep\r\n'; } > "$root/.hello-state.crlf"
  mv "$root/.hello-state.crlf" "$root/.hello-state"
  disclosure_before_configure=$(sed -n 's/^last_capture_disclosed_at=//p' "$root/.hello-state")
  sh "$0" configure --root "$root" --capture-mode prompt --next-review-at 2030-01-01T00:00:00Z --confirmed >/dev/null || fail 'Self-test configure failed.'
  grep -q '^legacy_crlf=keep$' "$root/.hello-state" || fail 'Self-test did not preserve an unknown state key.'
  cr_count=$(LC_ALL=C tr -cd '\r' < "$root/.hello-state" | wc -c | tr -d ' ')
  [ "$cr_count" -eq 0 ] || fail 'Self-test state rewrite left CRLF in an unknown key.'
  disclosure_after_configure=$(sed -n 's/^last_capture_disclosed_at=//p' "$root/.hello-state")
  [ "$disclosure_after_configure" = "$disclosure_before_configure" ] || fail 'Self-test configure faked a disclosure timestamp.'
  disclosed_status=$(sh "$0" status --root "$root") || fail 'Self-test status after configure failed.'
  printf '%s' "$disclosed_status" | grep -Eq '"capture_mode":"prompt".*"last_capture_disclosed_at":"[^"]+".*"last_capture_disclosed_mode":"prompt"' || fail 'Self-test configure changed disclosure timestamp.'
  printf '%s' "$disclosed_status" | grep -q '"baseline_split_unknown":false' || fail 'Self-test baseline split status failed.'
  # Changing the policy invalidates the previous disclosure until the new
  # effective policy is shown and recorded.
  sh "$0" configure --root "$root" --capture-mode auto-stage --confirmed >/dev/null || fail 'Self-test policy change failed.'
  if sh "$0" stage --root "$root" --input "$candidate" --kind 经历 --source 自测-无披露 --confirmed >/dev/null 2>&1; then fail 'Self-test stage accepted a policy without a matching disclosure.'; fi
  sh "$0" record-disclosure --root "$root" --capture-mode auto-stage --confirmed >/dev/null || fail 'Self-test auto-stage disclosure failed.'
  recorded_disclosure=$(sh "$0" record-disclosure --root "$root" --capture-mode auto-stage --confirmed) || fail 'Self-test record-disclosure failed.'
  printf '%s' "$recorded_disclosure" | grep -Eq '"capture_mode":"auto-stage".*"last_capture_disclosed_at":"[^\"]+".*"last_capture_disclosed_mode":"auto-stage"' || fail 'Self-test record-disclosure output failed.'
  if sh "$0" record-disclosure --root "$root" --capture-mode explicit --confirmed >/dev/null 2>&1; then fail 'Self-test accepted a stale capture mode.'; fi
  state_snapshot=$temporary/state.snapshot
  cp "$root/.hello-state" "$state_snapshot"
  sed 's/^last_capture_disclosed_at=.*/last_capture_disclosed_at=not-a-timestamp/' "$state_snapshot" > "$root/.hello-state.invalid"
  mv "$root/.hello-state.invalid" "$root/.hello-state"
  if sh "$0" validate --root "$root" >/dev/null 2>&1; then fail 'Self-test accepted invalid disclosure timestamp.'; fi
  mv "$state_snapshot" "$root/.hello-state"
  sh "$0" stage --root "$root" --input "$candidate" --kind 经历 --source 自测-再次 --confirmed >/dev/null || fail 'Self-test stage after configure failed.'
  disclosed_after_stage=$(sh "$0" status --root "$root") || fail 'Self-test status after stage failed.'
  printf '%s' "$disclosed_after_stage" | grep -Eq '"last_capture_disclosed_at":"[^"]+"' || fail 'Self-test disclosure timestamp was cleared by stage.'
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
  sed -e 's/^schema_version=2$/schema_version=1/' -e '/^progress_version=/d' -e '/^last_session_id=/d' -e '/^last_turn_id=/d' "$root/.hello-state" > "$root/.hello-state.legacy"
  printf '%s\n' 'legacy_marker=keep' >> "$root/.hello-state.legacy"
  mv "$root/.hello-state.legacy" "$root/.hello-state"
  cp "$root/访谈进度.md" "$temporary/progress.legacy"
  sed '/^- 进度版本：/d' "$temporary/progress.legacy" > "$root/访谈进度.md"
  if sh "$0" apply --root "$root" --input "$profile" --summary-input "$summary" --expected-version 1 --confirmed --simulate-failure >/dev/null 2>&1; then fail 'Simulated apply failure did not fail.'; fi
  validation=$(sh "$0" validate --root "$root" 2>&1) || fail "Self-test rollback validation failed: $validation"
  grep -q '^- 进度版本：' "$root/访谈进度.md" && fail 'Self-test rollback unexpectedly added progress metadata.'
  applied=$(sh "$0" apply --root "$root" --input "$profile" --summary-input "$summary" --expected-version 1 --confirmed 2>&1) || fail "Self-test apply failed: $applied"
  grep -q '^schema_version=2$' "$root/.hello-state" || fail 'Self-test schema migration did not upgrade schema.'
  grep -q '^progress_version=1$' "$root/.hello-state" || fail 'Self-test schema migration missed progress default.'
  grep -q '^last_session_id=$' "$root/.hello-state" || fail 'Self-test schema migration missed session default.'
  grep -q '^last_turn_id=$' "$root/.hello-state" || fail 'Self-test schema migration missed turn default.'
  grep -q '^legacy_marker=keep$' "$root/.hello-state" || fail 'Self-test schema migration dropped unknown state key.'
  grep -q '^- 进度版本：1$' "$root/访谈进度.md" || fail 'Self-test schema migration did not add progress metadata.'
  [ -z "$(find "$root/.backups/transactions" -type f -print -quit)" ] || fail 'Transaction backups were not cleaned after apply.'
  if sh "$0" apply --root "$root" --input "$profile" --summary-input "$summary" --expected-version 1 --confirmed >/dev/null 2>&1; then
    fail 'Version conflict did not fail.'
  fi
  cp "$root/访谈进度.md" "$progress"
  printf '%s\n' '# 自测访谈轮次' '' '- 仅使用临时数据。' > "$turn"
  blank_turn=$temporary/blank-turn.md
  printf ' \t\n' > "$blank_turn"
  if sh "$0" record-turn --root "$root" --session-id 2030-01-01-self-test --turn-id Q000 --input "$blank_turn" --progress-input "$progress" --expected-progress-version 1 --confirmed >/dev/null 2>&1; then fail 'Self-test accepted a whitespace-only turn.'; fi
  malformed_progress=$temporary/malformed-progress.md
  sed 's/^- 进度版本：.*/- 进度版本：abc/' "$progress" > "$malformed_progress"
  if sh "$0" record-turn --root "$root" --session-id 2030-01-01-self-test --turn-id Q000 --input "$turn" --progress-input "$malformed_progress" --expected-progress-version 1 --confirmed >/dev/null 2>&1; then fail 'Self-test accepted malformed progress metadata.'; fi
  duplicate_progress=$temporary/duplicate-progress.md
  {
    cat "$progress"
    printf '%s\n' '- 进度版本：1'
  } > "$duplicate_progress"
  if sh "$0" record-turn --root "$root" --session-id 2030-01-01-self-test --turn-id Q000 --input "$turn" --progress-input "$duplicate_progress" --expected-progress-version 1 --confirmed >/dev/null 2>&1; then fail 'Self-test accepted duplicate progress metadata.'; fi
  long_session="2030-01-01-$(awk 'BEGIN { for (i = 1; i <= 118; i++) printf "x" }')"
  if sh "$0" record-turn --root "$root" --session-id "$long_session" --turn-id Q001 --input "$turn" --progress-input "$progress" --expected-progress-version 1 --confirmed >/dev/null 2>&1; then fail 'Self-test accepted an overlong session id.'; fi
  long_turn="Q$(awk 'BEGIN { for (i = 1; i <= 128; i++) printf "x" }')"
  if sh "$0" record-turn --root "$root" --session-id 2030-01-01-self-test --turn-id "$long_turn" --input "$turn" --progress-input "$progress" --expected-progress-version 1 --confirmed >/dev/null 2>&1; then fail 'Self-test accepted an overlong turn id.'; fi
  sh "$0" record-turn --root "$root" --session-id 2030-01-01-self-test --turn-id Q001 --input "$turn" --progress-input "$progress" --expected-progress-version 1 --confirmed >/dev/null || fail 'Self-test record-turn failed.'
  [ -z "$(find "$root/.backups/transactions" -type f -print -quit)" ] || fail 'Transaction backups were not cleaned after record-turn.'
  idempotent=$(sh "$0" record-turn --root "$root" --session-id 2030-01-01-self-test --turn-id Q001 --input "$turn" --progress-input "$progress" --expected-progress-version 1 --confirmed) || fail 'Self-test idempotent record-turn failed.'
  printf '%s' "$idempotent" | grep -q '"idempotent":true' || fail 'Self-test record-turn was not idempotent.'
  turn2=$temporary/turn-2.md
  printf '%s\n' '# 第二轮记录' '' '- 仅使用隔离自测数据。' > "$turn2"
  progress2=$temporary/progress-2.md
  sed 's/下一项自测。/第二项自测。/' "$root/访谈进度.md" > "$progress2"
  second_record=$(sh "$0" record-turn --root "$root" --session-id 2030-01-01-self-test --turn-id Q002 --input "$turn2" --progress-input "$progress2" --expected-progress-version 2 --confirmed) || fail 'Self-test second record-turn failed.'
  printf '%s' "$second_record" | grep -q '"idempotent":false' || fail 'Self-test second record-turn was unexpectedly idempotent.'
  old_retry=$(sh "$0" record-turn --root "$root" --session-id 2030-01-01-self-test --turn-id Q001 --input "$turn" --progress-input "$progress" --expected-progress-version 1 --confirmed) || fail 'Self-test old record-turn retry failed.'
  printf '%s' "$old_retry" | grep -q '"idempotent":true' || fail 'Self-test old record-turn retry was not idempotent.'
  sh "$0" configure --root "$root" --review-stage first-review --next-review-at 2030-02-01T00:00:00Z --confirmed >/dev/null || fail 'Self-test explicit baseline completion failed.'
  state_before_clear=$temporary/state.before-clear
  cp "$root/.hello-state" "$state_before_clear"
  if sh "$0" configure --root "$root" --next-review-at none --confirmed >/dev/null 2>&1; then fail 'Self-test first-review clear guard did not fail.'; fi
  cmp -s "$state_before_clear" "$root/.hello-state" || fail 'Self-test first-review clear changed state.'
  if sh "$0" configure --root "$root" --capture-mode prompt --next-review-at '' --confirmed >/dev/null 2>&1; then fail 'Self-test empty next-review clear guard did not fail.'; fi
  cmp -s "$state_before_clear" "$root/.hello-state" || fail 'Self-test empty next-review clear changed state.'
  awk '{printf "%s\r\n", $0}' "$root/待确认信息.md" > "$root/待确认信息.md.crlf"
  mv "$root/待确认信息.md.crlf" "$root/待确认信息.md"
  sh "$0" withdraw --root "$root" --id "$staged_id" --confirmed >/dev/null || fail 'Self-test withdraw failed for CRLF pending data.'
  validation=$(sh "$0" validate --root "$root" 2>&1) || fail "Self-test final validation failed: $validation"

  # Target-layout migration fixture: all content is synthetic and isolated
  # under the self-test temporary directory.  Exercise the full plan -> apply
  # -> index -> switch -> status -> rollback path, plus the version fence.
  target_source=$temporary/target-source
  target_draft=$temporary/target-draft
  target_formal=$temporary/target-formal
  sh "$0" init --root "$target_source" --confirmed >/dev/null || fail 'Self-test target source init failed.'
  target_required_source_hashes "$target_source" || fail 'Self-test target source hashing failed.'
  target_saved_root=${ROOT-}; ROOT=$target_source
  target_init_draft "$target_draft" self-test-layout 1 1 "$TARGET_SOURCE_PROFILE_HASH" "$TARGET_SOURCE_PROGRESS_HASH" "$TARGET_SOURCE_PENDING_HASH" "$(utc_now)" pkg-self-test subject-self-test || fail 'Self-test target draft fixture creation failed.'
  ROOT=$target_saved_root
  target_plan=$(sh "$0" migrate-plan --root "$target_source" --target "$target_draft" --migration-id self-test-layout) || fail 'Self-test migrate-plan failed.'
  printf '%s' "$target_plan" | grep -q '"migration_id":"self-test-layout"' || fail 'Self-test migrate-plan id missing.'
  sh "$0" target-validate --root "$target_draft" >/dev/null || fail 'Self-test target draft validation failed.'
  if sh "$0" migrate-apply --root "$target_source" --target "$target_draft" --destination "$target_formal" --expected-version 2 --expected-progress-version 1 --confirmed >/dev/null 2>&1; then
    fail 'Self-test migration version fence did not fail.'
  fi
  sh "$0" migrate-apply --root "$target_source" --target "$target_draft" --destination "$target_formal" --expected-version 1 --expected-progress-version 1 --confirmed >/dev/null || fail 'Self-test migrate-apply failed.'
  sh "$0" target-validate --root "$target_formal" >/dev/null || fail 'Self-test formal target validation failed.'
  sh "$0" rebuild-index --root "$target_formal" --confirmed >/dev/null || fail 'Self-test rebuild-index failed.'
  sh "$0" switch-layout --root "$target_source" --target "$target_formal" --expected-version 1 --expected-progress-version 1 --confirmed >/dev/null || fail 'Self-test switch-layout failed.'
  target_status=$(sh "$0" status --root "$target_source") || fail 'Self-test target status failed.'
  printf '%s' "$target_status" | grep -q '"layout":"target"' || fail 'Self-test target status did not expose layout.'
  sh "$0" rollback-layout --root "$target_source" --migration-id self-test-layout --confirmed >/dev/null || fail 'Self-test rollback-layout failed.'
  sh "$0" validate --root "$target_source" >/dev/null || fail 'Self-test post-rollback validation failed.'
  rm -rf "$temporary"
  trap - EXIT HUP INT TERM
  unset HELLO_SELF_TEST_ACTIVE
  printf '%s\n' '{"ok":true,"command":"self-test"}'
}

if [ "$COMMAND" = self-test ]; then
  self_test
  exit 0
fi

resolve_root

# Resolve secondary target/destination roots only for the target-layout
# commands.  They never inherit HELLO_HOME and are checked for independence
# inside each command before any write occurs.
case $COMMAND in
  target-validate)
    # For target-validate --root itself is the target root.
    ;;
  migrate-plan|migrate-apply|switch-layout)
    resolve_explicit_path "$TARGET_ARG" '--target'
    TARGET_PATH=$SECONDARY_PATH
    if [ "$COMMAND" = migrate-apply ] && [ "$DESTINATION_ARG_SET" = true ]; then
      resolve_explicit_path "$DESTINATION_ARG" '--destination'
      DESTINATION_PATH=$SECONDARY_PATH
    fi
    ;;
esac

# Serialize every public operation that touches a profile space.  `init`
# creates its root only after the confirmation guard, then contends for the
# same atomic directory lock; read-only commands on a missing root need no
# lock and simply report the missing space.
if [ "$COMMAND" = init ]; then
  require_confirmed
  mkdir -p "$ROOT" || fail "Cannot create root: $ROOT"
fi
if [ "$COMMAND" != resolve-root ]; then
  acquire_store_lock
fi

case $COMMAND in
  resolve-root)
    printf '{"ok":true,"command":"resolve-root","root":"%s"}\n' "$(json_escape "$ROOT")" ;;
  init) init_space ;;
  validate)
    if validate_space; then
      printf '{"ok":true,"command":"validate","root":"%s","issues":[]}\n' "$(json_escape "$ROOT")"
    else
      printf '{"ok":false,"command":"validate","root":"%s","issues":%s}\n' "$(json_escape "$ROOT")" "$VALIDATION_ISSUES_JSON"
      exit 1
    fi ;;
  status) status_space ;;
  recover) recover_space ;;
  configure) configure_space ;;
  record-disclosure) record_disclosure ;;
  diff)
    require_valid
    [ -n "$INPUT" ] || fail 'diff requires --input.'
    [ -f "$INPUT" ] || fail "Candidate profile does not exist: $INPUT"
    # Python and PowerShell normalize CRLF/CR while reading text.  Normalize
    # both inputs here too, so `diff` agrees with `apply` instead of treating
    # line-ending-only changes as substantive edits.
    diff_old=$(mktemp "${TMPDIR:-/tmp}/hello-diff-old.XXXXXX") || fail 'Cannot create diff temporary file.'
    diff_new=$(mktemp "${TMPDIR:-/tmp}/hello-diff-new.XXXXXX") || { rm -f "$diff_old"; fail 'Cannot create diff temporary file.'; }
    if ! sed 's/\r$//' "$ROOT/个人全景档案.md" > "$diff_old" || ! sed 's/\r$//' "$INPUT" > "$diff_new"; then
      rm -f "$diff_old" "$diff_new"
      fail 'Cannot normalize diff input.'
    fi
    if cmp -s "$diff_old" "$diff_new"; then
      rm -f "$diff_old" "$diff_new"
      printf '%s\n' 'No changes.'
    else
      diff -u "$diff_old" "$diff_new"
      diff_code=$?
      rm -f "$diff_old" "$diff_new"
      [ "$diff_code" -eq 1 ] || exit "$diff_code"
    fi ;;
  stage) stage_candidate ;;
  apply) apply_profile ;;
  record-turn) record_turn ;;
  withdraw) withdraw_candidate ;;
  target-validate) target_validate_command ;;
  migrate-plan) migrate_plan_command ;;
  migrate-apply) migrate_apply_command ;;
  rebuild-index) rebuild_index_command ;;
  switch-layout) switch_layout_command ;;
  rollback-layout) rollback_layout_command ;;
esac
