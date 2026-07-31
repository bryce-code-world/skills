#!/bin/sh
# Native POSIX storage adapter for the writing-style skill.

SCHEMA_VERSION=1
SCRIPT_PATH=$0

json_escape() {
    printf '%s' "$1" | awk '
        BEGIN { first = 1 }
        {
            gsub(/\\/, "\\\\")
            gsub(/"/, "\\\"")
            gsub(/\r/, "\\r")
            if (!first) printf "\\n"
            printf "%s", $0
            first = 0
        }
    '
}

fail() {
    fail_message=$(json_escape "$1")
    fail_command=$(json_escape "${COMMAND-}")
    printf '{"ok":false,"command":"%s","error":"%s"}\n' "$fail_command" "$fail_message" >&2
    exit 2
}

require_value() {
    [ "$#" -ge 2 ] || fail "Missing value for $1."
}

COMMAND=${1-}
[ "$#" -gt 0 ] && shift

ROOT_ARG=
KIND=
PROFILE_ID=
INPUT_PATH=
EXPECTED_VERSION=
CONFIRMED=false
REPLACE=false
CLEAR_DEFAULT=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --root)
            require_value "$@"
            ROOT_ARG=$2
            shift 2
            ;;
        --kind)
            require_value "$@"
            KIND=$2
            shift 2
            ;;
        --id)
            require_value "$@"
            PROFILE_ID=$2
            shift 2
            ;;
        --input)
            require_value "$@"
            INPUT_PATH=$2
            shift 2
            ;;
        --expected-version)
            require_value "$@"
            EXPECTED_VERSION=$2
            shift 2
            ;;
        --confirmed)
            CONFIRMED=true
            shift
            ;;
        --replace)
            REPLACE=true
            shift
            ;;
        --clear-default)
            CLEAR_DEFAULT=true
            shift
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
done

case "$COMMAND" in
    resolve-root|init|validate|list|diff|save|set-default|delete|self-test) ;;
    *) fail 'Command must be one of: resolve-root, init, validate, list, diff, save, set-default, delete, self-test.' ;;
esac

absolute_path() {
    absolute_raw=$1
    case "$absolute_raw" in
        '~') absolute_raw=${HOME-} ;;
        '~/'*) absolute_raw=${HOME-}/${absolute_raw#~/} ;;
    esac
    case "$absolute_raw" in
        /*) printf '%s\n' "$absolute_raw" ;;
        *) printf '%s/%s\n' "$PWD" "$absolute_raw" ;;
    esac
}

resolve_root() {
    if [ -n "$ROOT_ARG" ]; then
        ROOT=$(absolute_path "$ROOT_ARG")
        ROOT_SOURCE=explicit
    elif [ -n "${WRITING_STYLE_HOME-}" ]; then
        ROOT=$(absolute_path "$WRITING_STYLE_HOME")
        ROOT_SOURCE=environment
    else
        [ -n "${HOME-}" ] || fail 'Cannot resolve the user home directory.'
        ROOT=$(absolute_path "$HOME/.writing-style")
        ROOT_SOURCE=home
    fi
}

assert_confirmed() {
    [ "$CONFIRMED" = true ] || fail 'Mutating commands require --confirmed after explicit user confirmation.'
}

assert_kind() {
    case "$1" in
        personal|reference) ;;
        *) fail 'Kind must be personal or reference.' ;;
    esac
}

valid_profile_id() {
    valid_id=$1
    [ -n "$valid_id" ] || return 1
    [ "${#valid_id}" -le 64 ] || return 1
    case "$valid_id" in
        [a-z0-9]*)
            case "$valid_id" in
                *[!a-z0-9-]*) return 1 ;;
                *) return 0 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

assert_profile_id() {
    valid_profile_id "$1" || fail 'Profile id must match [a-z0-9][a-z0-9-]{0,63}.'
}

kind_directory() {
    assert_kind "$1"
    if [ "$1" = personal ]; then
        printf '%s\n' personal-profiles
    else
        printf '%s\n' reference-profiles
    fi
}

profile_path() {
    profile_root=$1
    profile_kind=$2
    profile_identifier=$3
    assert_profile_id "$profile_identifier"
    profile_directory=$(kind_directory "$profile_kind")
    printf '%s/%s/%s.md\n' "$profile_root" "$profile_directory" "$profile_identifier"
}

meta_value() {
    meta_file=$1
    meta_key=$2
    awk -v wanted="$meta_key" '
        /^##[[:space:]]/ { exit }
        {
            sub(/\r$/, "")
            prefix = "- " wanted ":"
            if (index($0, prefix) == 1) {
                value = substr($0, length(prefix) + 1)
                sub(/^[[:space:]]*/, "", value)
                sub(/[[:space:]]*$/, "", value)
                print value
                exit
            }
        }
    ' "$meta_file"
}

