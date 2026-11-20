# alias ls="eza --icons --grid --classify --colour=auto --sort=type --group-directories-first --header --created --modified --git --binary"
alias ls="eza --icons=always"
# alias ls="eza -l --icons --git -a"
alias ll="eza -al --icons=always --total-size"
alias vi="nvim"
alias cat="bat -p"
alias e="exit"
alias q="quit"
alias c="clear"
alias zshrc="vi ~/.zshrc"
alias lg="lazygit"
alias doc="cd ~/Documents/"
alias dow="cd ~/Downloads/"
alias tf="terraform"
alias chz="chezmoi"
alias tconf="vi ~/.config/tmux/tmux.conf"
alias ali="vi ~/.config/zsh/aliases.zsh"
alias mk="make"
alias ibd="./ibdNinja"
alias sz="source ~/.zshrc"
alias python="python3"
alias ob="obsidian"
alias cc="claude --dangerously-skip-permissions"
alias pgcli="~/.local/bin/pgcli"
alias lg="lazygit"
# fd/fzf/bat file finders that open results in nvim (from Sin-cy/dotfiles)
alias nzo="~/.config/zsh/scripts/zoxide_openfiles_nvim.sh"
alias nlof="~/.config/zsh/scripts/fzf_listoldfiles.sh"
# throwaway nvim config (~/.config/nvim-scratch) for trying plugins without touching the real one
alias nvim-scratch="NVIM_APPNAME=nvim-scratch nvim"
# create a private GitHub repo from cwd, push everything, open it (fails if `origin` already exists)
alias gh-create='gh repo create --private --source=. --remote=origin && git push -u --all && gh browse'

