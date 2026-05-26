// Ship FE6b (2026-05-26): browse-tokens management section для FE2
// семя details screen. Lists active/expired/revoked browse tokens,
// surfaces per-row revoke action gated by owner-or-creator backend
// permission.
//
// Design decisions (Артём confirmed via Phase 1 checkpoint):
//   • НЕТ «Копировать» action — backend strips plaintext token из
//     list responses (security: bearer-secret leaks ONCE на create).
//     Re-share = create fresh token via FE6a «Поделиться деревом».
//   • Revoke gate = `callerRole == owner` ИЛИ `token.createdByUserId
//     == currentUserId`. Matches backend store permission, no
//     surprise 403s.
//
// Layout: section header + tokens cards (newest first) либо empty
// state. Standalone state machine — does NOT touch SemyaDetailsController.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/models/semya.dart';
import '../backend/models/semya_browse_token.dart';

class BrowseTokensListSection extends StatefulWidget {
  const BrowseTokensListSection({
    super.key,
    required this.semyaId,
    required this.callerRole,
    required this.currentUserId,
    this.serviceOverride,
  });

  final String semyaId;
  final SemyaRole callerRole;

  /// Caller user id from AuthService — used для revoke-button gate
  /// (creator can revoke own tokens; owner can revoke any).
  final String? currentUserId;

  /// Test seam. Production resolves via GetIt.
  final SemyaCapableFamilyTreeService? serviceOverride;

  @override
  State<BrowseTokensListSection> createState() =>
      _BrowseTokensListSectionState();
}

class _BrowseTokensListSectionState extends State<BrowseTokensListSection> {
  bool _isLoading = false;
  bool _hasLoaded = false;
  List<SemyaBrowseTokenSummary> _tokens = const <SemyaBrowseTokenSummary>[];
  String? _errorMessage;
  String? _revokingTokenId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  SemyaCapableFamilyTreeService? _resolveService() {
    if (widget.serviceOverride != null) return widget.serviceOverride;
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) return null;
    final service = GetIt.I<FamilyTreeServiceInterface>();
    if (service is SemyaCapableFamilyTreeService) {
      return service as SemyaCapableFamilyTreeService;
    }
    return null;
  }

  Future<void> _load() async {
    final service = _resolveService();
    if (service == null) {
      setState(() {
        _hasLoaded = true;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final tokens = await service.listBrowseTokens(semyaId: widget.semyaId);
      final sorted = [...tokens]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _tokens = sorted;
        _hasLoaded = true;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasLoaded = true;
        _errorMessage = _describeError(error);
      });
    }
  }

  Future<void> _confirmAndRevoke(SemyaBrowseTokenSummary token) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Отозвать ссылку?'),
          content: const Text(
            'После отзыва ссылка перестанет работать. Действие нельзя отменить.',
          ),
          actions: [
            TextButton(
              key: const Key('revoke-cancel'),
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              key: const Key('revoke-confirm'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Отозвать'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final service = _resolveService();
    if (service == null) return;

    setState(() {
      _revokingTokenId = token.id;
    });
    try {
      final updated = await service.revokeBrowseToken(
        semyaId: widget.semyaId,
        tokenId: token.id,
      );
      if (!mounted) return;
      // Replace row in-place with returned summary (status='revoked').
      // Keep сортировку — replacement preserves createdAt position.
      final next = _tokens
          .map((t) => t.id == updated.id ? updated : t)
          .toList(growable: false);
      setState(() {
        _tokens = next;
        _revokingTokenId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка отозвана')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _revokingTokenId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_describeError(error))),
      );
    }
  }

  bool _canRevoke(SemyaBrowseTokenSummary token) {
    if (!token.isActive) return false;
    if (widget.callerRole == SemyaRole.owner) return true;
    final me = widget.currentUserId;
    if (me == null || me.isEmpty) return false;
    return token.createdByUserId == me;
  }

  String _describeError(Object error) {
    if (error is SemyaError) return error.message;
    return 'Не удалось загрузить ссылки';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Icon(
                Icons.link_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Активные ссылки',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _buildBody(context),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading && !_hasLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _errorMessage!,
                key: const Key('browse-tokens-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            TextButton.icon(
              key: const Key('browse-tokens-retry'),
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    if (_tokens.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Text(
          'Пока нет активных ссылок. Поделись деревом, чтобы создать.',
          key: Key('browse-tokens-empty'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: _tokens.map(_buildTokenCard).toList(growable: false),
      ),
    );
  }

  Widget _buildTokenCard(SemyaBrowseTokenSummary token) {
    final theme = Theme.of(context);
    final isInactive = !token.isActive;
    final revoking = _revokingTokenId == token.id;
    return Container(
      key: Key('browse-token-row-${token.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isInactive
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.link_rounded,
                size: 16,
                color: isInactive
                    ? theme.disabledColor
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Создана ${_formatDate(token.createdAt)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isInactive ? theme.disabledColor : null,
                  ),
                ),
              ),
              _StatusBadge(status: token.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Действует до ${_formatDate(token.expiresAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_canRevoke(token)) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('browse-token-revoke-${token.id}'),
                onPressed: revoking ? null : () => _confirmAndRevoke(token),
                icon: revoking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.link_off_rounded,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                label: Text(
                  'Отозвать',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Format ISO-8601 date → «DD MMM» (Russian locale-free,
  /// month names hardcoded для simplicity — Flutter intl heavy).
  static String _formatDate(String iso) {
    if (iso.isEmpty) return '—';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    const months = [
      'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    final mIdx = parsed.month - 1;
    if (mIdx < 0 || mIdx >= months.length) return iso;
    return '${parsed.day} ${months[mIdx]}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String label;
    final Color color;
    switch (status) {
      case 'active':
        label = 'Активна';
        color = theme.colorScheme.primary;
        break;
      case 'expired':
        label = 'Истекла';
        color = theme.colorScheme.onSurfaceVariant;
        break;
      case 'revoked':
        label = 'Отозвана';
        color = theme.colorScheme.error;
        break;
      default:
        label = status;
        color = theme.colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
