# mysqlsh-load 컬럼 매핑

기존 `mysqlsh-load`에 `mapping`, `duplicates`, `dry_run`, `interactive`, `clear_target` 선택 인자를 추가했다.
`mapping`을 생략하면 덤프 선택 후 저장된 매핑 JSON을 `fzf` 목록에서 고를 수 있다.
매핑이 없거나 `[매핑 없이 일반 적재]`를 선택하면 기존 `util.loadDump()` 경로를 사용한다.
매핑 모드는 `util.importTable()`로 **설정에 나열한 테이블의 데이터만** 기존 타깃 테이블에 넣는다.
소스 DDL로 타깃 구조를 교체하거나 컬럼 이름을 바꾸지 않는다. `clear_target=true`일 때만
선택한 타깃 테이블의 모든 행을 비운다.

## 대화형으로 선택하기

인자 없이 `j`를 열어 레시피를 고르면, 선택한 host는 접속 정보 카드로 표시된다. 나머지 항목은
설명·필수/선택·기본값·진행 단계가 있는 카드와 입력창으로 표시하며 기본값은 바로 수정할 수 있다.
불리언과 기존 객체/중복 처리 정책은 공통 테마의 `fzf`에서 선택한다. 입력 취소 시 작업을 실행하지 않는다.
이 입력 UI는 `~/.config/zsh/aliases.zsh`의 공통 `j()` 래퍼에 적용된다. 인자를 직접 넘기는 호출은 기존 방식대로 동작한다.

`j`에서 `mysqlsh-load` 또는 `mysqlsh-load-map`을 고르면 `target_schema`도 `fzf`로 선택한다.
앞에서 확정한 host·user·port로 접근 가능한 스키마 목록을 읽으며, 비밀번호는 Keychain에서
환경 변수로만 전달한다. `[비움]`은 매핑 파일/덤프의 스키마 설정을 유지하고, `[직접 입력]`도 가능하다.
목록 조회가 실패하면 이를 표시하고 직접 입력/기본 설정을 선택할 수 있다. `Esc`는 실행과 기록 전에 취소한다.

`mapping` 항목도 `fzf`에서 현재 폴더의 저장된 JSON을 선택한다. `[나중에 선택]`을 고르면
덤프 선택 뒤에 매핑 방식을 결정하며, `[직접 입력]`으로 다른 경로의 파일도 지정할 수 있다.
실제 소스→타깃 **테이블 연결은 덤프를 선택한 다음** `[새 테이블·컬럼 매핑]`에서 진행한다.

매핑 JSON을 미리 만들지 않아도 된다. 다음 명령에서 덤프, 타깃 스키마·테이블, 컬럼 연결·제외를 선택한다.

```bash
just mysqlsh-load-map target-host db-user

# 포트/스레드/타깃 스키마를 미리 지정
just mysqlsh-load-map target-host db-user 3306 4 target_db

# 선택·사전 검사·JSON 저장까지만 수행 (데이터 적재 없음)
just mysqlsh-load-map target-host db-user 3306 4 target_db '' error true

# 저장한 선택을 현재 구조와 다시 비교
just mysqlsh-load-map target-host db-user 3306 4 target_db ./mapping.json

# 선택한 타깃 테이블을 전체 비운 뒤 적재 (실제 테이블 목록 확인 필요)
just mysqlsh-load-map target-host db-user 3306 4 target_db ./mapping.json error false true
```

진행 순서는 다음과 같다.

1. 덤프와 기존 타깃 스키마를 선택한다. 소스는 원본 DB에 재접속하지 않고 덤프 당시 정보를 사용한다.
2. 소스 테이블을 선택하고 각 타깃 테이블을 연결한다. 여러 테이블은 선택 결과 순서로 적재되므로 부모 테이블을 먼저 둔다.
3. 이름·타입·NULL 허용·문자셋·콜레이션이 일치하는 컬럼은 자동 연결한다. 차이가 있는 컬럼은 `fzf`에서 타깃 컬럼이나 `[제외]`를 직접 선택한다. 유사한 이름은 후보 순위에만 반영한다.
4. 각 테이블의 전체 매핑과 타깃 전용 컬럼의 기본값/NULL/자동 생성 여부를 검토한다. 다시 편집하거나 해당 테이블을 제외할 수 있다. 값이 필요한 필수 컬럼이 남으면 승인할 수 없다.
5. 기존 행 처리 방식(`error`/`skip`/`replace`)을 선택하고 모든 테이블의 사전 검사를 수행한다.
6. JSON으로 저장하거나 저장 없이 진행한다. 기본 저장 위치는 덤프 안의 `mapping_<시각>.json`이다. 기존 파일은 덮어쓰지 않는다.
7. 최종 적재 질문에 `y`를 입력한 경우에만 데이터를 넣는다. Enter는 취소이며, `dry_run=true`에서는 이 질문 없이 검사로 끝난다.

