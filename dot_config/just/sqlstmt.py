#!/usr/bin/env python3
"""SQL 파일을 문장으로 잘라 고른 UPDATE · DELETE · INSERT 를 연결 하나 · 트랜잭션 하나로 돌린다.
~/.config/justfile/purge.just의 purge 레시피가 실행기 형식이 아닌 파일에 쓴다.

  sqlstmt.py scan DIR                  파일별 "상대경로 \t 형식 \t 쓰기 문장 수"
  sqlstmt.py list FILE                 "번호 \t 종류 \t 대상 표 \t 줄 \t 요약"
  sqlstmt.py run --expect prod|test|reader --host H --port P --user U --mode dry|execute --ids 1,3|all FILE
    비밀번호는 MYSQL_PWD 환경변수. SET 문은 고르지 않아도 파일 순서대로 함께 돈다 (@변수).
    dry     : SET · 고른 SELECT 실행, 고른 쓰기 문장은 같은 조건의 SELECT COUNT(*) 로 맞는 행만 센다 (reader 에서도 된다)
    --batch N : UPDATE · DELETE 를 PK 범위로 N행씩 나눠 배치마다 커밋 (5만 행 제한 없음, 끝에 되돌릴 수 없다)
                JOIN · USING · 다중 표 · 서브쿼리 · 복합 PK 도 된다 (JOIN 은 첫 표 / 대상 표의 PK 로 자른다). PK 없는 한 표 DELETE 는 LIMIT 반복.
                NOW() · CURDATE() 는 시작 때 서버 시각으로 고정한다. 락 대기 · 데드락은 같은 배치를 다시 시도한다.
    --sleep S : 배치 사이 쉬는 초 (락 경합 줄이기) · --lock-wait N : 락 기다리는 초 (기본 10 — 줄이면 앱에 먼저 양보한다)
    execute : 행 수를 먼저 센다(5만 넘거나 60초 넘으면 거부) → START TRANSACTION → 문장마다 ROW_COUNT → COMMIT/ROLLBACK 을 사람이 고른다
              오류가 나면 mysql 이 끊기며 트랜잭션은 자동 롤백된다
"""
import argparse, os, re, subprocess, sys, time

WRITE = ('UPDATE', 'DELETE', 'INSERT', 'REPLACE')
BIG_ROWS = 50000          # 조건에 맞는 행이 이보다 크면 문장 모드로 돌리지 않는다 (끊어 지우는 실행기 형식을 쓸 것)
EXECUTOR_MARK = '[0] 척추'


def split(sql):
    """주석 · 따옴표 밖의 ; 로 자른다. (시작 줄, 원문) 목록."""
    out, buf, i, n, line, start = [], [], 0, len(sql), 1, None
    st = None  # None | "'" | '"' | '`' | '--' | '/*'
    while i < n:
        c = sql[i]; nx = sql[i + 1] if i + 1 < n else ''
        if start is None and not c.isspace() and st is None and not (c == '-' and nx == '-') and c != '#' and not (c == '/' and nx == '*'):
            start = line
        if st is None:
            if c in "'\"`": st = c
            elif c == '-' and nx == '-' and (i + 2 >= n or sql[i + 2] in ' \t\r\n'): st = '--'
            elif c == '#': st = '--'
            elif c == '/' and nx == '*': st = '/*'; buf.append(c); i += 1; c = nx
            elif c == ';':
                txt = ''.join(buf).strip()
                if strip_comments(txt): out.append((start or line, txt))
                buf, start = [], None; i += 1; continue
        elif st == '--':
            if c == '\n': st = None
        elif st == '/*':
            if c == '*' and nx == '/': st = None; buf.append(c); i += 1; c = nx
        else:
            if c == '\\' and st != '`': buf.append(c); i += 1; c = nx
            elif c == st: st = None
        if c == '\n': line += 1
        buf.append(c); i += 1
    txt = ''.join(buf).strip()
    if strip_comments(txt): out.append((start or line, txt))
    return out


def strip_comments(s):
    s = re.sub(r'/\*.*?\*/', ' ', s, flags=re.S)
    s = re.sub(r'(?m)(^|\s)(--\s|#).*$', ' ', s)
    return re.sub(r'\s+', ' ', s).strip()


