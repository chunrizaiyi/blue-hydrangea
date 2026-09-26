"""Retain reproducible host test/analyzer output without credentials."""
import datetime as dt
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

sys.stdout.reconfigure(encoding='utf-8')

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--analyze-only', action='store_true')
options = parser.parse_args()
cwd = root.parent / 'blue_hydrangea_work'
if not cwd.samefile(root):
    raise RuntimeError('Unexpected workspace alias')
flutter = r'C:\Users\12713\develop\blue_hydrangea_tools\flutter\bin\flutter.bat'
env = os.environ.copy()
env['FLUTTER_STORAGE_BASE_URL'] = 'https://storage.flutter-io.cn'
folder = root / 'docs/testing/evidence/2026-09-26'
folder.mkdir(parents=True, exist_ok=True)
results = []
checks = [('analyze', ['analyze', '--no-pub'])] if options.analyze_only else [
    ('regression', ['test', '--no-pub', '-r', 'expanded']),
    ('analyze', ['analyze', '--no-pub'])]
for name, args in checks:
    started = dt.datetime.now().astimezone().isoformat()
    path = folder / f'host-{name}-{dt.datetime.now():%H%M%S}.log'
    with path.open('wb') as log:
        process = subprocess.Popen([flutter, *args], cwd=cwd, env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for line in process.stdout:
            log.write(line)
            log.flush()
            print(line.decode('utf-8', errors='replace').rstrip(), flush=True)
        code = process.wait()
    results.append({'name': name, 'startedAt': started,
                    'finishedAt': dt.datetime.now().astimezone().isoformat(),
                    'exitCode': code, 'log': path.name})
path = folder / f'host-checks-{dt.datetime.now():%H%M%S}.json'
path.write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(results, ensure_ascii=False), flush=True)
raise SystemExit(1 if any(result['exitCode'] for result in results) else 0)