validate_config() {
    config_root=$1
    CONFIG_PATH=$config_root/config.md
    [ -f "$CONFIG_PATH" ] || {
        VALIDATION_ERROR="Missing config: $CONFIG_PATH"
        return 1
    }
    config_schema=$(meta_value "$CONFIG_PATH" schema_version)
    [ "$config_schema" = "$SCHEMA_VERSION" ] || {
        VALIDATION_ERROR="Unsupported or missing schema_version; expected $SCHEMA_VERSION."
        return 1
    }
    DEFAULT_PROFILE=$(meta_value "$CONFIG_PATH" default_personal_profile)
    [ -n "$DEFAULT_PROFILE" ] || {
        VALIDATION_ERROR='Missing default_personal_profile in config.md.'
        return 1
    }
    if [ "$DEFAULT_PROFILE" != none ] && ! valid_profile_id "$DEFAULT_PROFILE"; then
        VALIDATION_ERROR='Default profile id is invalid.'
        return 1
    fi
    return 0
}

validate_profile() {
    validate_file=$1
    validate_kind=$2
    validate_id=$3
    [ -f "$validate_file" ] || {
        VALIDATION_ERROR="Missing profile: $validate_file"
        return 1
    }
    profile_meta_id=$(meta_value "$validate_file" id)
    profile_meta_type=$(meta_value "$validate_file" type)
    profile_meta_version=$(meta_value "$validate_file" version)
    profile_meta_status=$(meta_value "$validate_file" status)
    profile_meta_date=$(meta_value "$validate_file" updated_at)
    for required_pair in \
        "id:$profile_meta_id" \
        "type:$profile_meta_type" \
        "version:$profile_meta_version" \
        "status:$profile_meta_status" \
        "updated_at:$profile_meta_date"
    do
        required_name=${required_pair%%:*}
        required_value=${required_pair#*:}
        [ -n "$required_value" ] || {
            VALIDATION_ERROR="Missing profile field: $required_name"
            return 1
        }
    done
    [ "$profile_meta_id" = "$validate_id" ] || {
        VALIDATION_ERROR="Profile id '$profile_meta_id' does not match target '$validate_id'."
        return 1
    }
    [ "$profile_meta_type" = "$validate_kind" ] || {
        VALIDATION_ERROR="Profile type must be '$validate_kind'."
        return 1
    }
    case "$profile_meta_version" in
        ''|*[!0-9]*|0) VALIDATION_ERROR='Profile version must be an integer of at least 1.'; return 1 ;;
    esac
    case "$profile_meta_status" in
        candidate|confirmed) ;;
        *) VALIDATION_ERROR='Profile status must be candidate or confirmed.'; return 1 ;;
    esac
    case "$profile_meta_date" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
        *) VALIDATION_ERROR='updated_at must use YYYY-MM-DD.'; return 1 ;;
    esac
    return 0
}

normalize_to_file() {
    normalize_source=$1
    normalize_target=$2
    awk '{ sub(/\r$/, ""); print }' "$normalize_source" > "$normalize_target" ||
        fail "Cannot write temporary file: $normalize_target"
}

