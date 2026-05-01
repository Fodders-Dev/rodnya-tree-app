import 'dart:math' as math;
import 'dart:typed_data';

const int defaultVoiceWaveformBinCount = 64;
const int maxVoiceWaveformBinCount = 100;

List<double> normalizeVoiceWaveform(
  dynamic raw, {
  int maxBins = maxVoiceWaveformBinCount,
}) {
  if (raw is! Iterable) {
    return const <double>[];
  }

  final samples = raw
      .map((value) =>
          value is num ? value.toDouble() : double.tryParse('$value'))
      .whereType<double>()
      .where((value) => value.isFinite)
      .map((value) => value.clamp(0.0, 1.0).toDouble())
      .toList(growable: false);
  if (samples.isEmpty) {
    return const <double>[];
  }

  return downsampleVoiceWaveform(samples, maxBins: maxBins);
}

List<double> downsampleVoiceWaveform(
  List<double> samples, {
  int maxBins = defaultVoiceWaveformBinCount,
}) {
  if (samples.isEmpty || maxBins <= 0) {
    return const <double>[];
  }
  final normalizedSamples = samples
      .where((value) => value.isFinite)
      .map((value) => value.clamp(0.0, 1.0).toDouble())
      .toList(growable: false);
  if (normalizedSamples.isEmpty) {
    return const <double>[];
  }
  if (normalizedSamples.length <= maxBins) {
    return List<double>.unmodifiable(normalizedSamples);
  }

  final bucketSize = normalizedSamples.length / maxBins;
  final result = <double>[];
  for (var bucket = 0; bucket < maxBins; bucket++) {
    final start = (bucket * bucketSize).floor();
    final end = math.min(
      normalizedSamples.length,
      ((bucket + 1) * bucketSize).ceil(),
    );
    if (start >= end) {
      continue;
    }
    var sum = 0.0;
    for (var index = start; index < end; index++) {
      sum += normalizedSamples[index];
    }
    result.add((sum / (end - start)).clamp(0.0, 1.0).toDouble());
  }
  return List<double>.unmodifiable(result);
}

List<double> buildVoiceWaveformFromBytes(
  Uint8List bytes, {
  int bins = defaultVoiceWaveformBinCount,
}) {
  if (bytes.isEmpty || bins <= 0) {
    return const <double>[];
  }

  final sampleCount = math.min(bins, bytes.length);
  final bucketSize = (bytes.length / sampleCount).ceil();
  final values = <double>[];

  for (var start = 0; start < bytes.length; start += bucketSize) {
    final end = math.min(bytes.length, start + bucketSize);
    var sumSquares = 0.0;
    for (var index = start; index < end; index++) {
      final centered = (bytes[index] - 128).abs() / 128.0;
      sumSquares += centered * centered;
    }
    values.add(math.sqrt(sumSquares / math.max(1, end - start)));
  }

  final maxValue = values.fold<double>(0, math.max);
  if (maxValue <= 0) {
    return List<double>.unmodifiable(
      List<double>.filled(values.length, 0.08),
    );
  }

  return List<double>.unmodifiable(
    values
        .map((value) => (value / maxValue).clamp(0.04, 1.0).toDouble())
        .toList(growable: false),
  );
}
