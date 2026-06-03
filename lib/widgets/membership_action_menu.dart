// Ship FE8 (2026-05-27): per-row action menu для членов семьи в FE2
// details. Owner-only — viewer/editor callers не видят menu (просто
// read-only member list).
//
// 4 backend-enforced invariants gated UI-side:
//   • SELF_ROLE_CHANGE_FORBIDDEN — менu не render для self-row
//   • LAST_OWNER_DEMOTE_FORBIDDEN — backstop only (caller can't demote
//     self, и если caller is owner, demoting другого owner всегда
//     leaves ≥1 owner — caller)
//   • LAST_OWNER_REMOVE_FORBIDDEN — backstop only (same logic)
//   • INVITE_GRANT_ONLY_EDITOR — toggle item shown only когда
//     target.role == editor
//
// Confirmation dialogs gated на destructive ops:
//   • Promote → owner (grant powerful control)
//   • Demote owner → editor либо viewer (revoke power)
//   • Kick (remove access entirely)
//
// Non-destructive (viewer↔editor, invite-grant toggle) — immediate
// action с snackbar feedback.

import 'package:flutter/material.dart';

import '../backend/models/semya.dart';

/// Action callbacks supplied by caller. All async to allow service
/// invocation + refresh await without coupling menu widget к
/// controller internals.
class MembershipActions {
  const MembershipActions({
    required this.onChangeRole,
    required this.onToggleInviteGrant,
    required this.onKick,
  });

  /// Change member role. Caller handles confirmation dialog + service
  /// call + refresh. Provided role is the TARGET role (owner/editor/
  /// viewer).
  final Future<void> Function(SemyaRole newRole) onChangeRole;

  /// Toggle invite-grant flag. Caller handles service call + refresh.
  /// `enabled` is target state (true = grant, false = revoke).
  final Future<void> Function(bool enabled) onToggleInviteGrant;

  /// Kick member из семья. Caller handles confirmation dialog +
  /// service call + refresh.
  final Future<void> Function() onKick;
}

class MembershipActionMenu extends StatelessWidget {
  const MembershipActionMenu({
    super.key,
    required this.membership,
    required this.actions,
    this.isPending = false,
  });

  final SemyaMembership membership;
  final MembershipActions actions;

  /// Disable menu while service call in flight — prevents double tap.
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    if (isPending) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return PopupMenuButton<_MembershipMenuAction>(
      key: Key('membership-menu-${membership.userId}'),
      tooltip: 'Управление участником',
      icon: const Icon(Icons.more_vert_rounded),
      itemBuilder: (_) => _buildItems(),
      onSelected: (action) => _handleSelection(context, action),
    );
  }

  List<PopupMenuEntry<_MembershipMenuAction>> _buildItems() {
    final role = membership.role;
    final items = <PopupMenuEntry<_MembershipMenuAction>>[];

    // Role change options — conditional на current role.
    if (role != SemyaRole.owner) {
      items.add(_item(
        _MembershipMenuAction.promoteToOwner,
        Icons.workspace_premium_outlined,
        'Сделать владельцем',
      ));
    }
    if (role != SemyaRole.editor) {
      items.add(_item(
        _MembershipMenuAction.setEditor,
        Icons.edit_outlined,
        'Сделать редактором',
      ));
    }
    if (role != SemyaRole.viewer) {
      items.add(_item(
        _MembershipMenuAction.setViewer,
        Icons.visibility_outlined,
        'Сделать наблюдателем',
      ));
    }

    // Invite-grant toggle — только когда target.role == editor
    // (backend INVITE_GRANT_ONLY_EDITOR invariant).
    if (role == SemyaRole.editor) {
      items.add(const PopupMenuDivider());
      if (membership.hasInviteGrant) {
        items.add(_item(
          _MembershipMenuAction.revokeInviteGrant,
          Icons.lock_outline_rounded,
          'Запретить приглашать',
        ));
      } else {
        items.add(_item(
          _MembershipMenuAction.grantInvite,
          Icons.person_add_alt_outlined,
          'Разрешить приглашать',
        ));
      }
    }

    // Destructive — kick.
    items.add(const PopupMenuDivider());
    items.add(_item(
      _MembershipMenuAction.kick,
      Icons.person_remove_outlined,
      'Удалить из семьи',
      destructive: true,
    ));

    return items;
  }

  PopupMenuItem<_MembershipMenuAction> _item(
    _MembershipMenuAction action,
    IconData icon,
    String label, {
    bool destructive = false,
  }) {
    return PopupMenuItem<_MembershipMenuAction>(
      key: Key('membership-menu-item-${action.name}-${membership.userId}'),
      value: action,
      child: Builder(
        builder: (ctx) {
          final color = destructive ? Theme.of(ctx).colorScheme.error : null;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: destructive ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleSelection(
    BuildContext context,
    _MembershipMenuAction action,
  ) async {
    switch (action) {
      case _MembershipMenuAction.promoteToOwner:
        final confirmed = await _confirmRoleChange(
          context,
          title: 'Сделать владельцем семьи?',
          body: '${_displayName()} сможет управлять участниками и '
              'удалять семью.',
          confirmLabel: 'Подтвердить',
        );
        if (confirmed) await actions.onChangeRole(SemyaRole.owner);
        break;
      case _MembershipMenuAction.setEditor:
        if (membership.role == SemyaRole.owner) {
          final confirmed = await _confirmRoleChange(
            context,
            title: 'Снять права владельца?',
            body: '${_displayName()} останется в семье как редактор.',
            confirmLabel: 'Подтвердить',
          );
          if (!confirmed) break;
        }
        await actions.onChangeRole(SemyaRole.editor);
        break;
      case _MembershipMenuAction.setViewer:
        if (membership.role == SemyaRole.owner) {
          final confirmed = await _confirmRoleChange(
            context,
            title: 'Снять права владельца?',
            body: '${_displayName()} останется в семье как наблюдатель.',
            confirmLabel: 'Подтвердить',
          );
          if (!confirmed) break;
        }
        await actions.onChangeRole(SemyaRole.viewer);
        break;
      case _MembershipMenuAction.grantInvite:
        await actions.onToggleInviteGrant(true);
        break;
      case _MembershipMenuAction.revokeInviteGrant:
        await actions.onToggleInviteGrant(false);
        break;
      case _MembershipMenuAction.kick:
        final confirmed = await _confirmDestructive(
          context,
          title: 'Удалить ${_displayName()} из семьи?',
          body: '${_displayName()} больше не сможет смотреть либо '
              'редактировать дерево.',
          confirmLabel: 'Удалить',
        );
        if (confirmed) await actions.onKick();
        break;
    }
  }

  String _displayName() {
    // Resolved member name from the backend enrich (Phase B polish A);
    // falls back to userId when the name can't be resolved.
    return membership.displayLabel;
  }
}

Future<bool> _confirmRoleChange(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          key: const Key('membership-confirm-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Отмена'),
        ),
        TextButton(
          key: const Key('membership-confirm-ok'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

Future<bool> _confirmDestructive(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          key: const Key('membership-destructive-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Отмена'),
        ),
        TextButton(
          key: const Key('membership-destructive-ok'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

enum _MembershipMenuAction {
  promoteToOwner,
  setEditor,
  setViewer,
  grantInvite,
  revokeInviteGrant,
  kick,
}
