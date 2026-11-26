part of '../chat_screen.dart';

class _ChatMessageUrlMatch {
  const _ChatMessageUrlMatch({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;
}

class _HighlightedMessageText extends StatefulWidget {
  const _HighlightedMessageText({
    required this.text,
    required this.query,
    required this.color,
  });

  final String text;
  final String query;
  final Color color;

  @override
  State<_HighlightedMessageText> createState() =>
      _HighlightedMessageTextState();
}

class _HighlightedMessageTextState extends State<_HighlightedMessageText> {
  final List<TapGestureRecognizer> _linkRecognizers = <TapGestureRecognizer>[];
  bool _expanded = false;

  bool get _isLong => widget.text.length > _kLongMessageCollapseAt;

  String get _renderedText {
    if (_expanded || !_isLong) return widget.text;
    // Trim to a safe character count, then back off to the nearest
    // whitespace so we don't slice through a word mid-letter.
    final hardCap = widget.text.substring(0, _kLongMessageCollapseAt);
    final lastWhitespace = hardCap.lastIndexOf(RegExp(r'\s'));
    final softCap = lastWhitespace > _kLongMessageCollapseAt - 80
        ? hardCap.substring(0, lastWhitespace)
        : hardCap;
    return '$softCap…';
  }

  @override
  void dispose() {
    _disposeLinkRecognizers();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _HighlightedMessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the user types into the search bar we want any long
    // message that contains a hit to expand automatically — otherwise
    // a match buried past the truncation point is invisible.
    final query = widget.query.trim();
    if (!_expanded && query.isNotEmpty && _isLong) {
      final hit = widget.text.toLowerCase().indexOf(query.toLowerCase());
      if (hit >= _kLongMessageCollapseAt) {
        _expanded = true;
      }
    }
  }

  void _disposeLinkRecognizers() {
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeLinkRecognizers();
    final normalizedQuery = widget.query.trim();
    final body = _renderedText;
    final color = widget.color;

    final textWidget = _buildTextWidget(
      context: context,
      body: body,
      normalizedQuery: normalizedQuery,
      color: color,
    );

    if (!_isLong) return textWidget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        textWidget,
        const SizedBox(height: 4),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              _expanded ? 'Свернуть' : 'Показать ещё',
              style: TextStyle(
                color: color.withValues(alpha: 0.85),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: color.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextWidget({
    required BuildContext context,
    required String body,
    required String normalizedQuery,
    required Color color,
  }) {
    final urlMatches = _findUrlMatches(body);
    if (normalizedQuery.isEmpty && urlMatches.isEmpty) {
      return Text(
        body,
        // M3 (50+): 16/1.3 — раньше 14.5 по веб-референсу, но на
        // 720×1560 старшим читать тяжело; 16 — минимум для сообщений.
        // Плотность (чанк 22): 1.35 → 1.3 (спека), 16sp не трогаем.
        style: TextStyle(
          color: color,
          fontSize: 16,
          height: 1.3,
        ),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textBrightness = ThemeData.estimateBrightnessForColor(color);
    final linkColor = textBrightness == Brightness.dark
        ? scheme.primary
        : scheme.primaryContainer;
    final baseStyle = TextStyle(
      color: color,
      fontSize: 16,
      height: 1.3,
    );
    final linkStyle = baseStyle.copyWith(
      color: linkColor,
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
      decorationColor: linkColor.withValues(alpha: 0.7),
    );
    final spans = <TextSpan>[];
    var currentIndex = 0;

    for (final match in urlMatches) {
      if (match.start < currentIndex) {
        continue;
      }
      if (match.start > currentIndex) {
        _appendHighlightedSpans(
          spans: spans,
          text: body.substring(currentIndex, match.start),
          query: normalizedQuery,
          style: baseStyle,
        );
      }

      final recognizer = TapGestureRecognizer()
        ..onTap = () => unawaited(_openMessageUrl(match.text));
      _linkRecognizers.add(recognizer);
      _appendHighlightedSpans(
        spans: spans,
        text: match.text,
        query: normalizedQuery,
        style: linkStyle,
        recognizer: recognizer,
      );
      currentIndex = match.end;
    }

    if (currentIndex < body.length) {
      _appendHighlightedSpans(
        spans: spans,
        text: body.substring(currentIndex),
        query: normalizedQuery,
        style: baseStyle,
      );
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  List<_ChatMessageUrlMatch> _findUrlMatches(String text) {
    final matches = <_ChatMessageUrlMatch>[];
    for (final match in _chatMessageUrlPattern.allMatches(text)) {
      final raw = match.group(0);
      if (raw == null || raw.trim().isEmpty) {
        continue;
      }
      final trimmed = _trimTrailingUrlPunctuation(raw);
      if (trimmed.isEmpty) {
        continue;
      }
      matches.add(
        _ChatMessageUrlMatch(
          start: match.start,
          end: match.start + trimmed.length,
          text: trimmed,
        ),
      );
    }
    return matches;
  }

  String _trimTrailingUrlPunctuation(String value) {
    var end = value.length;
    while (end > 0) {
      final char = value[end - 1];
      if (char == '.' ||
          char == ',' ||
          char == '!' ||
          char == '?' ||
          char == ';' ||
          char == ':' ||
          char == ')' ||
          char == ']' ||
          char == '}' ||
          char == '"' ||
          char == '\'' ||
          char == '»') {
        end -= 1;
        continue;
      }
      break;
    }
    return value.substring(0, end);
  }

  void _appendHighlightedSpans({
    required List<TextSpan> spans,
    required String text,
    required String query,
    required TextStyle style,
    GestureRecognizer? recognizer,
  }) {
    if (text.isEmpty) {
      return;
    }
    if (query.isEmpty) {
      spans.add(
        TextSpan(
          text: text,
          style: style,
          recognizer: recognizer,
        ),
      );
      return;
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    var currentIndex = 0;
    while (currentIndex < text.length) {
      final nextMatch = lowerText.indexOf(lowerQuery, currentIndex);
      if (nextMatch == -1) {
        spans.add(
          TextSpan(
            text: text.substring(currentIndex),
            style: style,
            recognizer: recognizer,
          ),
        );
        break;
      }
      if (nextMatch > currentIndex) {
        spans.add(
          TextSpan(
            text: text.substring(currentIndex, nextMatch),
            style: style,
            recognizer: recognizer,
          ),
        );
      }
      final matchEnd = nextMatch + query.length;
      spans.add(
        TextSpan(
          text: text.substring(nextMatch, matchEnd),
          style: style.copyWith(
            backgroundColor: Colors.amber.withValues(alpha: 0.55),
            fontWeight: FontWeight.w800,
          ),
          recognizer: recognizer,
        ),
      );
      currentIndex = matchEnd;
    }
  }

  Future<void> _openMessageUrl(String rawUrl) async {
    final uri = _normalizeMessageUrl(rawUrl);
    if (uri == null) {
      return;
    }

    final internalRoute = _internalRouteFor(uri);
    if (internalRoute != null) {
      if (!mounted) {
        return;
      }
      GoRouter.of(context).go(internalRoute);
      return;
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await launchUrl(uri);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку.')),
      );
    }
  }

  Uri? _normalizeMessageUrl(String rawUrl) {
    var value = rawUrl.trim();
    if (value.isEmpty) {
      return null;
    }
    if (value.startsWith('www.')) {
      value = 'https://$value';
    } else if (!value.contains('://')) {
      value = 'https://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    return uri;
  }

  String? _internalRouteFor(Uri uri) {
    final host = uri.host.toLowerCase();
    final isRodnyaHost =
        host == 'rodnya-tree.ru' || host == 'www.rodnya-tree.ru';
    if (!isRodnyaHost) {
      return null;
    }

    final fragment = uri.fragment.trim();
    if (fragment.startsWith('/')) {
      return fragment;
    }

    final path = uri.path.trim().isEmpty ? '/' : uri.path.trim();
    final route = uri.hasQuery ? '$path?${uri.query}' : path;
    return route == '/' ? null : route;
  }
}
