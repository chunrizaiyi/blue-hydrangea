"""Run isolated Flutter device tests and retain their terminal evidence.

Only the .stage3test application is addressed. No personal app data is read.
"""
import argparse
import datetime as dt
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import threading

sys.stdout.reconfigure(encoding='utf-8')

parser = argparse.ArgumentParser()
parser.add_argument("--device", required=True)
parser.add_argument("--test", required=True)
parser.add_argument("--name", required=True)
parser.add_argument("--seconds", type=int, default=30)
parser.add_argument("--repeat", type=int, default=1)
parser.add_argument("--lock-timer", action="store_true")
parser.add_argument("--physical-taps", action="store_true")
parser.add_argument("--native-text", action="store_true")
parser.add_argument("--plain-name")
parser.add_argument("--test-pattern")
args = parser.parse_args()
for value in [args.test, args.plain_name, args.test_pattern]:
    if value and any(char in value for char in '&|<>^%\r\n'):
        parser.error('Windows batch arguments must not contain shell operators; use a character class such as [DC]-01 for test selection.')
if not re.fullmatch(r'[a-z0-9-]+', args.name):
    parser.error('--name must contain only lowercase letters, digits and hyphens')
root = Path(__file__).resolve().parent.parent
build_root = root.parent / "blue_hydrangea_work"
if not build_root.exists() or not build_root.samefile(root):
    raise RuntimeError("Expected the verified ASCII workspace junction")
tool_root = Path(r"C:\Users\12713\develop\blue_hydrangea_tools")
adb = tool_root / "android-sdk/platform-tools/adb.exe"
flutter = tool_root / "flutter/bin/flutter.bat"
evidence = root / "docs/testing/evidence/2026-09-26"
evidence.mkdir(parents=True, exist_ok=True)
lock = threading.Lock()
wakers = []

def adb_command(*parts):
    result = subprocess.run([str(adb), "-s", args.device, *parts],
                            capture_output=True, text=True, encoding="utf-8",
                            errors="replace", timeout=20)
    return result.stdout.strip(), result.returncode

def timestamp():
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")