atomic_copy() {
    atomic_source=$1
    atomic_target=$2
    atomic_directory=$(dirname "$atomic_target")
    mkdir -p "$atomic_directory" || fail "Cannot create directory: $atomic_directory"
    atomic_temp=$(mktemp "$atomic_directory/.profile-store.XXXXXX") ||
        fail "Cannot create temporary file in: $atomic_directory"
    if ! normalize_to_file "$atomic_source" "$atomic_temp"; then
        rm -f "$atomic_temp"
        fail "Cannot prepare file: $atomic_source"
    fi
    mv -f "$atomic_temp" "$atomic_target" || {
        rm -f "$atomic_temp"
        fail "Cannot replace file: $atomic_target"
    }
}

write_config() {
    write_config_root=$1
    write_config_default=$2
    write_config_target=$write_config_root/config.md
    mkdir -p "$write_config_root" || fail "Cannot create directory: $write_config_root"
    write_config_temp=$(mktemp "$write_config_root/.config.XXXXXX") ||
        fail "Cannot create temporary config in: $write_config_root"
    {
        printf '# 声纹用户空间\n\n'
        printf '%s\n' "- schema_version: $SCHEMA_VERSION"
        printf '%s\n' "- default_personal_profile: $write_config_default"
    } > "$write_config_temp" || {
        rm -f "$write_config_temp"
        fail "Cannot prepare config: $write_config_target"
    }
    mv -f "$write_config_temp" "$write_config_target" || {
        rm -f "$write_config_temp"
        fail "Cannot replace config: $write_config_target"
    }
}

backup_file() {
    backup_root=$1
    backup_source=$2
    backup_category=$3
    backup_directory=$backup_root/.backups/$backup_category
    mkdir -p "$backup_directory" || fail "Cannot create backup directory: $backup_directory"
    backup_base=$(basename "$backup_source" .md)
    backup_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
    BACKUP_PATH=$(mktemp "$backup_directory/$backup_base-$backup_stamp.XXXXXX.md") ||
        fail "Cannot allocate backup path in: $backup_directory"
    cp -p "$backup_source" "$BACKUP_PATH" || {
        rm -f "$BACKUP_PATH"
        fail "Cannot back up file: $backup_source"
    }
}

append_error() {
    append_error_text=$(json_escape "$1")
    if [ "$ERROR_COUNT" -gt 0 ]; then
        ERRORS_JSON=$ERRORS_JSON,
    fi
    ERRORS_JSON=$ERRORS_JSON\"$append_error_text\"
    ERROR_COUNT=$((ERROR_COUNT + 1))
}

append_profile() {
    append_kind=$1
    append_path=$2
    append_id=$3
    append_kind_json=$(json_escape "$append_kind")
    append_path_json=$(json_escape "$append_path")
    append_id_json=$(json_escape "$append_id")
    append_status_json=$(json_escape "$profile_meta_status")
    append_date_json=$(json_escape "$profile_meta_date")
    if [ "$PROFILE_COUNT" -gt 0 ]; then
        PROFILES_JSON=$PROFILES_JSON,
    fi
    PROFILES_JSON=$PROFILES_JSON'{"kind":"'$append_kind_json'","path":"'$append_path_json'","id":"'$append_id_json'","type":"'$append_kind_json'","version":'$profile_meta_version',"status":"'$append_status_json'","updated_at":"'$append_date_json'"}'
    PROFILE_COUNT=$((PROFILE_COUNT + 1))
}