def classify(txt):
    s = strip_comments(txt); w = s.split(' ', 1)[0].upper() if s else ''
    kind = {'SET': 'SET', 'SELECT': 'SELECT', 'WITH': 'SELECT', 'START': 'TXN', 'BEGIN': 'TXN', 'COMMIT': 'TXN', 'ROLLBACK': 'TXN',
            'DELIMITER': 'DELIM'}.get(w, w if w in WRITE else 'OTHER')
    tbl = ''
    m = (re.match(r'(?i)UPDATE\s+(?:LOW_PRIORITY\s+|IGNORE\s+)*([`\w.]+)', s) if kind == 'UPDATE' else
         re.match(r'(?i)DELETE\s+(?:\w+\s+)?FROM\s+([`\w.]+)', s) if kind == 'DELETE' else
         re.match(r'(?i)(?:INSERT|REPLACE)\s+(?:IGNORE\s+)?INTO\s+([`\w.]+)', s) if kind in ('INSERT', 'REPLACE') else None)
    if m: tbl = m.group(1).replace('`', '')
    if kind == 'TXN' and re.match(r'(?i)BEGIN\s+\S', s) and not re.fullmatch(r'(?i)BEGIN\s+WORK', s): kind = 'DELIM'   # BEGIN … 블록 = 루틴 본문
    if re.match(r'(?i)CREATE\s+(DEFINER\s*=\s*\S+\s+)?(PROCEDURE|FUNCTION|TRIGGER|EVENT)\b', s): kind = 'DELIM'   # 본문을 ; 로 자르면 안 된다
    nowhere = kind in ('UPDATE', 'DELETE') and not re.search(r'(?i)\bWHERE\b', s)
    return kind, tbl, nowhere, s


def top(flat, kw, start=0):
    """괄호 · 따옴표 밖에서 단어 kw 가 처음 나오는 위치 (없으면 -1)"""
    d, q, i, n, k = 0, None, start, len(flat), len(kw)
    while i < n:
        c = flat[i]
        if q:
            if c == '\\' and q != '`': i += 2; continue
            if c == q: q = None
        elif c in "'\"`": q = c
        elif c == '(': d += 1
        elif c == ')': d -= 1
        elif d == 0 and flat[i:i + k].upper() == kw and (i == 0 or not (flat[i - 1].isalnum() or flat[i - 1] == '_')) \
                and (i + k >= n or not (flat[i + k].isalnum() or flat[i + k] == '_')):
            return i
        i += 1
    return -1


def to_count(s):
    """쓰기 문장 → 같은 조건의 SELECT COUNT(*) (조건에 맞는 행 수). 못 바꾸면 None"""
    f = s['flat']
    def cut(w):   # WHERE 절에서 ORDER BY · LIMIT 을 뗀다
        for kw in ('ORDER BY', 'LIMIT'):
            j = top(w, kw)
            if j > 0: w = w[:j]
        return w
    if s['kind'] == 'UPDATE':
        a = re.match(r'(?i)UPDATE\s+(?:LOW_PRIORITY\s+|IGNORE\s+)*', f).end(); b = top(f, 'SET', a); w = top(f, 'WHERE', b)
        if b < 0 or w < 0: return None
        return f'SELECT COUNT(*) FROM {f[a:b]} {cut(f[w:])}'
    if s['kind'] == 'DELETE':
        a = top(f, 'FROM'); w = top(f, 'WHERE', a)
        if a < 0 or w < 0: return None
        u = top(f, 'USING', a)
        return f'SELECT COUNT(*) FROM {f[u + 5:w] if u >= 0 else f[a + 4:w]} {cut(f[w:])}'
    if s['kind'] in ('INSERT', 'REPLACE'):
        j = top(f, 'SELECT')
        if j <= 0: return None
        k = top(f, 'FROM', j)
        # 값 목록을 1 로 바꿔 센다 — 감싸기만 하면 NULL · 같은 값이 여러 개일 때 열 이름이 겹쳐 거부된다 (DISTINCT · GROUP BY 는 행 수가 달라지므로 감싼다)
        if k > 0 and not re.match(r'(?i)SELECT\s+DISTINCT\b', f[j:]) and top(f, 'GROUP BY', k) < 0:
            return f'SELECT COUNT(*) FROM (SELECT 1 {f[k:]}) _t'
        return f'SELECT COUNT(*) FROM ({f[j:]}) _t'
    return None


JOIN_MODS = r'(?:INNER|CROSS|LEFT|RIGHT|OUTER|NATURAL)'


def split_refs(refs):
    """FROM 절의 표 참조를 최상위 JOIN · 쉼표에서 자른다 (괄호 · 따옴표 안은 건드리지 않는다)"""
    out, d, q, i, st, n = [], 0, None, 0, 0, len(refs)
    while i < n:
        c = refs[i]
        if q:
            if c == '\\' and q != '`': i += 2; continue
            if c == q: q = None
        elif c in "'\"`": q = c
        elif c == '(': d += 1
        elif c == ')': d -= 1
        elif d == 0 and c == ',': out.append(refs[st:i]); st = i + 1
        elif d == 0 and (i == 0 or not (refs[i - 1].isalnum() or refs[i - 1] == '_')):
            m = re.match(r'(?i)(?:STRAIGHT_)?JOIN\b', refs[i:])
            if m: out.append(refs[st:i]); i += m.end(); st = i; continue
        i += 1
    out.append(refs[st:])
    return out


