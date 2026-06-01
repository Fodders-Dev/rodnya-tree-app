// Viewer phase — SUB-CHUNK 1 (2026-06-01): the «Биография» section on a
// relative's profile. Read-first — visible to ANY card viewer (read is
// can-view-person; the backend GET is gated by tree access, not edit).
//
// Self-loads the article via the registered ProfileArticleServiceInterface
// and renders it read-only (ArticleReadView). The edit affordance (✏️ when
// non-empty, «Добавить историю» CTA when empty) is shown only to editors
// (canEdit = the caller's _canDirectEditProfile) and opens the existing
// ProfileArticleEditorScreen; the section reloads on return.
//
// Empty + viewer → renders nothing (no phantom gap). This is the
// permanent read entry; it replaces the temporary «Биография (бета)» pill.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/profile_article_service_interface.dart';
import '../backend/models/profile_article.dart';
import '../screens/profile_article_editor_screen.dart';
import 'article_read_view.dart';

class ProfileBiographySection extends StatefulWidget {
  const ProfileBiographySection({
    super.key,
    required this.personId,
    required this.fullName,
    required this.canEdit,
    this.relation,
    this.gender,
    this.serviceOverride,
  });

  final String personId;
  final String fullName;

  /// Whether the viewer may edit this person (caller's _canDirectEditProfile).
  /// Gates the ✏️ / «Добавить историю» affordances only — reading is open.
  final bool canEdit;
  final String? relation;
  final String? gender;

  /// Test seam — production resolves ProfileArticleServiceInterface via GetIt.
  final ProfileArticleServiceInterface? serviceOverride;

  @override
  State<ProfileBiographySection> createState() =>
      _ProfileBiographySectionState();
}

class _ProfileBiographySectionState extends State<ProfileBiographySection> {
  bool _loaded = false;
  List<ArticleBlock> _blocks = const [];

  @override
  void initState() {
    super.initState();
    // Post-frame: _load may setState synchronously (e.g. when no service is
    // registered) — that must not run during initState.
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
      if (mounted) setState(() => _loaded = true);
      return;
    }
    try {
      final article = await svc.getArticle(widget.personId);
      if (!mounted) return;
      setState(() {
        _blocks = article.blocks;
        _loaded = true;
      });
    } catch (_) {
      // A failed bio load must not break the profile — treat as empty.
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _openEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileArticleEditorScreen(
          personId: widget.personId,
          personName: widget.fullName,
          personRelation: widget.relation,
          personGender: widget.gender,
        ),
      ),
    );
    if (mounted) _load(); // reflect any edits
  }

  @override
  Widget build(BuildContext context) {
    // Silent until loaded, and silent when there's nothing to show for a
    // viewer — no phantom section gap on the profile.
    if (!_loaded) return const SizedBox.shrink();
    final hasContent = _blocks.isNotEmpty;
    if (!hasContent && !widget.canEdit) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      key: const Key('biography-section'),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Биография',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontFamily: 'Lora',
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (widget.canEdit && hasContent)
                IconButton(
                  key: const Key('biography-edit'),
                  tooltip: 'Редактировать',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _openEditor,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasContent)
            ArticleReadView(blocks: _blocks)
          else
            _emptyCta(theme),
        ],
      ),
    );
  }

  Widget _emptyCta(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Биография ещё не написана.',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'Lora',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          key: const Key('biography-add'),
          onPressed: _openEditor,
          icon: const Icon(Icons.auto_stories_outlined, size: 18),
          label: const Text('Добавить историю'),
        ),
      ],
    );
  }
}
