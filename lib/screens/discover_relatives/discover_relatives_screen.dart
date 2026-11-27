import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backend/interfaces/auth_service_interface.dart';
import '../../backend/interfaces/family_tree_service_interface.dart';
import '../../backend/interfaces/kinship_check_capable_family_tree_service.dart';
import '../../backend/interfaces/profile_service_interface.dart';
import '../../backend/models/kinship_check.dart';
import '../../models/family_relation.dart';
import '../../models/user_profile.dart';
import '../../providers/kinship_check_controller.dart';
import '../../providers/tree_provider.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/relation_chain_strip.dart';
import '../../widgets/relation_picker_sheet.dart';

/// Phase 6 chunk 3 (PHASE-6-PROPOSAL.md §2.4-§2.6): «мы родственники?»
/// discover entry. Hosts:
///   • outgoing 4-step flow (search → preview → send → result).
///   • incoming pending banner с bilateral-consent action sheet.
///   • issued recent history (collapsed below search field).
///
/// Capability gating: если backend не implements
/// [KinshipCheckCapableFamilyTreeService] — screen renders friendly
/// «функция недоступна» state. Router guard normally redirects
/// раньше; defensive landing для direct deep-links.
class DiscoverRelativesScreen extends StatefulWidget {
  const DiscoverRelativesScreen({
    super.key,
    this.incomingCheckId,
    this.resultCheckId,
    this.treeId,
    this.initialProfileCode,
  });

  /// Если задан — screen открывается с action sheet для этого
  /// received pending check (deep-link из notification tap).
  final String? incomingCheckId;

  /// Phase 6 chunk 4b: если задан — screen открывается на result step
  /// для этого issued check (deep-link из `kinship_check_confirmed`
  /// notification). Caller waits для issued list refresh, then sets
  /// matching check as submittedCheck + transitions step=result.
  final String? resultCheckId;

  /// Optional active tree id when opened from a specific tree/relatives screen
  /// or profile connection link (enables direct «Добавить в дерево» relation request).
  final String? treeId;

  /// Optional @username/profile code prefill to search immediately.
  final String? initialProfileCode;

  @override
  State<DiscoverRelativesScreen> createState() =>
      _DiscoverRelativesScreenState();
}

class _DiscoverRelativesScreenState extends State<DiscoverRelativesScreen> {
  late final KinshipCheckController _controller;
  late final FamilyTreeServiceInterface _familyTreeService;
  late final ProfileServiceInterface _profileService;
  AuthServiceInterface? _authService;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  bool _isSearching = false;
  bool _isSubmittingRelationRequest = false;
  List<UserProfile> _searchResults = const <UserProfile>[];
  Set<String> _existingTreeUserIds = const <String>{};
  RelationType? _selectedRelation;
  String? _searchError;
  bool _autoSheetPresented = false;
  bool _resultDeepLinkPresented = false;

  String? get _resolvedTreeId {
    final explicit = widget.treeId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (GetIt.I.isRegistered<TreeProvider>()) {
      final selected = GetIt.I<TreeProvider>().selectedTreeId?.trim();
      if (selected != null && selected.isNotEmpty) return selected;
    }
    try {
      final selected = Provider.of<TreeProvider>(context, listen: false)
          .selectedTreeId
          ?.trim();
      if (selected != null && selected.isNotEmpty) return selected;
    } catch (_) {}
    return null;
  }