function yz() {
  local tmp cwd
  tmp="$(mktemp -t yazi-cwd.XXXXXX)" || return

  yazi "$@" --cwd-file="$tmp"

  cwd="$(cat -- "$tmp" 2>/dev/null)"
  rm -f -- "$tmp"

  if [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
    cd -- "$cwd"
  fi
}

# asurion
ASURION_HOME="${ASURION_HOME:-$HOME/20_Work/01_Asurion}"
if [[ -d "$ASURION_HOME" ]]; then
  export ASURION_HOME
  alias asurion_claude_login="$HOME/.claude/claude_login.sh"
  alias db="$HOME/.local/bin/db-connect.sh"
  alias aa="source $ASURION_HOME/utils/aws-switch.sh"
  alias tag="$ASURION_HOME/utils/tag"
  alias decrypt="noglob $ASURION_HOME/utils/voltage/d"
  alias encrypt="noglob $ASURION_HOME/utils/voltage/e"
  alias encrypt-soho="noglob $ASURION_HOME/utils/voltage/e-soho"
  alias decrypt-soho="noglob $ASURION_HOME/utils/voltage/d-soho"
  alias encrypt-otg="noglob $ASURION_HOME/utils/voltage/e-otg"
  alias decrypt-otg="noglob $ASURION_HOME/utils/voltage/d-otg"
  alias encrypt-otg-dev="noglob $ASURION_HOME/utils/voltage/e-otg-dev"
  alias decrypt-otg-dev="noglob $ASURION_HOME/utils/voltage/d-otg-dev"
  alias encrypt-hz-uat="noglob $ASURION_HOME/utils/voltage/e-hz-uat"
  alias decrypt-hz-uat="noglob $ASURION_HOME/utils/voltage/d-hz-uat"
fi


alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias ......="cd ../../../../.."

# Git
alias gc="git commit -m"
alias gca="git commit -a -m"
alias gp="git push origin HEAD"
alias gpu="git pull origin"
alias gst="git status"
alias glog="git log --graph --topo-order --pretty='%w(100,0,6)%C(yellow)%h%C(bold)%C(black)%d %C(cyan)%ar %C(green)%an%n%C(bold)%C(white)%s %N' --abbrev-commit"
alias gdiff="git diff"
alias gco="git checkout"
alias gb='git branch'
alias gba='git branch -a'
alias gadd='git add'
alias ga='git add -p'
alias gcoall='git checkout -- .'
alias gr='git remote'
alias gre='git reset'

if [[ -d "$ASURION_HOME" ]]; then
# just
export JUSTFILE="${JUSTFILE:-$HOME/.config/justfile/justfile}"
export DDB_SCRIPT_DIR="$HOME/10_Database/AWS/dynamodb"
alias vj="vi $JUSTFILE"
unalias j 2>/dev/null
# Execution seam for j(). Kept as its own function so tests/test_j_wrapper.zsh
# can override it and inspect the composed command; overriding `print -z` used
# to serve that purpose, but j now runs the recipe directly.
#
# bash -c, not -lc: a login bash runs /etc/profile, whose path_helper moves /usr/bin
# ahead of /opt/homebrew/bin. There is no ~/.bash_profile, so -l added nothing but
# that reorder -- and python3 then resolved to the system 3.9 without yaml/boto3,
# so the ddb-* recipes died with "No module named 'yaml'" under j but not under
# plain just. -c keeps the PATH j was called with, the same as running just.
__j_exec() {
  eval "bash -c $1"
}

# Ask before running a recipe marked [confirm] in the justfile. Separate from
# __j_exec so tests can answer it without a terminal. Returns non-zero on "no".
__j_confirm() {
  local reply
  print -n -u2 -- "$1 [y/N] "
  read -r reply || reply=''
  print -u2 -- ''
  [[ "$reply" == (y|Y|yes|YES) ]]
}

# Reuse the justfile's Catppuccin renderer, including its CJK width handling.
# Custom justfiles without that renderer still get a readable plain fallback.
__j_card() {
  local renderer="${JUSTFILE:h}/lib/table.py" color=0 card_key card_value
  local width=${COLUMNS:-80}
  (( width <= 0 )) && width=80
  local cell=$(( width - 20 ))
  (( cell < 12 )) && cell=12
  (( cell > 88 )) && cell=88
  [[ -t 2 && -z ${NO_COLOR+x} && ${TERM:-dumb} != dumb ]] && color=1
  if [[ -f "$renderer" ]]; then
    {
      while (( $# >= 2 )); do
        card_key="${1//$'\n'/ }"
        card_value="${2//$'\n'/ }"
        printf '%s\t%s\n' "${card_key//$'\t'/ }" "${card_value//$'\t'/ }"
        shift 2
      done
    } | COLOR="$color" CELL="$cell" python3 "$renderer" >&2 && return 0
  fi
  print -u2 -- "╭─ $1 · $2"
  shift 2
  while (( $# >= 2 )); do
    print -u2 -- "│ $1: $2"
    shift 2
  done
  print -u2 -- '╰────────────────────────'
}

# A pending shell autosuggestion can arrive after vared loads an argument's
# default. Its asynchronous reply uses this widget; mute it only during vared.
__j_vared_no_suggestion() {
  POSTDISPLAY=''
}

# Return the raw argument through REPLY; presentation never changes its value.
__j_prompt() {
  local name="$1" default="$2" hint="$3" required="$4" step="$5" total="$6"
  local input_value="$default" selected choice choice_key choice_label
  local controls='Enter: 기본값 유지 · Ctrl-C: 취소'
  local -a choices=() ordered=()
  case "$default" in
    true|false)
      choices=($'false\t사용 안 함 · false' $'true\t사용함 · true') ;;
  esac
  case "$name" in
    on_exist)
      choices=($'error\t일반 적재: 기존 객체가 있으면 중단'
               $'ignore\t일반 적재: 기존 객체의 DDL 무시'
               $'drop\t일반 적재: 삭제 후 재생성 · 기존 데이터 삭제') ;;
    duplicates)
      choices=($'error\t빈 타깃 적재 · 전체 비우기 선택 시 먼저 비움'
               $'skip\t기존 행 유지 · 중복 키 행 건너뛰기'
               $'replace\t중복 키 행만 교체 · 다른 기존 행은 유지') ;;
    clear_target)
      choices=($'false\t기존 데이터 유지 · 중복 키 처리만 적용'
               $'true\t선택한 타깃 테이블 전체 비우고 적재 · 롤백 불가') ;;
    dry_run)
      choices=($'false\t실제 실행 · false' $'true\t사전 검사만 · true') ;;
    interactive)
      choices=($'false\t일반 / 파일 매핑 · false' $'true\t대화형 매핑 · true') ;;
  esac
  (( ${#choices[@]} )) && controls='Enter: 선택 · Esc: 취소'
  __j_card "설정 $step/$total" "$name" \
    설명 "${hint:-사용할 값을 입력하세요}" \
    구분 "$required" 기본값 "${default:-(비움)}" \
    조작 "$controls"
  if (( ${#choices[@]} )); then
    for choice in "${choices[@]}"; do
      choice_key="${choice%%$'\t'*}"
      choice_label="${choice#*$'\t'}"
      if [[ "$choice_key" == "$default" ]]; then
        ordered=("$choice_key"$'\t'"$choice_label [기본]" "${ordered[@]}")
      else
        ordered+=("$choice_key"$'\t'"$choice_label")
      fi
    done
    selected=$(printf '%s\n' "${ordered[@]}" \
      | fzf --prompt="$name> " --height=40% --scheme=default --no-sort \
        --delimiter=$'\t' --with-nth=2) || return 1
    [[ -n "$selected" ]] || return 1
    REPLY="${selected%%$'\t'*}"
    for choice in "${choices[@]}"; do
      [[ "${choice%%$'\t'*}" == "$REPLY" ]] && return 0
    done
    return 1
  fi
  local saved_suggestion=''
  zmodload zsh/zleparameter
  if (( ${+widgets[autosuggest-suggest]} )); then
    saved_suggestion="__j_saved_suggestion_$$"
    while (( ${+widgets[$saved_suggestion]} )); do saved_suggestion+='_'; done
    zle -A autosuggest-suggest "$saved_suggestion"
    zle -N autosuggest-suggest __j_vared_no_suggestion
  fi
  {
    vared -p "  $name › " input_value || return 1
  } always {
    if [[ -n "$saved_suggestion" ]]; then
      zle -A "$saved_suggestion" autosuggest-suggest
      zle -D "$saved_suggestion"
    fi
  }
  REPLY="${input_value:-$default}"
}

__j_schema_prompt() {
  local target_host="$1" target_user="$2" target_port="${3:-3306}" default="$4"
  local hint="$5" required="$6" step="$7" total="$8"
  local pw schemas='' lookup='목록 조회 완료' selected choice_id schema
  local -a schema_values=("$default" '') schema_options=()
  pw=$(security find-generic-password -s mysql-db-connect -a "$target_user" -w 2>/dev/null || true)
  if ! schemas=$(MYSQL_PWD="$pw" mysql --host="$target_host" --port="$target_port" \
      --user="$target_user" --connect-timeout=10 --batch --skip-column-names \
      -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA
          WHERE SCHEMA_NAME NOT IN ('mysql','sys','information_schema','performance_schema')
          ORDER BY SCHEMA_NAME"); then
    schemas=''
    lookup='목록 조회 실패 · 직접 입력하거나 기본 설정을 선택하세요'
  fi
  if [[ -n "$default" ]]; then
    schema_options+=("1"$'\t'"[기본값 유지] $default")
  else
    schema_options+=($'1\t[비움] 매핑 파일/덤프의 스키마 사용 (대화형이면 뒤에서 선택)')
  fi
  schema_options+=($'2\t[직접 입력] 스키마 이름 입력')
  if [[ -n "$schemas" ]]; then
    for schema in "${(@f)schemas}"; do
      [[ "$schema" == "$default" ]] && continue
      schema_values+=("$schema")
      schema_options+=("${#schema_values[@]}"$'\t'"$schema")
    done
  fi
  __j_card "설정 $step/$total" target_schema \
    '대상 서버' "$target_host:$target_port" '접속 계정' "$target_user" \
    설명 "${hint:-대상 DB의 스키마를 선택하세요}" 조회 "$lookup" \
    조작 'Enter: 선택 · Esc: 취소'
  selected=$(printf '%s\n' "${schema_options[@]}" \
    | fzf --prompt='target_schema> ' --height=40% --scheme=default --no-sort \
      --delimiter=$'\t' --with-nth=2) || return 1
  choice_id="${selected%%$'\t'*}"
  [[ "$choice_id" == <-> ]] || return 1
  (( choice_id >= 1 && choice_id <= ${#schema_values[@]} )) || return 1
  if (( choice_id == 2 )); then
    __j_prompt target_schema "$default" "$hint" "$required" "$step" "$total" || return 1
  else
    REPLY="${schema_values[$choice_id]}"
  fi
  __j_card '대상 스키마' "${REPLY:-(매핑 파일/덤프 설정)}" \
    '대상 서버' "$target_host:$target_port" '접속 계정' "$target_user"
}

__j_mapping_prompt() {
  local default="$1" hint="$2" required="$3" step="$4" total="$5"
  local helper="${JUSTFILE:h}/lib/mysqlsh_load.py" mapping_list='' lookup selected choice_id mapping_file
  local -a mapping_values=("$default" '') mapping_choices=()
  if [[ -f "$helper" ]] && mapping_list=$(python3 "$helper" --list-mappings "$PWD"); then
    lookup='현재 폴더와 하위 한 단계의 저장된 매핑'
  else
    lookup='목록 조회 실패 · 실행 단계에서 선택하거나 직접 입력하세요'
  fi
  if [[ -n "$default" ]]; then
    mapping_choices+=("1"$'\t'"[기본값 유지] $default")
  else
    mapping_choices+=($'1\t[나중에 선택] 덤프 선택 후 파일/새 테이블 매핑 선택')
  fi
  mapping_choices+=($'2\t[직접 입력] 매핑 JSON 경로 입력')
  if [[ -n "$mapping_list" ]]; then
    for mapping_file in "${(@f)mapping_list}"; do
      [[ "$mapping_file" == "$default" ]] && continue
      mapping_values+=("$mapping_file")
      mapping_choices+=("${#mapping_values[@]}"$'\t'"$mapping_file")
    done
  fi
  __j_card "설정 $step/$total" mapping \
    설명 "${hint:-저장된 매핑을 선택하거나 덤프 선택 후 새로 연결하세요}" \
    조회 "$lookup" 조작 'Enter: 선택 · Esc: 취소'
  selected=$(printf '%s\n' "${mapping_choices[@]}" \
    | fzf --prompt='mapping> ' --height=40% --scheme=default --no-sort \
      --delimiter=$'\t' --with-nth=2) || return 1
  choice_id="${selected%%$'\t'*}"
  [[ "$choice_id" == <-> ]] || return 1
  (( choice_id >= 1 && choice_id <= ${#mapping_values[@]} )) || return 1
  if (( choice_id == 2 )); then
    __j_prompt mapping "$default" "$hint" "$required" "$step" "$total" || return 1
  else
    REPLY="${mapping_values[$choice_id]}"
  fi
  __j_card '매핑 설정' "${REPLY:-(덤프 선택 후 파일/테이블 연결 선택)}"
}

j() {
  # `alias j=just` is just's documented convention, so keep that meaning when
  # arguments are given and only open the picker when called bare. The flags are
  # the ones from the README's "Forwarding Alias" tip; $JUSTFILE is our own
  # variable and just does not read it (its env var is JUST_JUSTFILE), so
  # without --justfile this fails with "no justfile found" outside a project.
  # --working-directory . matches what the picker path does for a non-module
  # recipe. This path also honours [confirm], since just runs the recipe itself
  # rather than j extracting the body and re-running it under bash.
  if (( $# )); then
    just --justfile "$JUSTFILE" --working-directory . "$@"
    return
  fi

  local selected recipe sig rest param name default val cmd dry line fzf_selected
  local -a params args db_hosts db_labels db_users host_options just_lines
  local -A hints
  local -A input_values=()
  local hosts_file="${MYSQL_HOSTS_FILE:-$HOME/.config/mysql/hosts}"
  local selected_user=""

  # ── Parse module declarations: `mod NAME 'PATH'` / `mod? NAME 'PATH'` ──
  local -a mod_names mod_paths
  local _ml _mod_path
  while IFS= read -r _ml; do
    if [[ "$_ml" =~ '^[[:space:]]*mod[?]?[[:space:]]+([A-Za-z0-9_-]+)[[:space:]]+["'\'']([^"'\'']+)["'\'']' ]]; then
      _mod_path="${match[2]/#\~/$HOME}"
      [[ -f "$_mod_path" ]] || continue
      mod_names+=("${match[1]}")
      mod_paths+=("$_mod_path")
    fi
  done < "$JUSTFILE"

  # ── Build combined recipe list (top-level + module recipes, prefixed) ──
  local list_out mi mname
  list_out=$(just --list --justfile "$JUSTFILE" --list-heading='' --list-prefix='' 2>/dev/null)
  for (( mi = 1; mi <= ${#mod_names[@]}; mi++ )); do
    mname="${mod_names[$mi]}"
    list_out=$(printf '%s\n' "$list_out" | grep -vE "^[[:space:]]*${mname} \.\.\.")
    list_out="${list_out}"$'\n'"$(just --justfile "$JUSTFILE" --list "$mname" --list-heading='' --list-prefix='' 2>/dev/null | sed "s/^[[:space:]]*/${mname} /")"
  done

  # Drop blank lines and the `[group]` headers that --list started emitting once
  # recipes carry [group(...)] attributes. Neither is a selectable recipe, and a
  # header would parse as a recipe named `[mysqlsh]`.
  # Preview the recipe source on the right, like `just --choose`. A module row is
  # "MOD RECIPE ...", shown with `just --show MOD::RECIPE`; the preview runs in a
  # separate shell, so the module names travel in the command string.
  local _pv
  _pv="m=' ${mod_names[*]} '; if [ -n {2} ] && [ \"\${m#* {1} }\" != \"\$m\" ]; then r={1}::{2}; else r={1}; fi; just --justfile ${(q)JUSTFILE} --color always --show \"\$r\" 2>/dev/null"
  selected=$(printf '%s\n' "$list_out" \
    | sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*\[[^]]*\][[:space:]]*$/d' \
    | fzf --prompt="just> " --height=80% --preview "$_pv" --preview-window=right,60%)
  [ -z "$selected" ] && return

  # ── Detect module vs top-level recipe ──
  local first_tok src_file invoke_prefix is_mod=0 needs_confirm=0
  first_tok=$(echo "$selected" | sed 's/^[[:space:]]*//' | awk '{print $1}')
  src_file="$JUSTFILE"
  invoke_prefix=""
  for (( mi = 1; mi <= ${#mod_names[@]}; mi++ )); do
    if [[ "$first_tok" == "${mod_names[$mi]}" ]]; then
      is_mod=1
      invoke_prefix="${mod_names[$mi]}"
      src_file="${mod_paths[$mi]}"
      break
    fi
  done

  # ── Recipe signature (strip module prefix when present) ──
  sig=$(echo "$selected" | sed 's/#.*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  (( is_mod )) && sig="${sig#${invoke_prefix} }"
  recipe=$(echo "$sig" | awk '{print $1}')

  just_lines=("${(@f)$(<"$src_file")}")
  local i j
  for (( i = 1; i <= ${#just_lines[@]}; i++ )); do
    line=${just_lines[$i]}
    if [[ "$line" =~ "^${recipe}[[:space:](:]" ]]; then
      for (( j = i - 1; j >= 1; j-- )); do
        line=${just_lines[$j]}
        if [[ "$line" =~ '^# hint:[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*(.+)$' ]]; then
          hints[${match[1]}]="${match[2]}"
          continue
        fi
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" == '#'* ]] && continue
        # Attributes such as [group('mysqlsh')] and [confirm(...)] sit between
        # the doc/hint comments and the recipe line, so keep scanning past them
        # or every hint above an attribute is lost.
        if [[ "$line" =~ '^\[.*\][[:space:]]*$' ]]; then
          # j runs the extracted body under bash rather than through just, so
          # just's own confirmation never fires on this path -- note it and ask
          # below instead.
          [[ "$line" == '[confirm'* ]] && needs_confirm=1
          continue
        fi
        break
      done
      break
    fi
  done

  rest="${sig#${recipe}}"
  rest="${rest# }"
  params=()
  [[ -n "$rest" ]] && params=("${(z)rest}")

  local default_user="" input_step=0 input_required
  if [[ -f "$hosts_file" ]]; then
    local _line _label _host _user
    while IFS= read -r _line; do
      [[ -z "$_line" || "$_line" == \#* ]] && continue
      _label="${_line%%:*}"
      _host="${_line#*:}"
      _host="${_host%%:*}"
      _user="${_line##*:}"
      db_labels+=("$_label")
      db_hosts+=("$_host")
      db_users+=("$_user")
      host_options+=("${_label}  →  ${_host}")
      [[ -z "$default_user" ]] && default_user="$_user"
    done < "$hosts_file"
  fi

  args=()
  for param in "${params[@]}"; do
    (( input_step += 1 ))
    name=${param%%=*}
    default=""
    input_required="필수"
    if [[ "$param" == *=* ]]; then
      input_required="선택"
      default=${param#*=}
      default=${default#\"}
      default=${default%\"}
    fi

    if [[ "$name" == *host* && ${#host_options[@]} -gt 0 ]]; then
      local _q="" _sel="" _out="" _picked_label="직접 입력"
      _out=$(printf '%s\n' "${host_options[@]}" \
        | fzf --prompt="$name> " --height=40% --print-query)
      if [[ "$_out" == *$'\n'* ]]; then
        _q="${_out%%$'\n'*}"
        _sel="${_out#*$'\n'}"
      else
        _q="$_out"
        _sel=""
      fi
      if [[ -n "$_sel" ]]; then
        local matched=0 idx
        for (( idx = 1; idx <= ${#host_options[@]}; idx++ )); do
          if [[ "${host_options[$idx]}" == "$_sel" ]]; then
            val="${db_hosts[$idx]}"
            selected_user="${db_users[$idx]}"
            _picked_label="${db_labels[$idx]}"
            matched=1
            break
          fi
        done
        (( matched )) || val="$_sel"
      elif [[ -n "$_q" ]]; then
        # typed a host not in the list -> use it as-is (user falls back to default_user)
        val="$_q"
      else
        vared -p "$name: " val
      fi
      __j_card '접속 대상' "$_picked_label" "$name" "$val" \
        '기본 계정' "${selected_user:-$default_user}"
    else
      if [[ "$name" == *user* ]]; then
        if [[ -n "$selected_user" ]]; then
          default="$selected_user"
        elif [[ -n "$default_user" ]]; then
          default="$default_user"
        fi
      fi

      if (( ! is_mod )) && [[ "$name" == target_schema && "$recipe" == (mysqlsh-load|mysqlsh-load-map) ]]; then
        __j_schema_prompt "${input_values[host]}" "${input_values[user]}" \
          "${input_values[port]:-3306}" "$default" "${hints[$name]-}" "$input_required" \
          "$input_step" "${#params[@]}" || return 1
      elif (( ! is_mod )) && [[ "$name" == mapping && "$recipe" == (mysqlsh-load|mysqlsh-load-map) ]]; then
        __j_mapping_prompt "$default" "${hints[$name]-}" "$input_required" \
          "$input_step" "${#params[@]}" || return 1
      else
        __j_prompt "$name" "$default" "${hints[$name]-}" "$input_required" \
          "$input_step" "${#params[@]}" || return 1
      fi
      val="$REPLY"
    fi

    args+=("$val")
    input_values[$name]="$val"
    val=""
  done

  # Reject known incompatible mapping options before confirmation or history.
  if (( ! is_mod )) && [[ "$recipe" == mysqlsh-load-map || \
      ( "$recipe" == mysqlsh-load && ( -n "${input_values[mapping]-}" || "${input_values[interactive]:-false}" == true || "${input_values[clear_target]:-false}" == true ) ) ]]; then
    local ddl_policy="${input_values[on_exist]:-error}" drop_forced="${input_values[force_drop]:-false}"
    if [[ "$ddl_policy" == drop || "$drop_forced" != false ]]; then
      __j_card '매핑 옵션 오류' '기존 테이블 구조를 유지하는 모드입니다' \
        on_exist "$ddl_policy (error 또는 ignore 사용)" force_drop "$drop_forced (false 사용)"
      return 1
    fi
    __j_card '매핑 적재' '기존 테이블에 데이터만 적재' \
      'DDL 처리' "구조 유지 · on_exist=$ddl_policy 미적용" \
      '행 중복 처리' "${input_values[duplicates]:-error}" \
      '타깃 전체 비우기' "${input_values[clear_target]:-false}"
  fi

  # ── Resolve execution context ──
  # Module recipes are dry-run against their OWN justfile (so justfile_directory()
  # resolves correctly) and prefixed with a `cd` into the module dir so relative
  # paths and `terraform` run in the right place from anywhere.
  local _jf _wd _cdpfx=""
  if (( is_mod )); then
    _jf="$src_file"
    _wd="${src_file:h}"
    _cdpfx="cd ${(q)_wd} && "
  else
    _jf="$JUSTFILE"
    _wd="$PWD"
  fi

  # --yes is required: --dry-run also honours [confirm], and its prompt would be
  # captured by this substitution instead of shown, leaving the shell silently
  # waiting for input. The confirmation is asked below instead.
  dry=$(just --dry-run --yes --justfile "$_jf" --working-directory "$_wd" "$recipe" "${args[@]}" 2>&1) || {
    print -u2 -- "$dry"
    return 1
  }

  cmd=$(printf '%s' "$dry" | python3 -c 'import re, sys
text = sys.stdin.read()
# Only the shebang is dropped; it is meaningless inside `bash -c`.
# "set " and "echo" used to be stripped too, which silently ran every recipe
# without its `set -euo pipefail` (failures did not abort) and hid its progress
# messages.
lines = [line for line in text.splitlines() if line and not line.startswith("#!")]
text = "\n".join(lines)
text = re.sub(r"\\\n\s*", " ", text).rstrip()
print(text, end="")')

  local quoted_cmd
  quoted_cmd=$(printf '%s' "${_cdpfx}${cmd}" | python3 -c 'import shlex, sys; print(shlex.quote(sys.stdin.read()))')

  # Leave one re-runnable line in history rather than the multi-line body that
  # `print -z` used to push there. Running this line again re-invokes the same
  # recipe with the same arguments.
  local replay _a
  # Abbreviate $HOME to ~ so the line reads like the ones typed by hand, and
  # only leave it unquoted (so ~ still expands on replay) when the rest of the
  # path needs no quoting.
  local _rjf="${_jf/#$HOME/~}" _rwd="${_wd/#$HOME/~}"
  [[ $_rjf == *[^A-Za-z0-9_./~-]* ]] && _rjf=${(q-)_jf}
  [[ $_rwd == *[^A-Za-z0-9_./~-]* ]] && _rwd=${(q-)_wd}
  # (q-) is minimal quoting: plain words stay bare and only arguments that need
  # it get wrapped in single quotes, so the line looks hand-typed. Plain (q)
  # backslash-escapes every space, which triples the length of a long --alter.
  replay="just --justfile $_rjf --working-directory $_rwd ${(q-)recipe}"
  for _a in "${args[@]}"; do
    replay+=" ${(q-)_a}"
  done

  print -u2 -- "→ ${invoke_prefix:+$invoke_prefix }$recipe ${args[*]}"

  # Confirm before recording history, so an aborted run leaves no trace of a
  # command that never happened.
  if (( needs_confirm )) && ! __j_confirm "Run $recipe?"; then
    print -u2 -- 'Aborted.'
    return 1
  fi

  print -s -- "$replay"
  # print -s only reaches zsh's own history; atuin hooks preexec, so it needs
  # to be told directly or the entry never shows up in ctrl-r.
  if command -v atuin >/dev/null 2>&1; then
    atuin history start -- "$replay" >/dev/null 2>&1 || true
  fi

  # Run it here instead of pushing it to the prompt buffer: that always needed a
  # second Enter, and the body is what polluted history.
  __j_exec "$quoted_cmd"
}
fi

# ── Obsidian / Notes ────────────────────────────────────────
export NOTES_DIR="${NOTES_DIR:-$HOME/40_Notes}"
export NOTES_INBOX="$NOTES_DIR/00 Inbox"

# vsync : 볼트를 지금 즉시 커밋+push (수동 백업). 대화형 셸이라 TCC 제약 없음.
alias vsync="$HOME/.local/bin/obsidian-vault-sync.sh"

# gpub : 볼트 공개노트(publish:true) → Astro 블로그 빌드 + Cloudflare 배포 (한 방)
export BLOG_DIR="${BLOG_DIR:-$HOME/src/github.com/ggiho/blog}"
alias gpub='(cd "$BLOG_DIR" && npm run publish:site && npm run deploy)'

# n [제목...] : 새 노트를 00 Inbox에 만들고 nvim으로 편집
n() {
  local title slug file
  title="$*"; [[ -z "$title" ]] && vared -p "제목: " title
  [[ -z "$title" ]] && return
  slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9가-힣]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')
  file="$NOTES_INBOX/$(date +%Y-%m-%d)-${slug}.md"
  [[ -f "$file" ]] || printf -- '---\ntitle: %s\ncreated: %s\ntags: []\n---\n\n# %s\n\n' \
      "$title" "$(date '+%Y-%m-%d %H:%M')" "$title" > "$file"
  nvim "$file"
}

# nc [메모...] : 편집기 없이 오늘 데일리 노트에 타임스탬프로 append (초고속 캡처)
nc() {
  local file="$NOTES_INBOX/$(date +%Y-%m-%d).md" line="$*"
  [[ -f "$file" ]] || printf -- '# %s\n\n' "$(date +%Y-%m-%d)" > "$file"
  [[ -z "$line" ]] && vared -p "메모: " line
  [[ -z "$line" ]] && return
  printf -- '- %s  %s\n' "$(date +%H:%M)" "$line" >> "$file"
  echo "✓ 추가됨 → ${file:t}"
}
# nt : 오늘 메모(일일로그) 바로 열기 (nc로 쌓은 메모 확인·편집)
nt() {
  local f="$NOTES_INBOX/$(date +%Y-%m-%d).md"
  [[ -f "$f" ]] || printf -- '# %s\n\n' "$(date +%Y-%m-%d)" > "$f"
  nvim "$f"
}
# nb : 새 블로그 글 (50_Blog에 발행 준비된 frontmatter로 생성 후 nvim). gpub로 발행.
nb() {
  local title slug file
  title="$*"; [[ -z "$title" ]] && vared -p "블로그 제목: " title
  [[ -z "$title" ]] && return
  slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')
  [[ -z "$slug" ]] && slug="post-$(date +%Y%m%d)"   # 한글 제목이면 slug 직접 수정
  file="$NOTES_DIR/50_Blog/${slug}.md"
  mkdir -p "$NOTES_DIR/50_Blog"
  [[ -f "$file" ]] || printf -- '---\ntitle: %s\ndescription: \ntags: []\npublishDate: %s\npublish: true\nslug: %s\n---\n\n' \
      "$title" "$(date +%Y-%m-%d)" "$slug" > "$file"
  nvim "$file"
}
# npub : 지금 보는(또는 지정) 볼트 노트를 블로그로 승격 — 50_Blog로 이동 + publish:true 보강
npub() {
  local f="$1"; [[ -z "$f" ]] && { echo "사용법: npub <노트경로>"; return 1; }
  [[ -f "$f" ]] || { echo "파일 없음: $f"; return 1; }
  mkdir -p "$NOTES_DIR/50_Blog"
  grep -q '^publish:' "$f" || sed -i '' '1a\
publish: true
' "$f"
  mv "$f" "$NOTES_DIR/50_Blog/$(basename "$f")"
  echo "✓ 블로그로 승격 → 50_Blog/$(basename "$f")  (slug/description 확인 후 gpub)"
}
# ndel : 발행된 블로그 글 삭제 — 볼트 50_Blog에서 제거 후 gpub하면 사이트에서도 사라짐
ndel() {
  local slug="${1%.md}"
  [[ -z "$slug" ]] && { echo "사용법: ndel <slug>   (예: ndel my-post)"; return 1; }
  local f="$NOTES_DIR/50_Blog/${slug}.md"
  [[ -f "$f" ]] || { echo "없음: 50_Blog/${slug}.md  (nf로 파일명 확인)"; return 1; }
  rm -f "$f" && echo "✓ 삭제: 50_Blog/${slug}.md  → 이제 gpub 하면 사이트에서도 사라짐"
}
# ns <시리즈> : 한 주제(책 등)를 시리즈로 묶어 챕터를 순번대로 쌓는다. 블로그에서 시리즈로 수집됨.
#   50_Blog/<시리즈>/NN 소제목.md 를 series/seriesOrder/publish:true 로 생성. gpub로 발행.
ns() {
  local topic="$*"; [[ -z "$topic" ]] && vared -p "시리즈(책 제목): " topic
  [[ -z "$topic" ]] && return
  local dir="$NOTES_DIR/50_Blog/$topic"
  mkdir -p "$dir"
  # 다음 순번 = 기존 챕터의 최대 seriesOrder + 1
  local last=0 o _f
  for _f in "$dir"/*.md(N); do
    o=$(awk -F': *' '/^seriesOrder:/{print $2; exit}' "$_f")
    [[ "$o" == <-> ]] && (( o > last )) && last=$o
  done
  local n=$(( last + 1 )) nn; nn=$(printf '%02d' "$n")
  local sub; vared -p "소제목 (${nn}장): " sub
  [[ -z "$sub" ]] && return
  local slug; slug=$(printf '%s' "$topic $nn $sub" | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9가-힣]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')
  [[ -z "$slug" ]] && slug="series-$(date +%Y%m%d%H%M%S)"
  local file="$dir/$nn $sub.md"
  [[ -f "$file" ]] || printf -- '---\ntitle: "%s"\ndescription: ""\ntags: []\nseries: "%s"\nseriesOrder: %d\npublishDate: %s\npublish: true\nslug: %s\n---\n\n# %s\n\n' \
      "$sub" "$topic" "$n" "$(date +%Y-%m-%d)" "$slug" "$sub" > "$file"
  nvim "$file"
}

# ── Zettelkasten 흐름 (ZazenCodes 방식 응용) ──────────────────────────
# or : 00 Inbox 노트를 하나씩 리뷰 → 보관(Fleeting)/삭제/편집
zk_review() {
  local inbox="$NOTES_DIR/00 Inbox" keep="$NOTES_DIR/40 Zettelkasten/41 Fleeting Notes"
  mkdir -p "$keep"
  local files=("$inbox"/*.md(N))
  (( ${#files} == 0 )) && { echo "Inbox가 비어있다"; return; }
  local f a
  for f in $files; do
    clear
    echo "── ${f:t} ──   [k]보관  [d]삭제  [o]편집  [s]건너뜀  [q]종료"
    echo "────────────────────────────────────────────"
    bat -p --color=always --line-range=:40 "$f" 2>/dev/null || sed -n '1,40p' "$f"
    echo "────────────────────────────────────────────"
    read -k 1 "a?선택> "; echo
    case "$a" in
      k) mv "$f" "$keep/" && echo "→ 보관 (41 Fleeting Notes)" ;;
      d) mv "$f" ~/.Trash/ 2>/dev/null || rm -f "$f"; echo "→ 삭제" ;;
      o) nvim "$f" ;;
      q) break ;;
      *) ;;  # s/기타 = 건너뜀
    esac
  done
  echo "리뷰 끝."
}
alias or='zk_review'

# og : frontmatter 첫 태그 기준으로 노트를 Permanent Notes/<tag>/ 로 자동 정리
og() {
  local src="${1:-$NOTES_DIR/40 Zettelkasten/41 Fleeting Notes}"
  local base="$NOTES_DIR/40 Zettelkasten/43 Permanent Notes"
  local f tag
  for f in "$src"/*.md(N); do
    tag=$(awk '
      /^tags:/{ if($0 ~ /\[/){ l=$0; sub(/.*\[/,"",l); sub(/\].*/,"",l); split(l,a,","); t=a[1]; gsub(/[" ]/,"",t); print t; exit } inb=1; next }
      inb && /^[[:space:]]*-[[:space:]]/{ t=$0; sub(/^[[:space:]]*-[[:space:]]*/,"",t); gsub(/["]/,"",t); print t; exit }
      inb{ exit }' "$f")
    if [[ -z "$tag" ]]; then echo "태그 없음, 건너뜀: ${f:t}"; continue; fi
    mkdir -p "$base/$tag"
    mv "$f" "$base/$tag/" && echo "→ 43 Permanent/$tag/  (${f:t})"
  done
}

# oh : 주제 허브(MOC) 노트 생성/열기 (노트 간 연결의 중심)
oh() {
  local title="$*"; [[ -z "$title" ]] && vared -p "허브 주제: " title
  [[ -z "$title" ]] && return
  local dir="$NOTES_DIR/40 Zettelkasten/44 MOCs" f
  mkdir -p "$dir"; f="$dir/${title}.md"
  [[ -f "$f" ]] || printf -- '---\ntitle: %s\ntype: MOC\ntags: [moc]\n---\n\n# %s (MOC)\n\n## 관련 노트\n\n- \n' "$title" "$title" > "$f"
  nvim "$f"
}

# nh : 노트/블로그/제텔카스텐 명령 치트시트 (헷갈리면 nh)
nh() {
  print -P "%F{cyan}── 노트 & 블로그 명령 ──────────────────────────%f"
  print -P "%F{yellow}[캡처]%f"
  print    "  n  <제목>    새 노트 (00 Inbox)"
  print    "  nc <메모>    오늘 일일로그에 한 줄 추가"
  print    "  nt           오늘 메모(일일로그) 열기"
  print -P "%F{yellow}[탐색]%f"
  print    "  nf           노트 찾아 열기 (fzf 미리보기)"
  print    "  ng <키워드>  내용 검색해서 그 줄로 열기"
  print    "  ob           Obsidian 앱 열기"
  print -P "%F{yellow}[Zettelkasten]  캡처→리뷰→정리→연결%f"
  print    "  or           Inbox 리뷰 → k보관 / d삭제 / o편집 / q종료"
  print    "  og           보관 노트를 태그별 폴더로 자동 정리"
  print    "  oh <주제>    허브(MOC) 노트 생성/열기 → [[링크]]로 연결"
  print -P "%F{yellow}[블로그]%f"
  print    "  nb <제목>    새 블로그 글 (50_Blog, 발행 준비 상태)"
  print    "  ns <시리즈>  책 등 주제를 챕터별로 쌓기 (블로그 시리즈로 수집)"
  print    "  npub <경로>  기존 노트를 블로그로 승격"
  print    "  ndel <slug>  발행 글 삭제 (→ gpub)"
  print    "  gpub         블로그 변환+빌드+배포 (한 방)"
  print -P "%F{yellow}[백업]%f"
  print    "  vsync        볼트 즉시 커밋+push"
  print -P "%F{cyan}────────────────────────────────  (헷갈리면 nh)%f"
}

# nf : 볼트 전체에서 파일명으로 찾아 열기 (fzf + bat 미리보기)
nf() {
  local f; f=$(cd "$NOTES_DIR" && rg --files -g '*.md' \
    | fzf --prompt="note> " --height=80% --reverse \
          --preview 'bat -p --color=always '"$NOTES_DIR"'/{}' --preview-window=right:60%)
  [[ -n "$f" ]] && nvim "$NOTES_DIR/$f"
}

# ng [검색어] : 노트 내용 전문검색 → 매칭 줄에서 바로 열기 (ripgrep + fzf)
ng() {
  local m; m=$(cd "$NOTES_DIR" && rg --line-number --no-heading --color=always --smart-case "${*:-}" -g '*.md' \
    | fzf --ansi --prompt="grep> " --height=80% --reverse -d: \
          --preview 'bat -p --color=always --highlight-line {2} '"$NOTES_DIR"'/{1}' \
          --preview-window='right:60%:+{2}-/2')
  [[ -z "$m" ]] && return
  local f="${m%%:*}" l="${m#*:}"; l="${l%%:*}"   # file:line:text → file, line
  nvim "+${l}" "$NOTES_DIR/$f"
}
