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
export DMSCTL_ROOT="$HOME/20_Work/01_Asurion/scripts/aws/dms"
export DDB_SCRIPT_DIR="$HOME/10_Database/AWS/dynamodb"
alias vj="vi $JUSTFILE"
unalias j 2>/dev/null
j() {
  local selected recipe sig rest param name default prompt_str val cmd dry line fzf_selected
  local -a params args db_hosts db_labels db_users host_options just_lines
  local -A hints
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

  selected=$(printf '%s\n' "$list_out" | sed '/^[[:space:]]*$/d' | fzf --prompt="just> " --height=40%)
  [ -z "$selected" ] && return

  # ── Detect module vs top-level recipe ──
  local first_tok src_file invoke_prefix is_mod=0
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
        break
      done
      break
    fi
  done

  rest="${sig#${recipe}}"
  rest="${rest# }"
  params=()
  [[ -n "$rest" ]] && params=("${(z)rest}")

  local default_user=""
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
    name=${param%%=*}
    default=""
    if [[ "$param" == *=* ]]; then
      default=${param#*=}
      default=${default#\"}
      default=${default%\"}
    fi

    if [[ "$name" == *host* && ${#host_options[@]} -gt 0 ]]; then
      local _q="" _sel="" _out=""
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
            matched=1
            break
          fi
        done
        (( matched )) || val="$_sel"
        echo "$name: $val"
      elif [[ -n "$_q" ]]; then
        # typed a host not in the list -> use it as-is (user falls back to default_user)
        val="$_q"
        echo "$name: $val"
      else
        vared -p "$name: " val
      fi
    else
      if [[ "$name" == *user* ]]; then
        if [[ -n "$selected_user" ]]; then
          default="$selected_user"
        elif [[ -n "$default_user" ]]; then
          default="$default_user"
        fi
      fi

      if [[ -n "${hints[$name]-}" && -n "$default" ]]; then
        prompt_str="$name (${hints[$name]}) [$default]: "
      elif [[ -n "${hints[$name]-}" ]]; then
        prompt_str="$name (${hints[$name]}): "
      elif [[ -n "$default" ]]; then
        prompt_str="$name [$default]: "
      else
        prompt_str="$name: "
      fi

      vared -p "$prompt_str" val
      val=${val:-$default}
    fi

    args+=("$val")
    val=""
  done

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

  dry=$(just --dry-run --justfile "$_jf" --working-directory "$_wd" "$recipe" "${args[@]}" 2>&1) || {
    print -u2 -- "$dry"
    return 1
  }

  cmd=$(printf '%s' "$dry" | python3 -c 'import re, sys
text = sys.stdin.read()
lines = [line for line in text.splitlines() if line and not line.startswith("#!") and not line.startswith("set ") and not line.startswith("echo")]
text = "\n".join(lines)
text = re.sub(r"\\\n\s*", " ", text).rstrip()
print(text, end="")')

  local quoted_cmd
  quoted_cmd=$(printf '%s' "${_cdpfx}${cmd}" | python3 -c 'import shlex, sys; print(shlex.quote(sys.stdin.read()))')

  print -z "bash -lc $quoted_cmd"
}
fi

# ── Obsidian / Notes ────────────────────────────────────────
export NOTES_DIR="$HOME/40_Notes"
export NOTES_INBOX="$NOTES_DIR/00 Inbox"

# vsync : 볼트를 지금 즉시 커밋+push (수동 백업). 대화형 셸이라 TCC 제약 없음.
alias vsync="$HOME/.local/bin/obsidian-vault-sync.sh"

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

# nf : 볼트 전체에서 파일명으로 찾아 열기 (fzf + bat 미리보기)
nf() {
  local f; f=$(cd "$NOTES_DIR" && rg --files -g '*.md' \
    | fzf --prompt="note> " --height=80% --reverse \
          --preview 'bat -p --color=always "'"$NOTES_DIR"'/{}"' --preview-window=right:60%)
  [[ -n "$f" ]] && nvim "$NOTES_DIR/$f"
}

# ng [검색어] : 노트 내용 전문검색 → 매칭 줄에서 바로 열기 (ripgrep + fzf)
ng() {
  local m; m=$(cd "$NOTES_DIR" && rg --line-number --no-heading --color=always --smart-case "${*:-}" -g '*.md' \
    | fzf --ansi --prompt="grep> " --height=80% --reverse -d: \
          --preview 'bat -p --color=always --highlight-line {2} "'"$NOTES_DIR"'/{1}"' \
          --preview-window='right:60%:+{2}-/2')
  [[ -z "$m" ]] && return
  local f="${m%%:*}" l="${m#*:}"; l="${l%%:*}"   # file:line:text → file, line
  nvim "+${l}" "$NOTES_DIR/$f"
}