run_name = f"{args.name}-{dt.datetime.now():%H%M%S}"
with (evidence / f"{run_name}.log").open("w", encoding="utf-8") as log:
    def emit(line):
        with lock:
            line = line.replace(args.device, 'xiaomi14')
            line = f"{timestamp()} {line.rstrip()}"
            print(line, flush=True)
            log.write(line + "\n")
            log.flush()

    def wake():
        _, code = adb_command("shell", "input", "keyevent", "224")
        emit(f"HOST_WAKE returnCode={code}")

    environment = os.environ.copy()
    environment.update({
        "BLUE_HYDRANGEA_ISOLATED_TEST": "1",
        "FLUTTER_STORAGE_BASE_URL": "https://storage.flutter-io.cn",
        "ANDROID_HOME": str(tool_root / "android-sdk"),
        "ANDROID_SDK_ROOT": str(tool_root / "android-sdk"),
        "JAVA_HOME": str(tool_root / "jdk/jdk-17.0.20+8"),
    })
    metadata = {"startedAt": timestamp(), "test": args.test,
                "deviceAlias": "xiaomi14", "seconds": args.seconds,
                "repeat": args.repeat, "screenOff": args.lock_timer,
                "plainName": args.plain_name, "testPattern": args.test_pattern,
                "physicalTaps": args.physical_taps, "nativeText": args.native_text}
    for key, prop in [("model", "ro.product.model"), ("android", "ro.build.version.release"),
                      ("systemBuild", "ro.build.version.incremental")]:
        metadata[key] = adb_command("shell", "getprop", prop)[0]
    metadata["baseCommit"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    emit("RUN_METADATA " + json.dumps(metadata, ensure_ascii=False))
    command = [str(flutter), "test", args.test, "-d", args.device,
               "--no-pub", "-r", "expanded",
               f"--dart-define=STAGE3_TIMER_SECONDS={args.seconds}",
               f"--dart-define=STAGE3_TIMER_REPEATS={args.repeat}",
               f"--dart-define=STAGE3_PHYSICAL_TAPS={str(args.physical_taps).lower()}",
               f"--dart-define=STAGE3_NATIVE_TEXT={str(args.native_text).lower()}"]
    if args.plain_name:
        command.extend(['--plain-name', args.plain_name])
    if args.test_pattern:
        command.extend(['--name', args.test_pattern])
    process = subprocess.Popen(command, cwd=build_root, env=environment, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT)
    try:
        for raw_line in process.stdout:
            try:
                line = raw_line.decode("utf-8")
            except UnicodeDecodeError:
                line = raw_line.decode("gb18030", errors="replace")
            emit(line)
            entry = re.search(r'DEVICE_TEXT_INPUT value=(stage3-mood-[0-3])', line)
            if entry and args.native_text:
                windows, _ = adb_command('shell', 'dumpsys', 'window')
                if any('mCurrentFocus=' in s and 'com.example.blue_hydrangea.stage3test/' in s
                       for s in windows.splitlines()):
                    _, code = adb_command('shell', 'input', 'text', entry.group(1))
                    emit(f'HOST_TEXT_INPUT returnCode={code}')
                else:
                    emit('HOST_TEXT_INPUT_SKIPPED test application is not foreground')
            tap = re.search(r"DEVICE_DOUBLE_TAP x=(\d+) y=(\d+)", line)
            if tap and args.physical_taps:
                x, y = tap.groups()
                # One shell avoids the extra latency of two Windows adb calls.
                # Flutter records received event times in diagnostic reruns;
                # the shell sleep alone does not prove the actual tap interval.
                windows, _ = adb_command("shell", "dumpsys", "window")
                if any('mCurrentFocus=' in s and 'com.example.blue_hydrangea.stage3test/' in s
                       for s in windows.splitlines()):
                    _, code = adb_command("shell", f"input tap {x} {y}; sleep 0.08; input tap {x} {y}")
                    emit(f"HOST_DOUBLE_TAP returnCode={code}")
                else:
                    emit('HOST_DOUBLE_TAP_SKIPPED test application is not foreground')
            marker = re.search(r"DEVICE_UI_CHECKPOINT ([a-z0-9-]+)", line)
            if marker:
                windows, _ = adb_command("shell", "dumpsys", "window")
                current = [s for s in windows.splitlines() if "mCurrentFocus=" in s]
                if any("com.example.blue_hydrangea.stage3test/" in s for s in current):
                    shot = subprocess.run([str(adb), "-s", args.device, "exec-out", "screencap", "-p"],
                                          capture_output=True, timeout=20)
                    if shot.returncode == 0 and shot.stdout.startswith(b"\x89PNG"):
                        filename = f"{run_name}-{marker.group(1)}.png"
                        (evidence / filename).write_bytes(shot.stdout)
                        emit(f"HOST_SCREENSHOT {filename}")
                else:
                    emit("HOST_SCREENSHOT_SKIPPED test application is not foreground")
            if "STAGE3_STARTED session=" in line and args.lock_timer:
                _, code = adb_command("shell", "input", "keyevent", "223")
                power, _ = adb_command("shell", "dumpsys", "power")
                state = next((s.strip() for s in power.splitlines() if "mWakefulness=" in s), "unknown")
                emit(f"HOST_SCREEN_OFF returnCode={code} {state}")
                waker = threading.Timer(args.seconds + 6, wake)
                wakers.append(waker)
                waker.start()
            if "STAGE3_CLEANUP session=" in line and args.lock_timer:
                for waker in wakers:
                    waker.cancel()
                wake()
        result = process.wait()
    finally:
        for waker in wakers:
            waker.cancel()
        if args.lock_timer:
            wake()
    metadata.update({"finishedAt": timestamp(), "exitCode": result})
    (evidence / f"{run_name}.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    emit(f"RUN_EXIT_CODE={result}")
raise SystemExit(result)
