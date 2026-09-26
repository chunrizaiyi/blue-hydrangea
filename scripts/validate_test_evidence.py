"""Check report links and 60-case inventory; optionally hash public evidence."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import sys
import subprocess
from urllib.parse import unquote

sys.stdout.reconfigure(encoding='utf-8')
parser = argparse.ArgumentParser()
parser.add_argument('--write-manifest', action='store_true')
parser.add_argument('--verify-index', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
reports = root / 'docs/testing'
inventory = (reports / '08-全量用例覆盖明细.md').read_text(encoding='utf-8')
ids = re.findall(r'^\|\s*([HNAMDVCW]-\d{2})\s*\|', inventory, re.MULTILINE)
expected = {f'{group}-{i:02}' for group, count in
            [('H', 5), ('N', 4), ('A', 12), ('M', 10), ('D', 8), ('V', 6), ('C', 10), ('W', 5)]
            for i in range(1, count + 1)}
errors = []
if len(ids) != 60 or set(ids) != expected:
    errors.append(f'Case inventory mismatch: count={len(ids)} missing={expected - set(ids)}')
for document in reports.glob('*.md'):
    for target in re.findall(r'\[[^\]]+\]\(([^)]+)\)', document.read_text(encoding='utf-8')):
        if target.startswith(('https:', 'http:', '#')):
            continue
        path = unquote(target.split('#', 1)[0])
        if not (document.parent / path).exists():
            errors.append(f'{document.name}: missing {target}')
if errors:
    print('\n'.join(errors))
    raise SystemExit(1)
print('Report links exist; inventory contains exactly 60 unique cases.')
if args.write_manifest:
    folder = reports / 'evidence/2026-09-26'
    entries = []
    for path in sorted(folder.iterdir()):
        if not path.is_file() or path.name == 'SHA256-MANIFEST.json':
            continue
        content = path.read_bytes()
        entries.append({'file': path.name, 'bytes': len(content),
                        'sha256': hashlib.sha256(content).hexdigest()})
    manifest = {'generatedAt': dt.datetime.now().astimezone().isoformat(),
                'algorithm': 'SHA-256', 'files': entries}
    (folder / 'SHA256-MANIFEST.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Evidence manifest written: {len(entries)} files.')
if args.verify_index:
    folder = reports / 'evidence/2026-09-26'
    manifest = json.loads((folder / 'SHA256-MANIFEST.json').read_text(encoding='utf-8'))
    for entry in manifest['files']:
        path = folder / entry['file']
        staged_path = path.relative_to(root).as_posix()
        staged = subprocess.check_output(['git', 'show', f':{staged_path}'], cwd=root)
        if hashlib.sha256(staged).hexdigest() != entry['sha256']:
            raise SystemExit(f'Staged evidence hash mismatch: {entry["file"]}')
    print(f'Staged evidence hashes verified: {len(manifest["files"])} files.')