def base_refs(refs):
    """표 참조 → [(부르는 이름, 스키마, 표, 별칭 여부)]. 파생 표 · 해석 못 하는 조각은 건너뛴다"""
    res = []
    for it in split_refs(refs):
        it = re.sub(r'(?i)\s*\b' + JOIN_MODS + r'(?:\s+' + JOIN_MODS + r')*\s*$', '', it.strip())   # JOIN 앞의 LEFT · INNER … 는 앞 조각 끝에 붙는다
        for kw in ('ON', 'USING'):
            j = top(it, kw)
            if j > 0: it = it[:j]
        m = re.fullmatch(r'(?i)(?:`?(\w+)`?\.)?`?(\w+)`?(?:\s+(?:AS\s+)?`?(\w+)`?)?\s*', it.strip())
        if m: res.append((m.group(3) or m.group(2), m.group(1), m.group(2), bool(m.group(3))))
    return res


def single_ref(s):
    """쪼갤 수 있는 UPDATE · DELETE → dict, 아니면 {'err': 이유}.
    prefix : WHERE 앞까지 · refs : 표 참조(경계 SELECT 의 FROM) · ref : PK 앞에 붙일 이름 · schema · table : PK 를 읽을 표
    cond : WHERE 조건 · multi : 한 표 DELETE 문법이 아님 (LIMIT 반복 불가). JOIN 이면 대상 표(여럿이면 첫 번째, UPDATE 는 첫 표)의 PK 로 자른다"""
    f = s['flat']
    if s['kind'] == 'UPDATE':
        a = re.match(r'(?i)UPDATE\s+(?:LOW_PRIORITY\s+|IGNORE\s+)*', f).end(); b = top(f, 'SET', a)
        if b < 0: return dict(err='SET 이 없다')
        w = top(f, 'WHERE', b)
        if w < 0: return dict(err='WHERE 가 없다')
        refs, targets = f[a:b].strip(), None
    elif s['kind'] == 'DELETE':
        a = re.match(r'(?i)DELETE\s+(?:(?:LOW_PRIORITY|QUICK|IGNORE)\s+)*', f).end()
        kf, ku = top(f, 'FROM', a), top(f, 'USING', a)
        if kf < 0: return dict(err='FROM 이 없다')
        w = top(f, 'WHERE', kf)
        if w < 0: return dict(err='WHERE 가 없다')
        if kf == a and ku < 0: refs, targets = f[kf + 4:w].strip(), None                                # DELETE FROM t WHERE …
        elif kf == a: targets, refs = [x.strip() for x in f[kf + 4:ku].split(',')], f[ku + 5:w].strip()   # DELETE FROM a, b USING refs WHERE …
        else: targets, refs = [x.strip() for x in f[a:kf].split(',')], f[kf + 4:w].strip()               # DELETE a, b FROM refs WHERE …
    else:
        return dict(err='UPDATE · DELETE 만 쪼갠다')
    cond = f[w + 5:].strip()
    for kw in ('ORDER BY', 'LIMIT'):
        if top(cond, kw) >= 0: return dict(err=f'{kw} 가 있다 — 쪼개면 의미가 달라진다. 쪼갤 문장에서는 빼고, 한 번에 지울 양이면 배치 없이 돌린다')
    items = base_refs(refs)
    want = (targets[0] if targets else (items[0][0] if items else '')).replace('`', '')
    hit = next((x for x in items if x[0].lower() == want.lower() or (x[1] and f'{x[1]}.{x[2]}'.lower() == want.lower())), None)
    if not hit: return dict(err=f'대상 표를 찾지 못했다 ({want or "?"}) — FROM 의 스키마.표 [별칭] 으로 적을 것 (파생 표는 안 된다)')
    name, sch, tb, aliased = hit
    if not sch: return dict(err=f'스키마.표 로 적을 것 ({tb})')
    if targets and len(targets) > 1:
        return dict(err='여러 표를 한 번에 지우는 DELETE 는 쪼개지 않는다 — 첫 조각이 한 표의 행을 지우면 뒤 조각의 조인 상대가 사라진다. 표마다 따로 돌릴 것')
    multi = targets is not None or len(split_refs(refs)) > 1 or '(' in refs
    if s['kind'] == 'UPDATE' and multi:   # SET 이 첫 표 밖을 건드리면 조각마다 되풀이돼 한 번에 돌린 것과 달라진다
        for x in split_refs(f[b + 3:w]):
            owner = x.split('=', 1)[0].strip().replace('`', '').rsplit('.', 1)
            if len(owner) < 2 or owner[0].lower() not in (name.lower(), f'{sch}.{tb}'.lower()):
                return dict(err=f'JOIN UPDATE 의 SET 은 첫 표({name})의 열만, 표 이름을 붙여 적을 것 ({x.strip()[:40]})')
    return dict(prefix=f[:w].rstrip(), refs=refs, ref=f'`{name}`' if aliased or targets else f'`{sch}`.`{tb}`', schema=sch, table=tb, cond=cond, multi=multi)


