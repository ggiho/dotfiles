# alias ls="eza --icons --grid --classify --colour=auto --sort=type --group-directories-first --header --created --modified --git --binary"
alias ls="eza --icons=always"
# alias ls="eza -l --icons --git -a"
alias ll="ls -al"
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

# asurion
alias npd="export AWS_PROFILE=asurion-apac-nonprod.korea-dbadmin"
alias pd="export AWS_PROFILE=asurion-apac-prod.korea-dbadmin" 
alias db="~/dev/./db-connect.sh"

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
