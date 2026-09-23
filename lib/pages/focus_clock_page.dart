import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/garden_models.dart';
import '../services/focus_statistics.dart';
import '../services/focus_timer_bridge.dart';
import '../services/local_database.dart';
import '../widgets/garden_background.dart';

enum _ClockMode { clock, stopwatch, countdown, pomodoro }

class FocusClockPage extends StatefulWidget {
  const FocusClockPage({super.key});

  @override
  State<FocusClockPage> createState() => _FocusClockPageState();
}

class _FocusClockPageState extends State<FocusClockPage>
    with WidgetsBindingObserver {
  static const _displayChannel = MethodChannel('blue_hydrangea/display');
  static const _focusDuration = Duration(minutes: 25);
  static const _restDuration = Duration(minutes: 5);

  Timer? _ticker;
  Timer? _displaySettleTimer;
  DateTime _now = DateTime.now();
  late final ValueNotifier<int> _tickNotifier;
  late int _burnInShiftBucket;
  _ClockMode _mode = _ClockMode.clock;
  var _vividMode = false;

  final Stopwatch _stopwatch = Stopwatch();
  Duration _stopwatchOffset = Duration.zero;
  DateTime? _stopwatchStartedAt;
  String? _stopwatchSessionId;

  Duration _countdownSetting = const Duration(minutes: 25);
  Duration _countdownRemaining = const Duration(minutes: 25);
  DateTime? _countdownEnd;
  DateTime? _countdownStartedAt;
  DateTime? _countdownOvertimeStartedAt;
  String? _countdownSessionId;
  var _countdownAlarmActive = false;
  var _countdownSilentOvertime = false;
  var _countdownAlertGeneration = 0;
  final AudioPlayer _countdownAlertPlayer = AudioPlayer();

  var _pomodoroIsFocus = true;
  Duration _pomodoroRemaining = _focusDuration;
  DateTime? _pomodoroEnd;
  DateTime? _pomodoroPhaseStartedAt;
  String? _pomodoroSessionId;

  var _focusFullscreen = false;
  var _dialogVisible = false;
  var _clockVisualReady = false;
  var _closingClock = false;
  var _allowClockPop = false;
  var _orientationRestored = false;
  var _displayModeRevision = 0;
  final FocusTimerBridge _timerBridge = FocusTimerBridge.instance;
  var _nativeTimerActive = false;
  var _restoringNativeTimer = false;
  var _timerRevision = 0;
  var _notificationHintShown = false;
  final Set<String> _handledNativeCompletions = <String>{};
  Future<void> _nativeSnapshotWriteTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tickNotifier = ValueNotifier(0);
    _burnInShiftBucket = _now.minute ~/ 5;
    _timerBridge.clockIsVisible = true;
    final displayRevision = ++_displayModeRevision;
    unawaited(_enterClockMode(displayRevision));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restoreNativeTimerState());
    });
  }

  bool _canContinueEnteringClock(int revision) =>
      mounted &&
      revision == _displayModeRevision &&
      !_orientationRestored &&
      !_closingClock;

  Future<void> _enterClockMode(int revision) async {
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } on PlatformException {
      // Continue behind the launch curtain if a device rejects orientation.
    }
    if (!_canContinueEnteringClock(revision)) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } on PlatformException {
      // The clock still opens when immersive mode is unavailable.
    }
    if (!_canContinueEnteringClock(revision)) return;
    try {
      await _displayChannel.invokeMethod<void>('setClockDisplayMode', {
        'enabled': true,
        // Entry and rotation animations must run at the normal refresh rate.
        // Low-power mode is applied only after the visual has settled.
        'lowPower': false,
      });
    } on PlatformException {
      // The clock remains accurate even when a device rejects the display hint.
    }
    if (!_canContinueEnteringClock(revision)) return;
    await _waitForStableLandscapeFrames(revision);
    if (!_canContinueEnteringClock(revision)) return;
    setState(() => _clockVisualReady = true);
    _scheduleDisplaySettle(const Duration(milliseconds: 1100));
  }

  Future<void> _waitForStableLandscapeFrames(int revision) async {
    Size? previousSize;
    var stableFrames = 0;
    for (var attempt = 0; attempt < 12; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!_canContinueEnteringClock(revision)) return;
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return;
      final size = views.first.physicalSize;
      final landscape = size.width > size.height;
      if (landscape && size == previousSize) {
        stableFrames += 1;
        if (stableFrames >= 1) return;
      } else {
        stableFrames = 0;
      }
      previousSize = size;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_restoreNativeTimerState());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _displaySettleTimer?.cancel();
    _tickNotifier.dispose();
    _timerBridge.clockIsVisible = false;
    unawaited(_countdownAlertPlayer.dispose().catchError((_) {}));
    if (!_orientationRestored) unawaited(_leaveClockMode());
    super.dispose();
  }

  Future<void> _leaveClockMode() async {
    if (_orientationRestored) return;
    _orientationRestored = true;
    _displayModeRevision += 1;
    _displaySettleTimer?.cancel();
    try {
      await _displayChannel.invokeMethod<void>('setClockDisplayMode', {
        'enabled': false,
        'lowPower': false,
      });
    } on PlatformException {
      // Continue restoring the portrait UI when a device rejects the hint.
    }
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } on PlatformException {
      // Continue restoring portrait even when the system UI call is rejected.
    }
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    } on PlatformException {
      // The next portrait page also declares its own preferred orientation.
    }
  }

  Duration get _stopwatchElapsed => _stopwatchOffset + _stopwatch.elapsed;

  String _newSessionId(String mode) =>
      '$mode-${DateTime.now().microsecondsSinceEpoch}';

  bool _sessionIsStillCurrent(String sessionId) =>
      sessionId == _stopwatchSessionId ||
      sessionId == _countdownSessionId ||
      sessionId == _pomodoroSessionId;

  Future<void> _startNativeTimer(FocusTimerSnapshot snapshot) {
    final revision = _timerRevision;
    return _queueNativeSnapshotWrite(
      () => _performStartNativeTimer(snapshot, revision),
    );
  }

  Future<void> _performStartNativeTimer(
    FocusTimerSnapshot snapshot,
    int revision,
  ) async {
    final enrichedSnapshot = await _withTodayAccumulated(snapshot);
    if (!mounted ||
        revision != _timerRevision ||
        !_sessionIsStillCurrent(snapshot.sessionId)) {
      return;
    }
    final started = await _timerBridge.startTimer(enrichedSnapshot);
    if (!mounted ||
        revision != _timerRevision ||
        !_sessionIsStillCurrent(snapshot.sessionId)) {
      if (started) {
        await _timerBridge.stopTimer(sessionId: snapshot.sessionId);
      }
      return;
    }
    _nativeTimerActive = started;
    if (started) {
      // Persist and start the native clock before opening either permission UI.
      // The timer therefore keeps running if Android recreates the Activity,
      // and pause/end updates are not blocked behind a settings screen.
      unawaited(_ensureNativeTimerPermissions(snapshot.sessionId));
    }
  }

  Future<void> _ensureNativeTimerPermissions(String sessionId) async {
    try {
      final notificationGranted = await _timerBridge
          .ensureNotificationPermission();
      if (!mounted || !_sessionIsStillCurrent(sessionId)) return;
      if (!notificationGranted && !_notificationHintShown) {
        _notificationHintShown = true;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('计时会继续，但灵动岛和息屏显示需要允许通知哦~'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Color(0xFF526B9F),
            ),
          );
      }
      final exactAlarmGranted = await _timerBridge.ensureExactAlarmPermission();
      if (!mounted || !_sessionIsStillCurrent(sessionId)) return;
      if (!exactAlarmGranted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('没有开启“闹钟与提醒”权限，息屏后到点可能会晚一点哦~'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Color(0xFF526B9F),
            ),
          );
      }
    } on PlatformException {
      // Permission UI is supplementary; the already-started native timer must
      // never be cancelled because Android is handling another request.
    }
  }

  void _updateNativeTimer(FocusTimerSnapshot snapshot) {
    if (!_sessionIsStillCurrent(snapshot.sessionId)) return;
    unawaited(
      _queueNativeSnapshotWrite(() async {
        final enrichedSnapshot = await _withTodayAccumulated(snapshot);
        if (!mounted || !_sessionIsStillCurrent(snapshot.sessionId)) return;
        final updated = await _timerBridge.setTimerSnapshot(enrichedSnapshot);
        if (mounted && _sessionIsStillCurrent(snapshot.sessionId)) {
          _nativeTimerActive = updated;
        }
      }),
    );
  }

  Future<void> _queueNativeSnapshotWrite(Future<void> Function() operation) {
    final queued = _nativeSnapshotWriteTail.then((_) => operation());
    _nativeSnapshotWriteTail = queued.catchError((Object _) {});
    return _nativeSnapshotWriteTail;
  }

  Future<FocusTimerSnapshot> _withTodayAccumulated(
    FocusTimerSnapshot snapshot,
  ) async {
    try {
      final now = DateTime.now();
      final endOfToday = DateTime(now.year, now.month, now.day + 1);
      final completedSessions = await LocalDatabase.instance.focusSessions(
        endExclusive: endOfToday,
      );
      final completedSeconds = completedFocusSecondsForDay(
        completedSessions,
        now,
        excludingSessionKey: snapshot.sessionId,
      );
      return snapshot.copyWith(todayAccumulatedMs: completedSeconds * 1000);
    } catch (_) {
      // Statistics are supplementary. A temporary database problem must never
      // prevent the native timer, notification, or exact alarm from starting.
      return snapshot;
    }
  }

  void _stopNativeTimer(String? sessionId) {
    if (sessionId == null) return;
    _nativeTimerActive = false;
    unawaited(
      _queueNativeSnapshotWrite(() async {
        await _timerBridge.stopTimer(sessionId: sessionId);
      }),
    );
  }

  FocusTimerSnapshot _stopwatchSnapshot(FocusTimerStatus status) {
    final elapsed = _stopwatchElapsed;
    return FocusTimerSnapshot(
      sessionId: _stopwatchSessionId!,
      mode: FocusTimerMode.stopwatch,
      phase: FocusTimerPhase.none,
      status: status,
      startedAtEpochMs: DateTime.now().subtract(elapsed).millisecondsSinceEpoch,
      recordStartedAtEpochMs: _stopwatchStartedAt?.millisecondsSinceEpoch,
      elapsedMs: elapsed.inMilliseconds,
      remainingMs: 0,
      totalDurationSeconds: 0,
    );
  }

  FocusTimerSnapshot _countdownSnapshot(FocusTimerStatus status) {
    final overtime = _countdownOvertime;
    final elapsed = status == FocusTimerStatus.overtime
        ? _countdownSetting + overtime
        : _countdownSetting - _countdownRemaining;
    return FocusTimerSnapshot(
      sessionId: _countdownSessionId!,
      mode: FocusTimerMode.countdown,
      phase: FocusTimerPhase.none,
      status: status,
      startedAtEpochMs:
          (_countdownStartedAt ?? DateTime.now()).millisecondsSinceEpoch,
      recordStartedAtEpochMs: _countdownStartedAt?.millisecondsSinceEpoch,
      endAtEpochMs:
          _countdownEnd?.millisecondsSinceEpoch ??
          _countdownOvertimeStartedAt?.millisecondsSinceEpoch,
      elapsedMs: elapsed.inMilliseconds.clamp(0, 1 << 62),
      remainingMs: _countdownRemaining.inMilliseconds.clamp(0, 1 << 62),
      totalDurationSeconds: _countdownSetting.inSeconds,
      overtimeMs: overtime.inMilliseconds.clamp(0, 1 << 62),
      isAlarmActive: _countdownAlarmActive,
      isSilentOvertime: _countdownSilentOvertime,
    );
  }

  FocusTimerSnapshot _pomodoroSnapshot(FocusTimerStatus status) {
    final total = _pomodoroIsFocus ? _focusDuration : _restDuration;
    return FocusTimerSnapshot(
      sessionId: _pomodoroSessionId!,
      mode: FocusTimerMode.pomodoro,
      phase: _pomodoroIsFocus ? FocusTimerPhase.focus : FocusTimerPhase.rest,
      status: status,
      startedAtEpochMs:
          (_pomodoroPhaseStartedAt ?? DateTime.now()).millisecondsSinceEpoch,
      recordStartedAtEpochMs: _pomodoroPhaseStartedAt?.millisecondsSinceEpoch,
      endAtEpochMs: _pomodoroEnd?.millisecondsSinceEpoch,
      elapsedMs: _pomodoroElapsed.inMilliseconds.clamp(0, 1 << 62),
      remainingMs: _pomodoroRemaining.inMilliseconds.clamp(0, 1 << 62),
      totalDurationSeconds: total.inSeconds,
    );
  }

  Future<void> _restoreNativeTimerState() async {
    if (_restoringNativeTimer) return;
    _restoringNativeTimer = true;
    final requestedRevision = _timerRevision;
    try {
      final snapshot = await _timerBridge.getState();
      if (!mounted || requestedRevision != _timerRevision) return;
      if (!mounted || snapshot == null) {
        _onTick();
        return;
      }
      _nativeTimerActive = snapshot.active;
      switch (snapshot.mode) {
        case FocusTimerMode.stopwatch:
          if (!snapshot.active &&
              snapshot.status == FocusTimerStatus.finished) {
            return;
          }
          setState(() {
            _mode = _ClockMode.stopwatch;
            _stopwatchSessionId = snapshot.sessionId;
            _stopwatchStartedAt =
                snapshot.recordStartedAt ?? snapshot.startedAt;
            _stopwatch
              ..stop()
              ..reset();
            _stopwatchOffset = snapshot.elapsed;
            if (snapshot.isRunning) _stopwatch.start();
            _focusFullscreen = snapshot.active;
            _now = DateTime.now();
          });
        case FocusTimerMode.countdown:
          final target = snapshot.totalDuration > Duration.zero
              ? snapshot.totalDuration
              : const Duration(seconds: 1);
          final endAt = snapshot.endAt;
          setState(() {
            _mode = _ClockMode.countdown;
            _countdownSessionId = snapshot.sessionId;
            _countdownSetting = target;
            _countdownStartedAt =
                snapshot.recordStartedAt ?? snapshot.startedAt;
            _countdownRemaining = snapshot.remaining;
            _countdownEnd = snapshot.isRunning
                ? endAt ?? DateTime.now().add(snapshot.remaining)
                : null;
            _countdownOvertimeStartedAt = snapshot.isOvertime
                ? endAt ?? DateTime.now().subtract(snapshot.overtime)
                : null;
            _countdownAlarmActive = snapshot.isAlarmActive;
            _countdownSilentOvertime = snapshot.isSilentOvertime;
            _focusFullscreen = snapshot.active;
            _now = DateTime.now();
          });
          if (snapshot.status == FocusTimerStatus.finished &&
              _handledNativeCompletions.add(snapshot.sessionId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(_completeRestoredCountdown(snapshot));
            });
          }
        case FocusTimerMode.pomodoro:
          final focusPhase = snapshot.phase != FocusTimerPhase.rest;
          setState(() {
            _mode = _ClockMode.pomodoro;
            _pomodoroSessionId = snapshot.sessionId;
            _pomodoroIsFocus = focusPhase;
            _pomodoroPhaseStartedAt =
                snapshot.recordStartedAt ?? snapshot.startedAt;
            _pomodoroRemaining = snapshot.remaining;
            _pomodoroEnd = snapshot.isRunning
                ? snapshot.endAt ?? DateTime.now().add(snapshot.remaining)
                : null;
            _focusFullscreen = snapshot.active;
            _now = DateTime.now();
          });
          if (snapshot.status == FocusTimerStatus.finished) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _finishPomodoroPhase(
                  fromNative: true,
                  expectedSessionId: snapshot.sessionId,
                );
              }
            });
          }
      }
      _onTick();
    } finally {
      _restoringNativeTimer = false;
    }
  }

  Future<void> _completeRestoredCountdown(FocusTimerSnapshot snapshot) async {
    if (!mounted) return;
    final actual = snapshot.totalDuration + snapshot.overtime;
    final startedAt = snapshot.startedAt;
    final sessionId = snapshot.sessionId;
    _resetCountdown();
    if (actual <= Duration.zero) return;
    await Future<void>.delayed(const Duration(milliseconds: 820));
    if (!mounted) return;
    await _showSessionCelebration(
      duration: actual,
      startedAt: startedAt,
      mode: FocusSessionMode.countdown,
      targetDurationSeconds: snapshot.totalDurationSeconds,
      sessionKey: sessionId,
      title: '宝宝，这次倒计时认真了${_friendlyDuration(actual)}，真棒呀~',
    );
  }

  void _onTick() {
    final now = DateTime.now();
    var countdownFinished = false;
    var pomodoroFinished = false;

    if (_countdownEnd case final end?) {
      final remaining = end.difference(now);
      if (remaining <= Duration.zero) {
        _countdownRemaining = Duration.zero;
        _countdownEnd = null;
        // Keep overtime exact even if Android resumes us a little after zero.
        _countdownOvertimeStartedAt = end;
        _countdownAlarmActive = true;
        _countdownSilentOvertime = false;
        countdownFinished = true;
        _timerRevision += 1;
      } else {
        _countdownRemaining = remaining;
      }
    }

    if (_pomodoroEnd case final end?) {
      final remaining = end.difference(now);
      if (remaining <= Duration.zero) {
        _pomodoroRemaining = Duration.zero;
        _pomodoroEnd = null;
        pomodoroFinished = true;
        _timerRevision += 1;
      } else {
        _pomodoroRemaining = remaining;
      }
    }

    if (!mounted) return;
    if (countdownFinished || pomodoroFinished) {
      _wakeDisplayForAnimation();
    }
    _now = now;
    final panelChangesEverySecond = switch (_mode) {
      _ClockMode.clock => true,
      _ClockMode.stopwatch => _stopwatch.isRunning,
      _ClockMode.countdown =>
        _countdownRunning || _countdownOvertimeStartedAt != null,
      _ClockMode.pomodoro => _pomodoroRunning,
    };
    if (panelChangesEverySecond || countdownFinished || pomodoroFinished) {
      _tickNotifier.value += 1;
    }
    final nextBurnInShiftBucket = now.minute ~/ 5;
    if (nextBurnInShiftBucket != _burnInShiftBucket) {
      _burnInShiftBucket = nextBurnInShiftBucket;
      setState(() {});
    }
    if (countdownFinished && !_nativeTimerActive) {
      unawaited(_startCountdownAlert());
    }
    if (pomodoroFinished) _finishPomodoroPhase();
  }

  void _announceFinished(String message, {bool quietly = false}) {
    if (!quietly) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF526B9F),
        ),
      );
  }

  Future<void> _startCountdownAlert() async {
    final generation = ++_countdownAlertGeneration;
    HapticFeedback.heavyImpact();
    try {
      await _countdownAlertPlayer.setReleaseMode(ReleaseMode.loop);
      if (!mounted ||
          generation != _countdownAlertGeneration ||
          !_countdownAlarmActive) {
        return;
      }
      await _countdownAlertPlayer.play(
        AssetSource('audio/gentle_breeze_50m.ogg', mimeType: 'audio/ogg'),
        volume: .24,
      );
      if (!mounted ||
          generation != _countdownAlertGeneration ||
          !_countdownAlarmActive) {
        await _countdownAlertPlayer.stop();
        return;
      }
    } catch (_) {
      if (generation == _countdownAlertGeneration && _countdownAlarmActive) {
        SystemSound.play(SystemSoundType.alert);
      }
    }
    if (!mounted ||
        generation != _countdownAlertGeneration ||
        !_countdownAlarmActive) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('时间到啦宝宝，微风来提醒你了~'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF526B9F),
        ),
      );
  }

  Future<void> _stopCountdownAlert() async {
    _countdownAlertGeneration += 1;
    try {
      await _countdownAlertPlayer.stop();
    } catch (_) {
      // The countdown still resets if the device already released the player.
    }
  }

  void _finishPomodoroPhase({
    bool fromNative = false,
    String? expectedSessionId,
  }) {
    final currentSessionId = _pomodoroSessionId;
    final sessionId = expectedSessionId ?? currentSessionId;
    if (sessionId != null && sessionId != currentSessionId) return;
    if (sessionId != null && !_handledNativeCompletions.add(sessionId)) return;
    _timerRevision += 1;
    final finishedFocus = _pomodoroIsFocus;
    final startedAt = _pomodoroPhaseStartedAt;
    _stopNativeTimer(sessionId);
    setState(() {
      _pomodoroIsFocus = !_pomodoroIsFocus;
      _pomodoroRemaining = _pomodoroIsFocus ? _focusDuration : _restDuration;
      _pomodoroPhaseStartedAt = null;
      _pomodoroSessionId = null;
    });
    _announceFinished(
      finishedFocus ? '一朵专注番茄开花啦，休息一下吧' : '休息好啦宝宝，可以继续专注了',
      quietly: fromNative,
    );
    if (finishedFocus) {
      unawaited(
        _showSessionCelebration(
          duration: _focusDuration,
          startedAt: startedAt ?? DateTime.now().subtract(_focusDuration),
          mode: FocusSessionMode.pomodoro,
          sessionKey: sessionId,
          title: '宝宝，25 分钟的专注番茄开花啦！',
        ),
      );
    }
  }

  void _selectMode(_ClockMode mode) {
    if (_focusFullscreen) return;
    _timerRevision += 1;
    _wakeDisplayForAnimation();
    setState(() {
      _mode = mode;
      _now = DateTime.now();
    });
  }

  bool get _sessionKeepsFullscreen => switch (_mode) {
    _ClockMode.clock => false,
    _ClockMode.stopwatch => _stopwatchStartedAt != null,
    _ClockMode.countdown => _countdownStartedAt != null,
    _ClockMode.pomodoro => _pomodoroPhaseStartedAt != null,
  };

  void _requestLeaveClock() {
    if (!_sessionKeepsFullscreen) {
      unawaited(_closeClockSmoothly());
      return;
    }
    _wakeDisplayForAnimation();
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('宝宝，这段计时还在呢，先点“结束”再离开吧~'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF526B9F),
        ),
      );
  }

  Future<void> _closeClockSmoothly() async {
    if (_closingClock) return;
    _displaySettleTimer?.cancel();
    setState(() => _closingClock = true);
    // First fade to the stable curtain, then rotate the activity underneath.
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await _leaveClockMode();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    setState(() => _allowClockPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _setFocusFullscreen(bool value) {
    if (_focusFullscreen == value) return;
    _wakeDisplayForAnimation();
    setState(() => _focusFullscreen = value);
  }

  void _wakeDisplayForAnimation({
    Duration settleAfter = const Duration(milliseconds: 980),
  }) {
    unawaited(_applyNativeDisplayPreference(lowPower: false));
    _scheduleDisplaySettle(settleAfter);
  }

  void _scheduleDisplaySettle(Duration settleAfter) {
    _displaySettleTimer?.cancel();
    _displaySettleTimer = Timer(settleAfter, () {
      if (!mounted || _dialogVisible) return;
      unawaited(_applyNativeDisplayPreference(lowPower: !_vividMode));
    });
  }

  void _beginAnimatedOverlay() {
    if (!mounted) return;
    _displaySettleTimer?.cancel();
    unawaited(_applyNativeDisplayPreference(lowPower: false));
    setState(() => _dialogVisible = true);
  }

  void _endAnimatedOverlay() {
    if (!mounted) return;
    setState(() => _dialogVisible = false);
    _wakeDisplayForAnimation();
  }

  Future<T?> _withAnimatedOverlay<T>(Future<T?> Function() showOverlay) async {
    if (!mounted || _dialogVisible) return null;
    _beginAnimatedOverlay();
    try {
      return await showOverlay();
    } finally {
      _endAnimatedOverlay();
    }
  }

  Future<void> _applyNativeDisplayPreference({required bool lowPower}) async {
    if (_orientationRestored) return;
    try {
      await _displayChannel.invokeMethod<void>('setClockDisplayMode', {
        'enabled': true,
        'lowPower': lowPower,
      });
    } on PlatformException {
      // The playful transition remains available without the native hint.
    }
  }

  void _handlePanelDoubleTap() {
    if (_dialogVisible || _sessionKeepsFullscreen) return;
    HapticFeedback.selectionClick();
    _setFocusFullscreen(!_focusFullscreen);
  }

  void _toggleVividMode() {
    final vividMode = !_vividMode;
    setState(() => _vividMode = vividMode);
    _wakeDisplayForAnimation();
  }

  void _toggleStopwatch() {
    _timerRevision += 1;
    final wasRunning = _stopwatch.isRunning;
    final isNewSession = _stopwatchStartedAt == null;
    final shouldEnterFocus = !wasRunning;
    _wakeDisplayForAnimation();
    setState(() {
      if (wasRunning) {
        _stopwatch.stop();
      } else {
        _stopwatchStartedAt ??= DateTime.now();
        _stopwatchSessionId ??= _newSessionId('stopwatch');
        _stopwatch.start();
      }
      if (shouldEnterFocus) _focusFullscreen = true;
      _now = DateTime.now();
    });
    final snapshot = _stopwatchSnapshot(
      wasRunning ? FocusTimerStatus.paused : FocusTimerStatus.running,
    );
    if (isNewSession) {
      unawaited(_startNativeTimer(snapshot));
    } else {
      _updateNativeTimer(snapshot);
    }
  }

  Future<void> _endStopwatch() async {
    _timerRevision += 1;
    if (_stopwatchElapsed == Duration.zero) {
      _setFocusFullscreen(false);
      return;
    }
    final wasRunning = _stopwatch.isRunning;
    if (wasRunning) {
      setState(() {
        _stopwatch.stop();
        _now = DateTime.now();
      });
      _updateNativeTimer(_stopwatchSnapshot(FocusTimerStatus.paused));
    }
    final confirmed = await _showFocusConfirmation(
      title: '确定结束计时吗宝宝？',
      message: '这一段认真已经被好好记住啦。',
      cancelLabel: '再专注会儿',
      confirmLabel: '确定结束',
    );
    if (!mounted) return;
    if (!confirmed) {
      if (wasRunning) {
        setState(() {
          _stopwatch.start();
          _now = DateTime.now();
        });
        _updateNativeTimer(_stopwatchSnapshot(FocusTimerStatus.running));
      }
      return;
    }
    final elapsed = _stopwatchElapsed;
    final startedAt = _stopwatchStartedAt ?? DateTime.now().subtract(elapsed);
    final sessionId = _stopwatchSessionId;
    setState(() {
      _stopwatch
        ..stop()
        ..reset();
      _stopwatchOffset = Duration.zero;
      _stopwatchStartedAt = null;
      _stopwatchSessionId = null;
      _focusFullscreen = false;
      _now = DateTime.now();
    });
    _stopNativeTimer(sessionId);
    await Future<void>.delayed(const Duration(milliseconds: 820));
    if (!mounted) return;
    await _showSessionCelebration(
      duration: elapsed,
      startedAt: startedAt,
      mode: FocusSessionMode.stopwatch,
      sessionKey: sessionId,
      title: '宝宝，这次计时${_friendlyDuration(elapsed)}，宝宝真棒~',
    );
  }

  Future<bool> _showFocusConfirmation({
    required String title,
    required String message,
    required String cancelLabel,
    required String confirmLabel,
  }) async {
    final result = await _withAnimatedOverlay(
      () => showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .66),
        builder: (_) => _FocusConfirmDialog(
          title: title,
          message: message,
          cancelLabel: cancelLabel,
          confirmLabel: confirmLabel,
        ),
      ),
    );
    return result == true;
  }

  Future<void> _showSessionCelebration({
    required Duration duration,
    required DateTime startedAt,
    required FocusSessionMode mode,
    required String title,
    int? targetDurationSeconds,
    String? sessionKey,
  }) async {
    if (duration.inSeconds <= 0 || !mounted) return;
    final choice = await _withAnimatedOverlay(
      () => showDialog<_LearningChoice>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: .7),
        builder: (_) => _SessionCelebrationDialog(title: title),
      ),
    );
    if (choice == null) return;
    bool added;
    try {
      added = await LocalDatabase.instance.addFocusSession(
        FocusSession(
          startedAt: startedAt,
          durationSeconds: duration.inSeconds,
          mode: mode,
          category: choice.category,
          subcategory: choice.subcategory,
          targetDurationSeconds: targetDurationSeconds,
          sessionKey: sessionKey,
        ),
      );
    } catch (_) {
      added = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(added ? '这次努力已经收进成长记录啦，宝宝真棒~' : '专注记录已经有 1500 条啦。'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF526B9F),
        ),
      );
  }

  Future<void> _showGentleResult(String message) async {
    if (!mounted) return;
    await _withAnimatedOverlay(
      () => showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .68),
        builder: (_) => _GentleResultDialog(message: message),
      ),
    );
  }

  Future<void> _showFocusInsights() async {
    await _withAnimatedOverlay(
      () => showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭专注成长记录',
        barrierColor: Colors.black.withValues(alpha: .72),
        transitionDuration: const Duration(milliseconds: 480),
        pageBuilder: (context, _, __) => const SafeArea(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: _FocusInsightsOverlay(),
            ),
          ),
        ),
        transitionBuilder: (context, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween(begin: .86, end: 1.0).animate(curved),
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(.04, .03),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  bool get _countdownRunning => _countdownEnd != null;

  void _toggleCountdown() {
    if (_countdownRunning && !_countdownEnd!.isAfter(DateTime.now())) {
      _onTick();
      return;
    }
    if (!_countdownRunning &&
        _countdownStartedAt != null &&
        _countdownRemaining <= Duration.zero) {
      _timerRevision += 1;
      setState(() {
        _countdownOvertimeStartedAt ??= DateTime.now();
        _countdownAlarmActive = true;
        _countdownSilentOvertime = false;
      });
      _updateNativeTimer(_countdownSnapshot(FocusTimerStatus.overtime));
      return;
    }
    _timerRevision += 1;
    final wasRunning = _countdownRunning;
    final isNewSession = _countdownStartedAt == null;
    final shouldEnterFocus = !wasRunning;
    _wakeDisplayForAnimation();
    setState(() {
      if (wasRunning) {
        _countdownRemaining = _countdownEnd!.difference(DateTime.now());
        if (_countdownRemaining.isNegative) {
          _countdownRemaining = Duration.zero;
        }
        _countdownEnd = null;
      } else {
        if (_countdownRemaining == Duration.zero) {
          _countdownRemaining = _countdownSetting;
        }
        _countdownStartedAt ??= DateTime.now();
        _countdownSessionId ??= _newSessionId('countdown');
        _countdownEnd = DateTime.now().add(_countdownRemaining);
      }
      if (shouldEnterFocus) _focusFullscreen = true;
      _now = DateTime.now();
    });
    final snapshot = _countdownSnapshot(
      wasRunning ? FocusTimerStatus.paused : FocusTimerStatus.running,
    );
    if (isNewSession) {
      unawaited(_startNativeTimer(snapshot));
    } else {
      _updateNativeTimer(snapshot);
    }
  }

  void _resetCountdown({bool exitFullscreen = true}) {
    _timerRevision += 1;
    final sessionId = _countdownSessionId;
    _wakeDisplayForAnimation();
    unawaited(_stopCountdownAlert());
    setState(() {
      _countdownEnd = null;
      _countdownRemaining = _countdownSetting;
      _countdownStartedAt = null;
      _countdownSessionId = null;
      _countdownOvertimeStartedAt = null;
      _countdownAlarmActive = false;
      _countdownSilentOvertime = false;
      if (exitFullscreen) _focusFullscreen = false;
    });
    _stopNativeTimer(sessionId);
  }

  Duration get _countdownOvertime {
    final startedAt = _countdownOvertimeStartedAt;
    if (startedAt == null) return Duration.zero;
    return DateTime.now().difference(startedAt);
  }

  Duration get _countdownActualDuration {
    if (_countdownOvertimeStartedAt != null) {
      return _countdownSetting + _countdownOvertime;
    }
    final remaining = _countdownRunning
        ? _countdownEnd!.difference(DateTime.now())
        : _countdownRemaining;
    final safeRemaining = remaining.isNegative ? Duration.zero : remaining;
    final actual = _countdownSetting - safeRemaining;
    return actual.isNegative ? Duration.zero : actual;
  }

  Future<void> _confirmEndCountdown() async {
    _timerRevision += 1;
    if (_countdownStartedAt == null) {
      _resetCountdown();
      return;
    }
    final wasRunning = _countdownRunning;
    if (wasRunning) {
      setState(() {
        _countdownRemaining = _countdownEnd!.difference(DateTime.now());
        if (_countdownRemaining.isNegative) {
          _countdownRemaining = Duration.zero;
        }
        _countdownEnd = null;
        _now = DateTime.now();
      });
      _updateNativeTimer(_countdownSnapshot(FocusTimerStatus.paused));
    }
    final confirmed = await _showFocusConfirmation(
      title: '宝宝这么快？好厉害！',
      message: '现在结束的话，这一次倒计时会重新回到起点。',
      cancelLabel: '其实不是！',
      confirmLabel: '其实是的！',
    );
    if (!mounted) return;
    if (confirmed) {
      final actual = _countdownActualDuration;
      final startedAt = _countdownStartedAt ?? DateTime.now().subtract(actual);
      final sessionId = _countdownSessionId;
      final targetSeconds = _countdownSetting.inSeconds;
      _resetCountdown();
      if (actual > Duration.zero) {
        await Future<void>.delayed(const Duration(milliseconds: 820));
        if (!mounted) return;
        await _showSessionCelebration(
          duration: actual,
          startedAt: startedAt,
          mode: FocusSessionMode.countdown,
          targetDurationSeconds: targetSeconds,
          sessionKey: sessionId,
          title: '宝宝，这次倒计时认真了${_friendlyDuration(actual)}，已经很棒啦~',
        );
      }
      return;
    }
    if (wasRunning) {
      _wakeDisplayForAnimation();
      setState(() {
        _countdownEnd = DateTime.now().add(_countdownRemaining);
        _now = DateTime.now();
      });
      _updateNativeTimer(_countdownSnapshot(FocusTimerStatus.running));
    }
  }

  Future<void> _stopAtCountdownFinish() async {
    final overtime = _countdownOvertime;
    final actual = _countdownSetting + overtime;
    final startedAt = _countdownStartedAt ?? DateTime.now().subtract(actual);
    final sessionId = _countdownSessionId;
    final targetSeconds = _countdownSetting.inSeconds;
    await _stopCountdownAlert();
    if (!mounted) return;
    _resetCountdown();
    await Future<void>.delayed(const Duration(milliseconds: 820));
    if (!mounted) return;
    await _showSessionCelebration(
      duration: actual,
      startedAt: startedAt,
      mode: FocusSessionMode.countdown,
      targetDurationSeconds: targetSeconds,
      sessionKey: sessionId,
      title: '宝宝，这次倒计时认真了${_friendlyDuration(actual)}，真棒呀~',
    );
    if (mounted && overtime.inSeconds >= 60) {
      await _showGentleResult('宝宝多花了${_friendlyDuration(overtime)}~');
    }
  }

  Future<void> _silenceCountdownAndContinue() async {
    _timerRevision += 1;
    await _stopCountdownAlert();
    if (!mounted) return;
    _wakeDisplayForAnimation();
    setState(() {
      _countdownAlarmActive = false;
      _countdownSilentOvertime = true;
    });
    _updateNativeTimer(_countdownSnapshot(FocusTimerStatus.overtime));
  }

  Future<void> _finishSilentCountdown() async {
    final overtime = _countdownOvertime;
    final actual = _countdownSetting + overtime;
    final startedAt = _countdownStartedAt ?? DateTime.now().subtract(actual);
    final sessionId = _countdownSessionId;
    final targetSeconds = _countdownSetting.inSeconds;
    await _stopCountdownAlert();
    if (!mounted) return;
    _resetCountdown();
    await Future<void>.delayed(const Duration(milliseconds: 820));
    if (!mounted) return;
    await _showSessionCelebration(
      duration: actual,
      startedAt: startedAt,
      mode: FocusSessionMode.countdown,
      targetDurationSeconds: targetSeconds,
      sessionKey: sessionId,
      title: '宝宝，这次倒计时认真了${_friendlyDuration(actual)}，真棒呀~',
    );
    if (mounted && overtime.inSeconds >= 60) {
      await _showGentleResult('宝宝多花了${_friendlyDuration(overtime)}~');
    }
  }

  void _setCountdown(Duration duration) {
    if (_countdownStartedAt != null) return;
    _timerRevision += 1;
    _wakeDisplayForAnimation();
    setState(() {
      _countdownSetting = duration;
      _countdownRemaining = duration;
    });
  }

  Future<void> _showCustomCountdownDialog() async {
    if (_countdownStartedAt != null) return;
    final duration = await _withAnimatedOverlay(
      () => showDialog<Duration>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .62),
        builder: (_) => _CustomCountdownDialog(initial: _countdownSetting),
      ),
    );
    if (duration != null && mounted) _setCountdown(duration);
  }

  bool get _pomodoroRunning => _pomodoroEnd != null;

  void _togglePomodoro() {
    if (_pomodoroRunning && !_pomodoroEnd!.isAfter(DateTime.now())) {
      _onTick();
      return;
    }
    if (!_pomodoroRunning &&
        _pomodoroPhaseStartedAt != null &&
        _pomodoroRemaining <= Duration.zero) {
      _finishPomodoroPhase(expectedSessionId: _pomodoroSessionId);
      return;
    }
    _timerRevision += 1;
    final wasRunning = _pomodoroRunning;
    final isNewSession = _pomodoroPhaseStartedAt == null;
    final shouldEnterFocus = !wasRunning;
    _wakeDisplayForAnimation();
    setState(() {
      if (wasRunning) {
        _pomodoroRemaining = _pomodoroEnd!.difference(DateTime.now());
        if (_pomodoroRemaining.isNegative) {
          _pomodoroRemaining = Duration.zero;
        }
        _pomodoroEnd = null;
      } else {
        if (_pomodoroRemaining == Duration.zero) {
          _pomodoroRemaining = _pomodoroIsFocus
              ? _focusDuration
              : _restDuration;
        }
        _pomodoroPhaseStartedAt ??= DateTime.now();
        _pomodoroSessionId ??= _newSessionId('pomodoro');
        _pomodoroEnd = DateTime.now().add(_pomodoroRemaining);
      }
      if (shouldEnterFocus) _focusFullscreen = true;
      _now = DateTime.now();
    });
    final snapshot = _pomodoroSnapshot(
      wasRunning ? FocusTimerStatus.paused : FocusTimerStatus.running,
    );
    if (isNewSession) {
      unawaited(_startNativeTimer(snapshot));
    } else {
      _updateNativeTimer(snapshot);
    }
  }

  void _resetPomodoro({bool exitFullscreen = true}) {
    _timerRevision += 1;
    final sessionId = _pomodoroSessionId;
    _wakeDisplayForAnimation();
    setState(() {
      _pomodoroEnd = null;
      _pomodoroIsFocus = true;
      _pomodoroRemaining = _focusDuration;
      _pomodoroPhaseStartedAt = null;
      _pomodoroSessionId = null;
      if (exitFullscreen) _focusFullscreen = false;
    });
    _stopNativeTimer(sessionId);
  }

  Duration get _pomodoroElapsed {
    final total = _pomodoroIsFocus ? _focusDuration : _restDuration;
    final remaining = _pomodoroRunning
        ? _pomodoroEnd!.difference(DateTime.now())
        : _pomodoroRemaining;
    final safeRemaining = remaining.isNegative ? Duration.zero : remaining;
    final elapsed = total - safeRemaining;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Future<void> _endPomodoro() async {
    _timerRevision += 1;
    if (_pomodoroPhaseStartedAt == null) {
      _resetPomodoro();
      return;
    }
    final wasRunning = _pomodoroRunning;
    if (wasRunning) {
      setState(() {
        _pomodoroRemaining = _pomodoroEnd!.difference(DateTime.now());
        if (_pomodoroRemaining.isNegative) {
          _pomodoroRemaining = Duration.zero;
        }
        _pomodoroEnd = null;
      });
      _updateNativeTimer(_pomodoroSnapshot(FocusTimerStatus.paused));
    }
    final confirmed = await _showFocusConfirmation(
      title: '确定结束这轮番茄钟吗宝宝？',
      message: '已经认真过的每一分钟都算数。',
      cancelLabel: '再坚持一下',
      confirmLabel: '结束这轮',
    );
    if (!confirmed || !mounted) {
      if (wasRunning && mounted) _togglePomodoro();
      return;
    }
    final elapsed = _pomodoroElapsed;
    final startedAt =
        _pomodoroPhaseStartedAt ?? DateTime.now().subtract(elapsed);
    final wasFocus = _pomodoroIsFocus;
    final sessionId = _pomodoroSessionId;
    _resetPomodoro();
    if (!wasFocus || elapsed == Duration.zero) return;
    await Future<void>.delayed(const Duration(milliseconds: 820));
    if (!mounted) return;
    await _showSessionCelebration(
      duration: elapsed,
      startedAt: startedAt,
      mode: FocusSessionMode.pomodoro,
      sessionKey: sessionId,
      title: '宝宝，这次番茄专注了${_friendlyDuration(elapsed)}，很棒呀~',
    );
  }

  void _switchPomodoroPhase() {
    if (_pomodoroPhaseStartedAt != null) return;
    _timerRevision += 1;
    _wakeDisplayForAnimation();
    setState(() {
      _pomodoroEnd = null;
      _pomodoroIsFocus = !_pomodoroIsFocus;
      _pomodoroRemaining = _pomodoroIsFocus ? _focusDuration : _restDuration;
      _pomodoroPhaseStartedAt = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final minuteShift = (_burnInShiftBucket % 5) - 2;
    final pageTheme = Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(
        primary: _vividMode ? const Color(0xFF8057B7) : const Color(0xFF526B9F),
        onPrimary: Colors.white,
      ),
    );
    return PopScope(
      canPop: _allowClockPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestLeaveClock();
      },
      child: Theme(
        data: pageTheme,
        child: Scaffold(
          backgroundColor: const Color(0xFF0D1425),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            reverseDuration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: !_clockVisualReady || _closingClock
                ? const _ClockLaunchCurtain(key: ValueKey('clock-curtain'))
                : _ClockBackdrop(
                      key: const ValueKey('clock-content'),
                      vividMode: _vividMode,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                          child: Transform.translate(
                            offset: Offset(
                              minuteShift.toDouble(),
                              -minuteShift / 2,
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) => Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    left: 0,
                                    top: 66,
                                    bottom: 0,
                                    width: 196,
                                    child: AnimatedSlide(
                                      duration: const Duration(
                                        milliseconds: 520,
                                      ),
                                      curve: Curves.easeInOutCubic,
                                      offset: _focusFullscreen
                                          ? const Offset(-1.4, 0)
                                          : Offset.zero,
                                      child: AnimatedOpacity(
                                        duration: const Duration(
                                          milliseconds: 320,
                                        ),
                                        opacity: _focusFullscreen ? 0 : 1,
                                        child: RepaintBoundary(
                                          child: _ModeRail(
                                            selected: _mode,
                                            vividMode: _vividMode,
                                            onSelected: _selectMode,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: 0,
                                    height: 54,
                                    child: AnimatedSlide(
                                      duration: const Duration(
                                        milliseconds: 520,
                                      ),
                                      curve: Curves.easeInOutCubic,
                                      offset: _focusFullscreen
                                          ? const Offset(.24, -1.6)
                                          : Offset.zero,
                                      child: AnimatedOpacity(
                                        duration: const Duration(
                                          milliseconds: 320,
                                        ),
                                        opacity: _focusFullscreen ? 0 : 1,
                                        child: RepaintBoundary(
                                          child: _ClockTopBar(
                                            vividMode: _vividMode,
                                            onBack: _requestLeaveClock,
                                            onVividToggle: _toggleVividMode,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  AnimatedPositioned(
                                    duration: const Duration(milliseconds: 520),
                                    curve: Curves.easeInOutCubic,
                                    left: _focusFullscreen ? 0 : 212,
                                    top: _focusFullscreen ? 0 : 66,
                                    right: 0,
                                    bottom: 0,
                                    child: RepaintBoundary(
                                      child: _buildClockPanel(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
    );
  }

  Widget _buildClockPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _vividMode ? .12 : .055),
        borderRadius: BorderRadius.circular(_focusFullscreen ? 42 : 34),
        border: Border.all(
          color: Colors.white.withValues(alpha: _vividMode ? .25 : .11),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 42,
            offset: Offset(0, 14),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        _focusFullscreen ? 48 : 30,
        _focusFullscreen ? 28 : 18,
        _focusFullscreen ? 48 : 30,
        _focusFullscreen ? 28 : 20,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 460),
        reverseDuration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(.035, .018),
              end: Offset.zero,
            ).animate(animation),
            child: ScaleTransition(
              scale: Tween<double>(begin: .975, end: 1).animate(animation),
              child: child,
            ),
          ),
        ),
        child: AnimatedBuilder(
          key: ValueKey(_mode),
          animation: _tickNotifier,
          builder: (context, _) => switch (_mode) {
            _ClockMode.clock => _clockView(),
            _ClockMode.stopwatch => _stopwatchView(),
            _ClockMode.countdown => _countdownView(),
            _ClockMode.pomodoro => _pomodoroView(),
          },
        ),
      ),
    );
  }

  Widget _clockView() {
    final hour = _two(_now.hour);
    final minute = _two(_now.minute);
    final second = _two(_now.second);
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _PanelEyebrow(icon: Icons.nights_stay_rounded, text: '此刻，安静地陪着你'),
        const Spacer(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _handlePanelDoubleTap,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeInOutCubic,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _focusFullscreen ? 184 : 148,
                    height: .86,
                    fontWeight: FontWeight.w300,
                    letterSpacing: _focusFullscreen ? -6 : -5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  child: Text('$hour:$minute'),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 14, bottom: 12),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeInOutCubic,
                    style: TextStyle(
                      color: const Color(0xFF9CB5EE),
                      fontSize: _focusFullscreen ? 54 : 44,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    child: Text(second),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '${_now.year}年 ${_now.month}月${_now.day}日  ${weekdays[_now.weekday - 1]}',
          style: const TextStyle(
            color: Color(0xFFC8D2E8),
            fontSize: 20,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        const Text(
          '长时间摆放时，适当调低亮度会更省电',
          style: TextStyle(color: Color(0xFF7F8CA7), fontSize: 13),
        ),
      ],
    );
  }

  Widget _stopwatchView() {
    final elapsed = _stopwatchElapsed;
    return _TimerLayout(
      immersive: _focusFullscreen,
      onDisplayDoubleTap: _handlePanelDoubleTap,
      topRight: _FocusInsightsButton(onTap: _showFocusInsights),
      eyebrow: const _PanelEyebrow(icon: Icons.timer_outlined, text: '正计时'),
      display: _durationText(elapsed, showHours: true),
      caption: _stopwatch.isRunning ? '正在记录这一段专注' : '准备好时，就从此刻开始',
      controls: [
        _ClockAction(
          icon: _stopwatch.isRunning
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          label: _stopwatch.isRunning
              ? '暂停'
              : elapsed == Duration.zero
              ? '开始'
              : '继续',
          primary: true,
          activeFill: _stopwatch.isRunning || elapsed == Duration.zero,
          onTap: _toggleStopwatch,
        ),
        _ClockAction(
          icon: Icons.stop_circle_outlined,
          label: '结束',
          onTap: _endStopwatch,
        ),
      ],
    );
  }

  Widget _countdownView() {
    final overtime = _countdownOvertimeStartedAt != null;
    final display = overtime
        ? '+${_durationText(_countdownOvertime)}'
        : _durationText(_countdownRemaining);
    final caption = _countdownAlarmActive
        ? '时间到啦，微风正在轻轻提醒你'
        : _countdownSilentOvertime
        ? '不催你，默默陪你把它做完'
        : _countdownRunning
        ? '时间正在安静地走'
        : _countdownStartedAt != null
        ? '暂停一下也没关系，准备好再继续'
        : '选择一段想留给自己的时间';
    return _TimerLayout(
      immersive: _focusFullscreen,
      onDisplayDoubleTap: _handlePanelDoubleTap,
      topRight: _FocusInsightsButton(onTap: _showFocusInsights),
      eyebrow: const _PanelEyebrow(
        icon: Icons.hourglass_bottom_rounded,
        text: '倒计时',
      ),
      display: display,
      caption: caption,
      presets: overtime || _countdownStartedAt != null
          ? const []
          : [
              for (final minutes in const [5, 10, 25, 45])
                _PresetChip(
                  label: '$minutes 分钟',
                  selected: _countdownSetting.inMinutes == minutes,
                  enabled: _countdownStartedAt == null,
                  onTap: () => _setCountdown(Duration(minutes: minutes)),
                ),
              _PresetChip(
                label: '自定义',
                selected: !const [
                  Duration(minutes: 5),
                  Duration(minutes: 10),
                  Duration(minutes: 25),
                  Duration(minutes: 45),
                ].contains(_countdownSetting),
                enabled: _countdownStartedAt == null,
                onTap: _showCustomCountdownDialog,
              ),
            ],
      controls: _countdownAlarmActive
          ? [
              _ClockAction(
                icon: Icons.notifications_off_rounded,
                label: '停叭',
                primary: true,
                onTap: _stopAtCountdownFinish,
              ),
              _ClockAction(
                icon: Icons.volume_off_rounded,
                label: '吵死了！',
                onTap: _silenceCountdownAndContinue,
              ),
            ]
          : _countdownSilentOvertime
          ? [
              _ClockAction(
                icon: Icons.done_all_rounded,
                label: '搞完了就点这里吧宝宝',
                primary: true,
                wide: true,
                onTap: _finishSilentCountdown,
              ),
            ]
          : [
              _ClockAction(
                icon: _countdownRunning
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                label: _countdownRunning
                    ? '暂停'
                    : _countdownStartedAt == null
                    ? '开始'
                    : '继续',
                primary: true,
                activeFill: _countdownRunning || _countdownStartedAt == null,
                onTap: _toggleCountdown,
              ),
              _ClockAction(
                icon: Icons.stop_circle_outlined,
                label: _countdownStartedAt == null ? '重置' : '结束',
                onTap: _confirmEndCountdown,
              ),
            ],
    );
  }

  Widget _pomodoroView() {
    return _TimerLayout(
      immersive: _focusFullscreen,
      onDisplayDoubleTap: _handlePanelDoubleTap,
      topRight: _FocusInsightsButton(onTap: _showFocusInsights),
      eyebrow: _PanelEyebrow(
        icon: _pomodoroIsFocus
            ? Icons.local_florist_rounded
            : Icons.coffee_rounded,
        text: _pomodoroIsFocus ? '番茄钟 · 专注' : '番茄钟 · 休息',
      ),
      display: _durationText(_pomodoroRemaining),
      caption: _pomodoroRunning
          ? (_pomodoroIsFocus ? '先认真做好眼前这一件事' : '慢慢呼吸，让眼睛也休息一下')
          : (_pomodoroIsFocus ? '25 分钟专注，之后休息 5 分钟' : '休息好，再温柔地继续'),
      presets: _pomodoroPhaseStartedAt == null
          ? [
              _PresetChip(
                label: _pomodoroIsFocus ? '切到休息' : '切到专注',
                selected: false,
                enabled: true,
                onTap: _switchPomodoroPhase,
              ),
            ]
          : const [],
      controls: [
        _ClockAction(
          icon: _pomodoroRunning
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          label: _pomodoroRunning
              ? '暂停'
              : _pomodoroPhaseStartedAt == null
              ? '开始'
              : '继续',
          primary: true,
          activeFill: _pomodoroRunning || _pomodoroPhaseStartedAt == null,
          onTap: _togglePomodoro,
        ),
        _ClockAction(
          icon: Icons.stop_circle_outlined,
          label: _pomodoroPhaseStartedAt == null ? '重置' : '结束',
          onTap: _endPomodoro,
        ),
      ],
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _durationText(Duration value, {bool showHours = false}) {
    final safe = value.isNegative ? Duration.zero : value;
    final totalSeconds = safe.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds ~/ 60) % 60;
    final seconds = totalSeconds % 60;
    if (showHours || hours > 0) {
      return '${_two(hours)}:${_two(minutes)}:${_two(seconds)}';
    }
    return '${_two(minutes)}:${_two(seconds)}';
  }

  static String _friendlyDuration(Duration value) {
    final seconds = value.inSeconds.clamp(0, 359999);
    final hours = seconds ~/ 3600;
    final minutes = (seconds ~/ 60) % 60;
    final restSeconds = seconds % 60;
    if (hours > 0) {
      return '$hours小时${minutes > 0 ? '$minutes分钟' : ''}';
    }
    if (minutes > 0) {
      return '$minutes分钟${restSeconds > 0 ? '$restSeconds秒' : ''}';
    }
    return '$restSeconds秒';
  }
}

class _FocusConfirmDialog extends StatelessWidget {
  const _FocusConfirmDialog({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF171F35),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 570),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Butterfly(size: 38, color: Color(0xFFB7ABED)),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFA8B4CC),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(cancelLabel),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.favorite_rounded, size: 18),
                    label: Text(confirmLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LearningChoice {
  const _LearningChoice(this.category, this.subcategory);

  final String category;
  final String? subcategory;
}

class _SessionCelebrationDialog extends StatefulWidget {
  const _SessionCelebrationDialog({required this.title});

  final String title;

  @override
  State<_SessionCelebrationDialog> createState() =>
      _SessionCelebrationDialogState();
}

class _SessionCelebrationDialogState extends State<_SessionCelebrationDialog> {
  var _category = '专注';
  String? _subcategory;

  void _selectCategory(String value) {
    setState(() {
      _category = value;
      _subcategory = value == '行测'
          ? FocusSession.aptitudeSubcategories.first
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: const Color(0xFF171F35),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: Color(0xFF293A62),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Butterfly(size: 31, color: Color(0xFFD8D2FF)),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  '这次努力属于哪一类？',
                  style: TextStyle(
                    color: Color(0xFFAAB8D4),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 7,
                  children: FocusSession.categories
                      .map(
                        (item) => ChoiceChip(
                          label: Text(item),
                          selected: _category == item,
                          onSelected: (_) => _selectCategory(item),
                          selectedColor: const Color(0xFF526B9F),
                          backgroundColor: Colors.white.withValues(alpha: .055),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: .12),
                          ),
                          labelStyle: TextStyle(
                            color: _category == item
                                ? Colors.white
                                : const Color(0xFFC8D2E8),
                          ),
                        ),
                      )
                      .toList(),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  child: _category != '行测'
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '再分细一点，进步会更清楚',
                                style: TextStyle(
                                  color: Color(0xFF8F9DB8),
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: FocusSession.aptitudeSubcategories
                                    .map(
                                      (item) => ChoiceChip(
                                        label: Text(item),
                                        selected: _subcategory == item,
                                        onSelected: (_) =>
                                            setState(() => _subcategory = item),
                                        selectedColor: const Color(0xFF735FA2),
                                        backgroundColor: Colors.white
                                            .withValues(alpha: .04),
                                        side: BorderSide(
                                          color: Colors.white.withValues(
                                            alpha: .1,
                                          ),
                                        ),
                                        labelStyle: TextStyle(
                                          color: _subcategory == item
                                              ? Colors.white
                                              : const Color(0xFFB6C1D8),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('这次先不记录'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(
                        context,
                        _LearningChoice(_category, _subcategory),
                      ),
                      icon: const Icon(Icons.bookmark_added_rounded, size: 18),
                      label: const Text('收好这次努力'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GentleResultDialog extends StatelessWidget {
  const _GentleResultDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF171F35),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Butterfly(size: 42, color: Color(0xFFD8D2FF)),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '多花一点时间也没关系，认真做完已经很厉害啦。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFA6B2CA)),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.favorite_rounded, size: 18),
                label: const Text('知道啦'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusInsightsButton extends StatelessWidget {
  const _FocusInsightsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '看看宝宝的专注成长',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF31456F), Color(0xFF554978)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFB8C9EE).withValues(alpha: .3),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.insights_rounded,
                  color: Color(0xFFD4DFFF),
                  size: 18,
                ),
                SizedBox(width: 5),
                Butterfly(size: 18, color: Color(0xFFC9BAF3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusInsightsOverlay extends StatefulWidget {
  const _FocusInsightsOverlay();

  @override
  State<_FocusInsightsOverlay> createState() => _FocusInsightsOverlayState();
}

class _FocusInsightsOverlayState extends State<_FocusInsightsOverlay> {
  List<FocusSession>? _sessions;
  var _period = FocusStatisticsPeriod.week;
  FocusSessionMode? _mode;
  String? _category;
  String? _subcategory;
  DateTime? _customStart;
  DateTime? _customEnd;
  DateTime? _draftCustomStart;
  DateTime? _draftCustomEnd;
  late DateTime _customVisibleMonth;
  var _customCalendarOpen = false;
  var _customRangeAwaitingEnd = false;
  var _loadRevision = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _customVisibleMonth = DateTime(now.year, now.month);
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final revision = ++_loadRevision;
    try {
      final sessions = await LocalDatabase.instance.focusSessions();
      if (mounted && revision == _loadRevision) {
        setState(() => _sessions = sessions);
      }
    } catch (_) {
      if (mounted && revision == _loadRevision) {
        setState(() => _sessions ??= const []);
      }
    }
  }

  FocusSessionFilter get _filter => FocusSessionFilter(
    mode: _mode,
    category: _category,
    subcategory: _subcategory,
  );

  FocusStatisticsResult _statistics(List<FocusSession> sessions) {
    return calculateFocusStatistics(
      sessions,
      _period,
      DateTime.now(),
      customStart: _customStart,
      customEndInclusive: _customEnd,
      filter: _filter,
    );
  }

  void _openCustomRange() {
    final now = DateTime.now();
    setState(() {
      _draftCustomStart = _customStart;
      _draftCustomEnd = _customEnd;
      _customRangeAwaitingEnd = false;
      final initial = _customStart ?? now;
      _customVisibleMonth = DateTime(initial.year, initial.month);
      _customCalendarOpen = true;
    });
  }

  void _closeCustomRange() {
    setState(() {
      _customCalendarOpen = false;
      _customRangeAwaitingEnd = false;
    });
  }

  void _selectCustomDate(DateTime value) {
    final day = DateUtils.dateOnly(value);
    setState(() {
      if (!_customRangeAwaitingEnd || _draftCustomStart == null) {
        _draftCustomStart = day;
        _draftCustomEnd = null;
        _customRangeAwaitingEnd = true;
        return;
      }

      final first = _draftCustomStart!;
      if (day.isBefore(first)) {
        _draftCustomStart = day;
        _draftCustomEnd = first;
      } else {
        _draftCustomEnd = day;
      }
      _customRangeAwaitingEnd = false;
    });
  }

  void _setCustomPreset(DateTime start, DateTime end) {
    setState(() {
      _draftCustomStart = DateUtils.dateOnly(start);
      _draftCustomEnd = DateUtils.dateOnly(end);
      _customRangeAwaitingEnd = false;
      _customVisibleMonth = DateTime(start.year, start.month);
    });
  }

  void _moveCustomMonth(int amount) {
    final candidate = DateTime(
      _customVisibleMonth.year,
      _customVisibleMonth.month + amount,
    );
    final firstMonth = DateTime(2020);
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month);
    if (candidate.isBefore(firstMonth) || candidate.isAfter(lastMonth)) return;
    setState(() => _customVisibleMonth = candidate);
  }

  void _applyCustomRange() {
    final start = _draftCustomStart;
    final end = _draftCustomEnd;
    if (start == null || end == null) return;
    setState(() {
      _period = FocusStatisticsPeriod.custom;
      _customStart = start;
      _customEnd = end;
      _customCalendarOpen = false;
      _customRangeAwaitingEnd = false;
    });
  }

  Future<void> _delete(FocusSession session) async {
    if (session.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _FocusConfirmDialog(
        title: '删除这条专注记录吗？',
        message: '删掉后就不能恢复了，宝宝确认一下。',
        cancelLabel: '先留着',
        confirmLabel: '确认删除',
      ),
    );
    if (confirmed != true) return;
    await LocalDatabase.instance.deleteFocusSession(session.id!);
    await _reload();
  }

  List<FocusSession> _visibleSessions(
    List<FocusSession> sessions,
    FocusStatisticsResult result,
  ) {
    final filtered =
        sessions
            .where(_filter.matches)
            .where((entry) => result.range.contains(entry.startedAt))
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return filtered;
  }

  String _encouragement(FocusStatisticsResult result) {
    if (result.sessionCount == 0) {
      return '这段时间还没有记录也没关系，宝宝愿意坐下来时，就是新的开始。';
    }
    if (_mode == FocusSessionMode.countdown) {
      final summary = result.countdownSummary;
      if (summary.assessedSessionCount == 0) {
        return '倒计时已经被好好记住啦，下一次也会继续陪宝宝稳稳完成~';
      }
      final rate = (summary.achievementRate * 100).round();
      if (summary.extraDurationSeconds > 0) {
        return '宝宝的倒计时计划达成率是 $rate%，还多坚持了${_friendlyFocusDuration(summary.extraDurationSeconds)}，真的很有韧劲~';
      }
      return '宝宝的倒计时计划达成率是 $rate%，每一次坐下来都在变得更稳~';
    }
    final difference = result.comparison.durationDifferenceSeconds;
    if (result.comparison.isNewStart) {
      return '这是宝宝新留下的一段认真，每一分钟都在悄悄变成底气~';
    }
    if (difference > 0) {
      return '宝宝比上一段时间多专注了${_friendlyFocusDuration(difference)}，真的在稳稳进步呀~';
    }
    if (difference == 0) {
      return '宝宝一直在认真保持节奏，这份稳定本身就很厉害~';
    }
    return '不用赶，休息也是认真生活的一部分；宝宝已经做得很好啦。';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final sessions = _sessions;
    final overlayWidth = (size.width - safePadding.horizontal - 24)
        .clamp(0.0, 1120.0)
        .toDouble();
    final overlayHeight = (size.height - safePadding.vertical - 16)
        .clamp(0.0, 650.0)
        .toDouble();
    return SizedBox(
      width: overlayWidth,
      height: overlayHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF121A2D).withValues(alpha: .985),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: .13)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x77000000),
                    blurRadius: 28,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          color: Color(0xFF293B65),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.insights_rounded,
                          color: Color(0xFFD3DFFF),
                        ),
                      ),
                      const SizedBox(width: 11),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '宝宝的专注成长',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '看见进步，也看见每一次认真',
                            style: TextStyle(
                              color: Color(0xFF8795AF),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _FocusPeriodSelector(
                        period: _period,
                        onSelected: (period) {
                          if (period == FocusStatisticsPeriod.custom) {
                            _openCustomRange();
                          } else {
                            setState(() => _period = period);
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      _FocusFilterMenu(
                        label: switch (_mode) {
                          null => '全部方式',
                          FocusSessionMode.stopwatch => '正计时',
                          FocusSessionMode.countdown => '倒计时',
                          FocusSessionMode.pomodoro => '番茄钟',
                        },
                        options: const [
                          ('全部方式', 'all'),
                          ('正计时', 'stopwatch'),
                          ('倒计时', 'countdown'),
                          ('番茄钟', 'pomodoro'),
                        ],
                        onSelected: (value) => setState(() {
                          _mode = switch (value) {
                            'stopwatch' => FocusSessionMode.stopwatch,
                            'countdown' => FocusSessionMode.countdown,
                            'pomodoro' => FocusSessionMode.pomodoro,
                            _ => null,
                          };
                        }),
                      ),
                      const SizedBox(width: 7),
                      _FocusFilterMenu(
                        label: _category ?? '全部大类',
                        options: const [
                          ('全部大类', 'all'),
                          ('行测', '行测'),
                          ('申论', '申论'),
                          ('专注', '专注'),
                        ],
                        onSelected: (value) => setState(() {
                          _category = value == 'all' ? null : value;
                          _subcategory = null;
                        }),
                      ),
                      if (_category == '行测') ...[
                        const SizedBox(width: 7),
                        _FocusFilterMenu(
                          label: _subcategory ?? '全部细类',
                          options: [
                            const ('全部细类', 'all'),
                            ...FocusSession.aptitudeSubcategories.map(
                              (e) => (e, e),
                            ),
                          ],
                          onSelected: (value) => setState(
                            () => _subcategory = value == 'all' ? null : value,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (_period == FocusStatisticsPeriod.custom &&
                          _customStart != null &&
                          _customEnd != null)
                        TextButton.icon(
                          onPressed: _openCustomRange,
                          icon: const Icon(Icons.date_range_rounded, size: 17),
                          label: Text(
                            '${_shortDate(_customStart!)} — ${_shortDate(_customEnd!)}',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Expanded(
                    child: sessions == null
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF9CB5EE),
                            ),
                          )
                        : _buildInsights(sessions),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_customCalendarOpen,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                // Keep the switcher's source animation bounded. Feeding the
                // overshooting easeOutBack value into another Cubic curve can
                // make Flutter's release-mode curve solver loop forever.
                switchInCurve: Curves.linear,
                switchOutCurve: Curves.linear,
                transitionBuilder: (child, animation) {
                  final fade = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  );
                  final motion = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                    reverseCurve: Curves.easeInCubic,
                  );
                  return FadeTransition(
                    opacity: fade,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: .92, end: 1).animate(motion),
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, .035),
                          end: Offset.zero,
                        ).animate(motion),
                        child: child,
                      ),
                    ),
                  );
                },
                child: _customCalendarOpen
                    ? _FocusCustomRangeLayer(
                        key: const ValueKey('focus-custom-calendar'),
                        visibleMonth: _customVisibleMonth,
                        start: _draftCustomStart,
                        end: _draftCustomEnd,
                        awaitingEnd: _customRangeAwaitingEnd,
                        onClose: _closeCustomRange,
                        onDateSelected: _selectCustomDate,
                        onPreviousMonth: () => _moveCustomMonth(-1),
                        onNextMonth: () => _moveCustomMonth(1),
                        onPreset: _setCustomPreset,
                        onApply: _applyCustomRange,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('focus-custom-calendar-closed'),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsights(List<FocusSession> sessions) {
    final result = _statistics(sessions);
    final visible = _visibleSessions(sessions, result);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: _FocusGrowthPanel(
            result: result,
            encouragement: _encouragement(result),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          flex: 5,
          child: _FocusRecordPanel(entries: visible, onDelete: _delete),
        ),
      ],
    );
  }
}

class _FocusPeriodSelector extends StatelessWidget {
  const _FocusPeriodSelector({required this.period, required this.onSelected});

  final FocusStatisticsPeriod period;
  final ValueChanged<FocusStatisticsPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (FocusStatisticsPeriod.today, '今天'),
      (FocusStatisticsPeriod.week, '本周'),
      (FocusStatisticsPeriod.month, '本月'),
      (FocusStatisticsPeriod.custom, '自定义'),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          final selected = period == item.$1;
          return InkWell(
            onTap: () => onSelected(item.$1),
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF526B9F) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                item.$2,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFA6B2C9),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FocusCustomRangeLayer extends StatelessWidget {
  const _FocusCustomRangeLayer({
    super.key,
    required this.visibleMonth,
    required this.start,
    required this.end,
    required this.awaitingEnd,
    required this.onClose,
    required this.onDateSelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onPreset,
    required this.onApply,
  });

  final DateTime visibleMonth;
  final DateTime? start;
  final DateTime? end;
  final bool awaitingEnd;
  final VoidCallback onClose;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final void Function(DateTime start, DateTime end) onPreset;
  final VoidCallback onApply;

  String get _hint {
    if (awaitingEnd && start != null) {
      return '已经选好开始日期，再点一天作为结束；再点同一天就是查看当天。';
    }
    if (start != null && end != null) {
      return '这段时间已经选好啦，再点日期可以重新选择。';
    }
    return '先点开始日期，再点结束日期。';
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final monthStart = DateTime(today.year, today.month);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF080D1A).withValues(alpha: .78),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 680;
                  final panelWidth = constraints.maxWidth
                      .clamp(0.0, wide ? 760.0 : 520.0)
                      .toDouble();
                  final panelHeight = constraints.maxHeight
                      .clamp(0.0, 370.0)
                      .toDouble();
                  return Container(
                    width: panelWidth,
                    height: panelHeight,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF202B48), Color(0xFF181E34)],
                      ),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: const Color(0xFFAFC4F2).withValues(alpha: .28),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 34,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                color: Color(0xFF334B7C),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.calendar_month_rounded,
                                color: Color(0xFFDCE6FF),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '挑一段想回看的时光',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '日历会留在当前统计框里',
                                    style: TextStyle(
                                      color: Color(0xFF9EACC5),
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: '关闭日历',
                              onPressed: onClose,
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFFD9E2F6),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Expanded(
                          child: wide
                              ? Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      width: 248,
                                      child: _FocusCustomRangeSummary(
                                        start: start,
                                        end: end,
                                        awaitingEnd: awaitingEnd,
                                        hint: _hint,
                                        today: today,
                                        monthStart: monthStart,
                                        onPreset: onPreset,
                                      ),
                                    ),
                                    const SizedBox(width: 13),
                                    Expanded(
                                      child: _FocusCompactRangeCalendar(
                                        displayedMonth: visibleMonth,
                                        start: start,
                                        end: end,
                                        onPreviousMonth: onPreviousMonth,
                                        onNextMonth: onNextMonth,
                                        onDateSelected: onDateSelected,
                                      ),
                                    ),
                                  ],
                                )
                              : SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      SizedBox(
                                        height: 175,
                                        child: _FocusCustomRangeSummary(
                                          start: start,
                                          end: end,
                                          awaitingEnd: awaitingEnd,
                                          hint: _hint,
                                          today: today,
                                          monthStart: monthStart,
                                          onPreset: onPreset,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        height: 245,
                                        child: _FocusCompactRangeCalendar(
                                          displayedMonth: visibleMonth,
                                          start: start,
                                          end: end,
                                          onPreviousMonth: onPreviousMonth,
                                          onNextMonth: onNextMonth,
                                          onDateSelected: onDateSelected,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton(
                              onPressed: onClose,
                              child: const Text('先不选'),
                            ),
                            const Spacer(),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 240),
                              child: Text(
                                start == null || end == null
                                    ? '还差一个日期噢'
                                    : start == end
                                    ? '已选当天'
                                    : '已选 ${end!.difference(start!).inDays + 1} 天',
                                key: ValueKey((start, end)),
                                style: const TextStyle(
                                  color: Color(0xFF9EACC5),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: start == null || end == null
                                  ? null
                                  : onApply,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF607DB8),
                                disabledBackgroundColor: const Color(
                                  0xFF364158,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(
                                Icons.auto_awesome_rounded,
                                size: 17,
                              ),
                              label: const Text('看看这段时间'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusCustomRangeSummary extends StatelessWidget {
  const _FocusCustomRangeSummary({
    required this.start,
    required this.end,
    required this.awaitingEnd,
    required this.hint,
    required this.today,
    required this.monthStart,
    required this.onPreset,
  });

  final DateTime? start;
  final DateTime? end;
  final bool awaitingEnd;
  final String hint;
  final DateTime today;
  final DateTime monthStart;
  final void Function(DateTime start, DateTime end) onPreset;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white.withValues(alpha: .075)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _FocusDateRangeToken(
                    label: '开始',
                    date: start,
                    active: start == null,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: Color(0xFF7E8CA7),
                    size: 17,
                  ),
                ),
                Expanded(
                  child: _FocusDateRangeToken(
                    label: '结束',
                    date: end,
                    active: awaitingEnd,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: Text(
                hint,
                key: ValueKey(hint),
                style: const TextStyle(
                  color: Color(0xFFC0CBE0),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
            const Spacer(),
            const Text(
              '快速选择',
              style: TextStyle(color: Color(0xFF8290AA), fontSize: 10.5),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: [
                _FocusDatePresetChip(
                  label: '今天',
                  onTap: () => onPreset(today, today),
                ),
                _FocusDatePresetChip(
                  label: '近7天',
                  onTap: () =>
                      onPreset(today.subtract(const Duration(days: 6)), today),
                ),
                _FocusDatePresetChip(
                  label: '本月',
                  onTap: () => onPreset(monthStart, today),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusDateRangeToken extends StatelessWidget {
  const _FocusDateRangeToken({
    required this.label,
    required this.date,
    required this.active,
  });

  final String label;
  final DateTime? date;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF49649C).withValues(alpha: .46)
            : const Color(0xFF12192C),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: active
              ? const Color(0xFFAFC4F2).withValues(alpha: .62)
              : Colors.white.withValues(alpha: .07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF8F9DB6), fontSize: 9.5),
          ),
          const SizedBox(height: 1),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              date == null ? '待选择' : '${date!.month}月${date!.day}日',
              key: ValueKey(date),
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusDatePresetChip extends StatelessWidget {
  const _FocusDatePresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2A3756),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFD7E1F6),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _FocusCompactRangeCalendar extends StatelessWidget {
  const _FocusCompactRangeCalendar({
    required this.displayedMonth,
    required this.start,
    required this.end,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onDateSelected,
  });

  final DateTime displayedMonth;
  final DateTime? start;
  final DateTime? end;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDateSelected;

  bool _sameDay(DateTime? a, DateTime b) =>
      a != null && DateUtils.isSameDay(a, b);

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(displayedMonth.year, displayedMonth.month);
    final daysInMonth = DateTime(
      displayedMonth.year,
      displayedMonth.month + 1,
      0,
    ).day;
    final leadingDays = firstDay.weekday - DateTime.monday;
    final today = DateUtils.dateOnly(DateTime.now());
    final firstAllowed = DateTime(2020);
    final firstAllowedMonth = DateTime(2020);
    final lastAllowedMonth = DateTime(today.year, today.month);
    final canGoPrevious = firstDay.isAfter(firstAllowedMonth);
    final canGoNext = firstDay.isBefore(lastAllowedMonth);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF10172A).withValues(alpha: .82),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: const Color(0xFF7894CD).withValues(alpha: .2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 7),
        child: Column(
          children: [
            SizedBox(
              height: 35,
              child: Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '上个月',
                    onPressed: canGoPrevious ? onPreviousMonth : null,
                    icon: const Icon(Icons.chevron_left_rounded, size: 21),
                    color: const Color(0xFFD8E2F6),
                    disabledColor: const Color(0xFF4D5870),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: .96,
                            end: 1,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        '${firstDay.year}年 ${firstDay.month}月',
                        key: ValueKey(firstDay),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '下个月',
                    onPressed: canGoNext ? onNextMonth : null,
                    icon: const Icon(Icons.chevron_right_rounded, size: 21),
                    color: const Color(0xFFD8E2F6),
                    disabledColor: const Color(0xFF4D5870),
                  ),
                ],
              ),
            ),
            Row(
              children: const ['一', '二', '三', '四', '五', '六', '日']
                  .map(
                    (label) => Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF7887A3),
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 3),
            Expanded(
              child: LayoutBuilder(
                builder: (context, gridConstraints) => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 290),
                  child: GridView.builder(
                    key: ValueKey(firstDay),
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 42,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisExtent: gridConstraints.maxHeight / 6,
                    ),
                    itemBuilder: (context, index) {
                      final dayNumber = index - leadingDays + 1;
                      if (dayNumber < 1 || dayNumber > daysInMonth) {
                        return const SizedBox.shrink();
                      }
                      final day = DateTime(
                        displayedMonth.year,
                        displayedMonth.month,
                        dayNumber,
                      );
                      final disabled =
                          day.isBefore(firstAllowed) || day.isAfter(today);
                      final isStart = _sameDay(start, day);
                      final isEnd = _sameDay(end, day);
                      final endpoint = isStart || isEnd;
                      final inRange =
                          start != null &&
                          end != null &&
                          !day.isBefore(start!) &&
                          !day.isAfter(end!);
                      final isToday = DateUtils.isSameDay(today, day);

                      return Semantics(
                        button: !disabled,
                        selected: endpoint,
                        label:
                            '${day.year}年${day.month}月${day.day}日'
                            '${isStart ? '，开始日期' : ''}'
                            '${isEnd ? '，结束日期' : ''}',
                        child: Padding(
                          padding: const EdgeInsets.all(1.5),
                          child: InkWell(
                            onTap: disabled ? null : () => onDateSelected(day),
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: endpoint
                                    ? const Color(0xFF6484C4)
                                    : inRange
                                    ? const Color(0xFF405783)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: isToday && !endpoint
                                    ? Border.all(color: const Color(0xFFB7A7E3))
                                    : null,
                              ),
                              child: Text(
                                '$dayNumber',
                                style: TextStyle(
                                  color: disabled
                                      ? const Color(0xFF566078)
                                      : endpoint
                                      ? Colors.white
                                      : const Color(0xFFD5DDEF),
                                  fontSize: 10.5,
                                  fontWeight: endpoint
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusFilterMenu extends StatelessWidget {
  const _FocusFilterMenu({
    required this.label,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final List<(String, String)> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '筛选 $label',
      onSelected: onSelected,
      color: const Color(0xFF202A42),
      itemBuilder: (_) => options
          .map(
            (option) => PopupMenuItem(
              value: option.$2,
              child: Text(
                option.$1,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFFB9C5DC), fontSize: 11.5),
            ),
            const SizedBox(width: 5),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF8FA2C8),
              size: 17,
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusGrowthPanel extends StatelessWidget {
  const _FocusGrowthPanel({required this.result, required this.encouragement});

  final FocusStatisticsResult result;
  final String encouragement;

  @override
  Widget build(BuildContext context) {
    final comparison = result.comparison.durationChangePercent;
    final comparisonText = comparison == null
        ? (result.totalDurationSeconds > 0 ? '新的开始' : '等待开始')
        : '${comparison >= 0 ? '+' : ''}${comparison.toStringAsFixed(0)}%';
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: _insightDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _InsightMetric(
                  label: '总专注',
                  value: _friendlyFocusDuration(result.totalDurationSeconds),
                  icon: Icons.timelapse_rounded,
                ),
              ),
              Expanded(
                child: _InsightMetric(
                  label: '记录次数',
                  value: '${result.sessionCount} 次',
                  icon: Icons.auto_awesome_rounded,
                ),
              ),
              Expanded(
                child: _InsightMetric(
                  label: '连续坚持',
                  value: '${result.currentStreakDays} 天',
                  icon: Icons.local_fire_department_outlined,
                ),
              ),
              Expanded(
                child: _InsightMetric(
                  label: '较上一段',
                  value: comparisonText,
                  icon: Icons.trending_up_rounded,
                ),
              ),
            ],
          ),
          if (result.countdownSummary.sessionCount > 0) ...[
            const SizedBox(height: 8),
            _CountdownInsightStrip(summary: result.countdownSummary),
          ],
          const SizedBox(height: 10),
          Expanded(child: _FocusDailyChart(entries: result.dailySummaries)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0x332F68A5), Color(0x335F4688)],
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              encouragement,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD0D9EF),
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownInsightStrip extends StatelessWidget {
  const _CountdownInsightStrip({required this.summary});

  final FocusCountdownSummary summary;

  @override
  Widget build(BuildContext context) {
    final assessed = summary.assessedSessionCount;
    final rate = assessed == 0
        ? '待积累'
        : '${(summary.achievementRate * 100).round()}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF31456F).withValues(alpha: .46),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: const Color(0xFF91ACE6).withValues(alpha: .2),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.hourglass_bottom_rounded,
            color: Color(0xFFADC2F2),
            size: 17,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '倒计时 ${summary.sessionCount} 次 · 实际 ${_friendlyFocusDuration(summary.durationSeconds)} / 计划 ${_friendlyFocusDuration(summary.plannedDurationSeconds)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD4DDF0),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '达成 ${summary.achievedSessionCount}/$assessed · 达成率 $rate${summary.extraDurationSeconds > 0 ? ' · 多坚持 ${_friendlyFocusDuration(summary.extraDurationSeconds)}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFACBDE1),
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightMetric extends StatelessWidget {
  const _InsightMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF9CB5EE), size: 18),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF7F8DA8), fontSize: 9.5),
        ),
      ],
    );
  }
}

class _FocusDailyChart extends StatelessWidget {
  const _FocusDailyChart({required this.entries});

  final Map<DateTime, FocusAggregate> entries;

  List<_FocusChartBucket> _buckets() {
    final source = entries.entries.toList(growable: false);
    if (source.isEmpty) return const [];
    const maximumBars = 72;
    final bucketSize = (source.length / maximumBars).ceil();
    return [
      for (var start = 0; start < source.length; start += bucketSize)
        (() {
          final end = (start + bucketSize).clamp(0, source.length);
          final slice = source.sublist(start, end);
          var durationSeconds = 0;
          var sessionCount = 0;
          for (final entry in slice) {
            durationSeconds += entry.value.durationSeconds;
            sessionCount += entry.value.sessionCount;
          }
          return _FocusChartBucket(
            start: slice.first.key,
            end: slice.last.key,
            aggregate: FocusAggregate(
              durationSeconds: durationSeconds,
              sessionCount: sessionCount,
            ),
          );
        })(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final values = _buckets();
    final maxSeconds = values.fold<int>(
      1,
      (max, entry) => entry.aggregate.durationSeconds > max
          ? entry.aggregate.durationSeconds
          : max,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '每天都算数',
          style: TextStyle(
            color: Color(0xFFAAB7D0),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: values.indexed.map((indexedEntry) {
              final index = indexedEntry.$1;
              final entry = indexedEntry.$2;
              final ratio = entry.aggregate.durationSeconds / maxSeconds;
              final showLabel =
                  values.length <= 10 ||
                  index % ((values.length / 7).ceil()) == 0 ||
                  index == values.length - 1;
              final dateLabel = DateUtils.isSameDay(entry.start, entry.end)
                  ? _shortDate(entry.start)
                  : '${_shortDate(entry.start)}—${_shortDate(entry.end)}';
              return Expanded(
                child: Tooltip(
                  message:
                      '$dateLabel · ${_friendlyFocusDuration(entry.aggregate.durationSeconds)}',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: ratio == 0
                                ? .025
                                : ratio.clamp(.08, 1),
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 1.5,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Color(0xFF5576B4),
                                    Color(0xFFA28CD5),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        showLabel
                            ? '${entry.start.month}/${entry.start.day}'
                            : '',
                        style: const TextStyle(
                          color: Color(0xFF75829C),
                          fontSize: 7.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _FocusChartBucket {
  const _FocusChartBucket({
    required this.start,
    required this.end,
    required this.aggregate,
  });

  final DateTime start;
  final DateTime end;
  final FocusAggregate aggregate;
}

class _FocusRecordPanel extends StatelessWidget {
  const _FocusRecordPanel({required this.entries, required this.onDelete});

  final List<FocusSession> entries;
  final ValueChanged<FocusSession> onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 8, 9),
      decoration: _insightDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 3, right: 5, bottom: 7),
            child: Row(
              children: [
                const Icon(
                  Icons.bookmarks_outlined,
                  color: Color(0xFF9CB5EE),
                  size: 17,
                ),
                const SizedBox(width: 6),
                const Text(
                  '这段时间的认真',
                  style: TextStyle(
                    color: Color(0xFFD5DDEF),
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${entries.length} 条',
                  style: const TextStyle(
                    color: Color(0xFF7987A1),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      '还没有符合筛选条件的记录\n下一次认真会在这里发光~',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF8491AA), height: 1.5),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final modeLabel = switch (entry.mode) {
                        FocusSessionMode.stopwatch => '正计时',
                        FocusSessionMode.countdown => '倒计时',
                        FocusSessionMode.pomodoro => '番茄钟',
                      };
                      final countdownDetail = switch ((
                        entry.mode,
                        entry.targetDurationSeconds,
                      )) {
                        (FocusSessionMode.countdown, final int target)
                            when entry.durationSeconds > target =>
                          ' · 计划${_friendlyFocusDuration(target)} · 多坚持${_friendlyFocusDuration(entry.durationSeconds - target)}',
                        (FocusSessionMode.countdown, final int target)
                            when entry.durationSeconds == target =>
                          ' · 按计划完成',
                        (FocusSessionMode.countdown, final int target) =>
                          ' · 计划${_friendlyFocusDuration(target)} · 距计划${_friendlyFocusDuration(target - entry.durationSeconds)}',
                        _ => '',
                      };
                      return Container(
                        padding: const EdgeInsets.fromLTRB(10, 7, 3, 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .04),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .055),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              switch (entry.mode) {
                                FocusSessionMode.stopwatch =>
                                  Icons.timer_outlined,
                                FocusSessionMode.countdown =>
                                  Icons.hourglass_bottom_rounded,
                                FocusSessionMode.pomodoro =>
                                  Icons.local_florist_outlined,
                              },
                              color: const Color(0xFF91ACE6),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${entry.category}${entry.subcategory == null ? '' : ' · ${entry.subcategory}'}  ${_friendlyFocusDuration(entry.durationSeconds)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFE0E6F3),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${_shortDate(entry.startedAt)}  ${_twoDigit(entry.startedAt.hour)}:${_twoDigit(entry.startedAt.minute)} · $modeLabel$countdownDetail',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF7D8AA4),
                                      fontSize: 9.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '删除这条记录',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => onDelete(entry),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Color(0xFF8390A8),
                                size: 17,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _insightDecoration() => BoxDecoration(
  color: Colors.white.withValues(alpha: .035),
  borderRadius: BorderRadius.circular(21),
  border: Border.all(color: Colors.white.withValues(alpha: .075)),
);

String _friendlyFocusDuration(num secondsValue) {
  final seconds = secondsValue.round().clamp(0, 359999);
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  final secondsOnly = seconds % 60;
  if (hours > 0) return '$hours小时${minutes > 0 ? '$minutes分' : ''}';
  if (minutes > 0) return '$minutes分${secondsOnly > 0 ? '$secondsOnly秒' : ''}';
  return '$secondsOnly秒';
}

String _shortDate(DateTime value) =>
    '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';

String _twoDigit(int value) => value.toString().padLeft(2, '0');

class _ClockLaunchCurtain extends StatelessWidget {
  const _ClockLaunchCurtain({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0D1425),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: .82, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value.clamp(0, 1),
            child: Transform.scale(scale: value, child: child),
          ),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF617DB5), Color(0xFF8057B7)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7895D0).withValues(alpha: .3),
                  blurRadius: 30,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: Colors.white,
              size: 35,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClockBackdrop extends StatelessWidget {
  const _ClockBackdrop({
    required this.vividMode,
    required this.child,
    super.key,
  });

  final bool vividMode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF101A31), Color(0xFF11182A), Color(0xFF17152A)],
            ),
          ),
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeInOutCubic,
            opacity: vividMode ? 1 : 0,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF254A91),
                    Color(0xFF5F4F9E),
                    Color(0xFF92558F),
                  ],
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeInOutCubic,
            opacity: vividMode ? 1 : 0,
            child: const RepaintBoundary(
              child: Stack(
                children: [
                  Positioned(
                    right: -45,
                    top: -100,
                    child: Opacity(
                      opacity: .28,
                      child: HydrangeaCluster(size: 280),
                    ),
                  ),
                  Positioned(
                    left: 430,
                    bottom: -155,
                    child: Opacity(
                      opacity: .2,
                      child: HydrangeaCluster(size: 250),
                    ),
                  ),
                  Positioned(
                    right: 330,
                    top: 72,
                    child: Opacity(
                      opacity: .7,
                      child: Butterfly(size: 34, color: Color(0xFFD8D2FF)),
                    ),
                  ),
                  Positioned(
                    left: 620,
                    top: 30,
                    child: Opacity(
                      opacity: .44,
                      child: Butterfly(size: 25, color: Color(0xFFBFD8FF)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        RepaintBoundary(child: child),
      ],
    );
  }
}

class _CustomCountdownDialog extends StatefulWidget {
  const _CustomCountdownDialog({required this.initial});

  final Duration initial;

  @override
  State<_CustomCountdownDialog> createState() => _CustomCountdownDialogState();
}

class _CustomCountdownDialogState extends State<_CustomCountdownDialog> {
  late final TextEditingController _hours;
  late final TextEditingController _minutes;
  late final TextEditingController _seconds;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final totalSeconds = widget.initial.inSeconds;
    _hours = TextEditingController(text: '${totalSeconds ~/ 3600}');
    _minutes = TextEditingController(text: '${(totalSeconds ~/ 60) % 60}');
    _seconds = TextEditingController(text: '${totalSeconds % 60}');
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _confirm() {
    final hours = int.tryParse(_hours.text) ?? 0;
    final minutes = int.tryParse(_minutes.text) ?? 0;
    final seconds = int.tryParse(_seconds.text) ?? 0;
    if (hours > 99 || minutes > 59 || seconds > 59) {
      setState(() => _errorText = '分钟和秒数最多 59，小时最多 99');
      return;
    }
    final duration = Duration(hours: hours, minutes: minutes, seconds: seconds);
    if (duration == Duration.zero) {
      setState(() => _errorText = '请至少留下一秒钟');
      return;
    }
    Navigator.of(context).pop(duration);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF171F35),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 630),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.hourglass_bottom_rounded,
                    color: Color(0xFF9CB5EE),
                  ),
                  SizedBox(width: 10),
                  Text(
                    '自定义倒计时',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  Butterfly(size: 31, color: Color(0xFFB7ABED)),
                ],
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '想专注多久，由你自己决定。',
                  style: TextStyle(color: Color(0xFF909DB7)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _DurationField(
                      controller: _hours,
                      label: '小时',
                      maxLength: 2,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      ':',
                      style: TextStyle(color: Color(0xFF8290AA), fontSize: 30),
                    ),
                  ),
                  Expanded(
                    child: _DurationField(
                      controller: _minutes,
                      label: '分钟',
                      maxLength: 2,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      ':',
                      style: TextStyle(color: Color(0xFF8290AA), fontSize: 30),
                    ),
                  ),
                  Expanded(
                    child: _DurationField(
                      controller: _seconds,
                      label: '秒',
                      maxLength: 2,
                    ),
                  ),
                ],
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorText!,
                  style: const TextStyle(color: Color(0xFFFFA9B8)),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _confirm,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('设定时间'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationField extends StatelessWidget {
  const _DurationField({
    required this.controller,
    required this.label,
    required this.maxLength,
  });

  final TextEditingController controller;
  final String label;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: maxLength,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        color: Colors.white,
        fontSize: 25,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF9AA9C5)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: .055),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .13)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF8CA7E5), width: 1.5),
        ),
      ),
    );
  }
}

class _ClockTopBar extends StatelessWidget {
  const _ClockTopBar({
    required this.vividMode,
    required this.onBack,
    required this.onVividToggle,
  });

  final bool vividMode;
  final VoidCallback onBack;
  final VoidCallback onVividToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: '返回花园',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.white.withValues(alpha: .08),
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '横屏专注时钟',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '给你认真一会儿',
              style: TextStyle(color: Color(0xFF8996B1), fontSize: 12),
            ),
          ],
        ),
        const Spacer(),
        Semantics(
          button: true,
          toggled: vividMode,
          label: '不省电模式',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onVividToggle,
              borderRadius: BorderRadius.circular(22),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.fromLTRB(13, 8, 9, 8),
                decoration: BoxDecoration(
                  gradient: vividMode
                      ? const LinearGradient(
                          colors: [Color(0xFF668DE0), Color(0xFF9061C2)],
                        )
                      : null,
                  color: vividMode
                      ? null
                      : const Color(0xFF6E82B7).withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: vividMode
                        ? const Color(0xFFD8CAFF).withValues(alpha: .72)
                        : const Color(0xFF92A9DD).withValues(alpha: .22),
                  ),
                  boxShadow: vividMode
                      ? const [
                          BoxShadow(
                            color: Color(0x557F67D8),
                            blurRadius: 22,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: vividMode
                          ? const Butterfly(
                              key: ValueKey('butterfly'),
                              size: 24,
                              color: Colors.white,
                            )
                          : const Icon(
                              Icons.energy_savings_leaf_outlined,
                              key: ValueKey('leaf'),
                              color: Color(0xFFAFC2EE),
                              size: 19,
                            ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '不省电模式',
                      style: TextStyle(
                        color: vividMode
                            ? Colors.white
                            : const Color(0xFFAFC2EE),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 9),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 360),
                      width: 38,
                      height: 22,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: vividMode
                            ? Colors.white.withValues(alpha: .9)
                            : Colors.white.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 360),
                        curve: Curves.easeOutBack,
                        alignment: vividMode
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: vividMode
                                ? const Color(0xFF7754B0)
                                : const Color(0xFF8EA2D0),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeRail extends StatelessWidget {
  const _ModeRail({
    required this.selected,
    required this.vividMode,
    required this.onSelected,
  });

  final _ClockMode selected;
  final bool vividMode;
  final ValueChanged<_ClockMode> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (_ClockMode.clock, Icons.schedule_rounded, '时钟', '看看现在'),
      (_ClockMode.stopwatch, Icons.timer_outlined, '正计时', '记录经过'),
      (_ClockMode.countdown, Icons.hourglass_bottom_rounded, '倒计时', '留一段时间'),
      (_ClockMode.pomodoro, Icons.local_florist_outlined, '番茄钟', '25 + 5'),
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final item in items) ...[
            _ModeButton(
              icon: item.$2,
              title: item.$3,
              subtitle: item.$4,
              selected: selected == item.$1,
              vividMode: vividMode,
              onTap: () => onSelected(item.$1),
            ),
            if (item != items.last) const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.vividMode,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool vividMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? (vividMode ? const Color(0xFF7A58AE) : const Color(0xFF526B9F))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        boxShadow: selected && vividMode
            ? const [BoxShadow(color: Color(0x557F61C1), blurRadius: 18)]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? Colors.white : const Color(0xFF91A0BF),
                  size: 23,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : const Color(0xFFD2D8E6),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: selected
                              ? const Color(0xFFD7E2FF)
                              : const Color(0xFF77839C),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelEyebrow extends StatelessWidget {
  const _PanelEyebrow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFF9CB5EE), size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: const TextStyle(
              color: Color(0xFFAAB8D4),
              fontSize: 14,
              letterSpacing: .6,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerLayout extends StatelessWidget {
  const _TimerLayout({
    required this.eyebrow,
    required this.display,
    required this.caption,
    required this.controls,
    this.presets = const [],
    this.immersive = false,
    this.topRight,
    this.onDisplayDoubleTap,
  });

  final Widget eyebrow;
  final String display;
  final String caption;
  final List<Widget> controls;
  final List<Widget> presets;
  final bool immersive;
  final Widget? topRight;
  final VoidCallback? onDisplayDoubleTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 292;
        final headerHeight = topRight != null ? 38.0 : (compact ? 24.0 : 30.0);
        final presetContent = SizedBox(
          height: 36,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < presets.length; index++) ...[
                  presets[index],
                  if (index != presets.length - 1) const SizedBox(width: 3),
                ],
              ],
            ),
          ),
        );

        return Stack(
          children: [
            Column(
              children: [
                SizedBox(
                  height: headerHeight,
                  child: Padding(
                    padding: EdgeInsets.only(right: topRight == null ? 0 : 92),
                    child: Align(alignment: Alignment.center, child: eyebrow),
                  ),
                ),
                SizedBox(height: compact ? 2 : 5),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: onDisplayDoubleTap,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 520),
                          curve: Curves.easeInOutCubic,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: immersive ? 156 : 122,
                            height: .9,
                            fontWeight: FontWeight.w300,
                            letterSpacing: immersive ? -4 : -3,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          child: Text(display),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: compact ? 3 : (immersive ? 10 : 7)),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 520),
                  style: TextStyle(
                    color: const Color(0xFF98A5BE),
                    fontSize: compact ? 13.5 : (immersive ? 16.5 : 15),
                  ),
                  child: Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (presets.isNotEmpty) ...[
                  SizedBox(height: compact ? 5 : 8),
                  presetContent,
                ],
                SizedBox(height: compact ? 5 : 9),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < controls.length; i++) ...[
                        controls[i],
                        if (i != controls.length - 1) const SizedBox(width: 12),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (topRight != null)
              Positioned(top: 0, right: 0, child: topRight!),
          ],
        );
      },
    );
  }
}

class _ClockAction extends StatelessWidget {
  const _ClockAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.activeFill = true,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool activeFill;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    if (!primary) {
      return TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFB9C4DA),
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
        ),
      );
    }
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeInOutCubic,
      width: wide ? 250 : 132,
      height: 48,
      decoration: BoxDecoration(
        color: activeFill
            ? color
            : const Color(0xFF171F33).withValues(alpha: .5),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: activeFill
              ? Colors.white.withValues(alpha: .05)
              : const Color(0xFF89A3DB).withValues(alpha: .72),
          width: activeFill ? 1 : 1.4,
        ),
        boxShadow: activeFill
            ? [
                BoxShadow(
                  color: color.withValues(alpha: .24),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: Icon(
                    icon,
                    key: ValueKey(icon),
                    color: activeFill ? Colors.white : const Color(0xFFB8C8E9),
                    size: 21,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 360),
                    style: TextStyle(
                      color: activeFill
                          ? Colors.white
                          : const Color(0xFFD3DDF2),
                      fontWeight: FontWeight.w600,
                      fontSize: wide ? 14 : 13.5,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Material(
        color: selected ? const Color(0x665B78B4) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minWidth: 76),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: selected
                  ? Border.all(color: const Color(0x997F9BD3))
                  : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFDCE4F5),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
