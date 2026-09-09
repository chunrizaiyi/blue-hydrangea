import 'package:blue_hydrangea/services/white_noise_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final uniqueAssets = WhiteNoiseKind.values
      .expand((sound) => sound.layers)
      .map((layer) => layer.assetPath)
      .toSet();

  for (final assetPath in uniqueAssets) {
    test('$assetPath 使用本地 OGG 长音轨', () async {
      final data = await rootBundle.load('assets/$assetPath');
      final bytes = data.buffer.asUint8List();

      expect(String.fromCharCodes(bytes.take(4)), 'OggS');
      expect(bytes.length, greaterThan(10 * 1024 * 1024));
    });
  }

  test('新增的舒缓音色由长音轨分层混合', () {
    expect(WhiteNoiseKind.rainyNight.layers, hasLength(2));
    expect(WhiteNoiseKind.coastalBreeze.layers, hasLength(2));
    expect(WhiteNoiseKind.gardenDream.layers, hasLength(3));
    for (final sound in WhiteNoiseKind.values) {
      expect(
        sound.layers.fold<double>(0, (sum, layer) => sum + layer.gain),
        closeTo(1, .0001),
      );
    }
  });
}
