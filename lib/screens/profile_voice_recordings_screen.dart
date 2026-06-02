// Viewer §3.2.5 (sub-chunk 2b, 2026-06-02): «Голосовые записи» — a quick
// list of every audio block in a person's biography article. Reuses the
// read-only ArticleAudioBlock player (play / pause / seek, no edit menu);
// each entry is labelled with its section («Раздел «Детство»») + duration
// and who recorded it (when resolvable). Especially valuable for the
// departed — the living voice, prominently accessible.
//
// Self-loads the article via ProfileArticleServiceInterface (mirrors
// ProfileBiographySection). Read-only — no mutation.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/profile_article_service_interface.dart';
import '../backend/models/profile_article.dart';
import '../widgets/article_audio_block.dart';

/// One audio block paired with the section it sits under + its author.
class _VoiceEntry {
  const _VoiceEntry({required this.block, this.sectionTitle, this.author});
  final ArticleBlock block;
  final String? sectionTitle;
  final String? author;
}

class ProfileVoiceRecordingsScreen extends StatefulWidget {
  const ProfileVoiceRecordingsScreen({
    super.key,
    required this.personId,
    required this.personName,
    this.authorNames = const {},
    this.serviceOverride,
  });

  final String personId;
  final String personName;

  /// userId → display name, for the «Записал(а) …» line.
  final Map<String, String> authorNames;

  /// Test seam — production resolves the service via GetIt.
  final ProfileArticleServiceInterface? serviceOverride;

  @override
  State<ProfileVoiceRecordingsScreen> createState() =>
      _ProfileVoiceRecordingsScreenState();
}

class _ProfileVoiceRecordingsScreenState
    extends State<ProfileVoiceRecordingsScreen> {
  bool _loading = true;
  List<_VoiceEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  ProfileArticleServiceInterface? _service() {
    if (widget.serviceOverride != null) return widget.serviceOverride;
    if (GetIt.I.isRegistered<ProfileArticleServiceInterface>()) {
      return GetIt.I<ProfileArticleServiceInterface>();
    }
    return null;
  }

  Future<void> _load() async {
    final svc = _service();
    if (svc == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final article = await svc.getArticle(widget.personId);
      if (!mounted) return;
      setState(() {
        _entries = _collect(article.blocks);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Walk the article in order; each audio block inherits the nearest
  // preceding header as its section, and its author (when known).
  List<_VoiceEntry> _collect(List<ArticleBlock> blocks) {
    final out = <_VoiceEntry>[];
    String? section;
    for (final b in blocks) {
      if (b.isHeader) {
        final t = b.headerText.trim();
        section = t.isEmpty ? null : t;
      } else if (b.isAudio) {
        final authorId = b.authorUserId ?? b.createdByUserId;
        out.add(_VoiceEntry(
          block: b,
          sectionTitle: section,
          author: authorId == null ? null : widget.authorNames[authorId],
        ));
      }
    }
    return out;
  }

  String _fmtDuration(int? sec) {
    if (sec == null || sec <= 0) return '';
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Голосовые записи')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _empty(theme)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 18),
                  itemBuilder: (_, i) => _entryCard(theme, _entries[i]),
                ),
    );
  }

  Widget _entryCard(ThemeData theme, _VoiceEntry entry) {
    final duration = _fmtDuration(entry.block.audioDurationSec);
    final titleParts = <String>[
      entry.sectionTitle != null
          ? 'Раздел «${entry.sectionTitle}»'
          : 'Запись голоса',
      if (duration.isNotEmpty) duration,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.graphic_eq_rounded,
                size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                titleParts.join(' · '),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: 'Lora',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (entry.author != null && entry.author!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 2),
            child: Text(
              'Записал(а) ${entry.author}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ArticleAudioBlock(
          key: Key('voice-entry-${entry.block.id}'),
          block: entry.block,
          readOnly: true,
        ),
      ],
    );
  }

  Widget _empty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_none_rounded,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'Здесь появятся голосовые записи',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'Lora',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Запишите живой голос в биографии — он соберётся здесь.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