`Esc`는 선택을 취소한다. 최종 취소 전 저장한 JSON은 유지되며 데이터는 적재하지 않는다.
비밀번호는 기존 방식으로 stdin에서 받고, 선택과 확인은 `/dev/tty`를 사용한다. 따라서 대화형 모드는 터미널과 기존 `fzf` 설치가 필요하다. 자동화에서는 파일 기반 매핑을 사용한다.

소스 타입은 덤프의 `CREATE TABLE` DDL을 읽어 비교한다. DDL을 실행하지 않는다. DDL이 없거나
해석하지 못한 컬럼은 타입·NULL 확인 불가로 표시하고 명시적인 연결/제외 선택을 요구한다.
타입 차이를 승인해도 실제 데이터 변환이 성공한다는 보장은 없으며 적재 경고 검사는 계속 적용된다.

저장 파일에는 선택 외에 `target_schema`와 `schema_snapshot`을 기록한다. 대화형 모드에서 같은 파일을
다시 열면 현재 덤프/타깃 정보를 읽어 변경된 컬럼을 재확인한다. 구조가 같은 이전 연결·제외 선택은
재사용한다. 일반 `mysqlsh-load`에 저장 파일을 주면 대화형 재검토 없이 기존 사전 검사를 사용한다.

## 파일로 지정하기

`mysqlsh-load`와 `mysqlsh-load-map` 모두 매핑 경로를 생략하면 선택한 덤프 폴더와 현재 폴더에서
각각 하위 폴더 한 단계까지 JSON을 찾는다. `tables`가 있는 매핑 형식만 목록에 포함하므로
덤프 메타데이터와 무관한 JSON은 제외된다. 경로를 인자로 지정하면 목록 선택은 생략한다.

저장된 JSON이 없어도 매핑 방식 선택 메뉴는 항상 표시된다. 일반 모드에서는
`[매핑 없이 일반 적재]`, `[새 테이블·컬럼 매핑]`, `[매핑 파일 경로 직접 입력]`을 제공한다.
새 매핑을 선택하면 대화형 테이블·컬럼 선택으로 이어진다. `mysqlsh-load-map`에서는
`[새 매핑 만들기]`와 파일 선택을 제공한다. `Esc` 또는 직접 입력에서 빈 경로를 입력하면
로더를 실행하지 않고 취소한다. 앞단 `j`의 스키마 목록 조회는 읽기 전용으로 이미 수행됐을 수 있다.

매핑 파일 예:

```json
{
  "tables": {
    "source_db.people": {
      "exclude_columns": ["secret", "debug_text"],
      "column_map": {"user_name": "display_name"},
      "target_table": "people"
    },
    "source_db.orders": {}
  }
}
```

`exclude_columns`, `column_map`, `target_table`은 모두 선택 사항이다. 생략한 컬럼은 같은 이름으로
적재하므로 타깃에 없는 컬럼은 명시적으로 제외해야 한다. 설정의 소스 이름은 덤프 메타데이터와
정확히 일치해야 한다. `target_schema`를 지정하면 모든 설정 테이블을 해당 스키마로 적재하고,
생략하면 저장 파일의 `target_schema`, 그것도 없으면 각 소스 스키마 이름을 사용한다.
`target_table`의 기본값은 소스 테이블 이름이다.
제외한 값도 원본 덤프 파일에는 남아 있다.

기존 인자의 위치를 유지했다. 직접 `just`를 호출할 때는 다음 순서로 위치 인자를 전달한다:

```text
mysqlsh-load host user port threads target_schema on_exist force_drop mapping duplicates dry_run interactive clear_target
```

