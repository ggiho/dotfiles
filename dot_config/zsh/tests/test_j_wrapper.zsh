#!/usr/bin/env zsh
set -eu

TEST_ALIASES=${TEST_ALIASES:-$HOME/.config/zsh/aliases.zsh}
TEST_JUSTFILE=${TEST_JUSTFILE:-$HOME/.config/justfile/justfile}

typeset -ga __vared_prompts
typeset -gA __prompt_answers
# Answers consumed in prompt order. Prefer this over keying on the exact prompt
# text, which changes whenever a hint is reworded.
typeset -ga __prompt_queue
typeset -g __buffer=""
typeset -g __history=""
typeset -g __atuin_cmd=""
typeset -g __fzf_queue_file=""

cleanup() {
  if [[ -n "$__fzf_queue_file" && -f "$__fzf_queue_file" ]]; then
    rm -f "$__fzf_queue_file"
  fi
  if [[ -n "$__fzf_input_file" && -f "$__fzf_input_file" ]]; then
    rm -f "$__fzf_input_file"
  fi
  return 0
}
trap cleanup EXIT

reset_mocks() {
  cleanup
  __vared_prompts=()
  __prompt_answers=()
  __prompt_queue=()
  __buffer=""
  __history=""
  __atuin_cmd=""
  __just_args=""
  __fzf_queue_file=$(mktemp)
  __fzf_input_file=$(mktemp)
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

# Must come AFTER the source: aliases.zsh defines __j_exec, so a mock defined
# earlier would be clobbered and the recipe would actually run.
# j() runs the recipe through __j_exec; overriding it keeps the composed command
# inspectable without dumping a database or creating a table for real.
__j_exec() {
  __buffer="bash -lc $1"
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
  assert_eq "${__vared_prompts[1]}" 'threads (parallel threads (default: 4)) [4]: ' 'mysqlsh-dump first prompt'
  assert_eq "${__vared_prompts[2]}" 'outdir (output directory (default: dump_<scope>_<timestamp>)): ' 'mysqlsh-dump second prompt'
  assert_contains "$__buffer" 'bash -lc ' 'mysqlsh-dump bash wrapper'
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
  assert_contains "$__buffer" 'bash -lc ' 'ddb-copy bash wrapper'
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
  assert_eq "$__buffer" '' 'passthrough does not compose a bash -lc body'
  assert_eq "$__history" '' 'passthrough writes no synthetic history entry'
  assert_eq "$__atuin_cmd" '' 'passthrough writes nothing to atuin'
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
PICKED_HOST='OnTheGo DEV  →  aurora-dev.otg.apac.npr.aws.asurion.net'

run_confirm_accepted_case() {
  reset_mocks
  __confirm_answer='y'
  queue_fzf "$MYSQLSH_LOAD_SIG" "$PICKED_HOST"

  j

  assert_contains "$__confirm_prompt" 'mysqlsh-load' 'confirm prompt names the recipe'
  assert_contains "$__buffer" 'bash -lc ' 'accepted confirm runs the recipe'
  assert_contains "$__history" 'mysqlsh-load' 'accepted confirm records history'
  assert_eq "$__atuin_cmd" "$__history" 'accepted confirm records to atuin'
  # Picking from the host list must yield the bare host, not the whole label.
  assert_contains "$__buffer" '--host="aurora-dev.otg.apac.npr.aws.asurion.net"' 'host extracted from the picker label'
  assert_contains "$__buffer" '--user="giho.seong"' 'user taken from the picked host entry'
  assert_eq "${__buffer##*OnTheGo DEV*}" "$__buffer" 'label text does not leak into the command'
}

run_confirm_declined_case() {
  reset_mocks
  __confirm_answer='n'
  queue_fzf "$MYSQLSH_LOAD_SIG" "$PICKED_HOST"

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
  assert_contains "$__buffer" 'bash -lc ' 'unmarked recipe still runs'
}

run_passthrough_case
run_passthrough_quoting_case
run_confirm_accepted_case
run_confirm_declined_case
run_no_confirm_case
run_mysqlsh_dump_case
run_ddb_copy_case

builtin print -- 'test_j_wrapper: ok'