_TIME_FN = [(re.compile(r'(?i)\b(?:NOW|SYSDATE)\s*\(\s*\d*\s*\)|\b(?:CURRENT_TIMESTAMP|LOCALTIMESTAMP)\b(?:\s*\(\s*\d*\s*\))?'), "CAST('{now}' AS DATETIME)"),
            (re.compile(r'(?i)\bCURDATE\s*\(\s*\)|\bCURRENT_DATE\b(?:\s*\(\s*\))?'), "CAST('{today}' AS DATE)")]


def freeze(sql, now, today):
    """따옴표 밖의 NOW() · CURDATE() · CURRENT_DATE · CURRENT_TIMESTAMP 를 시작 시각 값으로 바꾼다 — 배치가 길어도 기준이 움직이지 않게"""
    segs, q, i, st = [], None, 0, 0
    while i < len(sql):
        c = sql[i]
        if q:
            if c == '\\' and q != '`': i += 2; continue
            if c == q: segs.append((True, sql[st:i + 1])); st = i + 1; q = None
        elif c in "'\"`":
            segs.append((False, sql[st:i])); st = i; q = c
        i += 1
    segs.append((q is not None, sql[st:]))
    out = []
    for quoted, t in segs:
        if not quoted:
            for rx, rep in _TIME_FN: t = rx.sub(rep.format(now=now, today=today), t)
        out.append(t)
    return ''.join(out)


def stmts(path):
    sql = open(path, encoding='utf-8', errors='replace').read()
    res = []
    for k, (ln, txt) in enumerate(split(sql), 1):
        kind, tbl, nowhere, s = classify(txt)
        res.append(dict(no=k, line=ln, kind=kind, table=tbl, nowhere=nowhere, flat=s, text=txt))
    return res, EXECUTOR_MARK in sql


def is_rowcount(s):   # 파일의 SELECT ROW_COUNT() — 문장마다 직접 세므로 건너뛴다
    return re.fullmatch(r'(?i)SELECT ROW_COUNT\(\)', s['flat']) is not None


class Conn:
    def __init__(self, host, port, user):
        self.host, self.port, self.user = host, port, user
        self.k = 0; self.init = getattr(self, 'init', [])
        self.p = subprocess.Popen(['mysql', '-h', host, '-P', str(port), '-u', user, '--connect-timeout=10', '-n', '-B'],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)

    def q(self, sql, rowcount=False):
        """문장 하나를 보내고 결과 줄을 돌려준다. 오류면 (None, 오류 줄).
        rowcount : 문장 바로 뒤에 ROW_COUNT() 를 묻는다 (표지 SELECT 보다 먼저 — 뒤에 물으면 -1)"""
        self.k += 1; mark = f'__END_{self.k}__'
        rc = 'SELECT ROW_COUNT() AS __rc__;\n' if rowcount else ''
        try:
            self.p.stdin.write(sql.rstrip().rstrip(';') + ';\n' + rc + f"SELECT '{mark}' AS {mark};\n"); self.p.stdin.flush()
        except BrokenPipeError:
            return None, ['(연결이 이미 닫혔다)']
        out = []
        for line in self.p.stdout:
            line = line.rstrip('\n')
            if line == mark:
                self.p.stdout.readline()   # 값 줄
                return out, None
            out.append(line)
        return None, out or ['(연결이 닫혔다)']

    def sess(self, sql):
        """세션 설정 문장 — 연결을 다시 열어도 되풀이한다"""
        self.init.append(sql); return self.q(sql)

    def reopen(self):
        """mysql 클라이언트는 오류가 나면 끝나므로 다시 열고 세션 설정을 되풀이한다"""
        try: self.p.kill()
        except Exception: pass
        self.__init__(self.host, self.port, self.user)
        for x in self.init: self.q(x)

    def close(self):
        try: self.p.stdin.close()
        except Exception: pass
        self.p.wait(timeout=30)


class Tee:
    """화면과 기록 파일에 함께 쓴다 (--log)"""
    def __init__(self, stream, path): self.s = stream; self.f = open(path, 'a', encoding='utf-8')
    def write(self, x): self.s.write(x); self.f.write(x); return len(x)
    def flush(self): self.s.flush(); self.f.flush()
    def __getattr__(self, k): return getattr(self.s, k)


