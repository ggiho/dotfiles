"""Delete the given keys from one DynamoDB table.

usage: <DynamoDB-JSON key list on stdin> | ddb_delete.py <table>
  stdin: [{"id": {"S": "1"}}, ...]  (what `query --projection-expression <keys>` returns)

Uses the AWS_PROFILE already exported by the ddb-delete recipe. BatchWriteItem takes
25 deletes per call and may hand some back in UnprocessedItems (throttling), so
those are resent with a growing pause until none are left.
"""
import json
import os
import sys
import time

import boto3

table = sys.argv[1]
keys = json.load(sys.stdin)
client = boto3.Session(profile_name=os.environ.get("AWS_PROFILE")).client("dynamodb")

for i in range(0, len(keys), 25):
    pending = [{"DeleteRequest": {"Key": k}} for k in keys[i:i + 25]]
    delay = 0.1
    while pending:
        pending = client.batch_write_item(RequestItems={table: pending})["UnprocessedItems"].get(table, [])
        if pending:
            time.sleep(delay)
            delay = min(delay * 2, 5)
    print("\r%d/%d deleted" % (min(i + 25, len(keys)), len(keys)), end="", file=sys.stderr, flush=True)
print(file=sys.stderr)
print("deleted %d items from %s" % (len(keys), table))
