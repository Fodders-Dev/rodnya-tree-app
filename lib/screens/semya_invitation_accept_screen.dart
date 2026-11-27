import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/models/semya.dart';
import '../backend/models/semya_invitation.dart';
import '../providers/tree_provider.dart';
import '../services/semya_invitation_deep_link_service.dart';
import '../utils/user_facing_error.dart';

/// Deep-link invitation accept/decline screen for `/invite/:token`.
///
/// Loads safe metadata via `previewInvitation(token)` first, shows who is
/// inviting and which family/card is offered, and requires explicit confirmation
/// («Принять приглашение» / «Отклонить») before mutating membership.
class SemyaInvitationAcceptScreen extends StatefulWidget {
  const SemyaInvitationAcceptScreen({
    super.key,
    required this.token,
    this.serviceOverride,
    this.deepLinkServiceOverride,
  });

  final String token;

  /// Test seam.
  final SemyaCapableFamilyTreeService? serviceOverride;
  final SemyaInvitationDeepLinkService? deepLinkServiceOverride;

  @override
  State<SemyaInvitationAcceptScreen> createState() =>
      _SemyaInvitationAcceptScreenState();
}

class _SemyaInvitationAcceptScreenState
    extends State<SemyaInvitationAcceptScreen> {
  bool _loadingPreview = true;
  bool _submitting = false;
  SemyaInvitation? _preview;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
  }

  SemyaCapableFamilyTreeService? _resolveService() {
    if (widget.serviceOverride != null) return widget.serviceOverride;
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) return null;
    final svc = GetIt.I<FamilyTreeServiceInterface>();
    if (svc is SemyaCapableFamilyTreeService) {
      return svc as SemyaCapableFamilyTreeService;
    }
    return null;
  }

  SemyaInvitationDeepLinkService get _deepLinkSvc =>
      widget.deepLinkServiceOverride ?? SemyaInvitationDeepLinkService();

  Future<void> _loadPreview() async {
    final service = _resolveService();
    if (service == null) {
      setState(() {
        _loadingPreview = false;
        _errorMessage = 'Сервис недоступен';
      });
      return;
    }

    final trimmed = widget.token.trim();
    if (trimmed.isEmpty) {
      _deepLinkSvc.clearPendingToken();
      setState(() {
        _loadingPreview = false;
        _errorMessage = 'Некорректное приглашение';
      });
      return;
    }

    setState(() {
      _loadingPreview = true;
      _errorMessage = null;
    });

    try {
      final preview = await service.previewInvitation(trimmed);
      if (!mounted) return;
      if (preview == null) {
        _deepLinkSvc.clearPendingToken();
        setState(() {
          _loadingPreview = false;
          _errorMessage = 'Приглашение не найдено';
        });
        return;
      }
      if (preview.semyaDeleted || !preview.isPending) {
        _deepLinkSvc.clearPendingToken();
        setState(() {
          _loadingPreview = false;
          _preview = preview;
          _errorMessage = _terminalPreviewMessage(preview);
        });
        return;
      }
      setState(() {
        _loadingPreview = false;
        _preview = preview;
      });
    } on SemyaError catch (error) {
      _clearIfTerminal(error.code);
      if (!mounted) return;
      setState(() {
        _loadingPreview = false;
        _errorMessage = _friendlyMessage(error);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingPreview = false;
        _errorMessage = humanizeError(
          error,
          fallback: 'Не удалось проверить приглашение. Попробуйте ещё раз.',
        );
      });
    }
  }

  Future<void> _confirmAccept() async {
    final service = _resolveService();
    final trimmed = widget.token.trim();
    if (service == null || trimmed.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final result = await service.acceptInvitation(trimmed);
      _deepLinkSvc.clearPendingToken();
      if (GetIt.I.isRegistered<AuthServiceInterface>()) {
        final auth = GetIt.I<AuthServiceInterface>();
        if (auth.currentRequiresOnboarding) {
          await auth.markOnboardingSkipped();
        }
      }
      var targetRoute = '/';
      if (GetIt.I.isRegistered<TreeProvider>()) {
        final treeProvider = GetIt.I<TreeProvider>();
        await treeProvider.refreshAvailableTrees();
        final joinedTreeId = result.treeId;
        if (joinedTreeId != null && joinedTreeId.isNotEmpty) {
          final match = treeProvider.availableTrees
              .where((t) => t.id == joinedTreeId)
              .toList();
          treeProvider.selectTree(
            joinedTreeId,
            match.isNotEmpty
                ? match.first.name
                : (result.invitation.semyaName ??
                    _preview?.semyaName ??
                    'Семья'),
          );
          targetRoute = '/tree';
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Вы присоединились к семье. Роль: '
            '${result.role.displayLabel.toLowerCase()}',
          ),
        ),
      );
      context.go(targetRoute);
    } on SemyaError catch (error) {
      _clearIfTerminal(error.code);
      if (!mounted) return;
      final friendly = _friendlyMessage(error);
      setState(() {
        _submitting = false;
        _errorMessage = friendly;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendly)));
    } catch (error) {
      if (!mounted) return;
      final friendly = humanizeError(
        error,
        fallback: 'Не удалось принять приглашение. Попробуйте ещё раз.',
      );
      setState(() {
        _submitting = false;
        _errorMessage = friendly;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendly)));
    }
  }

  Future<void> _confirmDecline() async {
    final service = _resolveService();
    final trimmed = widget.token.trim();
    if (service == null || trimmed.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await service.declineInvitation(trimmed);
      _deepLinkSvc.clearPendingToken();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Приглашение отклонено')),
      );
      context.go('/');
    } on SemyaError catch (error) {
      _clearIfTerminal(error.code);
      if (!mounted) return;
      final friendly = _friendlyMessage(error);
      setState(() {
        _submitting = false;
        _errorMessage = friendly;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendly)));
    } catch (error) {
      if (!mounted) return;
      final friendly = humanizeError(
        error,
        fallback: 'Не удалось отклонить приглашение. Попробуйте ещё раз.',
      );
      setState(() {
        _submitting = false;
        _errorMessage = friendly;
      });
    }
  }

  void _clearIfTerminal(String code) {
    const terminalCodes = {
      'INVITATION_NOT_FOUND',
      'INVITATION_NOT_PENDING',
      'INVITATION_EXPIRED',
      'WRONG_RECIPIENT',
      'FORBIDDEN',
      'SEMYA_NOT_FOUND',
      'SEMYA_DELETED',
    };
    if (terminalCodes.contains(code)) {
      _deepLinkSvc.clearPendingToken();
    }
  }

  String _terminalPreviewMessage(SemyaInvitation preview) {
    if (preview.semyaDeleted) {
      return 'Семья больше недоступна';
    }
    switch (preview.status) {
      case SemyaInvitationStatus.accepted:
        return 'Это приглашение уже принято';
      case SemyaInvitationStatus.declined:
        return 'Это приглашение уже отклонено';
      case SemyaInvitationStatus.revoked:
        return 'Приглашение было отозвано';
      case SemyaInvitationStatus.expired:
        return 'Срок действия приглашения истёк';
      case SemyaInvitationStatus.pending:
      case SemyaInvitationStatus.unknown:
        return 'Это приглашение уже не действует';
    }
  }

  String _friendlyMessage(SemyaError error) {
    switch (error.code) {
      case 'INVITATION_NOT_FOUND':
        return 'Приглашение не найдено';
      case 'INVITATION_EXPIRED':
        return 'Срок действия приглашения истёк';
      case 'INVITATION_NOT_PENDING':
        return error.message;
      case 'WRONG_RECIPIENT':
      case 'FORBIDDEN':
        return 'Приглашение оформлено на другого пользователя';
      case 'SEMYA_NOT_FOUND':
      case 'SEMYA_DELETED':
        return 'Семья больше недоступна';
      default:
        return 'Не удалось обработать приглашение: ${error.message}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Приглашение в семью'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _buildContent(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_loadingPreview) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Проверяем приглашение...'),
        ],
      );
    }

    if (_errorMessage != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton(
              key: const Key('invitation-accept-go-home'),
              onPressed: () => context.go('/'),
              child: const Center(
                child: Text('Вернуться на главную'),
              ),
            ),
          ),
        ],
      );
    }

    final preview = _preview;
    if (preview == null) {
      return const SizedBox.shrink();
    }

    final semyaTitle = (preview.semyaName ?? '').trim().isNotEmpty
        ? preview.semyaName!.trim()
        : 'Семья';
    final inviterName = (preview.inviterName ?? '').trim();
    final targetPersonName = (preview.targetPersonName ?? '').trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.family_restroom_rounded,
              size: 28,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          semyaTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          inviterName.isNotEmpty
              ? '$inviterName приглашает вас присоединиться к семье в Родне.'
              : 'Вас пригласили присоединиться к семье в Родне.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.55,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Роль: ${preview.role.displayLabel.toLowerCase()}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (targetPersonName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Карточка в дереве: $targetPersonName',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: FilledButton(
            key: const Key('invitation-accept-confirm'),
            onPressed: _submitting ? null : _confirmAccept,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Принять приглашение'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: OutlinedButton(
            key: const Key('invitation-accept-decline'),
            onPressed: _submitting ? null : _confirmDecline,
            child: const Text('Отклонить'),
          ),
        ),
      ],
    );
  }
}
