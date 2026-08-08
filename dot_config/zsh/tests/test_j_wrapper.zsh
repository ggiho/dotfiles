#!/usr/bin/env zsh
set -eu

TEST_ALIASES=${TEST_ALIASES:-$HOME/.config/zsh/aliases.zsh}
TEST_JUSTFILE=${TEST_JUSTFILE:-$HOME/.config/justfile/justfile}

typeset -ga __vared_prompts
typeset -gA __prompt_answers
typeset -g __buffer=""
typeset -g __fzf_queue_file=""
typeset -g __hosts_file=""
typeset -g __work_home
__work_home=$(mktemp -d)
export ASURION_HOME="$__work_home"
export JUSTFILE="$TEST_JUSTFILE"

cleanup() {
  if [[ -n "$__fzf_queue_file" && -f "$__fzf_queue_file" ]]; then
    rm -f "$__fzf_queue_file"
  fi
  if [[ -n "$__hosts_file" && -f "$__hosts_file" ]]; then
    rm -f "$__hosts_file"
  fi
  if [[ -n "$__work_home" && -d "$__work_home" ]]; then
    rm -rf "$__work_home"
  fi
  return 0
}
trap cleanup EXIT

reset_mocks() {
  cleanup
  __vared_prompts=()
  __prompt_answers=()
  __buffer=""
  __fzf_queue_file=$(mktemp)
  __hosts_file=$(mktemp)
  printf '%s\n' 'OnTheGo DEV:aurora-dev.otg.apac.npr.aws.asurion.net:3306:giho.seong' > "$__hosts_file"
  export MYSQL_HOSTS_FILE="$__hosts_file"
}

queue_fzf() {
  printf '%s\n' "$@" > "$__fzf_queue_file"
}

just() {
  command just "$@"
}

fzf() {
  cat >/dev/null
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
  if [[ " $* " == *" --print-query "* ]]; then
    printf '\n%s\n' "$choice"
  else
    printf '%s\n' "$choice"
  fi
}

vared() {
  [[ "${1-}" == '-p' ]] || return 1
  local prompt="$2"
  local varname="$3"
  local value="${__prompt_answers["$prompt"]-}"
  __vared_prompts+=("$prompt")
  eval "$varname=\"$value\""
}

print() {
  if [[ "${1-}" == '-z' ]]; then
    __buffer="$2"
  else
    builtin print "$@"
  fi
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

run_mysqlsh_dump_tables_case() {
  reset_mocks
  queue_fzf \
    'mysqlsh-dump-tables host user database tables threads="4" outdir=""' \
    'OnTheGo DEV  →  aurora-dev.otg.apac.npr.aws.asurion.net'
  __prompt_answers["user (e.g. giho.seong) [giho.seong]: "]=''
  __prompt_answers["database (target schema (empty = user DBs only, excludes mysql/sys/information_schema/performance_schema)): "]='sample_db'
  __prompt_answers["tables (comma-separated table names (e.g. TABLE1,TABLE2)): "]='TABLE1,TABLE2'
  __prompt_answers["threads (parallel threads (default: 4)) [4]: "]=''
  __prompt_answers["outdir (output directory (default: dump_<database>_tables_<timestamp>)): "]=''

  j

  assert_eq "${#__vared_prompts[@]}" '5' 'mysqlsh-dump-tables prompt count'
  assert_eq "${__vared_prompts[1]}" 'user (e.g. giho.seong) [giho.seong]: ' 'mysqlsh-dump-tables first prompt'
  assert_eq "${__vared_prompts[2]}" 'database (target schema (empty = user DBs only, excludes mysql/sys/information_schema/performance_schema)): ' 'mysqlsh-dump-tables second prompt'
  assert_contains "$__buffer" 'bash -lc ' 'mysqlsh-dump-tables bash wrapper'
  assert_contains "$__buffer" 'mysqlsh --host="aurora-dev.otg.apac.npr.aws.asurion.net"' 'mysqlsh-dump-tables recipe body'
  assert_contains "$__buffer" 'aurora-dev.otg.apac.npr.aws.asurion.net' 'mysqlsh-dump-tables host'
  assert_contains "$__buffer" 'giho.seong' 'mysqlsh-dump-tables user'
  assert_contains "$__buffer" 'sample_db' 'mysqlsh-dump-tables database arg'
  assert_contains "$__buffer" 'TABLE1,TABLE2' 'mysqlsh-dump-tables tables arg'
}

run_ddb_copy_case() {
  reset_mocks
  queue_fzf 'ddb-copy source_table new_table                   # hint: new_table: 새로 만들 테이블 이름'
  __prompt_answers["source_table (복사할 원본 테이블): "]='SRC_TABLE'
  __prompt_answers["new_table (새로 만들 테이블 이름): "]='NEW_TABLE'

  j

  assert_eq "${#__vared_prompts[@]}" '2' 'ddb-copy prompt count'
  assert_eq "${__vared_prompts[1]}" 'source_table (복사할 원본 테이블): ' 'ddb-copy first prompt'
  assert_eq "${__vared_prompts[2]}" 'new_table (새로 만들 테이블 이름): ' 'ddb-copy second prompt'
  assert_contains "$__buffer" 'bash -lc ' 'ddb-copy bash wrapper'
  assert_contains "$__buffer" 'copy_table.py' 'ddb-copy command body'
  assert_contains "$__buffer" 'SRC_TABLE' 'ddb-copy source arg'
  assert_contains "$__buffer" 'NEW_TABLE' 'ddb-copy target arg'
}

run_mysqlsh_dump_tables_case
run_ddb_copy_case

builtin print -- 'test_j_wrapper: ok'