def tty_input(prompt):   # 읽기 · 쓰기를 따로 연다 ('r+' 는 /dev/tty 에서 seek 오류)
    with open('/dev/tty', 'w') as w, open('/dev/tty') as r:
        w.write(prompt); w.flush()
        ans = r.readline().strip()
    if isinstance(sys.stdout, Tee): sys.stdout.f.write(f'{prompt.strip()} {ans}\n'); sys.stdout.f.flush()   # 답도 기록
    return ans


def run(a):
    allst, _ = stmts(a.file)
    ids = None if a.ids == 'all' else {int(x) for x in a.ids.split(',') if x}
    chosen = [s for s in allst if s['kind'] in WRITE + ('SELECT',) and not is_rowcount(s) and (ids is None or s['no'] in ids)]
    for s in chosen:
        if s['nowhere']: sys.exit(f"✗ {s['no']}번 (줄 {s['line']}) WHERE 없는 {s['kind']} — 돌리지 않는다")
    bad = [s for s in allst if s['kind'] in ('DELIM',)]
    if bad: sys.exit('✗ DELIMITER 가 있는 파일(프로시저 정의 등)은 문장 모드로 돌리지 않는다')
    if not any(s['kind'] in WRITE for s in chosen) and a.mode == 'execute': sys.exit('✗ 고른 쓰기 문장이 없다')
    batch = int(a.batch or 0)
    if batch:
        for s in chosen:
            if s['kind'] in WRITE and single_ref(s).get('err'):
                sys.exit(f"✗ [{s['no']}] 배치로 나눌 수 없는 꼴 — {single_ref(s)['err']}")
    plan = [s for s in allst if s['kind'] == 'SET' or s in chosen]          # 파일 순서 · SET 은 늘 포함

    c = Conn(a.host, a.port, a.user)
    out, err = c.q('SELECT @@aurora_server_id, @@innodb_read_only')
    if err: sys.exit('✗ 접속 실패\n' + '\n'.join(err))
    sid, ro = out[-1].split('\t')
    print(f'접속 : {sid}  read_only={ro}')
    if a.expect == 'prod' and not (sid.startswith('webfulfillment-mdb-prod-04') and ro == '0'): sys.exit('✗ PROD writer 가 아니다 — 멈춤')
    if a.expect == 'reader' and ro != '1': sys.exit('✗ reader 가 아니다 — 멈춤')
    if a.expect == 'test' and sid.startswith('webfulfillment-mdb-prod'): sys.exit('✗ TEST 로 골랐는데 PROD 서버다 — 멈춤')   # TEST 이름에도 prod 가 들어 있어 SID 로 본다
    if a.mode == 'execute' and ro != '0': sys.exit('✗ 읽기 전용 인스턴스에서는 execute 를 하지 않는다')
    c.sess(f'SET SESSION innodb_lock_wait_timeout = {a.lock_wait}')
    c.sess(f"SET SESSION max_execution_time = {600000 if batch else 60000}")   # SELECT(행 수 세기 · 경계 찾기)만 제한 — 배치는 10분
    if batch:   # 배치가 길어도 기준이 움직이지 않게 시작 시각으로 고정 (실행기가 NOW() 를 고정하는 것과 같다)
        out, err = c.q('SELECT CAST(NOW() AS CHAR), CAST(CURDATE() AS CHAR)')
        if err: sys.exit('✗ 서버 시각을 읽지 못했다\n' + '\n'.join(err))
        now, today = out[-1].split('\t')
        for s in plan:
            if s['kind'] in WRITE: s['flat'] = freeze(s['flat'], now, today)
        print(f'기준 시각 고정 : NOW() → {now} · CURDATE() → {today} (서버)')

    def show(tag, s, lines):
        print(f"\n[{s['no']}] 줄 {s['line']} {tag} {s['table']}  {s['flat'][:110]}")
        for l in lines: print('    ' + l)

    # 1) 검사 — SET 실행 · 쓰기 문장 EXPLAIN (예상 행)
    big = []
    for s in plan:
        if s['kind'] == 'SET':
            _, err = c.sess(s['text'])
            if err: show('SET ✗', s, err); sys.exit(1)
        elif s['kind'] in WRITE:
            cq = to_count(s)
            if cq is None:
                if a.mode == 'execute': show('✗', s, ['조건에 맞는 행 수를 셀 수 없는 꼴 — 문장 모드로 돌리지 않는다']); sys.exit(1)
                show('셈 생략', s, ['(INSERT … VALUES 등)']); continue
            out, err = c.q(cq)
            if err:
                show('셈 ✗', s, err + ['(60초 넘으면 큰 문장으로 본다)']); sys.exit(1)
            est = int(out[-1]) if out and out[-1].isdigit() else 0
            s['total'] = est
            if est > BIG_ROWS and not batch: big.append((s, est))
            if batch:
                r = s['r'] = single_ref(s)
                pk, err = c.q(f"SELECT S.COLUMN_NAME, C.DATA_TYPE FROM information_schema.STATISTICS S JOIN information_schema.COLUMNS C USING (TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME) WHERE S.TABLE_SCHEMA = '{r['schema']}' AND S.TABLE_NAME = '{r['table']}' AND S.INDEX_NAME = 'PRIMARY' ORDER BY S.SEQ_IN_INDEX")
                if err: show('PK 읽기 ✗', s, err); sys.exit(1)
                s['cols'] = [tuple(l.split('\t')) for l in pk[1:]]      # 첫 줄은 열 이름
                if not s['cols'] and (r['multi'] or s['kind'] != 'DELETE'):
                    show('✗', s, [f"{r['schema']}.{r['table']} 에 PK 가 없다 — PK 없는 표는 한 표짜리 DELETE 만 LIMIT 반복으로 쪼갠다"]); sys.exit(1)
                how = f"PK {', '.join(x for x, _ in s['cols'])}" if s['cols'] else 'PK 없음 → LIMIT 반복'
                show(f'조건에 맞는 행 {est:,} → 배치 {batch:,} × 약 {max(1, -(-est // batch))}번 ({how})', s, [])
                if a.mode == 'dry': preview(c, s, batch)
            else:
                show(f'조건에 맞는 행 {est:,}', s, [])
        elif s['kind'] == 'SELECT' and a.mode == 'dry':
            out, err = c.q(s['text']); show('SELECT', s, out if not err else ['✗'] + err)
            if err: sys.exit(1)
    if big:
        for s, est in big: print(f"✗ [{s['no']}] {s['table']} 예상 {est:,}행 — {BIG_ROWS:,}행 넘는 쓰기는 문장 모드로 돌리지 않는다 (끊어 지우는 실행기 형식을 쓸 것)")
        sys.exit(1)
    if a.mode == 'dry':
        c.q('ROLLBACK'); c.close(); print('\n✓ dry 끝 — 바꾼 것 없음'); return

    if batch:
        run_batched(c, plan, batch, show, a.sleep); c.close(); return

    # 2) 실행 — 한 트랜잭션
    c.q('START TRANSACTION')
    total = []
    for s in plan:
        out, err = c.q(s['text'], rowcount=s['kind'] in WRITE)
        if err: show(f"{s['kind']} ✗", s, err + ['→ 연결이 끊기며 트랜잭션은 롤백된다']); sys.exit(1)
        if s['kind'] in WRITE:
            n = out[-1] if out and out[-2:-1] == ['__rc__'] else '?'
            total.append((s, n)); show(f'→ {n}행', s, [])
        elif s['kind'] == 'SELECT':
            show('SELECT', s, out)
    print('\n── 바뀐 행 (아직 커밋 안 함) ──')
    for s, n in total: print(f"  [{s['no']}] {s['kind']:<7} {s['table']:<45} {n}행")
    ans = tty_input("\nCOMMIT 하려면 'COMMIT' 입력 (그 밖은 ROLLBACK) : ")
    _, err = c.q('COMMIT' if ans == 'COMMIT' else 'ROLLBACK')
    c.close()
    if err: sys.exit('✗ 마무리 실패\n' + '\n'.join(err))
    print('✓ COMMIT 했다' if ans == 'COMMIT' else '↩ ROLLBACK 했다 — 바뀐 것 없음')


