#!/usr/bin/env python3
"""purge-spine.sh 진행률 — 실행기가 쓰는 로그(spine-*-<pid>.log)를 옆에서 따라 읽고 배치 줄마다 진행률을 덧붙인다.
실행기 출력은 건드리지 않는다 (파이프로 가로채지 않으므로 이 프로그램이 죽어도 실행기는 영향 없음).

  progress.py --pid PID --dir RUNNER_DIR --host H --port P --user U      (비밀번호 MYSQL_PWD)
  progress.py --replay LOG --minmax MIN MAX                               (시험 : 로그를 다시 읽기만)

진행률 = 1회차 배치 범위 끝 PK 가 그 표 PK 최솟값~최댓값 중 어디인지 (실행기는 PK 순서로 한 번 훑는다 — 키 공간 기준 추정).
"""
import argparse, glob, os, re, signal, subprocess, sys, time

HDR = re.compile(r'── \[\d+/\d+\] \d+\. (\S+)(.*)')
CNT = re.compile(r'(?:약\s*)?(\d[\d,]*(?:\.\d+)?)\s*(만)?\s*(?:이하)?\s*행')   # 머리글의 대상 수 — "약 6,031,422행" · "2,300만행" · "13,938,632 이하행"
TS = re.compile(r'^(\d\d):(\d\d):(\d\d)  ')
PKL = re.compile(r'PK `([^`]+)` 하한 방식')
BAT = re.compile(r'\[(\S+)\] 회차 (\d+) 배치 (\d+)\s+삭제 (\d+)\s+누적 (\d+).*?범위 (\S+)~(\S+)')


def key(v, width):
    """PK 값 → 비교할 정수. 16진(binary) 이면 같은 길이로 맞춘다, 10진(정수 PK) 은 그대로."""
    if v.isdigit() and width == 0: return int(v)
    return int(v.ljust(width, '0')[:width], 16)


def fmt_s(s):
    s = int(s)
    return f'{s // 3600}시간 {s % 3600 // 60}분' if s >= 3600 else f'{s // 60}분' if s >= 60 else f'{s}초'


class Tee:
    """화면과 기록 파일에 함께 쓴다 (--log)"""
    def __init__(self, stream, path): self.s = stream; self.f = open(path, 'a', encoding='utf-8')
    def write(self, x): self.s.write(x); self.f.write(x); return len(x)
    def flush(self): self.s.flush(); self.f.flush()
    def __getattr__(self, k): return getattr(self.s, k)


class Step:
    def __init__(self): self.table = None; self.lo = self.hi = None; self.width = 0; self.t0 = None; self.total = 0; self.stale = False


def head_count(desc):
    """머리글에서 대상 수 (없거나 '16,229,6xx' 처럼 숫자가 아니면 0)"""
    m = CNT.search(desc)
    if not m: return 0
    n = float(m.group(1).replace(',', ''))
    return int(n * 10000) if m.group(2) else int(n)


def now(line, a):
    """실제 실행은 지금 시각, --replay 는 로그 줄의 시각 (시험에서도 남은 시간을 볼 수 있게)"""
    if not a.replay: return time.time()
    m = TS.match(line)
    if not m: return None
    h, mi, se = map(int, m.groups()); t = h * 3600 + mi * 60 + se
    if a.last_t is not None and t < a.last_t: t += 86400   # 자정 넘김
    a.last_t = t; return t


def minmax(a, table, pk):
    """PK 최솟값 · 최댓값. 열 형식을 먼저 보고 binary 는 HEX 로만 받는다 (원본 바이트는 글자로 못 바꾼다)"""
    s, t = table.split('.')
    def q(sql):
        r = subprocess.run(['mysql', '-h', a.host, '-P', str(a.port), '-u', a.user, '--connect-timeout=10', '-N', '-B', '-e', sql],
                           capture_output=True, encoding='utf-8', errors='replace', timeout=60)
        return r.stdout.rstrip('\n') if r.returncode == 0 else ''
    typ = q(f"SELECT DATA_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='{s}' AND TABLE_NAME='{t}' AND COLUMN_NAME='{pk}'")
    if typ in ('tinyint', 'smallint', 'mediumint', 'int', 'bigint'):
        v = q(f"SELECT MIN(`{pk}`), MAX(`{pk}`) FROM `{s}`.`{t}`").split('\t'); return (v[0], v[1], 0) if len(v) == 2 else None
    if typ in ('binary', 'varbinary'):
        v = q(f"SELECT HEX(MIN(`{pk}`)), HEX(MAX(`{pk}`)) FROM `{s}`.`{t}`").split('\t')
        return (v[0], v[1], max(len(v[0]), len(v[1]))) if len(v) == 2 else None
    return None   # varchar 등 — 키 공간 추정이 맞지 않는다


