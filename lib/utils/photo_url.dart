import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

String? normalizePhotoUrl(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return null;
  }

  if (uri.scheme == 'http' && !_isLocalHost(uri.host)) {
    return uri.replace(scheme: 'https').toString();
  }

  return trimmed;
}

ImageProvider<Object>? buildAvatarImageProvider(String? raw) {
  final normalized = normalizePhotoUrl(raw);
  if (normalized == null || !_isRenderableNetworkImageUrl(normalized)) {
    return null;
  }

  return CachedNetworkImageProvider(normalized);
}

bool _isRenderableNetworkImageUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) {
    return false;
  }

  return uri.scheme == 'https' || uri.scheme == 'http';
}

bool _isLocalHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}
