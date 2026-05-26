import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:share_plus/share_plus.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/models/semya.dart' show SemyaError;
import '../backend/models/semya_browse_token.dart';

/// Ship FE6a (2026-05-26): «Поделиться деревом» modal. Owner либо
/// editor-с-grant invokes — creates browse-token (backend Ship 7),
/// surfaces shareable link с copy + system-share buttons.
///
/// Token secret leaks ONCE — caller must persist UI state. Modal
/// shows loading state while creating, then success view с link.
/// Caller doesn't get token back (only success/cancel); если нужно
/// дальнейшее tracking — use FE6b tokens list (deferred).
class ShareBrowseTokenModal extends StatefulWidget {
  const ShareBrowseTokenModal({
    super.key,
    required this.semyaId,
    required this.semyaName,
    this.serviceOverride,
  });

  final String semyaId;
  final String semyaName;
  final SemyaCapableFamilyTreeService? serviceOverride;

  @override
  State<ShareBrowseTokenModal> createState() => _ShareBrowseTokenModalState();
}

class _ShareBrowseTokenModalState extends State<ShareBrowseTokenModal> {
  SemyaBrowseToken? _token;
  bool _isCreating = false;
  String? _errorMessage;

  SemyaCapableFamilyTreeService? get _service {
    if (widget.serviceOverride != null) return widget.serviceOverride;
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) return null;
    final raw = GetIt.I<FamilyTreeServiceInterface>();
    if (raw is SemyaCapableFamilyTreeService) {
      return raw as SemyaCapableFamilyTreeService;
    }
    return null;
  }

  Future<void> _createToken() async {
    final service = _service;
    if (service == null) {
      setState(() => _errorMessage = 'Сервис недоступен');
      return;
    }
    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });
    try {
      final token = await service.createBrowseToken(semyaId: widget.semyaId);
      if (!mounted) return;
      setState(() {
        _token = token;
        _isCreating = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _errorMessage = error is SemyaError
            ? error.message
            : 'Не удалось создать ссылку';
      });
    }
  }

  Future<void> _copyLink() async {
    final token = _token;
    if (token == null) return;
    await Clipboard.setData(ClipboardData(text: token.shareUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка скопирована')),
      );
    }
  }

  Future<void> _shareLink() async {
    final token = _token;
    if (token == null) return;
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Открой моё семейное дерево «${widget.semyaName}»: ${token.shareUrl}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Поделиться деревом',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              _token != null
                  ? 'Ссылка действительна 30 дней. Получатель увидит '
                      'имена и связи, но не фото и заметки.'
                  : 'Создайте ссылку, чтобы родственники могли посмотреть '
                      'дерево «${widget.semyaName}» без регистрации в семье.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_token != null) _buildSuccessView(theme) else _buildCreateView(theme),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCreateView(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: FilledButton.icon(
        key: const Key('share-browse-create'),
        onPressed: _isCreating ? null : _createToken,
        icon: _isCreating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.link_rounded),
        label: Text(_isCreating ? 'Создаём…' : 'Создать ссылку'),
      ),
    );
  }

  Widget _buildSuccessView(ThemeData theme) {
    final token = _token!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            token.shareUrl,
            key: const Key('share-browse-link'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('share-browse-copy'),
                onPressed: _copyLink,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Скопировать'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                key: const Key('share-browse-share'),
                onPressed: _shareLink,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Поделиться'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

/// Helper: opens share modal as bottom sheet.
Future<void> showShareBrowseTokenModal(
  BuildContext context, {
  required String semyaId,
  required String semyaName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => ShareBrowseTokenModal(
      semyaId: semyaId,
      semyaName: semyaName,
    ),
  );
}