def fmt_s(s):
    s = int(s)
    return f'{s // 3600}시간 {s % 3600 // 60}분' if s >= 3600 else f'{s // 60}분' if s >= 60 else f'{s}초'


INTS = ('tinyint', 'smallint', 'mediumint', 'int', 'bigint')
BINS = ('binary', 'varbinary', 'tinyblob', 'blob', 'mediumblob', 'longblob')


def key_expr(ref, col, typ):
    """PK 값을 그대로 SQL 에 붙일 수 있는 글자로 읽는 식 (정수 · 이진 · 그 밖은 QUOTE)"""
    x = f'{ref}.`{col}`'
    if typ in INTS: return f'CAST({x} AS CHAR)'
    if typ in BINS: return f"CONCAT('UNHEX(''', HEX({x}), ''')')"
    return f'QUOTE({x})'


def after(ref, cols, vals, op):
    names = ', '.join(f'{ref}.`{c}`' for c, _ in cols)
    return f'{names} {op} {vals[0]}' if len(cols) == 1 else f'({names}) {op} ({", ".join(vals)})'


def batch_sqls(r, cols, last, batch):
    """(경계 SELECT, hi → 배치 문장). last : 앞 배치의 마지막 PK 값 목록 · None 이면 처음부터. PK 없으면 (None, LIMIT 문장)"""
    if not cols:
        stmt = f"{r['prefix']} WHERE ({r['cond']}) LIMIT {batch}"
        return None, lambda hi: stmt
    ref = r['ref']
    lower = f' AND {after(ref, cols, last, ">")}' if last else ''
    bsql = (f"SELECT {', '.join(key_expr(ref, c, t) for c, t in cols)} FROM {r['refs']} WHERE ({r['cond']}){lower} "
            f"ORDER BY {', '.join(f'{ref}.`{c}`' for c, _ in cols)} LIMIT 1 OFFSET {batch - 1}")
    return bsql, lambda hi: f"{r['prefix']} WHERE ({r['cond']}){lower}" + (f" AND {after(ref, cols, hi, '<=')}" if hi else '')