```bash
# 덤프 디렉토리를 fzf로 선택한 뒤, 매핑과 타깃을 읽기 전용으로 검사
just mysqlsh-load target-host db-user 3306 4 target_db error false ./mapping.json error true

# 빈 타깃에 적재 (위 명령의 마지막 인자만 false)
just mysqlsh-load target-host db-user 3306 4 target_db error false ./mapping.json error false

# 기존 행을 유지하고 중복 키 행은 건너뛰기
just mysqlsh-load target-host db-user 3306 4 target_db error false ./mapping.json skip false

# 중복 키 행을 소스 값으로 교체
just mysqlsh-load target-host db-user 3306 4 target_db error false ./mapping.json replace false

# 타깃 전체 비우고 적재: 마지막 인자 clear_target=true
just mysqlsh-load target-host db-user 3306 4 target_db ignore false ./mapping.json error false false true

# 전체 비우기 계획을 검사만 수행: dry_run=true, 데이터 변경 없음
just mysqlsh-load target-host db-user 3306 4 target_db ignore false ./mapping.json error true false true
```

매핑 모드에서는 `on_exist=error`와 `on_exist=ignore`를 모두 허용한다. 이 모드는 기존 테이블에
소스 DDL을 적용하지 않으므로 두 값 모두 덤프 DDL 처리에 사용하지 않는다. 행 중복은 `duplicates`로 결정한다.
예를 들어 `on_exist=ignore`, `force_drop=false`, `duplicates=replace`는 유효한 조합이다.
`on_exist=drop`과 `force_drop=true`는 매핑 모드에서 거부한다. `j`에서 이미 매핑 모드가
확정된 경우에는 실행 승인·히스토리 기록 전에 이 조합을 검사한다.

| duplicates | 동작 |
| --- | --- |
| `error` (기본) | 빈 타깃에 적재하고 행 수를 검증한다. 기존 데이터가 있으면 거부하되 `clear_target=true`이면 먼저 비우므로 허용한다. |
| `skip` | PK 또는 UNIQUE 키 충돌 시 기존 행 전체를 유지하고 소스 행을 건너뛴다. 신규 행은 추가한다. |
| `replace` | 중복 키 행만 삭제 후 삽입한다. 덤프에 없는 기존 행은 남는다. 테이블 전체 교체나 일부 컬럼만 갱신하는 upsert가 아니다. |

예를 들어 기존 타깃의 ID가 `1, 9`, 덤프의 ID가 `1, 2`라면 `replace` 결과는 `1, 2, 9`다.
`clear_target=true`로 전체 비우고 적재하면 `1, 2`만 남는다.

## 타깃 전체 비우기

`clear_target=false`가 기본값이다. `true`일 때는 모든 선택 테이블의 사전 검사를 끝낸 뒤
실제 타깃 테이블 목록과 되돌릴 수 없다는 안내를 표시한다. 최종 질문에 `y`를 입력한 후에만
각 타깃에 `TRUNCATE TABLE`을 실행하고 덤프 데이터를 적재한다. `--yes`는 이 최종 확인을 생략하지 않는다.

- 매핑 파일이 있으면 그 파일에 나열한 타깃만 비운다. 나머지 테이블은 건드리지 않는다.
- 매핑 파일 없이 일반 적재를 고르면 덤프 테이블을 같은 이름의 기존 타깃에 연결한다. 이름/컬럼이 다르면 매핑을 지정해야 하며 사전 검사 실패 시 비우지 않는다.
- 소스가 빈 테이블이면 기존 타깃도 빈 테이블로 끝난다. 완료된 데이터 덤프가 필요하며 DDL 전용 덤프는 거부한다.
- `dry_run=true`에서는 조회·계획 검사만 수행한다. 취소해도 타깃 데이터는 그대로 남는다.
- 타깃 테이블 정의·인덱스를 유지하고, 적재 후 행 수를 덤프와 비교한다.
- 다른 테이블이 외래 키로 참조하면 비우기 전에 거부한다. 자식 테이블도 함께 선택했더라도 외래 키 검사를 끄고 강제로 진행하지 않는다.

