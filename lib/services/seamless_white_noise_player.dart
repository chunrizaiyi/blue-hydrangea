import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'white_noise_service.dart';

/// Plays the long ambience assets with a short overlap at the loop boundary.
///
/// Android media decoders may insert a small gap when a compressed file loops.
/// Two players are therefore cross-faded before the 50-minute asset ends. The
/// UI never needs to rebuild while the fade is running.
class SeamlessWhiteNoisePlayer {
  final List<_SeamlessLayer> _layers = [];
  var _generation = 0;
  var _playing = false;
  var _volume = .38;

  bool get isPlaying => _playing;

  Future<void> play(WhiteNoiseKind kind, {required double volume}) async {
    await stop();
    final generation = ++_generation;
    _volume = volume;
    final layers = kind.layers
        .map(
          (definition) =>
              _SeamlessLayer(definition: definition, masterVolume: volume),
        )
        .toList(growable: false);
    _layers.addAll(layers);
    try {
      await Future.wait(layers.map((layer) => layer.start()));
      if (generation != _generation) {
        await Future.wait(layers.map((layer) => layer.dispose()));
        return;
      }
      _playing = true;
    } catch (_) {
      if (generation == _generation) {
        _layers.clear();
        _playing = false;
      }
      await Future.wait(layers.map((layer) => layer.dispose()));
      rethrow;
    }
  }

  Future<void> pause() async {
    if (!_playing) return;
    _playing = false;
    await Future.wait(_layers.map((layer) => layer.pause()));
  }

  Future<void> resume() async {
    if (_playing || _layers.isEmpty) return;
    await Future.wait(_layers.map((layer) => layer.resume()));
    _playing = true;
  }

  Future<void> setVolume(double volume) async {
    _volume = volume;
    await Future.wait(_layers.map((layer) => layer.setMasterVolume(_volume)));
  }

  Future<void> stop() async {
    _generation += 1;
    _playing = false;
    final oldLayers = List<_SeamlessLayer>.of(_layers);
    _layers.clear();
    await Future.wait(oldLayers.map((layer) => layer.dispose()));
  }

  Future<void> dispose() => stop();
}

class _SeamlessLayer {
  _SeamlessLayer({required this.definition, required double masterVolume})
    : _masterVolume = masterVolume;

  static const _trackDuration = Duration(minutes: 50);
  static const _crossfadeDuration = Duration(seconds: 6);
  static const _fadeSteps = 60;

  final WhiteNoiseLayer definition;
  AudioPlayer _current = AudioPlayer();
  AudioPlayer _standby = AudioPlayer();
  Timer? _seamTimer;
  Timer? _rampTimer;
  DateTime? _nextSeamAt;
  Duration? _pausedSeamDelay;
  double _masterVolume;
  var _fadeStep = 0;
  var _crossfading = false;
  var _paused = false;
  var _disposed = false;

  double get _targetVolume => (_masterVolume * definition.gain).clamp(0.0, 1.0);

  Future<void> start() async {
    await _configure(_current);
    await _configure(_standby);
    await _current.play(
      AssetSource(definition.assetPath, mimeType: 'audio/ogg'),
      volume: _targetVolume,
    );
    _scheduleSeam(_trackDuration - _crossfadeDuration);
  }

  Future<void> _configure(AudioPlayer player) async {
    await player.setReleaseMode(ReleaseMode.stop);
  }

  void _scheduleSeam(Duration delay) {
    if (_disposed || _paused) {
      _pausedSeamDelay = delay;
      return;
    }
    final safeDelay = delay.isNegative ? Duration.zero : delay;
    _seamTimer?.cancel();
    _nextSeamAt = DateTime.now().add(safeDelay);
    _seamTimer = Timer(safeDelay, () => unawaited(_beginCrossfade()));
  }

  Future<void> _beginCrossfade() async {
    if (_disposed || _paused || _crossfading) return;
    _crossfading = true;
    _fadeStep = 0;
    try {
      await _standby.play(
        AssetSource(definition.assetPath, mimeType: 'audio/ogg'),
        volume: 0,
      );
      if (_disposed) return;
      // The next seam is measured from the instant the new track begins.
      _scheduleSeam(_trackDuration - _crossfadeDuration);
      _continueRamp();
    } catch (_) {
      _crossfading = false;
      _scheduleSeam(const Duration(seconds: 2));
    }
  }

  void _continueRamp() {
    _rampTimer?.cancel();
    final stepDuration = Duration(
      milliseconds: _crossfadeDuration.inMilliseconds ~/ _fadeSteps,
    );
    _rampTimer = Timer.periodic(stepDuration, (timer) {
      if (_disposed || _paused) {
        timer.cancel();
        return;
      }
      _fadeStep += 1;
      final progress = (_fadeStep / _fadeSteps).clamp(0.0, 1.0);
      unawaited(_applyFadeVolumes(progress));
      if (_fadeStep >= _fadeSteps) {
        timer.cancel();
        unawaited(_finishCrossfade());
      }
    });
  }

  Future<void> _applyFadeVolumes(double progress) async {
    final target = _targetVolume;
    await Future.wait([
      _current.setVolume(target * (1 - progress)),
      _standby.setVolume(target * progress),
    ]);
  }

  Future<void> _finishCrossfade() async {
    if (_disposed) return;
    await _standby.setVolume(_targetVolume);
    await _current.stop();
    final oldCurrent = _current;
    _current = _standby;
    _standby = oldCurrent;
    await _standby.setVolume(0);
    _fadeStep = 0;
    _crossfading = false;
  }

  Future<void> pause() async {
    if (_disposed || _paused) return;
    _paused = true;
    final nextSeamAt = _nextSeamAt;
    _pausedSeamDelay = nextSeamAt == null
        ? _trackDuration - _crossfadeDuration
        : nextSeamAt.difference(DateTime.now());
    _seamTimer?.cancel();
    _rampTimer?.cancel();
    await Future.wait([_current.pause(), if (_crossfading) _standby.pause()]);
  }

  Future<void> resume() async {
    if (_disposed || !_paused) return;
    _paused = false;
    await Future.wait([_current.resume(), if (_crossfading) _standby.resume()]);
    _scheduleSeam(_pausedSeamDelay ?? _trackDuration - _crossfadeDuration);
    if (_crossfading) _continueRamp();
  }

  Future<void> setMasterVolume(double volume) async {
    _masterVolume = volume;
    if (_disposed) return;
    final progress = _crossfading
        ? (_fadeStep / _fadeSteps).clamp(0.0, 1.0)
        : 0.0;
    await _applyFadeVolumes(progress);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _seamTimer?.cancel();
    _rampTimer?.cancel();
    await Future.wait([
      _current.dispose().catchError((_) {}),
      _standby.dispose().catchError((_) {}),
    ]);
  }
}

