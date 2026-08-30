#!/bin/sh

set -u
umask 077

COMMAND=${1-}
[ -n "$COMMAND" ] || { printf '%s\n' '{"ok":false,"command":"","error":"Command is required."}'; exit 2; }
shift

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
    --root|--input|--summary-input|--expected-version|--kind|--source|--id|--capture-mode|--next-review-at|--review-stage|--session-id|--turn-id|--progress-input|--expected-progress-version)
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
      esac
      shift 2 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

case $COMMAND in
  resolve-root|init|validate|status|configure|record-disclosure|diff|stage|apply|withdraw|record-turn|recover|self-test) ;;
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
      init:confirmed|configure:confirmed|record-disclosure:confirmed|stage:confirmed|apply:confirmed|record-turn:confirmed|withdraw:confirmed|recover:confirmed) ;;
      *) fail "Option --$option is not valid for $COMMAND." ;;
    esac
  done
  case $COMMAND in
    resolve-root|validate|status|diff|self-test)
      [ "$CONFIRMED" = false ] || fail "Option --confirmed is not valid for $COMMAND." ;;
  esac
  case $COMMAND in
    apply|record-turn) ;;
    *) [ "$SIMULATE_FAILURE" = false ] || fail "Option --simulate-failure is not valid for $COMMAND." ;;
  esac
  case $COMMAND in
    init|configure|record-disclosure|stage|apply|record-turn|withdraw|recover)
      [ "$ROOT_ARG_SET" = true ] || fail 'Mutating commands require an explicit --root.' ;;
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
  [ -n "$raw" ] || fail 'Personal profile root is not configured. Pass --root or set HELLO_HOME.'
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

require_confirmed() {
  [ "$CONFIRMED" = true ] || fail 'Mutating commands require --confirmed after user authorization.'
}

release_store_lock() {
  [ "${STORE_LOCK_HELD-}" = true ] || return 0
  STORE_LOCK_HELD=false
  # Never remove a lock that no longer carries this process's owner marker.
  if [ ! -e "$STORE_LOCK_PATH/owner" ] || { [ -f "$STORE_LOCK_PATH/owner" ] && [ "$(sed -n 's/^pid=//p' "$STORE_LOCK_PATH/owner" | head -n 1)" = "$STORE_LOCK_PID" ]; }; then
    rm -f "$STORE_LOCK_PATH/owner" 2>/dev/null || true
    rmdir "$STORE_LOCK_PATH" 2>/dev/null || true
  fi
}

acquire_store_lock() {
  [ -d "$ROOT" ] || return 0
  STORE_LOCK_PATH=$ROOT/.hello-lock
  STORE_LOCK_PID=$$
  if ! mkdir "$STORE_LOCK_PATH" 2>/dev/null; then
    fail 'Profile space is busy; retry after the active operation finishes.'
  fi
  STORE_LOCK_HELD=true
  trap 'release_store_lock' 0 1 2 3 15
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
    if [ "$state_schema" = 2 ] || [ "$state_interview_present" = true ] || [ -n "$state_interview" ]; then
      printf 'last_interview_at=%s\n' "$state_interview"
    fi
    if [ "$state_schema" = 2 ] || [ "$state_progress_present" = true ]; then printf 'progress_version=%s\n' "$state_progress"; fi
    if [ "$state_schema" = 2 ] || [ "$state_session_present" = true ]; then printf 'last_session_id=%s\n' "$state_session"; fi
    if [ "$state_schema" = 2 ] || [ "$state_turn_present" = true ]; then printf 'last_turn_id=%s\n' "$state_turn"; fi
    if [ "$state_schema" = 2 ] || [ "$state_disclosed_present" = true ] || [ -n "${state_disclosed-}" ]; then
      printf 'last_capture_disclosed_at=%s\n' "${state_disclosed-}"
    fi
    if [ "$state_schema" = 2 ] || [ "$state_disclosed_mode_present" = true ] || [ -n "${state_disclosed_mode-}" ]; then
      printf 'last_capture_disclosed_mode=%s\n' "${state_disclosed_mode-}"
    fi
    if [ -f "$state_path" ]; then
      tr -d '\r' < "$state_path" | awk -F= '
        BEGIN { reserved["schema_version"]=1; reserved["profile_version"]=1; reserved["capture_mode"]=1; reserved["created_at"]=1; reserved["updated_at"]=1; reserved["last_confirmed_at"]=1; reserved["next_review_at"]=1; reserved["review_stage"]=1; reserved["last_interview_at"]=1; reserved["progress_version"]=1; reserved["last_session_id"]=1; reserved["last_turn_id"]=1; reserved["last_capture_disclosed_at"]=1; reserved["last_capture_disclosed_mode"]=1 }
        { key=tolower($1); if (!reserved[key]) print }
      '
    fi
  } > "$state_temp" || fail "Cannot write state file: $state_path"
  mv -f "$state_temp" "$state_path" || fail "Cannot replace state file: $state_path"
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
    write_state "$ROOT/.hello-state" 2 1 prompt "$current" "$current" '' '' baseline '' 1 '' '' '' ''
    add_created .hello-state
  fi
  printf '{"ok":true,"command":"init","root":"%s","created":[%s]}\n' "$(json_escape "$ROOT")" "$created_json"
}

status_space() {
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
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$new_capture" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$new_review" "$new_stage" "$STATE_INTERVIEW" "$STATE_PROGRESS" "$STATE_SESSION" "$STATE_TURN" "$STATE_DISCLOSED" "$STATE_DISCLOSED_MODE"
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
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$STATE_REVIEW" "$STATE_STAGE" "$STATE_INTERVIEW" "$STATE_PROGRESS" "$STATE_SESSION" "$STATE_TURN" "$current" "$STATE_CAPTURE"
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
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$STATE_REVIEW" "$STATE_STAGE" "$STATE_INTERVIEW" "$STATE_PROGRESS" "$STATE_SESSION" "$STATE_TURN" "$STATE_DISCLOSED" "$STATE_DISCLOSED_MODE"
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
  write_state "$ROOT/.hello-state" 2 "$STATE_VERSION" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$STATE_REVIEW" "$STATE_STAGE" "$current" "$new_progress" "$SESSION_ID" "$TURN_ID" "$STATE_DISCLOSED" "$STATE_DISCLOSED_MODE" || rollback_fail 'Cannot write state.'
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
  write_state "$ROOT/.hello-state" "$STATE_SCHEMA" "$STATE_VERSION" "$STATE_CAPTURE" "$STATE_CREATED" "$current" "$STATE_CONFIRMED" "$STATE_REVIEW" "$STATE_STAGE" "$STATE_INTERVIEW" "$STATE_PROGRESS" "$STATE_SESSION" "$STATE_TURN" "$STATE_DISCLOSED" "$STATE_DISCLOSED_MODE"
  printf '{"ok":true,"command":"withdraw","root":"%s","candidate_id":"%s","trash":"%s"}\n' \
    "$(json_escape "$ROOT")" "$CANDIDATE_ID" "$(json_escape "$trash")"
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
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/hello-self-test.XXXXXX") || fail 'Cannot create self-test directory.'
  trap 'rm -rf "$temporary"' EXIT HUP INT TERM
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
  rm -rf "$temporary"
  trap - EXIT HUP INT TERM
  printf '%s\n' '{"ok":true,"command":"self-test"}'
}

if [ "$COMMAND" = self-test ]; then
  self_test
  exit 0
fi

resolve_root

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
esac
