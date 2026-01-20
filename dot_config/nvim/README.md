# Neovim Configuration

현대적인 Neovim 설정으로 Lua와 lazy.nvim 패키지 매니저를 사용합니다.

## 🚀 주요 특징

- **완전한 Lua 설정**: 성능 향상을 위해 Lua로 작성
- **Lazy Loading**: 빠른 시작을 위한 지연 로딩
- **LSP 지원**: 여러 프로그래밍 언어 지원
- **자동 포맷팅**: 저장 시 자동 코드 포맷팅
- **아름다운 UI**: Catppuccin 테마와 투명 배경
- **생산성 도구**: 파일 탐색기, 퍼지 파인더, 자동 완성

## 📁 디렉토리 구조

```
~/.config/nvim/
├── init.lua              # 메인 진입점
├── lua/
│   ├── core/
│   │   ├── init.lua      # 코어 모듈 로더
│   │   ├── options.lua   # 에디터 옵션
│   │   ├── keymaps.lua   # 키 매핑
│   │   └── lsp.lua       # LSP 설정
│   ├── lazy.lua          # 패키지 매니저 설정
│   └── plugins/          # 플러그인 설정들
└── lsp/                  # LSP 서버 설정들
```

## ⌨️ 핵심 키 매핑

**리더 키**: `Space`

### 네비게이션
- `lk` (Insert 모드): Normal 모드로 전환
- `J`/`K` (Visual 모드): 선택한 라인 위/아래로 이동
- `<C-d>`/`<C-u>`: 페이지 이동 (커서 중앙 유지)
- `<leader>nh`: 검색 하이라이트 제거

### 창 관리
- `<leader>sv`: 수직 분할
- `<leader>sh`: 수평 분할
- `<leader>se`: 창 크기 균등화
- `<leader>sx`: 현재 창 닫기

### 파일 탐색
- `<leader>e`: 파일 탐색기 토글
- `<leader>ff`: 파일 찾기 (Telescope)
- `<leader>fs`: 텍스트 검색
- `<leader>fr`: 최근 파일

## 🎨 플러그인 목록

### UI & 테마
- **catppuccin**: 모던한 파스텔 테마
- **lualine.nvim**: 커스텀 상태바
- **nvim-tree.lua**: 파일 탐색기
- **noice.nvim**: 향상된 UI 요소
- **dressing.nvim**: 더 나은 UI 선택 창

### 코드 편집
- **nvim-treesitter**: 구문 하이라이팅
- **nvim-cmp**: 자동 완성
- **LuaSnip**: 스니펫 엔진
- **nvim-autopairs**: 자동 괄호 닫기
- **mini.nvim**: 주석, 서라운드, 공백 관리 등

### 개발 도구
- **telescope.nvim**: 퍼지 파인더
- **conform.nvim**: 코드 포맷터
- **nvim-lint**: 린터
- **todo-comments.nvim**: TODO 하이라이트

### LSP & 언어 지원
- **mason.nvim**: LSP 서버 관리
- **mason-lspconfig.nvim**: LSP 자동 설정
- 지원 언어: Lua, TypeScript/JavaScript, Python, HTML, C/C++

## 🛠️ LSP 서버

| 언어 | 서버 | 포맷터 | 린터 |
|------|------|--------|------|
| Lua | lua_ls | stylua | luacheck |
| TypeScript/JavaScript | ts_ls | prettier | eslint_d |
| Python | ruff | ruff | ruff |
| HTML/CSS | html | prettier | - |
| C/C++ | clangd | clang-format | cppcheck |

## 📦 설치된 플러그인 상세

### 자동 완성 (nvim-cmp)
- LSP, 버퍼, 경로, 스니펫 소스
- 스마트 Tab/Backspace
- Ghost text 지원
- Tailwind CSS 색상 미리보기

### 파일 탐색기 (nvim-tree)
- `<leader>e`: 토글
- `<leader>;`: 포커스 전환
- 상대 줄 번호 표시
- .DS_Store 파일 숨김

### 퍼지 파인더 (Telescope)
- 파일, 텍스트, Git 검색
- FZF 네이티브 확장
- TODO 코멘트 통합

### 포맷팅 (conform.nvim)
- 저장 시 자동 포맷팅
- `<leader>mp`: 수동 포맷팅
- 언어별 포맷터 설정

### 린팅 (nvim-lint)
- 실시간 오류 검사
- `<leader>l`: 수동 린팅
- 100KB 이상 파일 스킵

## 🔧 설정 커스터마이징

### 새 플러그인 추가
`lua/plugins/` 디렉토리에 새 파일을 만들어 플러그인을 추가할 수 있습니다:

```lua
-- lua/plugins/your-plugin.lua
return {
  "username/plugin-name",
  config = function()
    -- 플러그인 설정
  end,
}
```

### LSP 서버 추가
1. Mason으로 서버 설치: `lua/plugins/mason.lua`의 `ensure_installed`에 추가
2. LSP 활성화: `lua/core/lsp.lua`의 `vim.lsp.enable()`에 추가
3. 서버 설정: `lsp/` 디렉토리에 설정 파일 생성

## 💡 팁

- `:Lazy` 명령으로 플러그인 관리 UI 열기
- `:LspInfo` 명령으로 현재 LSP 상태 확인
- `:Mason` 명령으로 LSP 서버 관리
- `:checkhealth` 명령으로 설정 상태 확인

## 📝 라이선스

이 설정은 개인적인 사용을 위해 만들어졌습니다. 자유롭게 수정하고 사용하세요!