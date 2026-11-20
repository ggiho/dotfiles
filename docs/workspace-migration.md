# 새 Mac에서 작업 디렉토리 복원

chezmoi 초기화가 아래 폴더의 틀을 만든다. 기존 경로를 유지하면 셸 별칭, Neovim의 Obsidian 설정, just 레시피가 같은 위치를 찾을 수 있다.

| 경로 | 내용 복원 방법 |
| --- | --- |
| `~/00_Inbox/` | 아직 분류하지 않은 파일을 기존 Mac의 백업에서 복원한다. |
| `~/10_Database/` | DB별 스크립트, 설정, 문서와 쿼리를 복원한다. `DDB_SCRIPT_DIR`과 RDS just 모듈은 이 경로를 참조한다. |
| `~/20_Work/` | 업무 폴더를 회사에서 허용한 방법으로 이전한다. 로컬 전용 Git 저장소는 작업 파일과 `.git`을 함께 보존한다. |
| `~/30_Projects/{00_Ideas,01_Personal,02_Study,03_Tools}/` | 분류한 아이디어, 개인 프로젝트, 학습 자료와 도구 파일을 복원한다. |
| `~/40_Notes/` | notes-bootstrap이 별도 Git 저장소에서 복제한다. 블로그 원본은 `50_Blog/`에 있다. |
| `~/80_System/{App_Configs,Assets,Licenses,Manuals}/` | 앱 설정 백업, 자산, 라이선스와 안내서를 복원한다. |
| `~/99_Archive/` | 이전 Mac의 보관 자료를 복원한다. |
| `~/src/<호스트>/<조직>/<저장소>/` | 원격 Git 저장소 작업 사본을 같은 위치에 복제한다. 블로그는 `~/src/github.com/ggiho/blog`에 둔다. `~/src/local/`에 있는 로컬 프로젝트는 기존 Mac에서 복원한다. |

기존 chezmoi 환경에서 폴더 틀만 다시 만들려면 아래 명령을 실행한다. 같은 경로에 있는 파일은 보존된다.

```bash
bash "$(chezmoi source-path)/run_once_before_create-workspace-directories.sh"
```

## 이전 전에 확인할 것

- **dotfiles** · chezmoi 원격에 필요한 커밋이 있는지 확인하고, 실제 홈 설정과 관리 소스의 차이는 `chezmoi status`로 검토한다.
- **코드와 글** · 블로그, Obsidian 볼트, 작업 중인 Git 저장소의 원격에 필요한 커밋이 있는지 확인한다. 미커밋 파일과 원격이 없는 저장소는 기존 Mac의 백업에 포함한다. Cloudflare 배포와 Git 푸시는 별개다.
- **수동 복원** · DB 설정, macOS 권한, 키체인, 앱 내부 설치는 [수동 복원 문서](manual-setup.md)를 참고한다. `~/.codex/`에 있는 로컬 설정과 스킬은 필요한 항목을 별도로 확인한다.

새 Mac에서 폴더와 데이터를 복원한 뒤 블로그 저장소의 README에 따라 `npm ci`와 로컬 미리보기를 실행한다. 글을 수정할 때는 `~/40_Notes/50_Blog/`의 원본을 편집한다.