  @override
  void initState() {
    super.initState();
    _familyTreeService = GetIt.I<FamilyTreeServiceInterface>();
    _controller = KinshipCheckController(
      service: _familyTreeService is KinshipCheckCapableFamilyTreeService
          ? _familyTreeService as KinshipCheckCapableFamilyTreeService
          : null,
    );
    _profileService = GetIt.I<ProfileServiceInterface>();
    _authService = GetIt.I.isRegistered<AuthServiceInterface>()
        ? GetIt.I<AuthServiceInterface>()
        : null;
    final initialCode = widget.initialProfileCode?.trim() ?? '';
    if (initialCode.isNotEmpty) {
      _searchController.text =
          initialCode.startsWith('@') ? initialCode : '@$initialCode';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.isCapable) {
        _controller.refresh();
      }
      _loadExistingTreeUsers();
      if (initialCode.isNotEmpty) {
        _runSearch(initialCode);
      }
      _maybeAutoPresentIncomingSheet();
      _maybeAutoPresentResult();
    });
  }

  Future<void> _loadExistingTreeUsers() async {
    final treeId = _resolvedTreeId;
    if (treeId == null) return;
    try {
      final relatives = await _familyTreeService.getRelatives(treeId);
      if (!mounted) return;
      setState(() {
        _existingTreeUserIds = relatives
            .map((p) => p.userId)
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet();
      });
    } catch (_) {
      // Non-fatal; server still validates duplicate relation requests.
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _maybeAutoPresentIncomingSheet() {
    final incomingId = widget.incomingCheckId;
    if (incomingId == null || incomingId.isEmpty) return;
    if (_autoSheetPresented) return;
    _autoSheetPresented = true;
    // Wait for lists to load так что мы найдём check by id.
    Future<void>.delayed(const Duration(milliseconds: 150), () async {
      if (!mounted) return;
      KinshipCheck? check = _controller.findReceivedById(incomingId);
      if (check == null) {
        // Lists may не успели загрузиться — wait one more tick.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        check = _controller.findReceivedById(incomingId);
      }
      if (check != null && check.status == KinshipCheckStatus.pending) {
        await _showRespondSheet(check);
      }
    });
  }

  void _maybeAutoPresentResult() {
    final resultId = widget.resultCheckId;
    if (resultId == null || resultId.isEmpty) return;
    if (_resultDeepLinkPresented) return;
    _resultDeepLinkPresented = true;
    // Wait для issued list refresh, then find check by id.
    Future<void>.delayed(const Duration(milliseconds: 150), () async {
      if (!mounted) return;
      KinshipCheck? check = _controller.findIssuedById(resultId);
      if (check == null) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        check = _controller.findIssuedById(resultId);
      }
      if (check != null && check.result != null) {
        _controller.presentResult(check);
      }
    });
  }

  // ── Search ─────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = const <UserProfile>[];
        _searchError = null;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      _runSearch(trimmed);
    });
  }

  Future<void> _runSearch(String query) async {
    final normalized = query.trim().replaceFirst(RegExp(r'^@+'), '').trim();
    if (normalized.isEmpty) {
      setState(() {
        _searchResults = const <UserProfile>[];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    try {
      final results = await _profileService.searchUsers(normalized, limit: 12);
      if (!mounted) return;
      final currentUserId = _authService?.currentUserId;
      final filtered = results
          .where((u) => u.id.isNotEmpty && u.id != currentUserId)
          .toList(growable: false);
      setState(() {
        _searchResults = filtered;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchResults = const <UserProfile>[];
        _isSearching = false;
        _searchError = 'Не удалось найти пользователей. Попробуйте позже.';
      });
    }
  }

  // ── Outgoing flow actions ──────────────────────────────────────

  void _selectTarget(UserProfile profile) {
    if (_controller.isCapable) {
      _controller.selectTarget(
        userId: profile.id,
        displayName: _displayName(profile),
      );
      return;
    }
    if (_resolvedTreeId != null && !_existingTreeUserIds.contains(profile.id)) {
      _showRelationSelectDialog(profile);
    }
  }

  void _showRelationSelectDialog(UserProfile user) {
    final treeId = _resolvedTreeId;
    if (treeId == null || _isSubmittingRelationRequest) return;
    setState(() {
      _selectedRelation = null;
    });
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Добавить в дерево'),
        content: DropdownButtonFormField<RelationType>(
          initialValue: _selectedRelation,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          hint: const Text('Кем приходится?'),
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: RelationType.parent,
              child: Text('Родитель'),
            ),
            DropdownMenuItem(value: RelationType.child, child: Text('Ребёнок')),
            DropdownMenuItem(
              value: RelationType.spouse,
              child: Text('Супруг(а)'),
            ),
            DropdownMenuItem(
              value: RelationType.sibling,
              child: Text('Брат/сестра'),
            ),
            DropdownMenuItem(
              value: RelationType.cousin,
              child: Text('Двоюродный брат/сестра'),
            ),
            DropdownMenuItem(value: RelationType.uncle, child: Text('Дядя')),
            DropdownMenuItem(value: RelationType.aunt, child: Text('Тётя')),
            DropdownMenuItem(
              value: RelationType.grandparent,
              child: Text('Бабушка/дедушка'),
            ),
            DropdownMenuItem(
              value: RelationType.grandchild,
              child: Text('Внук/внучка'),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _selectedRelation = value;
            });
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('discover-confirm-add-relative'),
            onPressed: () {
              final chosen = _selectedRelation;
              if (chosen == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Сначала выберите тип родства'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext);
              unawaited(_sendRelationRequest(treeId, user, chosen));
            },
            child: const Text('Отправить запрос'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendRelationRequest(
    String treeId,
    UserProfile user,
    RelationType relationType,
  ) async {
    setState(() => _isSubmittingRelationRequest = true);
    try {
      final currentUserId = _authService?.currentUserId;
      if (currentUserId != null && currentUserId.isNotEmpty) {
        final hasPending = await _familyTreeService.hasPendingRelationRequest(
          treeId: treeId,
          senderId: currentUserId,
          recipientId: user.id,
        );
        if (!mounted) return;
        if (hasPending) {
          setState(() => _isSubmittingRelationRequest = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Запрос этому человеку уже отправлен.'),
            ),
          );
          return;
        }
      }
      await _familyTreeService.sendRelationRequest(
        treeId: treeId,
        recipientId: user.id,
        relationType: relationType,
        message: 'Запрос на подтверждение родственной связи',
      );
      if (!mounted) return;
      setState(() => _isSubmittingRelationRequest = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Запрос отправлен.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmittingRelationRequest = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            humanizeError(
              error,
              fallback: 'Не удалось отправить запрос. Попробуйте ещё раз.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _submitCheck() async {
    // Phase 6 chunk 4c (PHASE-6-PROPOSAL.md §4 «Privacy explainer copy»):
    // one-time explainer before first BFS request. Per-user `_v1` key
    // позволяет future re-show если copy changes.
    final proceeded = await _maybeShowPrivacyExplainer();
    if (!proceeded || !mounted) return;
    final ok = await _controller.submitCheck();
    if (!mounted) return;
    if (!ok && _controller.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_controller.error!)),
      );
    }
  }

  /// Returns true if user accepted либо already seen — proceed with
  /// submit. False if user dismissed dialog (cancel) либо tooltip
  /// rendered и user backed out.
  Future<bool> _maybeShowPrivacyExplainer() async {
    const key = 'discover_privacy_explainer_shown_v1';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) == true) return true;
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Как это работает'),
          content: const Text(
            'Чтобы посмотреть, родственники ли вы с другим человеком, '
            'мы спрашиваем у него разрешения. Так каждый сам решает, '
            'кому показывать свои семейные связи.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Понятно, отправить'),
            ),
          ],
        );
      },
    );
    if (result == true) {
      await prefs.setBool(key, true);
      return true;
    }
    return false;
  }

  void _resetFlow() {
    _searchController.clear();
    _searchResults = const <UserProfile>[];
    _controller.reset();
  }

  // ── Bilateral consent action sheet ─────────────────────────────

  Future<void> _showRespondSheet(KinshipCheck check) async {
    final theme = Theme.of(context);
    final initiatorName = check.initiatorUserId;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Запрос на подтверждение родственной связи',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Этот человек хочет узнать, родственники ли вы. '
                  'Если подтвердите — обе стороны увидят результат '
                  'проверки. Если откажете — он(а) узнает только об '
                  'отказе.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                _RespondButtons(
                  controller: _controller,
                  check: check,
                  initiatorName: initiatorName,
                  onClose: () => Navigator.of(sheetContext).maybePop(),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<KinshipCheckController>.value(
      value: _controller,
      child: Consumer<KinshipCheckController>(
        builder: (context, controller, _) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Найти родню'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  if (controller.step != DiscoverStep.start) {
                    _resetFlow();
                    return;
                  }
                  final router = GoRouter.of(context);
                  Navigator.of(context).maybePop().then((popped) {
                    if (!popped && mounted) {
                      router.go('/tree');
                    }
                  });
                },
              ),
            ),
            body: SafeArea(
              child: _buildBody(context, controller),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, KinshipCheckController controller) {
    switch (controller.step) {
      case DiscoverStep.start:
        return _buildStartBody(context, controller);
      case DiscoverStep.confirming:
        return _buildConfirmingBody(context, controller);
      case DiscoverStep.sent:
        return _buildSentBody(context, controller);
      case DiscoverStep.result:
        return _buildResultBody(context, controller);
    }
  }

  Widget _buildStartBody(BuildContext context, KinshipCheckController c) {
    final theme = Theme.of(context);
    final pendingReceived = c.pendingReceived;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        if (pendingReceived.isNotEmpty) ...[
          _IncomingPendingBanner(
            checks: pendingReceived,
            onTap: _showRespondSheet,
          ),
          const SizedBox(height: 20),
        ],
        Text(
          'Введите имя, @username, телефон либо email',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Поиск',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
        ),
        const SizedBox(height: 20),
        if (_searchController.text.isEmpty && _searchError == null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withValues(
                alpha: 0.55,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Как это работает',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Здесь можно найти человека, у которого уже есть аккаунт '
                  'Родни. Если аккаунта нет, добавьте его в дерево и '
                  'отправьте приглашение из карточки.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.go('/family'),
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('Открыть семью'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_searchError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _searchError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (_searchResults.isEmpty &&
            _searchController.text.isNotEmpty &&
            !_isSearching &&
            _searchError == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Никого не нашли. Проверьте запрос или добавьте человека '
                  'в дерево, а затем отправьте ему приглашение.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    final treeId = _resolvedTreeId;
                    if (treeId != null) {
                      unawaited(
                        showRelationPickerAndNavigateAdd(
                          context,
                          treeId: treeId,
                        ),
                      );
                      return;
                    }
                    context.go('/family');
                  },
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(
                    _resolvedTreeId != null
                        ? 'Добавить карточку родственника'
                        : 'Добавить человека в дерево',
                  ),
                ),
              ],
            ),
          ),
        for (final profile in _searchResults)
          _SearchResultTile(
            key: ValueKey('discover-result-${profile.id}'),
            profile: profile,
            onTap: () => _selectTarget(profile),
            onAddToTree: (_resolvedTreeId != null &&
                    !_existingTreeUserIds.contains(profile.id))
                ? () => _showRelationSelectDialog(profile)
                : null,
          ),
        if (c.isCapable && c.issued.isNotEmpty) ...[
          const SizedBox(height: 32),
          _IssuedHistorySection(
            checks: c.issued,
            controller: c,
          ),
        ],
      ],
    );
  }

  Widget _buildConfirmingBody(
    BuildContext context,
    KinshipCheckController c,
  ) {
    final theme = Theme.of(context);
    final name = c.selectedTargetDisplayName ?? 'этому человеку';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Отправить запрос?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Чтобы узнать вашу связь с $name, нужно подтверждение '
            'с другой стороны. $name получит уведомление с кнопками '
            '«Подтвердить» / «Отклонить». Результат увидите оба.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const Spacer(),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                c.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          FilledButton(
            onPressed: c.isSubmitting ? null : _submitCheck,
            child: c.isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Отправить запрос'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: c.isSubmitting ? null : c.backToSearch,
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  Widget _buildSentBody(BuildContext context, KinshipCheckController c) {
    final theme = Theme.of(context);
    final name = c.selectedTargetDisplayName ?? 'получателю';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Icon(
            Icons.send_rounded,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Запрос отправлен',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$name получит уведомление. Мы покажем результат, '
            'когда придёт ответ.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _resetFlow,
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultBody(BuildContext context, KinshipCheckController c) {
    final theme = Theme.of(context);
    final check = c.submittedCheck;
    final result = check?.result;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (result == null || !result.found) ...[
            const SizedBox(height: 12),
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Мы не нашли прямой связи',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Это не значит, что её нет — возможно, не хватает '
              'данных в одном из деревьев.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Icon(
              Icons.celebration_rounded,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Вы родственники!',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            RelationChainStrip(
              chain: result.chain,
              edges: result.edges,
            ),
            const SizedBox(height: 12),
            if (result.label.isNotEmpty)
              Text(
                result.label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
          const Spacer(),
          FilledButton(
            onPressed: _resetFlow,
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  static String _displayName(UserProfile profile) {
    final name = profile.displayName.trim();
    if (name.isNotEmpty) return name;
    final composite = '${profile.firstName} ${profile.lastName}'.trim();
    if (composite.isNotEmpty) return composite;
    if (profile.username.isNotEmpty) return '@${profile.username}';
    return 'пользователь';
  }
}

// ── Helper widgets ────────────────────────────────────────────────

/// Плотность (чанк 25): было Card(elevation:0)+ListTile — рамка-в-рамке
/// (каждая строка — отдельная скруглённая карточка на фоне страницы) с
/// паддингом 12/6, ~72dp на строку. Стало — плоская строка 56dp с
/// волосяной линией-разделителем (как остальные списки этого чанка):
/// аватар 40dp (CircleAvatar default radius уже даёт 40dp), имя 16sp,
/// @username/email 13sp, шеврон — визуальная подсказка, вся строка уже
/// тап-цель (высота 56dp ≥ 44dp).
class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    super.key,
    required this.profile,
    required this.onTap,
    this.onAddToTree,
  });

  final UserProfile profile;
  final VoidCallback onTap;
  final VoidCallback? onAddToTree;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = _DiscoverRelativesScreenState._displayName(profile);
    final usernameLine = profile.username.isNotEmpty
        ? '@${profile.username}'
        : (profile.email.isNotEmpty ? profile.email : '');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(
                  alpha: 0.35,
                ),
                width: 0.6,
              ),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage:
                    profile.photoURL != null && profile.photoURL!.isNotEmpty
                        ? NetworkImage(profile.photoURL!)
                        : null,
                child: profile.photoURL == null || profile.photoURL!.isEmpty
                    ? Text(
                        _initialOf(displayName),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (usernameLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        usernameLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (onAddToTree != null)
                IconButton(
                  key: Key('discover-add-relative-${profile.id}'),
                  tooltip: 'Добавить в дерево',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.person_add_alt_1_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  onPressed: onAddToTree,
                ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initialOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}

class _IncomingPendingBanner extends StatelessWidget {
  const _IncomingPendingBanner({
    required this.checks,
    required this.onTap,
  });

  final List<KinshipCheck> checks;
  final ValueChanged<KinshipCheck> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_active_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Запросы вам',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final check in checks)
            InkWell(
              onTap: () => onTap(check),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Кто-то хочет узнать, родственники ли вы',
                        style: theme.textTheme.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IssuedHistorySection extends StatelessWidget {
  const _IssuedHistorySection({
    required this.checks,
    required this.controller,
  });

  final List<KinshipCheck> checks;
  final KinshipCheckController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Limit to last 5 — full history доступна через future
    // «Ваши запросы» screen (Phase 6.5 polish).
    final visible = checks.take(5).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ваши запросы',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        for (final check in visible)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  _statusIcon(check.status),
                  size: 18,
                  color: _statusColor(theme, check.status),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusLabel(check.status),
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Phase 6.5: cancel button для pending issued items.
                // Tap → confirmation dialog → controller.revokeCheck
                // → snackbar feedback. Hidden для terminal statuses.
                if (check.status == KinshipCheckStatus.pending)
                  _RevokeButton(
                    controller: controller,
                    check: check,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  IconData _statusIcon(KinshipCheckStatus s) {
    switch (s) {
      case KinshipCheckStatus.pending:
        return Icons.hourglass_top_rounded;
      case KinshipCheckStatus.accepted:
        return Icons.check_circle_rounded;
      case KinshipCheckStatus.rejected:
        return Icons.cancel_rounded;
      case KinshipCheckStatus.expired:
        return Icons.access_time_filled_rounded;
      case KinshipCheckStatus.revoked:
        return Icons.cancel_schedule_send_rounded;
      case KinshipCheckStatus.unknown:
        return Icons.help_outline_rounded;
    }
  }

  Color _statusColor(ThemeData theme, KinshipCheckStatus s) {
    switch (s) {
      case KinshipCheckStatus.pending:
        return theme.colorScheme.primary;
      case KinshipCheckStatus.accepted:
        return Colors.green.shade600;
      case KinshipCheckStatus.rejected:
        return theme.colorScheme.error;
      case KinshipCheckStatus.expired:
        return theme.colorScheme.onSurfaceVariant;
      case KinshipCheckStatus.revoked:
        return theme.colorScheme.onSurfaceVariant;
      case KinshipCheckStatus.unknown:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  String _statusLabel(KinshipCheckStatus s) {
    switch (s) {
      case KinshipCheckStatus.pending:
        return 'Ожидаем ответа';
      case KinshipCheckStatus.accepted:
        return 'Связь подтверждена';
      case KinshipCheckStatus.rejected:
        return 'Запрос отклонён';
      case KinshipCheckStatus.expired:
        return 'Запрос истёк';
      case KinshipCheckStatus.revoked:
        return 'Запрос отозван';
      case KinshipCheckStatus.unknown:
        return 'Неизвестный статус';
    }
  }
}

/// Phase 6.5: trailing IconButton на pending issued row. Single-tap →
/// confirmation dialog → controller.revokeCheck → snackbar. Action
/// recoverable (initiator может re-create immediately), no double-
/// confirm.
class _RevokeButton extends StatefulWidget {
  const _RevokeButton({
    required this.controller,
    required this.check,
  });

  final KinshipCheckController controller;
  final KinshipCheck check;

  @override
  State<_RevokeButton> createState() => _RevokeButtonState();
}

class _RevokeButtonState extends State<_RevokeButton> {
  bool _isRevoking = false;

  Future<void> _handleTap() async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Отозвать запрос?'),
        content: const Text(
          'Получатель увидит уведомление об отзыве.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Отозвать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isRevoking = true);
    final updated = await widget.controller.revokeCheck(
      checkId: widget.check.id,
    );
    if (!mounted) return;
    setState(() => _isRevoking = false);
    if (updated != null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Запрос отозван')),
      );
    } else {
      final error = widget.controller.error ?? 'Не удалось отозвать запрос';
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isRevoking) {
      return const SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.close_rounded, size: 18),
      tooltip: 'Отозвать запрос',
      visualDensity: VisualDensity.compact,
      onPressed: _handleTap,
    );
  }
}

class _RespondButtons extends StatefulWidget {
  const _RespondButtons({
    required this.controller,
    required this.check,
    required this.initiatorName,
    required this.onClose,
  });

  final KinshipCheckController controller;
  final KinshipCheck check;
  final String initiatorName;
  final VoidCallback onClose;

  @override
  State<_RespondButtons> createState() => _RespondButtonsState();
}

class _RespondButtonsState extends State<_RespondButtons> {
  bool _isResponding = false;

  Future<void> _respond(KinshipCheckDecision decision) async {
    setState(() => _isResponding = true);
    final updated = await widget.controller.respondToCheck(
      checkId: widget.check.id,
      decision: decision,
    );
    if (!mounted) return;
    setState(() => _isResponding = false);
    widget.onClose();
    if (updated == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (decision == KinshipCheckDecision.accepted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Связь подтверждена')),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Запрос отклонён')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _isResponding
              ? null
              : () => _respond(KinshipCheckDecision.accepted),
          icon: const Icon(Icons.check_rounded),
          label: const Text('Подтвердить'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _isResponding
              ? null
              : () => _respond(KinshipCheckDecision.rejected),
          icon: const Icon(Icons.close_rounded),
          label: const Text('Отклонить'),
        ),
        if (_isResponding) ...[
          const SizedBox(height: 12),
          const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
      ],
    );
  }
}
