// Viewer §3.2.4 (2026-06-02): «История изменений» — the biography
// article's change log. Reads GET /v1/persons/:id/article/history (the
// backend filters treeChangeRecords to `article.*` for this person,
// newest-first). Each entry is humanized («Артём добавил фото»,
// «отредактировал абзац», «удалил галерею», «изменил порядок блоков»),
// the actor resolved to a name (like §3.1 «Соавторы»), with a date·time.
//
// This is the ARTICLE history only — distinct from the inline tree-level
// «История изменений» (all TreeChangeRecord, not just article.*). Read-
// access: visible to any card viewer. Self-loads; no mutation.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/profile_article_service_interface.dart';
import '../backend/models/profile_article.dart';

class ProfileArticleHistoryScreen extends StatefulWidget {
  const ProfileArticleHistoryScreen({
    super.key,
    required this.personId,
    required this.personName,
    this.actorNames = const {},
    this.serviceOverride,
  });

  final String personId;
  final String personName;

  /// userId → display name, for the actor («Артём добавил …»).
  final Map<String, String> actorNames;

  /// Test seam — production resolves the service via GetIt.
  final ProfileArticleServiceInterface? serviceOverride;

  @override
  State<ProfileArticleHistoryScreen> createState() =>
      _ProfileArticleHistoryScreenState();
}

class _ProfileArticleHistoryScreenState
    extends State<ProfileArticleHistoryScreen> {
  bool _loading = true;
  List<ArticleHistoryEntry> _entries = const [];

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
      final entries = await svc.getArticleHistory(widget.personId);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _actorName(String? actorId) {
    if (actorId == null) return 'Кто-то из семьи';
    final name = widget.actorNames[actorId];
    return (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : 'Кто-то из семьи';
  }

  // Accusative noun for «добавил <X>» / «удалил <X>».
  String _blockNoun(String? blockType) {
    switch (blockType) {
      case 'paragraph':
        return 'абзац';
      case 'header':
        return 'заголовок';
      case 'photo':
        return 'фото';
      case 'gallery':
        return 'галерею';
      case 'audio':
        return 'голосовую запись';
      case 'quote':
        return 'цитату';
      case 'divider':
        return 'разделитель';
      default:
        return 'блок';
    }
  }

  // Gender-neutral «(а)» verbs — the actor's gender isn't carried by the
  // log, only the name.
  String _humanize(ArticleHistoryEntry entry) {
    final actor = _actorName(entry.actorId);
    final noun = _blockNoun(entry.blockType);
    switch (entry.type) {
      case 'article.block-added':
        return '$actor добавил(а) $noun';
      case 'article.block-updated':
        return '$actor отредактировал(а) $noun';
      case 'article.block-removed':
        return '$actor удалил(а) $noun';
      case 'article.reordered':
        return '$actor изменил(а) порядок блоков';
      default:
        return '$actor изменил(а) биографию';
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'article.block-added':
        return Icons.add_circle_outline;
      case 'article.block-updated':
        return Icons.edit_outlined;
      case 'article.block-removed':
        return Icons.remove_circle_outline;
      case 'article.reordered':
        return Icons.swap_vert_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  String _fmtDateTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    final month = months[dt.month - 1];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $month, $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('История изменений')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _empty(theme)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 24,
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  itemBuilder: (_, i) => _entryRow(theme, _entries[i]),
                ),
    );
  }

  Widget _entryRow(ThemeData theme, ArticleHistoryEntry entry) {
    final when = _fmtDateTime(entry.createdAt);
    return Row(
      key: Key('history-entry-${entry.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_icon(entry.type), size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (when.isNotEmpty)
                Text(
                  when,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                _humanize(entry),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontFamily: 'Lora',
                  height: 1.3,
                ),
              ),
            ],
          ),
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
            Icon(Icons.history_rounded,
                size: 48,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'Пока нет изменений',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'Lora',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Здесь появится, кто и когда правил биографию.',
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