def read_key(out, cols):
    """경계 SELECT 결과 → PK 값 목록 (없으면 None = 마지막 배치)"""
    if not out or len(out) < 2: return None
    v = out[-1].split('\t')
    if len(v) != len(cols): sys.exit(f'✗ 경계 값이 {len(cols)}열이 아니다: {out[-1][:80]}')
    return v


def preview(c, s, batch):
    """dry : 첫 배치로 실제 나갈 문장과 실행 계획 (전체 읽기가 되는지 — 락을 많이 잡는지 — 미리 본다)"""
    r, cols = s['r'], s['cols']
    bsql, mk = batch_sqls(r, cols, None, batch)
    hi = None
    if bsql:
        out, err = c.q(bsql)
        if err: print('    ✗ 첫 경계를 찾지 못했다\n    ' + '\n    '.join(err)); return
        hi = read_key(out, cols)
    stmt = mk(hi)
    print(f"    첫 배치 : {stmt}")
    for tag, q in (('경계', bsql), ('배치', stmt)):
        if not q: continue
        out, err = c.q('EXPLAIN ' + q)
        if err and re.search(r'ERROR 1836', '\n'.join(err)):   # read-only 서버(reader)는 EXPLAIN DELETE · UPDATE 를 거부한다 → 같은 조건의 SELECT 로 대신 본다
            c.reopen()   # 오류가 나면 mysql 클라이언트가 끝난다
            out, err = c.q(f"EXPLAIN SELECT 1 FROM {r['refs']}" + q[len(r['prefix']):]); tag += '(SELECT 로 대신)'
        if err or not out: print(f"    {tag} 계획 : (읽지 못했다) {(err or [''])[0][:90]}"); continue
        head = out[0].split('\t')
        for l in out[1:]:
            d = dict(zip(head, l.split('\t')))
            warn = '  ⚠ 전체 읽기 — 락을 많이 잡는다' if d.get('type') == 'ALL' else ''
            print(f"    {tag} 계획 : {d.get('table')} type={d.get('type')} key={d.get('key')} rows={d.get('rows')} {d.get('Extra', '')}{warn}")


def exec_retry(c, sql, tries=6):
    """배치 한 개 실행. 락 대기(1205) · 데드락(1213) 은 그 문장이 롤백됐으니 같은 배치를 다시 시도한다"""
    for k in range(tries):
        out, err = c.q(sql, rowcount=True)
        if not err: return out, None
        if k < tries - 1 and re.search(r'ERROR (1205|1213)\b', '\n'.join(err)):
            wait = min(2 ** k, 30)
            print(f'     ⏳ 락 대기 · 데드락 — {wait}초 뒤 같은 배치를 다시 ({k + 1}/{tries - 1})', flush=True)
            time.sleep(wait); c.reopen(); continue
        return None, err


