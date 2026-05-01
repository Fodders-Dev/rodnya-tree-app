import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/utils/voice_waveform.dart';

void main() {
  test('buildVoiceWaveformFromBytes returns normalized bins', () {
    final waveform = buildVoiceWaveformFromBytes(
      Uint8List.fromList(List<int>.generate(256, (index) => index % 256)),
      bins: 32,
    );

    expect(waveform, hasLength(32));
    expect(waveform.every((value) => value >= 0 && value <= 1), isTrue);
    expect(waveform.any((value) => value > 0.5), isTrue);
  });

  test('normalizeVoiceWaveform clamps and downsamples samples', () {
    final waveform = normalizeVoiceWaveform(
      List<num>.generate(120, (index) => index.isEven ? 1.5 : -0.5),
      maxBins: 24,
    );

    expect(waveform, hasLength(24));
    expect(waveform.every((value) => value >= 0 && value <= 1), isTrue);
  });
}
