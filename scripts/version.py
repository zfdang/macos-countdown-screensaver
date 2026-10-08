#!/usr/bin/env python3
"""Version = latest commit's Singapore date + total commits reachable from HEAD."""
import datetime
import json
import subprocess
from zoneinfo import ZoneInfo


def metadata():
    def git(*args):
        return subprocess.check_output(['git', *args], text=True).strip()
    if git('rev-parse', '--is-shallow-repository') == 'true':
        raise SystemExit('Versioning requires full Git history (fetch-depth: 0).')
    count = int(git('rev-list', '--count', 'HEAD'))
    timestamp = int(git('show', '-s', '--format=%ct', 'HEAD'))
    date = datetime.datetime.fromtimestamp(timestamp, ZoneInfo('Asia/Singapore')).strftime('%Y%m%d')
    return {'version': f'{date}.{count}', 'build': str(count), 'commit': git('rev-parse', 'HEAD'), 'date': date}

if __name__ == '__main__':
    print(json.dumps(metadata()))
