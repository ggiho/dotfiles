#!/usr/bin/env zsh
set -eu

repo_root=${0:A:h:h}
TEST_ALIASES=${TEST_ALIASES:-$repo_root/dot_config/zsh/aliases.zsh}
TEST_JUSTFILE=${TEST_JUSTFILE:-$repo_root/dot_config/justfile/justfile}
export JUSTFILE="$TEST_JUSTFILE"

# j builds its host picker from MYSQL_HOSTS_FILE. Point it at a fixture, not the real
# ~/.config/mysql/hosts: this file is published, the real list is internal hostnames,
# and a fixture keeps the picker cases passing on machines without a hosts file.
# Two entries with different users, and the cases pick the second, so "user comes
# from the picked entry" cannot pass by falling back to the first entry's user.
TEST_HOSTS_FILE=$(mktemp)
print -r -- 'Example PROD:db-prod.example.internal:3306:produser' > "$TEST_HOSTS_FILE"
print -r -- 'Example DEV:db-dev.example.internal:3306:devuser' >> "$TEST_HOSTS_FILE"
export MYSQL_HOSTS_FILE=$TEST_HOSTS_FILE

typeset -ga __vared_prompts
typeset -ga __vared_initials __cards
typeset -gA __prompt_answers
# Answers consumed in prompt order. Prefer this over keying on the exact prompt
# text, which changes whenever a hint is reworded.
typeset -ga __prompt_queue
typeset -g __buffer=""
typeset -g __history=""
typeset -g __atuin_cmd=""
typeset -g __fzf_queue_file=""
typeset -g __vared_rc=0
typeset -g __schema_query_file='' __schema_query_rc=0

cleanup() {
  if [[ -n "$__fzf_queue_file" && -f "$__fzf_queue_file" ]]; then
    rm -f "$__fzf_queue_file"
  fi
  if [[ -n "$__fzf_input_file" && -f "$__fzf_input_file" ]]; then
    rm -f "$__fzf_input_file"
  fi
  [[ -z "$__schema_query_file" ]] || rm -f "$__schema_query_file"
  return 0
}
# reset_mocks calls cleanup before every case, so the hosts fixture (shared by all
# cases) is removed only here, on exit.
trap 'cleanup; rm -f "$TEST_HOSTS_FILE"' EXIT

reset_mocks() {
  cleanup
  __vared_prompts=()
  __vared_initials=()
  __cards=()
  __vared_rc=0
  __schema_query_rc=0
  __prompt_answers=()
  __prompt_queue=()
  __buffer=""
  __history=""
  __atuin_cmd=""
  __just_args=""
  __fzf_queue_file=$(mktemp)
  __fzf_input_file=$(mktemp)
  __schema_query_file=$(mktemp)
  __confirm_prompt=""
  __confirm_answer="y"
  __fzf_query=""
}

queue_fzf() {
  printf '%s\n' "$@" > "$__fzf_queue_file"
}

typeset -g __just_args=""
typeset -g __fzf_input_file=""
typeset -g __confirm_prompt=""
typeset -g __fzf_query=""
typeset -g __confirm_answer="y"
just() {
  # The picker path only calls just to enumerate recipes (--list) and to extract
  # a body (--dry-run); both are side-effect free and go to the real binary. The
  # passthrough path would really run the recipe, so capture it instead. Match on
  # the whole argument list, not $1 -- the passthrough also leads with --justfile.
  if [[ "$*" == *--dry-run* || "$*" == *--list* ]]; then
    command just "$@"
  else
    # Joined with | so the assertions can see word boundaries; "$*" would look
    # identical whether or not quoting survived.
    __just_args="${(j:|:)@}"
  fi
}

fzf() {
  # Record what the picker was offered. fzf runs inside $( ), so a variable set
  # here would stay in that subshell -- write to a file the parent can read.
  cat >> "$__fzf_input_file"
  local choice=''
  if [[ -f "$__fzf_queue_file" ]]; then
    choice=$(head -n 1 "$__fzf_queue_file")
    tail -n +2 "$__fzf_queue_file" > "$__fzf_queue_file.tmp"
    mv "$__fzf_queue_file.tmp" "$__fzf_queue_file"
  fi
  if [[ -z "$choice" ]]; then
    print -u2 -- 'fzf queue exhausted'
    return 1
  fi
  [[ "$choice" == '__CANCEL__' ]] && return 130
  # Real fzf with --print-query emits the query line before the selection. The
  # host picker relies on that to tell "picked from the list" (two lines) from
  # "typed something not in the list" (one line); a single-line mock silently
  # exercised the wrong branch and passed the whole label through as the host.
  [[ "$*" == *--print-query* ]] && printf '%s\n' "$__fzf_query"
  printf '%s\n' "$choice"
}

