#!/bin/bash
set -eu

: "${HOME:?HOME is required}"
src_root="${DOTFILES_SRC_ROOT:-$HOME/src}"

mkdir -p -- \
  "$HOME/00_Inbox" \
  "$HOME"/10_Database/{AWS,MongoDB,MySQL,PostgreSQL,Redshift,_Utils,docs,queries} \
  "$HOME/20_Work" \
  "$HOME"/30_Projects/{00_Ideas,01_Personal,02_Study,03_Tools} \
  "$HOME"/80_System/{App_Configs,Assets,Licenses,Manuals} \
  "$HOME/99_Archive" \
  "$src_root"/{github.com/ggiho,git.postgresql.org,local}
