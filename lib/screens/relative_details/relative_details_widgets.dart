part of '../relative_details_screen.dart';

class _RelativeContactStatus {
  const _RelativeContactStatus({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
}

enum _RelativeGalleryAction {
  makePrimary,
  delete,
}

/// P0b: честная классификация отказа загрузки КРИТИЧЕСКОЙ части карточки
/// (резолв дерева / сам человек). Второстепенные данные деградируют
/// секциями и сюда не попадают.
enum _CardErrorKind {
  /// Сеть/сервер не ответили — лечится повтором.
  network,

  /// Человека нет ни в одном доступном дереве (удалён или ссылка устарела).
  notFound,

  /// Бэк ответил «нельзя» — карточка закрыта настройками доступа.
  accessDenied,
}

class _EditableRelationLink {
  const _EditableRelationLink({
    required this.relation,
    required this.relatedPerson,
    required this.relationFromRelatedPerson,
  });

  final FamilyRelation relation;
  final FamilyPerson relatedPerson;
  final RelationType relationFromRelatedPerson;
}

/// Результат резолва «в каком дереве живёт человек» (P0). Если по пути
/// человек уже был загружен — несём его с собой, чтобы не дёргать GET
/// второй раз. [sawAccessDenied] — по пути встречался 403/401: если
/// цепочка кончилась ничем, честная заглушка — «Карточка закрыта», а не
/// «не нашлась» (чанк C).
class _PersonTreeResolution {
  const _PersonTreeResolution({
    this.treeId,
    this.person,
    this.sawAccessDenied = false,
  });

  final String? treeId;
  final FamilyPerson? person;
  final bool sawAccessDenied;
}

class _BasicInfoRow {
  const _BasicInfoRow(this.label, this.value, {this.memorial = false});
  final String label;
  final String value;
  final bool memorial;
}

/// Bottom-of-card destructive button for «Удалить из дерева». Matches
/// the design's red-tinted ghost treatment (Bordered, transparent
/// fill, soft red ink) — destructive intent without screaming red.
class _DeleteRelativeButton extends StatelessWidget {
  const _DeleteRelativeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const dangerInk = Color(0xFFC0392B);
    final dangerLine = dangerInk.withValues(alpha: 0.32);
    final dangerSoft = dangerInk.withValues(alpha: 0.06);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? dangerSoft
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: dangerLine, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: dangerInk),
              const SizedBox(width: 8),
              Text(
                'Удалить из дерева',
                style: AppTheme.sans(
                  color: dangerInk,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плитка действия в шапке карточки: иконка + подпись в две строки,
/// одинаковая высота в ряду (IntrinsicHeight у родителя). Первичная —
/// заливка акцентом, остальные — тихая поверхность с тонкой рамкой.
class _HeroActionTile extends StatelessWidget {
  const _HeroActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokensOf(context);
    final enabled = onTap != null;
    final background = primary ? tokens.accent : tokens.surfaceStrong;
    final foreground = primary ? tokens.accentInk : tokens.ink;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: primary
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tokens.surfaceLine, width: 0.8),
                  ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: foreground),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.sans(
                    color: foreground,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// MVP-1.1 «Спросить историю»: pure, synchronous merge for the «Кого
/// спросить» step's chip list (STORY-REQUEST-MVP1-BRIEF.md §3.3 + семья
/// extension — see docs/connected-trees-refactor/CURRENT-PHASE.md).
/// Order: герой (if their account isn't the viewer's) → tree members with
/// their own person in this tree → remaining семья members who have no
/// persona of their own here. Deduped by userId, viewer excluded
/// throughout. The backend already accepts any семья member as an
/// addressee (`store._isUserInTreeOrSemya`) — this only surfaces them
/// client-side. Top-level (not an instance method) so it's unit-testable
/// without a widget tree — see test/family_story_ask_targets_test.dart.
List<FamilyStoryAskTarget> buildStoryAskTargets({
  required FamilyPerson heroPerson,
  required String heroDisplayName,
  required List<FamilyPerson> treePeople,
  required List<SemyaMembership> semyaMembers,
  required String? currentUserId,
}) {
  final heroUserId = heroPerson.userId;
  final targets = <FamilyStoryAskTarget>[];
  if (heroUserId != null &&
      heroUserId.isNotEmpty &&
      heroUserId != currentUserId) {
    targets.add(FamilyStoryAskTarget(
      userId: heroUserId,
      displayName: '${_selfAskPrefix(heroPerson.gender)} $heroDisplayName',
      photoUrl: normalizePhotoUrl(heroPerson.photoUrl),
      isHero: true,
    ));
  }
  final seen = targets.map((t) => t.userId).toSet();
  for (final p in treePeople) {
    final uid = p.userId;
    if (uid == null || uid.isEmpty) continue;
    if (uid == currentUserId || !seen.add(uid)) continue;
    targets.add(
      FamilyStoryAskTarget(
          userId: uid,
          displayName: p.name,
          photoUrl: normalizePhotoUrl(p.photoUrl)),
    );
  }
  for (final m in semyaMembers) {
    final uid = m.userId;
    if (uid.isEmpty) continue;
    if (uid == currentUserId || !seen.add(uid)) continue;
    targets.add(
      FamilyStoryAskTarget(
        userId: uid,
        displayName: _semyaMemberDisplayName(m),
        photoUrl: normalizePhotoUrl(m.avatarUrl),
      ),
    );
  }
  return targets;
}

/// Chip label for a семья member with no persona in this tree. Deliberately
/// NOT `SemyaMembership.displayLabel` (which falls back to the raw userId)
/// — a bare id in a chip is confusing product copy, not a person's name.
String _semyaMemberDisplayName(SemyaMembership membership) {
  final name = membership.displayName?.trim();
  return (name != null && name.isNotEmpty) ? name : 'Участник семьи';
}

/// «Сама Лида» / «Сам Артём» — gender-aware so the chip doesn't read like
/// a form field («сам(а)»). Falls back to the slash notation only when
/// gender genuinely isn't known.
String _selfAskPrefix(Gender gender) {
  switch (gender) {
    case Gender.female:
      return 'Сама';
    case Gender.male:
      return 'Сам';
    case Gender.other:
    case Gender.unknown:
      return 'Сам(а)';
  }
}