vared() {
  [[ "${1-}" == '-p' ]] || return 1
  local prompt="$2"
  local varname="$3"
  __vared_initials+=("${(P)varname}")
  (( __vared_rc == 0 )) || return "$__vared_rc"
  local value="${__prompt_answers["$prompt"]-}"
  if [[ -z "$value" && ${#__prompt_queue[@]} -gt 0 ]]; then
    value="${__prompt_queue[1]}"
    shift __prompt_queue
  fi
  __vared_prompts+=("$prompt")
  eval "$varname=\"$value\""
}

# `print -s` appends to zsh history; capture instead so the test does not write
# to the real history file.
print() {
  if [[ "${1-}" == '-s' ]]; then
    __history="${@[-1]}"
  else
    builtin print "$@"
  fi
}

# Real atuin is on PATH, so without this mock every test run would add entries
# to the user's actual history database.
atuin() {
  if [[ "${1-}" == 'history' && "${2-}" == 'start' ]]; then
    __atuin_cmd="${@[-1]}"
  fi
  return 0
}

# Schema discovery must never contact a real database during these tests.
security() { builtin print -r -- 'fixture-password'; }
mysql() {
  builtin print -r -- "${(j:|:)@}" > "$__schema_query_file"
  [[ "${MYSQL_PWD:-}" == fixture-password ]] || return 1
  (( __schema_query_rc == 0 )) || return "$__schema_query_rc"
  builtin print -r -- 'analytics'
  builtin print -r -- 'reporting warehouse'
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "$actual" != "$expected" ]]; then
    print -u2 -- "ASSERT_EQ failed [$label]"
    print -u2 -- "  expected: $expected"
    print -u2 -- "  actual:   $actual"
    return 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    print -u2 -- "ASSERT_CONTAINS failed [$label]"
    print -u2 -- "  needle: $needle"
    print -u2 -- "  haystack: $haystack"
    return 1
  fi
}

set +e
source "$TEST_ALIASES"
set -e

# Check the REAL __j_exec before it is mocked below. A login bash (-l) runs
# /etc/profile, whose path_helper puts /usr/bin ahead of /opt/homebrew/bin, so
# python3 became the system 3.9 without yaml and the ddb-* recipes failed under j
# but not under plain just.
__real_j_exec=$(functions __j_exec)
if [[ "$__real_j_exec" != *'bash -c '* || "$__real_j_exec" == *'bash -l'* ]]; then
  print -u2 -- "ASSERT failed [__j_exec runs the body in a non-login bash -c]"
  print -u2 -- "$__real_j_exec"
  exit 1
fi

# Must come AFTER the source: aliases.zsh defines __j_exec, so a mock defined
# earlier would be clobbered and the recipe would actually run.
# j() runs the recipe through __j_exec; overriding it keeps the composed command
# inspectable without dumping a database or creating a table for real.
__j_exec() {
  __buffer="bash -c $1"
}

# Capture cards in flow tests; exercise the real renderer separately below.
if (( $+functions[__j_card] )); then
  functions[__real_j_card]=$functions[__j_card]
fi
__j_card() {
  __cards+=("${(j:|:)@}")
}

# Answer the [confirm] prompt without a terminal.
__j_confirm() {
  __confirm_prompt="$1"
  [[ "$__confirm_answer" == 'y' ]]
}

run_mysqlsh_dump_case() {
  reset_mocks
  # host/user/database/tables are no longer recipe parameters -- the recipe picks
  # them itself with fzf -- so j only prompts for threads and outdir and never
  # shows its own host picker.
  queue_fzf 'mysqlsh-dump threads="4" outdir=""'
  __prompt_answers["threads (parallel threads (default: 4)) [4]: "]=''
  __prompt_answers["outdir (output directory (default: dump_<scope>_<timestamp>)): "]=''

  j

  # --list emits `[group]` headers and blank separators once recipes are grouped;
  # a header reaching fzf would parse as a recipe named `[mysqlsh]`.
  assert_eq "$(grep -c '^\[' "$__fzf_input_file")" '0' 'no group headers in the picker'
  assert_eq "$(grep -c '^[[:space:]]*$' "$__fzf_input_file")" '0' 'no blank lines in the picker'
  assert_contains "$(<"$__fzf_input_file")" 'mysqlsh-load' 'picker still lists grouped recipes'
  assert_eq "${#__vared_prompts[@]}" '2' 'mysqlsh-dump prompt count'
  assert_eq "${__vared_prompts[1]}" '  threads › ' 'mysqlsh-dump first prompt'
  assert_eq "${__vared_prompts[2]}" '  outdir › ' 'mysqlsh-dump second prompt'
  assert_contains "$__buffer" 'bash -c ' 'mysqlsh-dump bash wrapper'
  assert_contains "$__buffer" 'mysqlsh --host=' 'mysqlsh-dump recipe body'
  assert_contains "$__buffer" '--threads=4' 'mysqlsh-dump threads default applied'
  assert_contains "$__buffer" 'dump host>' 'mysqlsh-dump keeps its own host picker'
  # The output filter used to strip these two, which silently ran every recipe
  # without `set -e` and hid its progress messages.
  assert_contains "$__buffer" 'set -euo pipefail' 'set -e survives the output filter'
  assert_contains "$__buffer" 'echo' 'progress echoes survive the output filter'

  # One re-runnable line in history, not the multi-line body.
  assert_eq "$(printf '%s' "$__history" | wc -l | tr -d ' ')" '0' 'history entry is single-line'
  assert_contains "$__history" 'just --justfile ' 'history entry invokes just'
  assert_contains "$__history" 'mysqlsh-dump' 'history entry names the recipe'
  assert_contains "$__history" ' 4 ' 'history entry keeps the threads arg'
  # The body is what used to land in history; make sure it no longer does.
  assert_eq "${__history##*mysqlsh --host*}" "$__history" 'history entry is not the recipe body'
  # atuin gets the same line; print -s alone never reaches it.
  assert_eq "$__atuin_cmd" "$__history" 'atuin receives the history entry'
}

run_ddb_copy_case() {
  reset_mocks
  queue_fzf 'ddb-copy source_table="" new_table=""'
  # Ordered answers: source_table, then new_table. ddb-copy's parameters are
  # optional now -- supplying them here is what keeps the recipe from opening its
  # own fzf pickers.
  __prompt_queue=(SRC_TABLE NEW_TABLE)

  j

  assert_eq "${#__vared_prompts[@]}" '2' 'ddb-copy prompt count'
  assert_contains "$__buffer" 'bash -c ' 'ddb-copy bash wrapper'
  assert_contains "$__buffer" 'copy_table.py' 'ddb-copy command body'
  assert_contains "$__buffer" 'SRC_TABLE' 'ddb-copy source arg reaches the body'
  assert_contains "$__buffer" 'NEW_TABLE' 'ddb-copy target arg reaches the body'

  assert_contains "$__history" 'ddb-copy' 'ddb-copy history entry names the recipe'
  assert_contains "$__history" 'SRC_TABLE' 'ddb-copy history entry keeps source arg'
  assert_contains "$__history" 'NEW_TABLE' 'ddb-copy history entry keeps target arg'
  assert_eq "$__atuin_cmd" "$__history" 'ddb-copy atuin receives the history entry'
}

# `alias j=just` is the documented convention, so arguments must reach just
# untouched and the picker must not open.
run_passthrough_case() {
  reset_mocks
  # No fzf queue: if the picker opened, fzf would fail with "queue exhausted".
  j mysqlsh-load somehost 3306

  # Flags from the README's "Forwarding Alias" tip; without --justfile the
  # passthrough fails outside a project directory.
  assert_contains "$__just_args" '--justfile|' 'passthrough pins the justfile'
  assert_contains "$__just_args" "|$TEST_JUSTFILE|" 'passthrough pins OUR justfile'
  assert_contains "$__just_args" '|--working-directory|.|' 'passthrough runs in the current directory'
  assert_eq "${__just_args##*|--working-directory|.|}" 'mysqlsh-load|somehost|3306' 'arguments reach just verbatim'
  assert_eq "${#__vared_prompts[@]}" '0' 'passthrough asks no parameter prompts'
  assert_eq "$__buffer" '' 'passthrough does not compose a bash -c body'
  assert_eq "$__history" '' 'passthrough writes no synthetic history entry'
  assert_eq "$__atuin_cmd" '' 'passthrough writes nothing to atuin'
  assert_eq "$(<"$__schema_query_file")" '' 'passthrough does not query schemas'
}

# An argument containing spaces must survive as one word.
run_passthrough_quoting_case() {
  reset_mocks
  j pt-osc 'ALTER TABLE t ADD COLUMN memo VARCHAR(64) NULL' true

  assert_eq "${__just_args##*|--working-directory|.|}" 'pt-osc|ALTER TABLE t ADD COLUMN memo VARCHAR(64) NULL|true' 'quoted argument stays one word'
}

# j runs the extracted body under bash, bypassing just, so just's own [confirm]
# never fires on the picker path -- j has to ask itself.
#
# These cases deliberately leave __prompt_answers empty: the vared mock returns
# "" for any prompt, which j treats as "accept the default". That keeps them from
# breaking every time a hint's wording changes.
MYSQLSH_LOAD_SIG='mysqlsh-load host user port="3306" threads="4" target_schema="" on_exist="error" force_drop="false"'
PICKED_HOST='Example DEV  →  db-dev.example.internal'

run_confirm_accepted_case() {
  reset_mocks
  __confirm_answer='y'
  queue_fzf "$MYSQLSH_LOAD_SIG" "$PICKED_HOST" 1 error false

  j

  assert_contains "$__confirm_prompt" 'mysqlsh-load' 'confirm prompt names the recipe'
  assert_contains "$__buffer" 'bash -c ' 'accepted confirm runs the recipe'
  assert_contains "$__history" 'mysqlsh-load' 'accepted confirm records history'
  assert_eq "$__atuin_cmd" "$__history" 'accepted confirm records to atuin'
  # Picking from the host list must yield the bare host, not the whole label.
  assert_contains "$__buffer" '--host="db-dev.example.internal"' 'host extracted from the picker label'
  assert_contains "$__buffer" '--user="devuser"' 'user taken from the picked host entry'
  assert_eq "${__buffer##*Example DEV*}" "$__buffer" 'label text does not leak into the command'
  assert_contains "${(j:;:)__cards}" '접속 대상|Example DEV|host|db-dev.example.internal|기본 계정|devuser' 'picked host has a connection card'
}

run_confirm_declined_case() {
  reset_mocks
  __confirm_answer='n'
  queue_fzf "$MYSQLSH_LOAD_SIG" "$PICKED_HOST" 1 error false

  local rc=0
  set +e; j; rc=$?; set -e

  assert_eq "$rc" '1' 'declined confirm returns non-zero'
  assert_eq "$__buffer" '' 'declined confirm runs nothing'
  assert_eq "$__history" '' 'declined confirm records no history'
  assert_eq "$__atuin_cmd" '' 'declined confirm writes nothing to atuin'
}

# A recipe with no [confirm] attribute must not be gated.
run_no_confirm_case() {
  reset_mocks
  __confirm_answer='n'
  queue_fzf 'mysqlsh-dump threads="4" outdir=""'

  j

  assert_eq "$__confirm_prompt" '' 'unmarked recipe is not gated'
  assert_contains "$__buffer" 'bash -c ' 'unmarked recipe still runs'
}

run_pretty_prompt_cases() {
  reset_mocks
  __j_prompt user devuser 'DB 접속 계정' 필수 2 7
  assert_eq "$REPLY" devuser 'blank input keeps default'
  assert_eq "${__vared_initials[1]}" devuser 'default is editable without retyping'
  assert_contains "${(j:;:)__cards}" '설정 2/7|user' 'input card shows step and parameter'
  assert_contains "${(j:;:)__cards}" '설명|DB 접속 계정' 'input card shows hint'
  assert_contains "${(j:;:)__cards}" '기본값|devuser' 'input card shows default'

  reset_mocks
  __prompt_queue=('custom user')
  __j_prompt user devuser 'DB 접속 계정' 필수 2 7
  assert_eq "$REPLY" 'custom user' 'custom input preserves spaces'

  reset_mocks
  queue_fzf true
  __j_prompt dry_run false '검사만 수행' 선택 6 7
  assert_eq "$REPLY" true 'boolean picker returns the original value'
  assert_eq "${#__vared_prompts[@]}" 0 'boolean uses a picker'
  assert_contains "$(<"$__fzf_input_file")" 'false' 'boolean picker offers false'
  assert_contains "$(<"$__fzf_input_file")" 'true' 'boolean picker offers true'

  reset_mocks
  queue_fzf skip
  __j_prompt duplicates error '중복 키 처리' 선택 7 7
  assert_eq "$REPLY" skip 'duplicate picker returns the original value'
  assert_contains "$(<"$__fzf_input_file")" 'replace' 'duplicate picker offers replace'
}

run_prompt_cancel_cases() {
  reset_mocks
  queue_fzf '__CANCEL__'
  local rc=0
  set +e; __j_prompt dry_run false '검사만 수행' 선택 1 1; rc=$?; set -e
  assert_eq "$rc" 1 'picker cancellation aborts'

  reset_mocks
  queue_fzf 'ddb-copy source_table="" new_table=""'
  __vared_rc=130
  set +e; j; rc=$?; set -e
  assert_eq "$rc" 1 'text input cancellation aborts'
  assert_eq "$__buffer" '' 'cancelled input runs nothing'
  assert_eq "$__history" '' 'cancelled input writes no history'
}

run_card_renderer_case() {
  local card COLUMNS=0
  card=$(__real_j_card '접속 대상' '테스트 서버' 주소 'db.example.internal' 계정 testuser 2>&1)
  assert_contains "$card" '╭' 'card has a border'
  assert_contains "$card" '테스트 서버' 'card renders Korean labels'
  assert_contains "$card" 'testuser' 'card renders values'
  card=$(__real_j_card '설정 2/7' user 조작 'Enter: 기본값 유지 · Ctrl-C: 취소' 2>&1)
  assert_contains "$card" 'Enter: 기본값 유지 · Ctrl-C: 취소' 'non-terminal width uses readable fallback'

  local JUSTFILE='/does-not-exist/justfile'
  card=$(__real_j_card '접속 대상' '테스트 서버' 계정 testuser 2>&1)
  assert_contains "$card" 'testuser' 'custom justfile without renderer has a fallback'
}

run_target_schema_picker_cases() {
  reset_mocks
  queue_fzf "$MYSQLSH_LOAD_SIG" "$PICKED_HOST" 3 error false
  __prompt_queue=(customuser 13306 2)
  j
  assert_contains "$(<"$__schema_query_file")" '--host=db-dev.example.internal' 'schema picker uses chosen host'
  assert_contains "$(<"$__schema_query_file")" '--port=13306' 'schema picker uses entered port'
  assert_contains "$(<"$__schema_query_file")" '--user=customuser' 'schema picker uses entered user'
  assert_contains "$(<"$__schema_query_file")" 'SELECT SCHEMA_NAME' 'schema query is read-only'
  assert_eq "${$(<"$__schema_query_file")##*fixture-password*}" "$(<"$__schema_query_file")" 'password is not in argv'
  assert_contains "$__history" ' analytics ' 'selected schema reaches recipe'
  assert_contains "$(<"$__fzf_input_file")" 'reporting warehouse' 'schema names preserve spaces'
  assert_eq "${(j:|:)__vared_prompts##*target_schema*}" "${(j:|:)__vared_prompts}" 'schema is selected rather than typed'

  reset_mocks
  queue_fzf "$MYSQLSH_LOAD_SIG" "$PICKED_HOST" 2 error false
  __prompt_queue=(devuser 3306 4 manual_schema)
  j
  assert_contains "$__history" ' manual_schema ' 'manual schema entry remains available'

  reset_mocks
  queue_fzf "$MYSQLSH_LOAD_SIG" "$PICKED_HOST" '__CANCEL__'
  local rc=0
  set +e; j; rc=$?; set -e
  assert_eq "$rc" 1 'schema picker cancellation aborts'
  assert_eq "$__buffer" '' 'schema cancellation executes nothing'
  assert_eq "$__history" '' 'schema cancellation writes no history'

  reset_mocks
  __schema_query_rc=1
  queue_fzf "$MYSQLSH_LOAD_SIG" "$PICKED_HOST" 2 error false
  __prompt_queue=(devuser 3306 4 manual_schema)
  j
  assert_contains "$__history" ' manual_schema ' 'query failure still permits explicit manual input'
  assert_contains "${(j:;:)__cards}" '목록 조회 실패' 'query failure is visible'

  reset_mocks
  queue_fzf 'mysqlsh-load-map host user port="3306" threads="4" target_schema="" mapping="" duplicates="error" dry_run="false"' "$PICKED_HOST" 4 1 error false
  j
  assert_contains "$__history" "'reporting warehouse'" 'map recipe keeps schema as one argument'
}

run_mapping_picker_cases() {
  local root mapping_file
  root=$(mktemp -d)
  root=$(cd "$root" && pwd -P)
  mapping_file="$root/saved mapping.json"
  print -r -- '{"tables":{"source.people":{"target_table":"members"}}}' > "$mapping_file"
  (
    cd "$root"
    reset_mocks
    queue_fzf 'mysqlsh-load-map host user port="3306" threads="4" target_schema="" mapping="" duplicates="error" dry_run="false"' "$PICKED_HOST" 3 3 error false
    j
    assert_contains "$__history" "'${mapping_file}'" 'mapping picker preserves file path with spaces'
    assert_contains "$(<"$__fzf_input_file")" 'saved mapping.json' 'mapping file is offered'
    assert_eq "${(j:|:)__vared_prompts##*mapping*}" "${(j:|:)__vared_prompts}" 'mapping file does not require typing'

    reset_mocks
    queue_fzf 1
    __j_mapping_prompt '' '매핑 설정' 선택 6 8
    assert_eq "$REPLY" '' 'defer choice keeps mapping empty'
    assert_contains "$(<"$__fzf_input_file")" '덤프 선택 후' 'defer choice explains when table mapping starts'

    reset_mocks
    queue_fzf 2
    __prompt_queue=("$mapping_file")
    __j_mapping_prompt '' '매핑 설정' 선택 6 8
    assert_eq "$REPLY" "$mapping_file" 'manual mapping path remains available'

    reset_mocks
    queue_fzf '__CANCEL__'
    local rc=0
    set +e; __j_mapping_prompt '' '매핑 설정' 선택 6 8; rc=$?; set -e
    assert_eq "$rc" 1 'mapping picker cancellation aborts'
    assert_eq "$__buffer" '' 'mapping cancellation runs nothing'

    local load_sig='mysqlsh-load host user port="3306" threads="4" target_schema="" on_exist="error" force_drop="false" mapping="" duplicates="error" dry_run="false" interactive="false"'
    reset_mocks
    queue_fzf "$load_sig" "$PICKED_HOST" 3 ignore false 3 replace false false
    j
    assert_contains "$__history" ' ignore false ' 'mapping permits the user chosen ignore policy'
    assert_contains "$__history" ' replace false false' 'row replacement is preserved'
    assert_contains "${(j:;:)__cards}" '행 중복 처리|replace' 'mapping summary shows the effective row policy'

    local ddl_policy force_value
    for ddl_policy force_value in drop false error true; do
      reset_mocks
      queue_fzf "$load_sig" "$PICKED_HOST" 3 "$ddl_policy" "$force_value" 3 replace false false
      set +e; j; rc=$?; set -e
      assert_eq "$rc" 1 'incompatible mapping DDL options are refused before running'
      assert_eq "$__confirm_prompt" '' 'invalid mapping is not offered for approval'
      assert_eq "$__history" '' 'invalid mapping writes no runnable history'
      assert_eq "$__buffer" '' 'invalid mapping executes nothing'
    done
  )
  local rc=$?
  rm -rf "$root"
  return "$rc"
}

run_passthrough_case
run_passthrough_quoting_case
run_confirm_accepted_case
run_confirm_declined_case
run_no_confirm_case
run_mysqlsh_dump_case
run_ddb_copy_case
run_pretty_prompt_cases
run_prompt_cancel_cases
run_card_renderer_case
run_target_schema_picker_cases
run_mapping_picker_cases

builtin print -- 'test_j_wrapper: ok'
