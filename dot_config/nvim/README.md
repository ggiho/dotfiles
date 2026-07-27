# Neovim Configuration

Neovim 0.12, native LSP, Treesitter, `lazy.nvim`을 사용하는 개인 설정입니다. Seth의
`vim.pack` 실험 설정에서 편집 워크플로는 가져오되, 메인 플러그인 관리자는 안정적인
`lazy.nvim`으로 유지합니다.

## 키를 찾는 방법

| 키 | 동작 |
| --- | --- |
| `<leader>`를 누르고 잠시 대기 | `mini.clue`로 현재 가능한 키 확인 |
| `<leader>fk` | 전체 키맵 검색 |
| `<leader>fh` | Neovim 도움말 검색 |
| `g`, `[`, `]`, `<C-w>`를 누르고 대기 | 해당 기본 키 계열 확인 |

리더 키는 `Space`입니다.

## 매일 쓰는 키

### 찾기와 파일

| 키 | 동작 |
| --- | --- |
| `<leader>ff` | 파일 찾기 |
| `<leader>fg` | 프로젝트 전체 문자열 검색 |
| `<leader>fr` | 최근 파일 |
| `<leader>fb` | 열린 버퍼 찾기 |
| `<leader>fd` | 진단 목록 찾기 |
| `<leader>/` | 현재 버퍼 안에서 찾기 |
| `<leader>e` | 현재 파일 위치에서 `mini.files` 열기 |
| `<leader>E` | 작업 디렉터리에서 `mini.files` 열기 |

`mini.files` 안에서는 `h/l`로 상위/하위 이동, `=`로 파일 작업 적용, `g?`로 도움말을
확인합니다. 삭제는 즉시 영구 삭제하지 않고 mini 전용 휴지통으로 이동합니다.

### 코드 이동과 LSP

Neovim 0.12 기본 LSP 키를 우선 사용합니다.

| 키 | 동작 |
| --- | --- |
| `gd` / `gD` | 정의 / 선언으로 이동 |
| `K` | hover 문서 |
| `grr` | 참조 찾기 |
| `gri` | 구현 찾기 |
| `grn` | 이름 변경 |
| `gra` | 코드 액션 |
| `gO` | 문서 심볼 |
| `<leader>ls` | 워크스페이스 심볼 검색 |
| `gl` | 현재 진단 보기 |
| `[d` / `]d` | 이전 / 다음 진단 |
| `<leader>lq` | 진단을 location list로 열기 |
| `<leader>lh` | inlay hint 토글 |
| `<leader>lf` | 파일 또는 선택 영역 포맷 |
| `<leader>ll` | 현재 파일 lint 실행 |

### 편집과 Git

| 키 | 동작 |
| --- | --- |
| `gc` + motion | 주석 토글 |
| `sa` / `sd` / `sr` | surrounding 추가 / 삭제 / 교체 |
| `gS` | 인자 목록 split/join |
| `<leader>gs` / `<leader>gr` | 현재 Git hunk stage / reset |
| `gh` / `gH` + motion | 선택 범위 Git hunk stage / reset |
| `[h` / `]h` | 이전 / 다음 Git hunk |
| `<leader>go` | 현재 버퍼 Git diff overlay |
| `<leader>cw` | trailing whitespace 정리 |
| Visual `J` / `K` | 선택한 줄 이동 |
| Visual `p` | 기존 yank를 보존하며 붙여넣기 |

`mini.ai`는 `a`/`i` text object를 확장합니다. 예를 들어 `daf`는 함수 전체 삭제,
`cia`는 함수 인자 변경에 사용할 수 있습니다.

### 버퍼와 창

| 키 | 동작 |
| --- | --- |
| `[b` / `]b` | 이전 / 다음 버퍼 |
| `<leader>bb` | 직전 버퍼 |
| `<leader>bd` / `<leader>bD` | 버퍼 안전 삭제 / 강제 삭제 |
| `<C-h/j/k/l>` | Neovim 창과 tmux pane 사이 이동 |
| `<C-w>`를 누르고 대기 | 분할, 크기 조정, 창 닫기 키 확인 |

### 기본 작업

| 키 | 동작 |
| --- | --- |
| `lk` | Insert 모드 종료 |
| `<leader>nh` | 검색 하이라이트 제거 |
| `<leader>w` / `<leader>q` | 저장 / 변경사항을 버리고 현재 창 종료 |
| `<leader>re` | Neovim 재시작 |
| `<leader>fp` | 현재 파일의 상대 경로 복사 |
| `<leader>s` | 커서 아래 단어를 버퍼 전체에서 치환 |

## 변경된 기존 키

| 기존 | 현재 |
| --- | --- |
| `<leader>n` / `<leader>p` | `]b` / `[b` |
| `<leader>bm` | `<leader>bb` |
| `<leader>mp` | `<leader>lf` |
| `<leader>l` (lint) | `<leader>ll` |
| `<leader>f` (LSP format) | `<leader>lf` |
| `<leader>rn` / `<leader>ca` | Neovim 기본 `grn` / `gra` |
| `<leader>ds` / `<leader>ws` | Neovim 기본 `gO` / `<leader>ls` |
| `nvim-tree` | `mini.files` (`<leader>e`) |

기본 `c`, `x`, `d`의 레지스터 동작은 더 이상 덮어쓰지 않습니다.

## 관리

- `:Lazy`: 플러그인 상태와 업데이트
- `:Mason`: LSP 및 개발 도구 설치 상태
- `:LspInfo`: 현재 버퍼 LSP 상태
- `:checkhealth`: 전체 설정 점검
