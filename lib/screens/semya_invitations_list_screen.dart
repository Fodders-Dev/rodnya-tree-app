import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../backend/models/semya_invitation.dart';
import '../providers/semya_invitations_controller.dart';
import 'semya_invite_screen.dart';

/// Ship FE3 (2026-05-26): семя invitations list screen. Shows all
/// sent invitations с status badges + per-row actions.
///
/// Actions:
///   • pending → «Скопировать ссылку», «Отозвать»
///   • terminal (accepted/revoked/expired) → read-only с status badge
///
/// CTA в app bar: «Пригласить» → SemyaInviteScreen.
class SemyaInvitationsListScreen extends StatefulWidget {
  const SemyaInvitationsListScreen({
    super.key,
    required this.semyaId,
    required this.canInvite,
  });

  final String semyaId;
  final bool canInvite;

  @override
  State<SemyaInvitationsListScreen> createState() =>
      _SemyaInvitationsListScreenState();
}

class _SemyaInvitationsListScreenState
    extends State<SemyaInvitationsListScreen> {
  late final SemyaInvitationsController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        SemyaInvitationsController(semyaId: widget.semyaId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openInviteScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SemyaInviteScreen(semyaId: widget.semyaId),
      ),
    );
    // Refresh после возврата — если invitation создалось, list updates.
    if (mounted) await _controller.refresh();
  }

  Future<void> _confirmRevoke(SemyaInvitation invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Отозвать приглашение?'),
          content: Text(
            'Приглашение для ${invitation.recipientLabel} больше нельзя будет использовать.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton.tonal(
              key: const Key('semya-invitation-revoke-confirm'),
              style: FilledButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
                backgroundColor:
                    Theme.of(dialogContext).colorScheme.errorContainer,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Отозвать'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final ok = await _controller.revoke(invitation.id);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Приглашение отозвано')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_controller.errorMessage ?? 'Не удалось отозвать'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  Future<void> _copyLink(SemyaInvitation invitation) async {
    final link =
        'https://rodnya-tree.ru/invite/${invitation.token}';
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка скопирована')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SemyaInvitationsController>.value(
      value: _controller,
      child: Consumer<SemyaInvitationsController>(
        builder: (context, controller, _) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Приглашения'),
              actions: [
                if (widget.canInvite)
                  IconButton(
                    key: const Key('semya-invitations-add'),
                    tooltip: 'Пригласить',
                    icon: const Icon(Icons.person_add_alt_outlined),
                    onPressed: _openInviteScreen,
                  ),
              ],
            ),
            body: _buildBody(controller),
          );
        },
      ),
    );
  }

  Widget _buildBody(SemyaInvitationsController controller) {
    if (controller.isLoading && !controller.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.invitations.isEmpty) {
      return _EmptyState(
        canInvite: widget.canInvite,
        onInvite: _openInviteScreen,
      );
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: controller.invitations.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final inv = controller.invitations[index];
          return _InvitationTile(
            invitation: inv,
            onRevoke: inv.isPending ? () => _confirmRevoke(inv) : null,
            onCopyLink: inv.isPending ? () => _copyLink(inv) : null,
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.canInvite, required this.onInvite});

  final bool canInvite;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mail_outline_rounded,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Пока нет приглашений',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              canInvite
                  ? 'Отправьте первое приглашение родственнику.'
                  : 'Когда владелец отправит приглашения — вы увидите их здесь.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (canInvite) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('semya-invitations-empty-cta'),
                onPressed: onInvite,
                icon: const Icon(Icons.person_add_alt_outlined),
                label: const Text('Пригласить'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InvitationTile extends StatelessWidget {
  const _InvitationTile({
    required this.invitation,
    required this.onRevoke,
    required this.onCopyLink,
  });

  final SemyaInvitation invitation;
  final VoidCallback? onRevoke;
  final VoidCallback? onCopyLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: Key('semya-invitation-tile-${invitation.id}'),
      title: Text(
        invitation.recipientLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'Роль: ${invitation.role.displayLabel}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusBadge(status: invitation.status),
          if (onCopyLink != null) ...[
            const SizedBox(width: 4),
            IconButton(
              key: Key('semya-invitation-copy-${invitation.id}'),
              tooltip: 'Скопировать ссылку',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: onCopyLink,
            ),
          ],
          if (onRevoke != null)
            IconButton(
              key: Key('semya-invitation-revoke-${invitation.id}'),
              tooltip: 'Отозвать',
              icon: Icon(
                Icons.cancel_outlined,
                size: 18,
                color: theme.colorScheme.error,
              ),
              onPressed: onRevoke,
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final SemyaInvitationStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color background;
    final Color foreground;
    switch (status) {
      case SemyaInvitationStatus.pending:
        background = theme.colorScheme.primary.withValues(alpha: 0.16);
        foreground = theme.colorScheme.primary;
        break;
      case SemyaInvitationStatus.accepted:
        background = Colors.green.withValues(alpha: 0.16);
        foreground = Colors.green.shade800;
        break;
      case SemyaInvitationStatus.revoked:
      case SemyaInvitationStatus.expired:
      case SemyaInvitationStatus.unknown:
        background = theme.colorScheme.surfaceContainerHighest;
        foreground = theme.colorScheme.onSurfaceVariant;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.displayLabel,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
