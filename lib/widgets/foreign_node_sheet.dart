import 'package:flutter/material.dart';

import '../backend/interfaces/blood_relation_capable_family_tree_service.dart';
import '../backend/models/blood_relation.dart';
import '../backend/models/extended_network_slice.dart';
import '../models/family_person.dart';

/// Phase 4 chunk 4a (PHASE-4-PROPOSAL.md §5.A Element 3 + §2.6
/// + DECISIONS.md 2026-05-12 Q4.A): foreign node tap-sheet.
///
/// Opens when user taps foreign node на canvas (через
/// InteractiveFamilyTree.onForeignNodeTap host callback). Contains:
///   • foreign person preview (name + dates)
///   • owner identity (avatar full-size + displayName + @handle)
///   • lazy relation-to-me row (FutureBuilder, fetched on open)
///   • actions: «Открыть карточку» / «Написать @owner»
///
/// **Excluded** per DECISIONS.md 2026-05-12 Q4.A:
///   • НЕТ «Попросить доступ» button (Phase 5+).
///   • НЕТ edit actions (no grants → read-only).
///   • НЕТ sensitive contacts (owner-only-всегда; backend filters).
///   • НЕТ «открыть в дереве владельца» (privacy regression).
class ForeignNodeSheet extends StatelessWidget {
  const ForeignNodeSheet({
    required this.person,
    required this.slice,
    required this.bloodRelationService,
    required this.onOpenCard,
    required this.onWriteToOwner,
    super.key,
  });

  /// Foreign person тапнутый user'ом.
  final FamilyPerson person;

  /// Slice contains owner info (`slice.getOwnerInfo(person.identityId
  /// ?? person.id)`) + viewer self-node id для relation fetch.
  final ExtendedNetworkSlice slice;

  /// Service для lazy fetch relation-to-me.
  final BloodRelationCapableFamilyTreeService bloodRelationService;

  /// Triggers navigation на `/relative/details/:id`. Phase 3.2 backend
  /// gates filter sensitive contacts / edit / delete для viewer'а —
  /// UI just renders whatever returned.
  final VoidCallback onOpenCard;