`TRUNCATE`에는 `DROP` 권한이 필요하고 `AUTO_INCREMENT`가 초기화되며 `ON DELETE` 트리거는
실행되지 않는다. [MySQL 공식 TRUNCATE 문서](https://dev.mysql.com/doc/refman/8.0/en/truncate-table.html).
**전체 비우기와 적재는 하나의 트랜잭션이 아니다.** 비우기는 롤백할 수 없으며 권한·네트워크·적재
오류가 나면 일부 테이블만 비워지거나 일부 데이터만 적재될 수 있다. 이 기능은 `on_exist=drop`으로
소스 DDL을 적용하는 기능과 별개이며, `force_drop`을 켜서 사용할 필요도 없다.

전체 비우기를 하지 않는 `skip`/`replace`에는 적재 컬럼으로 구성된 PK 또는 UNIQUE 키가 필요하다. NULL을 포함하는
UNIQUE 키는 반복 적재 시 같은 행을 식별하지 못할 수 있으므로 PK 사용을 권장한다.
`replace`는 제외하거나 매핑하지 않은 타깃 컬럼도 기본값으로 초기화하며, 삭제 트리거와
외래 키의 연쇄 삭제에도 영향을 줄 수 있다. 타깃에만 있는 값을 보존하려면 `skip`을 사용한다.

매핑 모드도 압축 청크와 병렬 적재를 사용하며 별도 스테이징 복사본은 만들지 않는다.
`error`는 검증을 위해 적재 후 `COUNT(*)`를 한 번 실행한다. `skip`은 경고 검증을 위해
트랜잭션이 작아질 수 있다. 대용량 데이터의 처리량은 별도로 측정하지 않았다.

모든 테이블의 컬럼 존재 여부, 생성 컬럼, 값/기본값이 필요한 필수 컬럼, 키, `local_infile` 설정을
첫 적재 전에 검사한다. 컬럼 순서는 덤프에서 읽고 BLOB/BIT 등의 디코딩과 UTC 시간대도 반영한다.
완료된 UTC 덤프의 `@.done.json`, `tableRows`, 청크 파일이 필요하다. 오래된 덤프에 `tableRows`가
없으면 현재 MySQL Shell로 다시 덤프한다. `dry_run`은 이 사전 검사까지 수행하며, 실제 값의
타입 변환·키 충돌·트리거 실행 결과까지 보장하지는 않는다.

MySQL은 `LOAD DATA LOCAL`의 데이터 오류를 경고로 처리할 수 있다. 매핑 적재는 콘솔 요약과
전용 임시 진단 로그를 검사하고, `skip`에서 허용한 중복 키 경고 이외의 적재 경고를 오류로 보고한다.
`skip`은 서버의 기존 경고 보관 한도를 읽어 트랜잭션 크기를 제한한다. 관리자 권한이 필요한
시스템 변수 변경은 하지 않는다. 매우 작은 보관 한도나 짧은 행 때문에 경고를 모두 수집하지
못한 경우에도 오류로 보고한다. 임시 로그는
실행 종료 시 지운다. 지원하지 않는 출력 형식이나 경고 수 불일치는 성공으로 처리하지 않는다.

적재는 청크별로 커밋하므로 **실패해도 이미 적재한 데이터는 남을 수 있다**. `loadDump`의
진행 파일을 사용하지 않으며 자동 이어받기도 없다. 재실행 전에 부분 적재 상태를 확인하고
`skip`/`replace`를 명시적으로 선택한다. 매핑·데이터·타깃이 달라지면 이전 실행의 결과를
그대로 이어받는다고 가정하지 않는다. 사전 검사와 행 수 검증 동안에는 타깃의 다른 쓰기를 중단한다.
타깃의 UNIQUE·외래 키 검사는 켠 상태로 적재한다. 외래 키 관계가 있으면 매핑 파일에 부모
테이블을 먼저 나열해야 하며, 같은 테이블 안의 부모·자식 행 순서가 필요한 경우에는 별도 적재 전략이 필요하다.

검증:

```bash
python3 -m unittest discover -s tests -v
ruff check lib/mysqlsh_load.py lib/mysqlsh_map.py tests
```

실제 DB 테스트는 별도의 폐기 가능한 로컬 MySQL에서만 실행한다. 설치되어 있는 Docker 이미지로
다음과 같이 띄울 수 있다. 이름이 같은 기존 컨테이너가 있으면 다른 이름을 사용한다.

```bash
docker run --pull=never --rm -d --name mysqlsh-mapping-test \
  -p 127.0.0.1::3306 -e MYSQL_ALLOW_EMPTY_PASSWORD=yes mysql:8.0 --local-infile=ON --skip-log-bin
docker port mysqlsh-mapping-test 3306
# mysqladmin ping이 성공한 후 출력된 포트를 지정
MYSQLSH_TEST_PORT=출력된포트 python3 -m unittest discover -s tests -v
docker stop mysqlsh-mapping-test
```

공식 참고: [덤프와 importTable 조합](https://dev.mysql.com/doc/mysql-shell/26.7/en/mysql-shell-utilities-load-dump.html),
[컬럼 매핑 및 중복 키 처리](https://dev.mysql.com/doc/mysql-shell/26.10/en/mysql-shell-utilities-parallel-table.html).
