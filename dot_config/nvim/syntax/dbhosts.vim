" Vim syntax file for the ~/.config/mysql/hosts DB host list.
" Format per line: Label:host:port:user[:client:db]

if exists("b:current_syntax")
  finish
endif

" Comments (in case any are added later)
syntax match dbhostsComment /^\s*#.*$/

" Field 1: the label, from start of line up to the first colon
syntax match dbhostsLabel /^[^:#][^:]*/ contains=dbhostsEnv

" Environment tags inside the label (contained so they overlay the label match)
syntax keyword dbhostsEnv PROD DEV SQA UAT PRD NPR LOCAL contained

" Port: digits sitting between two colons or a colon and end-of-line (colons kept via lookaround)
syntax match dbhostsPort /\%(:\)\@<=\d\+\%(:\|$\)\@=/

" Host / IP: a dotted token following a colon
syntax match dbhostsHost /\%(:\)\@<=[A-Za-z0-9._-]*\.[A-Za-z0-9._-]\+/

" Account/user: the field right after the port (:<port>:<user>); overrides dbhostsHost
syntax match dbhostsUser /\%(:\d\+:\)\@<=[A-Za-z0-9._-]\+/

" Field separators
syntax match dbhostsColon /:/

" Palette tuned to resemble the built-in tmux syntax:
"   label = leading command color (purple), host = normal text,
"   port = number (orange), user = string (green), env = accent (pink).
highlight default link dbhostsComment Comment
highlight default link dbhostsLabel   Statement
highlight default link dbhostsEnv     Function
highlight default link dbhostsPort    Number
highlight default link dbhostsHost    Normal
highlight default link dbhostsUser    String
highlight default link dbhostsColon   Delimiter

let b:current_syntax = "dbhosts"
