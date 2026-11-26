import 'dart:convert';

/// Attempts to decode [rawBody] as JSON. Returns `null` when [rawBody] is
/// empty or not valid JSON (e.g. HTML 502/504 gateway error pages).
dynamic tryDecodeJsonValue(String rawBody) {
  if (rawBody.trim().isEmpty) return null;
  try {
    return jsonDecode(rawBody);
  } on FormatException {
    return null;
  }
}

/// Decodes [rawBody] into a `Map<String, dynamic>` when possible, or wraps a
/// non-map JSON value under `'data'`. Returns `null` when [rawBody] is empty or
/// not valid JSON.
Map<String, dynamic>? tryDecodeJsonMap(String rawBody) {
  final decoded = tryDecodeJsonValue(rawBody);
  if (decoded == null) return null;
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return <String, dynamic>{'data': decoded};
}