def run_batched(c, plan, batch, show, sleep=0.0):
    """PK 범위로 나눠 배치마다 커밋 (autocommit). 다음 경계를 먼저 찾고 '> 이전 경계 AND <= 다음 경계' 를 붙여 실행한다.
    PK 가 없으면 한 표짜리 DELETE 를 LIMIT 으로 반복한다"""
    c.sess('SET SESSION autocommit = 1')
    for s in plan:
        if s['kind'] == 'SET':
            _, err = c.sess(s['text'])
            if err: show('SET ✗', s, err); sys.exit(1)
            continue
        if s['kind'] == 'SELECT':
            out, err = c.q(s['text']); show('SELECT', s, out if not err else ['✗'] + err); continue
        r, cols = s['r'], s['cols']
        if r['multi']:   # 다중 표 DELETE 는 기본 DB 가 있어야 돈다 (없으면 1046) — 대상 표의 스키마로 맞춘다
            _, err = c.sess(f"USE `{r['schema']}`")
            if err: show('USE ✗', s, err); sys.exit(1)
        last, cum, no, t0, total = None, 0, 0, time.time(), s.get('total') or 0
        print(f"\n[{s['no']}] 줄 {s['line']} {s['kind']} {s['table']} — 배치 {batch:,}행씩, 배치마다 커밋 (전체 {total:,}행)"
              + (f" · 배치 사이 {sleep}초" if sleep else ''))
        while True:
            bsql, mk = batch_sqls(r, cols, last, batch)
            hi = None
            if bsql:
                out, err = c.q(bsql)
                if err: show('경계 찾기 ✗', s, err); sys.exit(1)
                hi = read_key(out, cols)
            out, err = exec_retry(c, mk(hi))
            if err: show(f"{s['kind']} ✗", s, err + [f'→ 이 배치만 취소 — 앞의 {no}배치 {cum:,}행은 이미 커밋됐다']); sys.exit(1)
            n = int(out[-1]) if out and out[-2:-1] == ['__rc__'] and out[-1].lstrip('-').isdigit() else 0
            cum += max(n, 0); no += 1; el = time.time() - t0
            msg = f'     [배치 {no}] {n:,}행 · 누적 {cum:,}'
            if total: msg += f' / {total:,} ({min(cum / total, 1) * 100:.1f}%)'
            msg += f' · 경과 {fmt_s(el)}'
            if total and 0 < cum < total: msg += f' · 남은 시간 약 {fmt_s(el * (total - cum) / cum)}'
            print(msg, flush=True)
            if (cols and hi is None) or (not cols and n < batch): break
            last = hi
            if sleep: time.sleep(sleep)
        print(f"     ✓ 끝 — {no}배치 {cum:,}행 (배치마다 커밋)")
    print('\n✓ 배치 실행 끝 — 바뀐 것은 배치마다 이미 커밋됐다')


def main():
    ap = argparse.ArgumentParser(); sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('scan'); p.add_argument('dir')
    p = sub.add_parser('list'); p.add_argument('file')
    p = sub.add_parser('run'); p.add_argument('file')
    for k in ('--expect', '--host', '--port', '--user', '--mode', '--ids'): p.add_argument(k, required=True)
    p.add_argument('--batch', default='0')   # 0 = 한 트랜잭션
    p.add_argument('--sleep', type=float, default=0.0)   # 배치 사이 쉬는 초
    p.add_argument('--lock-wait', type=int, default=10)  # 락을 기다리는 초 (줄이면 앱에 먼저 양보한다)
    p.add_argument('--log', default='')      # 기록 파일 (화면과 함께)
    a = ap.parse_args()
    if getattr(a, 'log', ''):
        sys.stdout = Tee(sys.stdout, a.log); sys.stderr = Tee(sys.stderr, a.log)
    if a.cmd == 'scan':
        # operations 아래 .sql 전부 (숨김 · .git · node_modules 만 뺀다) — 최근에 고친 것부터
        rows = []
        for root, dirs, files in os.walk(a.dir):
            dirs[:] = [d for d in dirs if not d.startswith('.') and d != 'node_modules']
            for f in files:
                if not f.endswith('.sql'): continue
                path = os.path.join(root, f)
                try: st, exe = stmts(path)
                except Exception: continue
                nw = sum(s['kind'] in WRITE for s in st)
                ddl = any(s['kind'] == 'OTHER' and re.match(r'(?i)(ALTER|CREATE|DROP|TRUNCATE|RENAME)\b', s['flat']) for s in st)
                kind = ('실행기' if exe else '루틴' if any(s['kind'] == 'DELIM' for s in st) else '문장' if nw
                        else 'DDL' if ddl else '읽기')   # DDL 은 문장 모드가 돌리지 않는다 — 표시만
                mo = re.search(r'\.v(\d+)\.sql$', f)                      # 옛 판 — 숨기지 않고 표시만 (2026-10-19 batch2.v1 로 돌린 일)
                if mo: kind = f"⚠옛 판 {kind} → 새 판 {f[:mo.start()]}.sql"
                rows.append((os.path.getmtime(path), os.path.relpath(path, a.dir), kind, nw))
        import time
        for mt, rel, kind, nw in sorted(rows, reverse=True):
            print(f"{rel}\t{kind}\t{nw}\t{time.strftime('%m-%d %H:%M', time.localtime(mt))}")
    elif a.cmd == 'list':
        st, _ = stmts(a.file)
        for s in st:
            if s['kind'] in ('TXN',) or is_rowcount(s): continue
            flag = ' ✗WHERE없음' if s['nowhere'] else ''
            print(f"{s['no']}\t{s['kind']}\t{s['table']}\t{s['line']}\t{s['flat'][:150]}{flag}")
    else:
        run(a)


if __name__ == '__main__':
    main()
