import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum FocusTimerMode { stopwatch, countdown, pomodoro }

enum FocusTimerPhase { focus, rest, none }

enum FocusTimerStatus { running, paused, overtime, finished }

@immutable
class FocusTimerSnapshot {
  const FocusTimerSnapshot({
    required this.sessionId,
    required this.mode,
    required this.phase,
    required this.status,
    required this.startedAtEpochMs,
    required this.elapsedMs,
    required this.remainingMs,
    required this.totalDurationSeconds,
    this.endAtEpochMs,
    this.active = true,
    this.overtimeMs = 0,
    this.isAlarmActive = false,
    this.isSilentOvertime = false,
    this.notificationPermissionGranted,
    this.promotedNotificationsAvailable,
    this.recordStartedAtEpochMs,
    this.todayAccumulatedMs = 0,
  });

  final String sessionId;
  final FocusTimerMode mode;
  final FocusTimerPhase phase;
  final FocusTimerStatus status;
  final int startedAtEpochMs;
  final int? recordStartedAtEpochMs;
  final int? endAtEpochMs;
  final int elapsedMs;
  final int remainingMs;
  final int totalDurationSeconds;

  /// `getState` returns this native-owned flag so callers can distinguish an
  /// inactive service from a finished snapshot retained for display.
  final bool active;
  final int overtimeMs;
  final bool isAlarmActive;
  final bool isSilentOvertime;
  final bool? notificationPermissionGranted;
  final bool? promotedNotificationsAvailable;
  final int todayAccumulatedMs;

  DateTime get startedAt =>
      DateTime.fromMillisecondsSinceEpoch(startedAtEpochMs);

  DateTime? get recordStartedAt => recordStartedAtEpochMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(recordStartedAtEpochMs!);

  DateTime? get endAt => endAtEpochMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(endAtEpochMs!);

  Duration get elapsed => Duration(milliseconds: elapsedMs);

  Duration get remaining => Duration(milliseconds: remainingMs);

  Duration get totalDuration => Duration(seconds: totalDurationSeconds);

  Duration get overtime => Duration(milliseconds: overtimeMs);

  bool get isRunning => status == FocusTimerStatus.running;

  bool get isPaused => status == FocusTimerStatus.paused;

  bool get isOvertime => status == FocusTimerStatus.overtime;

  Map<String, Object?> toMap() => {
    'sessionId': sessionId,
    'mode': mode.name,
    'phase': phase.name,
    'status': status.name,
    'startedAtEpochMs': startedAtEpochMs,
    'recordStartedAtEpochMs': recordStartedAtEpochMs,
    'endAtEpochMs': endAtEpochMs,
    'elapsedMs': elapsedMs,
    'remainingMs': remainingMs,
    'totalDurationSeconds': totalDurationSeconds,
    'plannedDurationMs': totalDurationSeconds * 1000,
    'active': active,
    'overtimeMs': overtimeMs,
    'isAlarmActive': isAlarmActive,
    'isSilentOvertime': isSilentOvertime,
    'todayAccumulatedMs': todayAccumulatedMs,
  };

  factory FocusTimerSnapshot.fromMap(Map<Object?, Object?> map) {
    final sessionId = _stringValue(map['sessionId']);
    final startedAtEpochMs = _intValue(map['startedAtEpochMs']);
    if (sessionId == null || sessionId.isEmpty || startedAtEpochMs == null) {
      throw const FormatException('Invalid native focus timer snapshot.');
    }

    return FocusTimerSnapshot(
      sessionId: sessionId,
      mode: _enumValue(
        FocusTimerMode.values,
        map['mode'],
        FocusTimerMode.stopwatch,
      ),
      phase: _enumValue(
        FocusTimerPhase.values,
        map['phase'],
        FocusTimerPhase.none,
      ),
      status: _enumValue(
        FocusTimerStatus.values,
        map['status'],
        FocusTimerStatus.finished,
      ),
      startedAtEpochMs: startedAtEpochMs,
      recordStartedAtEpochMs: _intValue(map['recordStartedAtEpochMs']),
      endAtEpochMs: _intValue(map['endAtEpochMs']),
      elapsedMs: _nonNegativeInt(map['elapsedMs']),
      remainingMs: _nonNegativeInt(map['remainingMs']),
      totalDurationSeconds: _nonNegativeInt(map['totalDurationSeconds']),
      active: _boolValue(map['active']) ?? true,
      overtimeMs: _nonNegativeInt(map['overtimeMs']),
      isAlarmActive: _boolValue(map['isAlarmActive']) ?? false,
      isSilentOvertime: _boolValue(map['isSilentOvertime']) ?? false,
      notificationPermissionGranted: _boolValue(
        map['notificationPermissionGranted'],
      ),
      promotedNotificationsAvailable: _boolValue(
        map['promotedNotificationsAvailable'],
      ),
      todayAccumulatedMs: _nonNegativeInt(map['todayAccumulatedMs']),
    );
  }