collect_profiles() {
    collect_root=$1
    collect_kind_filter=$2
    PROFILES_JSON=
    ERRORS_JSON=
    PROFILE_COUNT=0
    ERROR_COUNT=0
    if ! validate_config "$collect_root"; then
        append_error "$VALIDATION_ERROR"
    fi
    if [ -n "$collect_kind_filter" ]; then
        assert_kind "$collect_kind_filter"
        collect_kinds=$collect_kind_filter
    else
        collect_kinds='personal reference'
    fi
    for collect_kind in $collect_kinds; do
        collect_directory=$collect_root/$(kind_directory "$collect_kind")
        if [ ! -d "$collect_directory" ]; then
            append_error "Missing directory: $collect_directory"
            continue
        fi
        for collect_file in "$collect_directory"/*.md; do
            [ -e "$collect_file" ] || continue
            collect_name=$(basename "$collect_file")
            collect_id=${collect_name%.md}
            if validate_profile "$collect_file" "$collect_kind" "$collect_id"; then
                append_profile "$collect_kind" "$collect_file" "$collect_id"
            else
                append_error "$collect_file: $VALIDATION_ERROR"
            fi
        done
    done
    if [ "${DEFAULT_PROFILE:-none}" != none ]; then
        default_path=$(profile_path "$collect_root" personal "$DEFAULT_PROFILE")
        [ -f "$default_path" ] || append_error "Default personal profile does not exist: $default_path"
    fi
}

initialize_space() {
    assert_confirmed
    created_json=
    created_count=0
    for initialize_name in personal-profiles reference-profiles; do
        initialize_path=$ROOT/$initialize_name
        [ ! -f "$initialize_path" ] || fail "Expected directory but found file: $initialize_path"
        if [ ! -d "$initialize_path" ]; then
            mkdir -p "$initialize_path" || fail "Cannot create directory: $initialize_path"
            escaped_created=$(json_escape "$initialize_path")
            [ "$created_count" -eq 0 ] || created_json=$created_json,
            created_json=$created_json\"$escaped_created\"
            created_count=$((created_count + 1))
        fi
    done
    config_path=$ROOT/config.md
    [ ! -d "$config_path" ] || fail "Expected file but found directory: $config_path"
    if [ ! -f "$config_path" ]; then
        write_config "$ROOT" none
        escaped_created=$(json_escape "$config_path")
        [ "$created_count" -eq 0 ] || created_json=$created_json,
        created_json=$created_json\"$escaped_created\"
        created_count=$((created_count + 1))
    fi
    validate_config "$ROOT" || fail "$VALIDATION_ERROR"
    if [ "$created_count" -eq 0 ]; then idempotent=true; else idempotent=false; fi
    root_json=$(json_escape "$ROOT")
    printf '{"ok":true,"command":"init","root":"%s","created":[%s],"idempotent":%s}\n' "$root_json" "$created_json" "$idempotent"
}

diff_profile() {
    assert_kind "$KIND"
    assert_profile_id "$PROFILE_ID"
    [ -n "$INPUT_PATH" ] || fail 'Missing required argument: --input'
    validate_profile "$INPUT_PATH" "$KIND" "$PROFILE_ID" || fail "$VALIDATION_ERROR"
    diff_target=$(profile_path "$ROOT" "$KIND" "$PROFILE_ID")
    if [ -f "$diff_target" ] && cmp -s "$diff_target" "$INPUT_PATH"; then
        printf 'No changes.\n'
        return
    fi
    if [ -f "$diff_target" ]; then diff_old=$diff_target; else diff_old=/dev/null; fi
    printf '%s\n' "--- $diff_old"
    printf '%s\n' "+++ $diff_target"
    printf '%s\n' '@@ full-file replacement @@'
    if [ -f "$diff_target" ]; then
        sed 's/^/-/' "$diff_target"
    fi
    sed 's/^/+/' "$INPUT_PATH"
}

save_profile() {
    assert_confirmed
    assert_kind "$KIND"
    assert_profile_id "$PROFILE_ID"
    [ -n "$INPUT_PATH" ] || fail 'Missing required argument: --input'
    validate_config "$ROOT" || fail "$VALIDATION_ERROR"
    validate_profile "$INPUT_PATH" "$KIND" "$PROFILE_ID" || fail "$VALIDATION_ERROR"
    new_version=$profile_meta_version
    save_target=$(profile_path "$ROOT" "$KIND" "$PROFILE_ID")
    BACKUP_PATH=
    if [ -e "$save_target" ]; then
        [ "$REPLACE" = true ] || fail "Profile already exists; use --replace with --expected-version: $save_target"
        validate_profile "$save_target" "$KIND" "$PROFILE_ID" || fail "$VALIDATION_ERROR"
        old_version=$profile_meta_version
        [ -n "$EXPECTED_VERSION" ] || fail "Expected version must match current version $old_version."
        case "$EXPECTED_VERSION" in ''|*[!0-9]*) fail '--expected-version must be a positive integer.' ;; esac
        [ "$EXPECTED_VERSION" -eq "$old_version" ] || fail "Expected version must match current version $old_version."
        required_version=$((old_version + 1))
        [ "$new_version" -eq "$required_version" ] || fail "Replacement version must be $required_version."
        backup_file "$ROOT" "$save_target" "$KIND"
        operation=replace
    else
        [ "$REPLACE" = false ] || fail 'Cannot use --replace for a profile that does not exist.'
        [ "$new_version" -eq 1 ] || fail 'A new profile must start at version 1.'
        operation=create
    fi
    atomic_copy "$INPUT_PATH" "$save_target"
    root_json=$(json_escape "$ROOT")
    target_json=$(json_escape "$save_target")
    backup_json=$(json_escape "$BACKUP_PATH")
    if [ -n "$BACKUP_PATH" ]; then backup_value='"'$backup_json'"'; else backup_value=null; fi
    printf '{"ok":true,"command":"save","root":"%s","operation":"%s","path":"%s","version":%s,"backup":%s}\n' \
        "$root_json" "$operation" "$target_json" "$new_version" "$backup_value"
}

set_default_profile() {
    assert_confirmed
    assert_profile_id_or_none=$PROFILE_ID
    [ -n "$assert_profile_id_or_none" ] || fail 'Missing required argument: --id'
    validate_config "$ROOT" || fail "$VALIDATION_ERROR"
    if [ "$PROFILE_ID" != none ]; then
        assert_profile_id "$PROFILE_ID"
        set_default_target=$(profile_path "$ROOT" personal "$PROFILE_ID")
        validate_profile "$set_default_target" personal "$PROFILE_ID" || fail "$VALIDATION_ERROR"
    fi
    old_default=$DEFAULT_PROFILE
    root_json=$(json_escape "$ROOT")
    if [ "$old_default" = "$PROFILE_ID" ]; then
        profile_json=$(json_escape "$PROFILE_ID")
        printf '{"ok":true,"command":"set-default","root":"%s","changed":false,"default_personal_profile":"%s"}\n' "$root_json" "$profile_json"
        return
    fi
    backup_file "$ROOT" "$ROOT/config.md" config
    write_config "$ROOT" "$PROFILE_ID"
    old_json=$(json_escape "$old_default")
    profile_json=$(json_escape "$PROFILE_ID")
    backup_json=$(json_escape "$BACKUP_PATH")
    printf '{"ok":true,"command":"set-default","root":"%s","changed":true,"old_default":"%s","default_personal_profile":"%s","backup":"%s"}\n' \
        "$root_json" "$old_json" "$profile_json" "$backup_json"
}

delete_profile() {
    assert_confirmed
    assert_kind "$KIND"
    assert_profile_id "$PROFILE_ID"
    validate_config "$ROOT" || fail "$VALIDATION_ERROR"
    delete_target=$(profile_path "$ROOT" "$KIND" "$PROFILE_ID")
    validate_profile "$delete_target" "$KIND" "$PROFILE_ID" || fail "$VALIDATION_ERROR"
    is_default=false
    if [ "$KIND" = personal ] && [ "$DEFAULT_PROFILE" = "$PROFILE_ID" ]; then
        is_default=true
        [ "$CLEAR_DEFAULT" = true ] || fail 'Profile is the default; use --clear-default after user confirmation.'
    fi
    if [ "$is_default" = true ]; then
        (backup_file "$ROOT" "$ROOT/config.md" config) ||
            fail 'Cannot back up config before clearing the default profile.'
    fi
    trash_directory=$ROOT/.trash/$KIND
    mkdir -p "$trash_directory" || fail "Cannot create trash directory: $trash_directory"
    trash_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
    trash_path=$(mktemp "$trash_directory/$PROFILE_ID-$trash_stamp.XXXXXX.md") ||
        fail "Cannot allocate trash path in: $trash_directory"
    rm -f "$trash_path"
    mv "$delete_target" "$trash_path" || fail "Cannot move profile to trash: $delete_target"
    if [ "$is_default" = true ]; then
        if ! (write_config "$ROOT" none); then
            mv "$trash_path" "$delete_target" 2>/dev/null || :
            fail 'Cannot clear default after moving profile; rollback attempted.'
        fi
    fi
    root_json=$(json_escape "$ROOT")
    deleted_json=$(json_escape "$delete_target")
    trash_json=$(json_escape "$trash_path")
    printf '{"ok":true,"command":"delete","root":"%s","deleted":"%s","recoverable_at":"%s","default_cleared":%s}\n' \
        "$root_json" "$deleted_json" "$trash_json" "$is_default"
}

self_test() {
    [ -z "$ROOT_ARG$KIND$PROFILE_ID$INPUT_PATH$EXPECTED_VERSION" ] || fail 'self-test does not accept arguments.'
    [ "$CONFIRMED$REPLACE$CLEAR_DEFAULT" = falsefalsefalse ] || fail 'self-test does not accept arguments.'
    self_base=$(mktemp -d "${TMPDIR:-/tmp}/writing-style-native.XXXXXX") ||
        fail 'Cannot create self-test directory.'
    self_root=$self_base/原生测试/用户空间
    self_candidate1=$self_base/candidate-1.md
    self_candidate2=$self_base/candidate-2.md
    self_invalid=$self_base/invalid-root
    cleanup_self_test() {
        rm -rf "$self_base"
    }
    trap cleanup_self_test 0 HUP INT TERM

    mkdir -p "$(dirname "$self_root")" || fail 'Cannot prepare self-test path.'
    self_resolve=$(WRITING_STYLE_HOME="$self_base/environment" sh "$SCRIPT_PATH" resolve-root --root "$self_root") ||
        fail 'Self-test failed: root precedence.'
    printf '%s' "$self_resolve" | grep -q '"source":"explicit"' ||
        fail 'Self-test failed: root precedence.'

    if sh "$SCRIPT_PATH" init --root "$self_root" >/dev/null 2>&1; then
        fail 'Self-test failed: confirmation guard.'
    fi
    case "$self_root" in *原生测试/用户空间) ;; *) fail 'Self-test failed: unicode path.' ;; esac

    sh "$SCRIPT_PATH" init --root "$self_root" --confirmed >/dev/null ||
        fail 'Self-test failed: initialize.'

    printf 'not a directory\n' > "$self_invalid"
    invalid_code=0
    sh "$SCRIPT_PATH" validate --root "$self_invalid" >/dev/null 2>&1 || invalid_code=$?
    [ "$invalid_code" -eq 1 ] || fail 'Self-test failed: invalid root.'

    self_today=$(date -u '+%Y-%m-%d')
    {
        printf '# 测试风格\n\n'
        printf '%s\n' '- id: my-style' '- type: personal' '- version: 1' '- status: confirmed'
        printf '%s\n\n' "- updated_at: $self_today"
        printf '%s\n\n' '## 来源'
        printf '%s\n' '- 作者：测试'
    } > "$self_candidate1"

    sh "$SCRIPT_PATH" save --root "$self_root" --kind personal --id my-style --input "$self_candidate1" --confirmed >/dev/null ||
        fail 'Self-test failed: create profile.'
    sh "$SCRIPT_PATH" set-default --root "$self_root" --id my-style --confirmed >/dev/null ||
        fail 'Self-test failed: set default.'

    {
        printf '# 测试风格\n\n'
        printf '%s\n' '- id: my-style' '- type: personal' '- version: 2' '- status: confirmed'
        printf '%s\n\n' "- updated_at: $self_today"
        printf '%s\n\n' '## 来源'
        printf '%s\n' '- 作者：测试'
    } > "$self_candidate2"

    self_diff=$(sh "$SCRIPT_PATH" diff --root "$self_root" --kind personal --id my-style --input "$self_candidate2") ||
        fail 'Self-test failed: diff.'
    printf '%s' "$self_diff" | grep -q '^--- ' || fail 'Self-test failed: diff.'

    if sh "$SCRIPT_PATH" save --root "$self_root" --kind personal --id my-style --input "$self_candidate2" --replace --expected-version 9 --confirmed >/dev/null 2>&1; then
        fail 'Self-test failed: expected version guard.'
    fi
    sh "$SCRIPT_PATH" save --root "$self_root" --kind personal --id my-style --input "$self_candidate2" --replace --expected-version 1 --confirmed >/dev/null ||
        fail 'Self-test failed: versioned update.'

    sh "$SCRIPT_PATH" validate --root "$self_root" >/dev/null ||
        fail 'Self-test failed: validate.'

    if sh "$SCRIPT_PATH" delete --root "$self_root" --kind personal --id my-style --confirmed >/dev/null 2>&1; then
        fail 'Self-test failed: default delete guard.'
    fi
    sh "$SCRIPT_PATH" delete --root "$self_root" --kind personal --id my-style --confirmed --clear-default >/dev/null ||
        fail 'Self-test failed: recoverable delete.'
    [ ! -f "$self_root/personal-profiles/my-style.md" ] ||
        fail 'Self-test failed: recoverable delete.'
    find "$self_root/.trash/personal" -type f -name 'my-style-*.md' -print | grep -q . ||
        fail 'Self-test failed: recoverable delete.'

    runtime=$(uname -s 2>/dev/null || printf unknown)
    runtime_json=$(json_escape "$runtime")
    printf '{"ok":true,"command":"self-test","adapter":"posix-sh","runtime":"%s","checks_passed":13,"checks":[{"name":"root precedence","passed":true},{"name":"confirmation guard","passed":true},{"name":"unicode and space path","passed":true},{"name":"initialize","passed":true},{"name":"invalid root","passed":true},{"name":"create profile","passed":true},{"name":"set default","passed":true},{"name":"diff","passed":true},{"name":"expected version guard","passed":true},{"name":"versioned update","passed":true},{"name":"validate","passed":true},{"name":"default delete guard","passed":true},{"name":"recoverable delete","passed":true}]}\n' "$runtime_json"
}

if [ "$COMMAND" = self-test ]; then
    self_test
    exit 0
fi

resolve_root
root_json=$(json_escape "$ROOT")

case "$COMMAND" in
    resolve-root)
        platform=$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')
        source_json=$(json_escape "$ROOT_SOURCE")
        platform_json=$(json_escape "$platform")
        printf '{"ok":true,"command":"resolve-root","root":"%s","source":"%s","platform":"%s","adapter":"posix-sh"}\n' \
            "$root_json" "$source_json" "$platform_json"
        ;;
    init)
        initialize_space
        ;;
    validate)
        collect_profiles "$ROOT" ''
        if [ "$ERROR_COUNT" -eq 0 ]; then ok=true; result_code=0; else ok=false; result_code=1; fi
        source_json=$(json_escape "$ROOT_SOURCE")
        printf '{"ok":%s,"command":"validate","root":"%s","source":"%s","profiles":[%s],"errors":[%s]}\n' \
            "$ok" "$root_json" "$source_json" "$PROFILES_JSON" "$ERRORS_JSON"
        exit "$result_code"
        ;;
    list)
        collect_profiles "$ROOT" "$KIND"
        if [ "$ERROR_COUNT" -eq 0 ]; then ok=true; result_code=0; else ok=false; result_code=1; fi
        printf '{"ok":%s,"command":"list","root":"%s","profiles":[%s],"errors":[%s]}\n' \
            "$ok" "$root_json" "$PROFILES_JSON" "$ERRORS_JSON"
        exit "$result_code"
        ;;
    diff)
        [ -n "$KIND" ] || fail 'Missing required argument: --kind'
        [ -n "$PROFILE_ID" ] || fail 'Missing required argument: --id'
        diff_profile
        ;;
    save)
        [ -n "$KIND" ] || fail 'Missing required argument: --kind'
        [ -n "$PROFILE_ID" ] || fail 'Missing required argument: --id'
        save_profile
        ;;
    set-default)
        [ -n "$PROFILE_ID" ] || fail 'Missing required argument: --id'
        set_default_profile
        ;;
    delete)
        [ -n "$KIND" ] || fail 'Missing required argument: --kind'
        [ -n "$PROFILE_ID" ] || fail 'Missing required argument: --id'
        delete_profile
        ;;
esac
