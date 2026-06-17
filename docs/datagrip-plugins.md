# DataGrip Plugins (재설치용 목록)

플러그인 **바이너리는 chezmoi로 관리하지 않음** (`~/Library/Application Support/JetBrains/DataGrip*/plugins/`, ~788MB, 버전·플랫폼 종속).
새 머신에서는 아래 목록을 보고 Marketplace에서 직접 설치한다.

설치: DataGrip → Settings → Plugins → Marketplace → 검색 후 설치.

## 직접 설치한 플러그인 (재설치 필요)

| 플러그인 | 폴더명 | 용도 |
|----------|--------|------|
| IdeaVim | `IdeaVIM` | Vim 에뮬레이션 |
| Rainbow Brackets | `intellij-rainbow-brackets` | 괄호 색상 |
| CodeGlance Pro | `CodeGlancePro` | 코드 미니맵 |
| Which-Key | `IDEA_Which-Key` | 단축키 힌트 팝업 |
| CodelyTV theme | `codelytv-theme` | "Codely Blue" 테마 (laf.xml이 참조) |
| ppy theme | `ppy-theme` | 테마 |

> 테마(`codelytv-theme`)를 먼저 설치해야 `options/laf.xml`의 테마 설정이 적용된다.

## 번들(기본 내장) — 재설치 불필요

DataGripHelp, performanceTesting, performanceTesting-yourkit, terminal,
vcs-hg, vcs-perforce, vcs-svn, ml-llm, settingsRepository

## 갱신 방법

플러그인을 추가/삭제했으면 현재 설치 목록을 다시 확인:

```bash
ls ~/Library/Application\ Support/JetBrains/DataGrip*/plugins/
```
