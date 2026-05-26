import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../backend/models/semya.dart';
import '../providers/semya_details_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/share_browse_token_modal.dart';
import 'semya_invitations_list_screen.dart';

/// Ship FE2 (2026-05-26): семя details screen.
///
/// Surfaces:
///   * Header — имя семья + member count + caller's role chip
///   * Tree access tile («Открыть дерево») — placeholder в FE2, wired
///     к active tree navigation в FE4+
///   * Members section — list (avatar placeholder + name + role chip)
///   * Owner-only «Управление семьёй» tile — disabled placeholder, FE3
///     enable's rename/delete/role flows
///   * Invitations tile — disabled placeholder, FE3 surface
///
/// Loading state: full-screen progress center.
/// Error state: centered message + retry button.
/// Read-only at этой stage (mutation actions deferred к FE3/FE8).
class SemyaDetailsScreen extends StatefulWidget {
  const SemyaDetailsScreen({
    super.key,
    required this.semyaId,
  });

  final String semyaId;

  @override
  State<SemyaDetailsScreen> createState() => _SemyaDetailsScreenState();
}

class _SemyaDetailsScreenState extends State<SemyaDetailsScreen> {
  late final SemyaDetailsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SemyaDetailsController(semyaId: widget.semyaId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SemyaDetailsController>.value(
      value: _controller,
      child: Consumer<SemyaDetailsController>(
        builder: (context, controller, _) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                controller.details?.semya.name ?? 'Семья',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            body: _buildBody(context, controller),
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SemyaDetailsController controller,
  ) {
    if (controller.isLoading && !controller.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final details = controller.details;
    if (details == null) {
      return _ErrorState(
        message: controller.errorMessage ?? 'Семья не найдена',
        onRetry: controller.refresh,
      );
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _HeaderSection(
            details: details,
            memberCount: controller.memberships.length,
          ),
          const SizedBox(height: 8),
          _TreeAccessTile(treeId: details.semya.treeId),
          const _SectionHeader('Участники'),
          if (controller.memberships.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text('Пока нет других участников.'),
            )
          else
            ..._buildMemberRows(controller.memberships, details.callerRole),
          const _SectionHeader('Управление'),
          _OwnerOnlyTile(
            icon: Icons.settings_outlined,
            label: 'Управление семьёй',
            subtitle: 'Переименовать, удалить, изменить роли участников.',
            visibleAsOwner: details.callerRole == SemyaRole.owner,
            placeholder: 'Появится в следующем обновлении',
          ),
          // Ship FE3 (2026-05-26): «Приглашения» tile активен для всех
          // member'ов (viewer+) — даже non-inviter может see existing
          // invitations и понять контекст. Кнопка «Пригласить» в самом
          // списке gated by canInvite.
          ListTile(
            key: const Key('semya-details-invitations'),
            leading: const Icon(Icons.mail_outline_rounded),
            title: const Text('Приглашения'),
            subtitle: Text(
              details.canInvite
                  ? 'Отправить или отозвать приглашения.'
                  : 'Список приглашений семьи.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SemyaInvitationsListScreen(
                    semyaId: details.semya.id,
                    canInvite: details.canInvite,
                  ),
                ),
              );
            },
          ),
          // Ship FE6a (2026-05-26): «Поделиться деревом» tile —
          // generates browse-token capability link для read-only
          // viewing вне семя. Owner либо editor-с-grant only
          // (backend Ship 7 enforces); UI gate matches canInvite
          // since invite-grant required для editor case.
          if (details.canInvite)
            ListTile(
              key: const Key('semya-details-share-browse'),
              leading: const Icon(Icons.share_outlined),
              title: const Text('Поделиться деревом'),
              subtitle: const Text(
                'Создать ссылку для просмотра без регистрации.',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showShareBrowseTokenModal(
                context,
                semyaId: details.semya.id,
                semyaName: details.semya.name,
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _buildMemberRows(
    List<SemyaMembership> members,
    SemyaRole callerRole,
  ) {
    return members
        .map((m) => _MemberRow(membership: m, callerRole: callerRole))
        .toList(growable: false);
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.details,
    required this.memberCount,
  });

  final SemyaDetails details;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            details.semya.name,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if ((details.semya.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              details.semya.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Chip(
                icon: Icons.group_outlined,
                label: '$memberCount '
                    '${_memberCountLabel(memberCount)}',
              ),
              _RoleChip(role: details.callerRole),
            ],
          ),
        ],
      ),
    );
  }

  static String _memberCountLabel(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'участник';
    if ([2, 3, 4].contains(mod10) && ![12, 13, 14].contains(mod100)) {
      return 'участника';
    }
    return 'участников';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final SemyaRole role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (isDark ? RodnyaDesignTokens.dark : RodnyaDesignTokens.light);
    final Color background;
    final Color foreground;
    switch (role) {
      case SemyaRole.owner:
        background = theme.colorScheme.primary.withValues(alpha: 0.16);
        foreground = theme.colorScheme.primary;
        break;
      case SemyaRole.editor:
        background = tokens.warm.withValues(alpha: 0.18);
        foreground = tokens.warm;
        break;
      case SemyaRole.viewer:
      case SemyaRole.unknown:
        background = theme.colorScheme.surfaceContainerHighest;
        foreground = theme.colorScheme.onSurfaceVariant;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        role.displayLabel,
        style: theme.textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TreeAccessTile extends StatelessWidget {
  const _TreeAccessTile({required this.treeId});

  final String treeId;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const Key('semya-details-open-tree'),
      leading: const Icon(Icons.account_tree_rounded),
      title: const Text('Открыть дерево'),
      subtitle: Text('id: $treeId'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).maybePop(),
    );
  }
}

class _OwnerOnlyTile extends StatelessWidget {
  const _OwnerOnlyTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.visibleAsOwner,
    required this.placeholder,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool visibleAsOwner;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = visibleAsOwner;
    return ListTile(
      enabled: false, // FE2 — disabled placeholder for both states.
      leading: Icon(
        icon,
        color: isEnabled
            ? theme.colorScheme.onSurfaceVariant
            : theme.disabledColor,
      ),
      title: Text(label),
      subtitle: Text(isEnabled ? placeholder : subtitle),
      trailing: const Icon(Icons.lock_outline_rounded, size: 16),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.membership,
    required this.callerRole,
  });

  final SemyaMembership membership;
  final SemyaRole callerRole;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = _initialsOf(membership.userId);
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor:
            theme.colorScheme.primary.withValues(alpha: 0.16),
        child: Text(
          initials,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      title: Text(
        membership.userId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _formatJoinedAt(membership.joinedAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: _RoleChip(role: membership.role),
    );
  }

  static String _initialsOf(String userId) {
    if (userId.isEmpty) return '?';
    return userId.substring(0, userId.length.clamp(0, 2)).toUpperCase();
  }

  static String _formatJoinedAt(String iso) {
    if (iso.isEmpty) return '';
    // ISO date-only display — ignore time component для readability.
    final dot = iso.indexOf('T');
    if (dot > 0) {
      return 'Присоединился ${iso.substring(0, dot)}';
    }
    return 'Присоединился $iso';
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
              size: 36,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
