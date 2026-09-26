"""Read only the isolated timer snapshot shortly after a known deadline.

This records whether completion was persisted while the secure screen was
still locked, before the main runner sends its wake event. It neither unlocks
the device nor addresses the production package.
"""
import argparse
import datetime as dt
import json
from pathlib import Path
import subprocess
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--device', required=True)
parser.add_argument('--deadline-ms', type=int, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
adb = Path(r'C:\Users\12713\develop\blue_hydrangea_tools\android-sdk\platform-tools\adb.exe')
wait = args.deadline_ms / 1000 + 2 - time.time()
print(f'Waiting for deadline+2s; remaining={max(0, wait):.1f}s', flush=True)
if wait > 0:
    time.sleep(wait)

def read(*parts):
    result = subprocess.run([str(adb), '-s', args.device, 'shell', *parts],
                            capture_output=True, text=True, encoding='utf-8',
                            errors='replace', timeout=15)
    if result.returncode:
        raise RuntimeError('Scoped device inspection failed')
    return result.stdout

observed = dt.datetime.now().astimezone().isoformat(timespec='milliseconds')
power = read('dumpsys', 'power')
policy = read('dumpsys', 'window', 'policy')
xml = read('run-as', 'com.example.blue_hydrangea.stage3test', 'cat',
           'shared_prefs/focus_timer_native_state_v1.xml')
snapshot = json.loads(ET.fromstring(xml).find("string[@name='snapshot']").text)
allowed = ['sessionId', 'mode', 'phase', 'status', 'endAtEpochMs',
           'completedAtEpochMs', 'isAlarmActive', 'isSilentOvertime', 'active']
result = {'observedAt': observed, 'plannedEndMs': args.deadline_ms,
          'power': [s.strip() for s in power.splitlines() if 'mWakefulness=' in s],
          'keyguard': [s.strip() for s in policy.splitlines()
                       if s.strip().startswith(('showing=', 'secure='))],
          'snapshot': {key: snapshot.get(key) for key in allowed}}
path = root / 'docs/testing/evidence/2026-09-26' / f'xiaomi14-deadline-{args.deadline_ms}.json'
path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result, ensure_ascii=False), flush=True)
