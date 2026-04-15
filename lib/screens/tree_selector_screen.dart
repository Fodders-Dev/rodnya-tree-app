// ignore_for_file: library_private_types_in_public_api
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../models/family_tree.dart';
import '../providers/tree_provider.dart';
import '../services/public_tree_link_service.dart';
import '../widgets/glass_panel.dart';

class TreeSelectorScreen extends StatefulWidget {
  const TreeSelectorScreen({super.key});

  @override
  _TreeSelectorScreenState createState() => _TreeSelectorScreenState();
}

class _TreeSelectorScreenState extends State<TreeSelectorScreen> {
  final AuthServiceInterface? _authService =
      GetIt.I.isRegistered<AuthServiceInterface>()
          ? GetIt.I<AuthServiceInterface>()
          : null;
  final FamilyTreeServiceInterface _familyTreeService =
      GetIt.I<FamilyTreeServiceInterface>();

  bool _isLoading = true;
  List<FamilyTree> _userTrees = [];
  String _errorMessage = '';
  String? _selectingTreeId;

  @override
  void initState() {
    super.initState();
    _loadUserTrees();
  }

  Future<void> _loadUserTrees() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final trees = await _familyTreeService.getUserTrees();
      if (!mounted) return;

      setState(() {
        _userTrees = trees;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки деревьев: $e');
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Не удалось загрузить список деревьев.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Деревья'),
        actions: [
          if (isCompact)
            IconButton(
              tooltip: 'Каталог',
              onPressed: () => context.push('/trees'),
              icon: const Icon(Icons.explore_outlined),
            )
          else
            TextButton.icon(
              onPressed: () => context.push('/trees'),
              icon: const Icon(Icons.explore_outlined),
              label: const Text('Каталог'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.07),
              theme.colorScheme.surface,
              theme.colorScheme.secondary.withValues(alpha: 0.04),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage.isNotEmpty
                      ? _buildErrorState()
                      : _userTrees.isEmpty
                          ? _buildEmptyState()
                          : _buildTreeList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: GlassPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 14),
              Text(
                'Не удалось загрузить деревья',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _loadUserTrees,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: GlassPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  Icons.account_tree_outlined,
                  color: theme.colorScheme.primary,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Создайте дерево',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Или откройте приглашение.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Семья'),
                    onPressed: _openCreateTree,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.diversity_3_outlined),
                    label: const Text('Круг'),
                    onPressed: _openCreateFriendsTree,
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/trees'),
                    icon: const Icon(Icons.mail_outline),
                    label: const Text('Приглашения'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTreeList() {
    final treeProvider = context.read<TreeProvider>();
    final selectedTreeId = context.select<TreeProvider, String?>(
      (provider) => provider.selectedTreeId,
    );
    final currentTree = selectedTreeId == null
        ? null
        : _userTrees.cast<FamilyTree?>().firstWhere(
              (tree) => tree?.id == selectedTreeId,
              orElse: () => null,
            );
    final ownTrees = _userTrees
        .where(
          (tree) => _isOwnedByCurrentUser(tree) && tree.id != selectedTreeId,
        )
        .toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    final memberTrees = _userTrees
        .where(
          (tree) => !_isOwnedByCurrentUser(tree) && tree.id != selectedTreeId,
        )
        .toList()
      ..sort((left, right) => left.name.compareTo(right.name));

    return RefreshIndicator(
      onRefresh: _loadUserTrees,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          GlassPanel(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ваши деревья',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (currentTree != null)
                      _SelectorChip(
                        icon: Icons.check_circle_outline,
                        label: currentTree.name,
                        highlighted: true,
                      ),
                    _SelectorChip(
                      icon: Icons.forest_outlined,
                      label: '${_userTrees.length}',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _openCreateTree,
                      icon: const Icon(Icons.add),
                      label: const Text('Семья'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openCreateFriendsTree,
                      icon: const Icon(Icons.diversity_3_outlined),
                      label: const Text('Круг'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loadUserTrees,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Обновить'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (currentTree != null) ...[
            const _SelectorSectionHeader(title: 'Активное'),
            _buildTreeCard(
              tree: currentTree,
              treeProvider: treeProvider,
              isSelected: true,
            ),
          ],
          if (ownTrees.isNotEmpty) ...[
            _SelectorSectionHeader(
              title: ownTrees.length == 1 ? 'Моё дерево' : 'Мои',
            ),
            ...ownTrees.map(
              (tree) => _buildTreeCard(
                tree: tree,
                treeProvider: treeProvider,
                isSelected: false,
              ),
            ),
          ],
          if (memberTrees.isNotEmpty) ...[
            _SelectorSectionHeader(
              title: memberTrees.length == 1 ? 'Приглашение' : 'Другие',
            ),
            ...memberTrees.map(
              (tree) => _buildTreeCard(
                tree: tree,
                treeProvider: treeProvider,
                isSelected: false,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTreeCard({
    required FamilyTree tree,
    required TreeProvider treeProvider,
    required bool isSelected,
  }) {
    final treeId = tree.id;
    final treeName = tree.name;
    final createdAt = tree.createdAt;
    final certificationNote = tree.certificationNote?.trim();
    final isSelecting = _selectingTreeId == treeId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: isSelecting
              ? null
              : () async {
                  setState(() {
                    _selectingTreeId = treeId;
                  });
                  await treeProvider.selectTree(
                    treeId,
                    treeName,
                    treeKind: tree.kind,
                  );
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _selectingTreeId = null;
                  });
                  final encodedName = Uri.encodeComponent(treeName);
                  if (!context.mounted) {
                    return;
                  }
                  context.go('/tree/view/$treeId?name=$encodedName');
                },
          child: GlassPanel(
            color: isSelected
                ? Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.56)
                : null,
            borderRadius: BorderRadius.circular(28),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Icon(
                    tree.isFriendsTree
                        ? Icons.diversity_3_outlined
                        : Icons.account_tree,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        treeName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _SelectorChip(
                            icon: tree.isPrivate
                                ? Icons.lock_outline
                                : Icons.public,
                            label: tree.isPrivate ? 'Приватное' : 'Публичное',
                          ),
                          _SelectorChip(
                            icon: tree.isFriendsTree
                                ? Icons.diversity_3_outlined
                                : Icons.family_restroom,
                            label: tree.kindLabel,
                          ),
                          _SelectorChip(
                            icon: _isOwnedByCurrentUser(tree)
                                ? Icons.star_outline
                                : Icons.groups_2_outlined,
                            label: _isOwnedByCurrentUser(tree)
                                ? 'Создатель'
                                : 'Участник',
                          ),
                          if (tree.isCertified)
                            const _SelectorChip(
                              icon: Icons.verified_outlined,
                              label: 'Проверено',
                              highlighted: true,
                            ),
                          if (isSelected)
                            const _SelectorChip(
                              icon: Icons.check_circle_outline,
                              label: 'Сейчас',
                              highlighted: true,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatDate(createdAt),
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      if (certificationNote != null &&
                          certificationNote.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          certificationNote,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                isSelecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (tree.isPublic)
                            IconButton(
                              tooltip: 'Скопировать публичную ссылку',
                              onPressed: () => _copyPublicLink(tree),
                              icon: const Icon(Icons.link_outlined),
                            ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  Future<void> _copyPublicLink(FamilyTree tree) async {
    final publicUri = PublicTreeLinkService.buildPublicTreeUri(
      tree.publicRouteId,
      publicAppUrl: BackendRuntimeConfig.current.publicAppUrl,
    );
    await Clipboard.setData(ClipboardData(text: publicUri.toString()));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Публичная ссылка скопирована.')),
    );
  }

  void _openCreateTree() {
    context.push('/trees/create').then((result) {
      if (result == true) {
        _loadUserTrees();
      }
    });
  }

  void _openCreateFriendsTree() {
    context.push('/trees/create?kind=friends').then((result) {
      if (result == true) {
        _loadUserTrees();
      }
    });
  }

  bool _isOwnedByCurrentUser(FamilyTree tree) {
    final currentUserId = _authService?.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return true;
    }
    return tree.creatorId == currentUserId;
  }
}

class _SelectorSectionHeader extends StatelessWidget {
  const _SelectorSectionHeader({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectorChip extends StatelessWidget {
  const _SelectorChip({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chipBackground = highlighted
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.82);
    final chipForeground = highlighted
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipForeground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: chipForeground,
            ),
          ),
        ],
      ),
    );
  }
}
