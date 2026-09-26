import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Ogg Opus granules use 48 kHz units; pre-skip is subtracted from the last
// granule to obtain duration. RFC 7845 sections 4 and 5.1:
// https://www.rfc-editor.org/rfc/rfc7845.html
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final name in ['rain', 'ocean', 'breeze']) {
    test(
      'W-03 $name Ogg pages are complete and duration is 50 minutes',
      () async {
        final asset = await rootBundle.load(
          'assets/audio/gentle_${name}_50m.ogg',
        );
        final bytes = asset.buffer.asUint8List(
          asset.offsetInBytes,
          asset.lengthInBytes,
        );
        final data = ByteData.sublistView(bytes);
        var offset = 0;
        var sequence = 0;
        int? serial;
        int? preSkip;
        int? finalGranule;
        while (offset < bytes.length) {
          expect(offset + 27, lessThanOrEqualTo(bytes.length));
          expect(ascii.decode(bytes.sublist(offset, offset + 4)), 'OggS');
          expect(bytes[offset + 4], 0);
          final flags = bytes[offset + 5];
          final granule = data.getInt64(offset + 6, Endian.little);
          final currentSerial = data.getUint32(offset + 14, Endian.little);
          serial ??= currentSerial;
          expect(currentSerial, serial);
          expect(data.getUint32(offset + 18, Endian.little), sequence++);
          final segments = bytes[offset + 26];
          final body = offset + 27 + segments;
          expect(body, lessThanOrEqualTo(bytes.length));
          var length = 0;
          for (var segment = 0; segment < segments; segment++) {
            length += bytes[offset + 27 + segment];
          }
          expect(body + length, lessThanOrEqualTo(bytes.length));
          if (offset == 0) {
            expect(flags & 2, 2);
            expect(length, greaterThanOrEqualTo(19));
            expect(ascii.decode(bytes.sublist(body, body + 8)), 'OpusHead');
            preSkip = data.getUint16(body + 10, Endian.little);
          }
          offset = body + length;
          if (flags & 4 != 0) {
            finalGranule = granule;
            expect(offset, bytes.length);
          }
        }
        expect(finalGranule, isNotNull);
        final seconds = (finalGranule! - preSkip!) / 48000;
        expect(seconds, closeTo(3000, .02));
        // ignore: avoid_print
        print(
          'AUDIO_ASSET name=$name durationSeconds=$seconds pages=$sequence bytes=${bytes.length}',
        );
      },
    );
  }
}