  /// Triggers chat flow с owner userId. Existing infrastructure
  /// «open or create» chat между two users.
  final ValueChanged<String> onWriteToOwner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ownerInfo = slice.getOwnerInfo(person.identityId ?? person.id);
    final selfId = slice.viewerSelfGraphPersonId;
    final foreignGraphPersonId = person.identityId ?? person.id;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _PersonHeader(person: person),
            const SizedBox(height: 18),
            const _SectionLabel('Кто это добавил'),
            const SizedBox(height: 6),
            _OwnerRow(ownerInfo: ownerInfo),
            const SizedBox(height: 18),
            const _SectionLabel('Как связаны со мной'),
            const SizedBox(height: 6),
            _RelationRow(
              service: bloodRelationService,
              selfGraphPersonId: selfId,
              foreignGraphPersonId: foreignGraphPersonId,
            ),
            const SizedBox(height: 22),
            _ActionRow(
              onOpenCard: onOpenCard,
              ownerUserId: ownerInfo?.userId,
              ownerDisplayName: ownerInfo?.displayName,
              onWriteToOwner: onWriteToOwner,
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonHeader extends StatelessWidget {
  const _PersonHeader({required this.person});

  final FamilyPerson person;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lifeRange = _lifeRange(person);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          backgroundImage: person.photoUrl != null && person.photoUrl!.isNotEmpty
              ? NetworkImage(person.photoUrl!)
              : null,
          child: (person.photoUrl == null || person.photoUrl!.isEmpty)
              ? Text(
                  _initialsOf(person.name),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                person.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (lifeRange != null)
                Text(
                  lifeRange,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String? _lifeRange(FamilyPerson person) {
    final birth = person.birthDate?.year.toString();
    final death = person.deathDate?.year.toString();
    if (birth == null && death == null) return null;
    return '${birth ?? '?'} — ${death ?? (person.isAlive ? '' : '?')}'.trim();
  }

  static String _initialsOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _OwnerRow extends StatelessWidget {
  const _OwnerRow({required this.ownerInfo});

  final ExtendedNetworkOwnerInfo? ownerInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (ownerInfo == null || ownerInfo!.userId == null) {
      // Anonymous foreign person — creator не привязан к user-аккаунту
      // (e.g. бабушка добавленная Степой без claim'а).
      return Text(
        'Карточка без аккаунта (создана незарегистрированным пользователем)',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    final info = ownerInfo!;
    final hasPhoto = info.photoUrl != null && info.photoUrl!.isNotEmpty;
    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: theme.colorScheme.primaryContainer,
          backgroundImage: hasPhoto ? NetworkImage(info.photoUrl!) : null,
          child: hasPhoto
              ? null
              : Text(
                  _initials(info.displayName ?? ''),
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.displayName?.trim().isNotEmpty == true
                    ? info.displayName!
                    : 'Без имени',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _RelationRow extends StatelessWidget {
  const _RelationRow({
    required this.service,
    required this.selfGraphPersonId,
    required this.foreignGraphPersonId,
  });

  final BloodRelationCapableFamilyTreeService service;
  final String? selfGraphPersonId;
  final String foreignGraphPersonId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (selfGraphPersonId == null || selfGraphPersonId!.isEmpty) {
      return _RelationCopy(
        text: 'Связь не найдена в видимом графе',
        muted: true,
      );
    }
    return FutureBuilder<BloodRelation>(
      future: service.findBloodRelation(
        fromGraphPersonId: selfGraphPersonId!,
        toGraphPersonId: foreignGraphPersonId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                'Считаем связь...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        }
        if (snapshot.hasError) {
          return _RelationCopy(
            text: 'Не удалось вычислить связь',
            muted: true,
          );
        }
        final relation = snapshot.data;
        if (relation == null || !relation.found) {
          return _RelationCopy(
            text: 'Связь не найдена в видимом графе',
            muted: true,
          );
        }
        return _RelationCopy(
          text: relation.label,
          subtitle: _degreeCaption(relation.degree),
        );
      },
    );
  }

  static String? _degreeCaption(int? degree) {
    if (degree == null || degree <= 0) return null;
    return 'через $degree ${_pluralHops(degree)} по родне';
  }

  static String _pluralHops(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'шаг';
    if ([2, 3, 4].contains(mod10) && ![12, 13, 14].contains(mod100)) {
      return 'шага';
    }
    return 'шагов';
  }
}

class _RelationCopy extends StatelessWidget {
  const _RelationCopy({
    required this.text,
    this.subtitle,
    this.muted = false,
  });

  final String text;
  final String? subtitle;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: muted
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
            fontStyle: muted ? FontStyle.italic : FontStyle.normal,
            fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.onOpenCard,
    required this.ownerUserId,
    required this.ownerDisplayName,
    required this.onWriteToOwner,
  });

  final VoidCallback onOpenCard;
  final String? ownerUserId;
  final String? ownerDisplayName;
  final ValueChanged<String> onWriteToOwner;

  @override
  Widget build(BuildContext context) {
    final canChat = ownerUserId != null && ownerUserId!.isNotEmpty;
    final chatLabel = canChat
        ? 'Написать ${ownerDisplayName?.trim().isNotEmpty == true ? ownerDisplayName : 'владельцу'}'
        : 'Чат недоступен';
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: onOpenCard,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Открыть карточку'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                canChat ? () => onWriteToOwner(ownerUserId!) : null,
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text(chatLabel, overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
        ),
      ],
    );
  }
}

/// Helper для открытия sheet'а из host (tree_view_screen).
Future<void> showForeignNodeSheet(
  BuildContext context, {
  required FamilyPerson person,
  required ExtendedNetworkSlice slice,
  required BloodRelationCapableFamilyTreeService bloodRelationService,
  required VoidCallback onOpenCard,
  required ValueChanged<String> onWriteToOwner,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false, // custom handle above
    builder: (sheetContext) {
      return ForeignNodeSheet(
        person: person,
        slice: slice,
        bloodRelationService: bloodRelationService,
        onOpenCard: () {
          Navigator.of(sheetContext).pop();
          onOpenCard();
        },
        onWriteToOwner: (userId) {
          Navigator.of(sheetContext).pop();
          onWriteToOwner(userId);
        },
      );
    },
  );
}