  FocusTimerSnapshot copyWith({
    String? sessionId,
    FocusTimerMode? mode,
    FocusTimerPhase? phase,
    FocusTimerStatus? status,
    int? startedAtEpochMs,
    int? recordStartedAtEpochMs,
    int? endAtEpochMs,
    bool clearEndAt = false,
    int? elapsedMs,
    int? remainingMs,
    int? totalDurationSeconds,
    bool? active,
    int? overtimeMs,
    bool? isAlarmActive,
    bool? isSilentOvertime,
    bool? notificationPermissionGranted,
    bool? promotedNotificationsAvailable,
    int? todayAccumulatedMs,
  }) => FocusTimerSnapshot(
    sessionId: sessionId ?? this.sessionId,
    mode: mode ?? this.mode,
    phase: phase ?? this.phase,
    status: status ?? this.status,
    startedAtEpochMs: startedAtEpochMs ?? this.startedAtEpochMs,
    recordStartedAtEpochMs:
        recordStartedAtEpochMs ?? this.recordStartedAtEpochMs,
    endAtEpochMs: clearEndAt ? null : endAtEpochMs ?? this.endAtEpochMs,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    remainingMs: remainingMs ?? this.remainingMs,
    totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
    active: active ?? this.active,
    overtimeMs: overtimeMs ?? this.overtimeMs,
    isAlarmActive: isAlarmActive ?? this.isAlarmActive,
    isSilentOvertime: isSilentOvertime ?? this.isSilentOvertime,
    notificationPermissionGranted:
        notificationPermissionGranted ?? this.notificationPermissionGranted,
    promotedNotificationsAvailable:
        promotedNotificationsAvailable ?? this.promotedNotificationsAvailable,
    todayAccumulatedMs: todayAccumulatedMs ?? this.todayAccumulatedMs,
  );

  static T _enumValue<T extends Enum>(
    List<T> values,
    Object? rawValue,
    T fallback,
  ) {
    final name = _stringValue(rawValue);
    if (name == null) return fallback;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  static int _nonNegativeInt(Object? value) {
    final parsed = _intValue(value) ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _stringValue(Object? value) {
    if (value == null) return null;
    return value.toString();
  }

  static bool? _boolValue(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return switch (value?.toString().toLowerCase()) {
      'true' || '1' => true,
      'false' || '0' => false,
      _ => null,
    };
  }
}

class FocusTimerBridge {
  FocusTimerBridge._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final FocusTimerBridge instance = FocusTimerBridge._();

  static const MethodChannel _channel = MethodChannel(
    'blue_hydrangea/timer_service',
  );

  final StreamController<void> _openFocusClockController =
      StreamController<void>.broadcast(sync: true);

  bool clockIsVisible = false;

  Stream<void> get openFocusClockRequests => _openFocusClockController.stream;

  Future<bool> ensureNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>(
            'ensureNotificationPermission',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> ensureExactAlarmPermission() async {
    try {
      return await _channel.invokeMethod<bool>('ensureExactAlarmPermission') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Updates an already running native notification/service snapshot.
  Future<bool> setTimerSnapshot(FocusTimerSnapshot snapshot) =>
      _sendSnapshot('setTimerSnapshot', snapshot);

  /// Starts the native foreground timer and its ongoing notification.
  Future<bool> startTimer(FocusTimerSnapshot snapshot) =>
      _sendSnapshot('startTimer', snapshot);

  Future<bool> _sendSnapshot(String method, FocusTimerSnapshot snapshot) async {
    try {
      await _channel.invokeMethod<void>(method, snapshot.toMap());
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> stopTimer({String? sessionId}) async {
    try {
      await _channel.invokeMethod<void>(
        'stopTimer',
        sessionId == null ? null : {'sessionId': sessionId},
      );
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<FocusTimerSnapshot?> getState() async {
    try {
      final result = await _channel.invokeMethod<Object?>('getState');
      final map = _asMap(result);
      if (map == null) return null;

      final nestedSnapshot = _asMap(map['snapshot']);
      final snapshotMap = nestedSnapshot ?? map;
      if (_explicitlyInactive(snapshotMap) &&
          snapshotMap['sessionId'] == null) {
        return null;
      }
      return FocusTimerSnapshot.fromMap(snapshotMap);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<bool> consumeOpenTimerRequest() async {
    try {
      return await _channel.invokeMethod<bool>('consumeOpenTimerRequest') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method != 'openFocusClock') return null;
    if (!clockIsVisible) _openFocusClockController.add(null);
    return null;
  }

  static Map<Object?, Object?>? _asMap(Object? value) {
    if (value is Map<Object?, Object?>) return value;
    if (value is Map) return Map<Object?, Object?>.from(value);
    return null;
  }

  static bool _explicitlyInactive(Map<Object?, Object?> map) {
    final value = map['active'];
    return value == false || value == 0 || value?.toString() == 'false';
  }
}