def handle(line, st, a, out):
    m = HDR.search(line)
    if m:
        st.table = m.group(1); st.lo = st.hi = None; st.t0 = None; st.total = head_count(m.group(2)); st.stale = False; return
    m = PKL.search(line)
    if m and st.table:
        mm = (a.minmax_fixed if a.replay else minmax(a, st.table, m.group(1)))
        if mm and mm[0] not in ('', 'NULL'):
            st.width = mm[2]; st.lo = key(mm[0], st.width); st.hi = key(mm[1], st.width); st.t0 = now(line, a)
            out(f'     ↳ 진행률 기준 : ' + (f'행 — 머리글 대상 {st.total:,}행 (PK {m.group(1)} 위치 함께)' if st.total else f'PK {m.group(1)} 위치 (머리글에 대상 수 없음)'))
        else:
            out('     ↳ 진행률 : 이 표는 PK 범위로 추정하지 않는다')
        return
    m = BAT.search(line)
    if m and m.group(1) == st.table:
        # 실행기는 배치 줄을 로그에만 쓴다 (화면은 5배치마다 요약) → 여기서 배치마다 한 줄을 찍는다
        rnd, no, d, cum, end = int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5)), m.group(7)
        msg = f'     [회차 {rnd} 배치 {no}] 삭제 {d:,} · 누적 {cum:,}'
        if rnd == 1 and st.lo is not None:
            if end == '-': msg += ' · 키 끝 — 확인 회차로'
            else:
                span = max(st.hi - st.lo, 1); pk = min(max((key(end, st.width) - st.lo) / span, 0.0), 1.0)
                pr = cum / st.total if st.total else None
                # 머리글 수를 믿지 않는 경우 : 누적이 대상을 넘거나, PK 가 25% 를 넘었는데 행 기준이 그 1/4 도 안 된다 (오래된 측정값)
                if pr is not None and not st.stale and (pr > 1.02 or (pk > 0.25 and pr < pk / 4)):
                    st.stale = True; out('     ↳ 머리글 대상 수가 실제와 맞지 않는다 — PK 위치 기준으로 바꾼다')
                use_rows = pr is not None and not st.stale
                p = min(pr, 1.0) if use_rows else pk
                msg += f' · ≈ {p * 100:.1f}%' + (f' (키 위치 {pk * 100:.0f}%)' if use_rows else ' (키 위치)')
                t = now(line, a); el = (t - st.t0) if (t is not None and st.t0 is not None) else None
                if el and el > 0:
                    msg += f' · 경과 {fmt_s(el)}'
                    if p > 0.01 and p < 1: msg += f' · 남은 시간 약 {fmt_s(el * (1 - p) / p)}'
                    msg += f' · {cum / el:,.0f}행/s'
        elif rnd > 1:
            msg += ' · 확인 회차'
        out(msg)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--pid', type=int); ap.add_argument('--dir'); ap.add_argument('--host'); ap.add_argument('--port'); ap.add_argument('--user')
    ap.add_argument('--replay'); ap.add_argument('--minmax', nargs=2); ap.add_argument('--log', default='')
    a = ap.parse_args(); a.last_t = None
    if a.log: sys.stdout = Tee(sys.stdout, a.log)
    signal.signal(signal.SIGINT, signal.SIG_IGN)               # Ctrl-C 는 실행기 쪽 안내만 — 진행률은 끝까지
    out = lambda s: (print(s, flush=True))
    st = Step()
    if a.replay:
        isint = all(v.isdigit() and len(v) < 20 for v in a.minmax)          # 32자리 16진(binary 16) 은 숫자로만 돼 있어도 16진
        a.minmax_fixed = (a.minmax[0], a.minmax[1], 0 if isint else max(map(len, a.minmax)))
        for line in open(a.replay, encoding='utf-8', errors='replace'):
            print(line.rstrip('\n')); handle(line, st, a, out)
        return
    try:
        alive = lambda: os.path.exists(f'/proc/{a.pid}') or subprocess.run(['kill', '-0', str(a.pid)], capture_output=True).returncode == 0
        log = None
        for _ in range(120):                                   # 실행기가 로그를 만들 때까지 (최대 60초)
            hit = glob.glob(os.path.join(a.dir, f'spine-*-{a.pid}.log'))
            if hit: log = hit[0]; break
            if not alive(): return
            time.sleep(0.5)
        if not log: return
        with open(log, encoding='utf-8', errors='replace') as f:
            buf = ''
            while True:
                chunk = f.readline()
                if chunk:
                    buf += chunk
                    if buf.endswith('\n'): handle(buf, st, a, out); buf = ''
                    continue
                if not alive(): break
                time.sleep(0.5)
    except Exception as e:                                     # 진행률은 덤 — 실패해도 조용히 끝낸다
        print(f'     ↳ 진행률 표시 멈춤 ({e.__class__.__name__})', flush=True)


if __name__ == '__main__':
    main()
