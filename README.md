# dotfiles

## 새 Mac 세팅

### 1. Xcode Command Line Tools 설치

```bash
xcode-select --install
```

### 2. dotfiles 설치

```bash
curl -fsSL https://raw.githubusercontent.com/ggiho/dotfiles/main/install.sh | bash
```

자동으로 아래 순서로 실행됩니다:

1. Homebrew 설치
2. chezmoi 설치
3. dotfiles 적용 (`chezmoi init --apply`)
4. Brewfile로 패키지 설치
5. macOS 기본 설정 적용

---

## 관리

### 변경사항 반영

```bash
# 파일 수정 후 chezmoi에 반영
chezmoi add <파일경로>

# chezmoi source로 이동
cd ~/.local/share/chezmoi
git add .
git commit -m "message"
git push
```

### 다른 Mac에서 업데이트

```bash
chezmoi update
```

### Brewfile 업데이트

```bash
brew bundle dump --file=~/.config/brew/Brewfile --force
chezmoi add ~/.config/brew/Brewfile
```

---

## 구성

| 파일/폴더 | 설명 |
|-----------|------|
| `install.sh` | 새 Mac 초기 세팅 스크립트 |
| `run_once_bootstrap.sh` | Brewfile로 패키지 설치 (최초 1회) |
| `run_onchange_macos-defaults.sh` | macOS 시스템 설정 (변경 시 재실행) |
| `dot_zshrc` | zsh 설정 |
| `dot_config/wezterm/` | WezTerm 설정 |
| `dot_config/brew/Brewfile` | Homebrew 패키지 목록 |
