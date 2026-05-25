#!/usr/bin/env python3
import sys
import json

rows = json.load(sys.stdin)
if not rows:
    print("No results.")
    sys.exit(0)

cols = list(rows[0].keys())

# Writer/Reader 엔드포인트는 cluster identifier 부분만 표시
for r in rows:
    for k in ('Writer', 'Reader'):
        if r.get(k):
            r[k] = r[k].split('.')[0]

widths = {c: max(len(c), max(len(str(r.get(c, ''))) for r in rows)) for c in cols}
sep = '+-' + '-+-'.join('-' * widths[c] for c in cols) + '-+'
header = '| ' + ' | '.join(c.ljust(widths[c]) for c in cols) + ' |'

print(sep)
print(header)
print(sep)
for r in rows:
    print('| ' + ' | '.join(str(r.get(c, '')).ljust(widths[c]) for c in cols) + ' |')
print(sep)
