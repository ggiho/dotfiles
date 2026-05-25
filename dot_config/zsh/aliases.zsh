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
alias asurion_claude_login="/Users/giho.seong/.claude/claude_login.sh"

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
export ASURION_HOME="$HOME/20_Work/01_Asurion"
alias db="$ASURION_HOME/utils/db-connect.sh"
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

# just
export JUSTFILE="$HOME/.config/justfile/justfile"
export DMSCTL_ROOT="$HOME/20_Work/01_Asurion/scripts/aws/dms"
export DDB_SCRIPT_DIR="$HOME/10_Database/AWS/dynamodb"
alias vj="vi $JUSTFILE"
unalias j 2>/dev/null
j() {
  local selected recipe sig rest param name default prompt_str val cmd dry line fzf_selected
  local -a params args db_hosts db_labels db_users host_options just_lines
  local -A hints
  local hosts_file="$HOME/.config/mysql/hosts"
  local selected_user=""

  selected=$(just --list --justfile "$JUSTFILE" --list-heading='' --list-prefix='' | fzf --prompt="just> " --height=40%)
  [ -z "$selected" ] && return

  recipe=$(echo "$selected" | sed 's/^[[:space:]]*//' | awk '{print $1}')

  just_lines=("${(@f)$(<"$JUSTFILE")}")
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
        break
      done
      break
    fi
  done

  sig=$(echo "$selected" | sed 's/#.*//' | sed 's/^ *//')
  rest="${sig#${recipe}}"
  rest="${rest# }"
  params=()
  [[ -n "$rest" ]] && params=("${(z)rest}")

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
      fzf_selected=$(printf '%s\n' "${host_options[@]}" | fzf --prompt="$name> " --height=40%)
      if [[ -n "$fzf_selected" ]]; then
        local matched=0 idx
        for (( idx = 1; idx <= ${#host_options[@]}; idx++ )); do
          if [[ "${host_options[$idx]}" == "$fzf_selected" ]]; then
            val="${db_hosts[$idx]}"
            selected_user="${db_users[$idx]}"
            matched=1
            echo "$name: $val"
            break
          fi
        done
        (( matched )) || vared -p "$name: " val
      else
        vared -p "$name: " val
      fi
    else
      if [[ "$name" == *user* && -n "$selected_user" ]]; then
        default="$selected_user"
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

  dry=$(just --dry-run --justfile "$JUSTFILE" --working-directory "$PWD" "$recipe" "${args[@]}" 2>&1) || {
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
  quoted_cmd=$(printf '%s' "$cmd" | python3 -c 'import shlex, sys; print(shlex.quote(sys.stdin.read()))')

  print -z "bash -lc $quoted_cmd"
}
