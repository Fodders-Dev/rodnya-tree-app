import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/circle_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../models/circle.dart';
import '../models/family_person.dart';
import '../utils/user_facing_error.dart';
import 'person_multi_picker_sheet.dart';

/// Opens a bottom sheet for viewing, creating, renaming, editing members of,
/// and deleting custom [FamilyCircle]s on a tree. Returns `true` if any change
/// occurred so callers (e.g. audience picker) can refresh their list.
Future<bool?> showManageCirclesSheet(
  BuildContext context, {
  required String treeId,
  required String viewerUserId,
  required bool canCreate,
  required bool isOwner,
  CircleServiceInterface? circleService,
  FamilyTreeServiceInterface? treeService,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ManageCirclesSheet(
      treeId: treeId,
      viewerUserId: viewerUserId,
      canCreate: canCreate,
      isOwner: isOwner,
      circleService: circleService,
      treeService: treeService,
    ),
  );
}

class _ManageCirclesSheet extends StatefulWidget {
  const _ManageCirclesSheet({
    required this.treeId,
    required this.viewerUserId,
    required this.canCreate,
    required this.isOwner,
    this.circleService,
    this.treeService,
  });

  final String treeId;
  final String viewerUserId;
  final bool canCreate;
  final bool isOwner;
  final CircleServiceInterface? circleService;
  final FamilyTreeServiceInterface? treeService;

  @override
  State<_ManageCirclesSheet> createState() => _ManageCirclesSheetState();
}

class _ManageCirclesSheetState extends State<_ManageCirclesSheet> {
  CircleServiceInterface? get _circles {
    if (widget.circleService != null) return widget.circleService;
    if (GetIt.I.isRegistered<CircleServiceInterface>()) {
      return GetIt.I<CircleServiceInterface>();
    }
    return null;
  }

  FamilyTreeServiceInterface? get _trees {
    if (widget.treeService != null) return widget.treeService;
    if (GetIt.I.isRegistered<FamilyTreeServiceInterface>()) {
      return GetIt.I<FamilyTreeServiceInterface>();
    }
    return null;
  }

  List<FamilyCircle> _circleList = const <FamilyCircle>[];
  List<FamilyPerson> _relatives = const <FamilyPerson>[];
  bool _loading = true;
  bool _mutating = false;
  bool _mutated = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = _circles;
    if (service == null) {
      setState(() {
        _loading = false;
        _error = 'Сервис кругов недоступен.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final circles = await service.getCircles(widget.treeId);
      List<FamilyPerson> people = _relatives;
      final treeService = _trees;
      if (treeService != null) {
        try {
          people = await treeService.getRelatives(widget.treeId);
        } catch (_) {
          // Optional relatives load — creation/rename still works without members.
        }
      }
      if (!mounted) return;
      setState(() {
        _circleList = circles
            .where((c) => c.isCustom || c.isFavorites)
            .toList(growable: false);
        _relatives = people;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = humanizeError(error, fallback: 'Не удалось загрузить круги.');
      });
    }
  }

  bool _canManage(FamilyCircle circle) {
    if (!circle.isCustom && !circle.isFavorites) {
      return false;
    }
    if (widget.isOwner) {
      return true;
    }
    final createdBy = circle.createdBy?.trim();
    return createdBy != null &&
        createdBy.isNotEmpty &&
        createdBy == widget.viewerUserId;
  }

  Future<void> _openCreateDialog() async {
    final result = await showDialog<_CircleFormResult>(
      context: context,
      builder: (_) => const _CircleFormDialog(
        title: 'Новый круг',
        descriptionLabel: 'Описание (необязательно)',
        submitLabel: 'Создать',
      ),
    );
    if (result == null || !mounted) return;
    final service = _circles;
    if (service == null) return;

    setState(() => _mutating = true);
    try {
      final created = await service.createCircle(
        treeId: widget.treeId,
        name: result.name,
        description: result.description,
      );
      _mutated = true;

      if (_relatives.isNotEmpty && mounted) {
        final picked = await PersonMultiPickerSheet.show(
          context,
          people: _relatives,
          initialSelection: const <String>{},
          title: 'Участники «${created.name}»',
        );
        if (picked != null && picked.isNotEmpty && mounted) {
          await service.replaceCircleMembers(
            treeId: widget.treeId,
            circleId: created.id,
            personIds: picked.toList(growable: false),
          );
        }
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              humanizeError(error, fallback: 'Не удалось создать круг.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _mutating = false);
      }
    }
  }

  Future<void> _openEditDialog(FamilyCircle circle) async {
    final result = await showDialog<_CircleFormResult>(
      context: context,
      builder: (_) => _CircleFormDialog(
        title: 'Изменить круг',
        descriptionLabel: 'Описание',
        submitLabel: 'Сохранить',
        initialName: circle.name,
        initialDescription: circle.description ?? '',
      ),
    );
    if (result == null || !mounted) return;
    final service = _circles;
    if (service == null) return;

    setState(() => _mutating = true);
    try {
      await service.updateCircle(
        treeId: widget.treeId,
        circleId: circle.id,
        name: result.name,
        description: result.description ?? '',
      );
      _mutated = true;
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              humanizeError(error, fallback: 'Не удалось обновить круг.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _mutating = false);
      }
    }
  }

  Future<void> _editMembers(FamilyCircle circle) async {
    final service = _circles;
    if (service == null) return;
    if (_relatives.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала добавьте людей в семейное дерево.'),
        ),
      );
      return;
    }

    setState(() => _mutating = true);
    try {
      final identityIds = await service.getCircleMemberIdentityIds(
        treeId: widget.treeId,
        circleId: circle.id,
      );
      if (!mounted) return;
      final identitySet = identityIds.toSet();
      final initialPersonIds = _relatives
          .where(
              (p) => p.identityId != null && identitySet.contains(p.identityId))
          .map((p) => p.id)
          .toSet();
      setState(() => _mutating = false);

      final picked = await PersonMultiPickerSheet.show(
        context,
        people: _relatives,
        initialSelection: initialPersonIds,
        title: 'Участники «${circle.name}»',
      );
      if (picked == null || !mounted) return;

      setState(() => _mutating = true);
      await service.replaceCircleMembers(
        treeId: widget.treeId,
        circleId: circle.id,
        personIds: picked.toList(growable: false),
      );
      _mutated = true;
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              humanizeError(error,
                  fallback: 'Не удалось обновить состав круга.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _mutating = false);
      }
    }
  }

  Future<void> _confirmAndDelete(FamilyCircle circle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Удалить круг «${circle.name}»?'),
        content: const Text(
          'Все посты, истории, опросы и встречи, опубликованные в этот круг, '
          'станут видны всему семейному дереву.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('circle-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final service = _circles;
    if (service == null) return;

    setState(() => _mutating = true);
    try {
      await service.deleteCircle(treeId: widget.treeId, circleId: circle.id);
      _mutated = true;
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              humanizeError(error, fallback: 'Не удалось удалить круг.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _mutating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop(_mutated);
        }
      },
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.78,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Круги аудиторий',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.canCreate)
                      FilledButton.tonalIcon(
                        key: const Key('circles-create-btn'),
                        onPressed: _mutating ? null : _openCreateDialog,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Создать'),
                      ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.of(context).pop(_mutated),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  )
                else if (_circleList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Пользовательских кругов пока нет.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _circleList.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final circle = _circleList[index];
                        final canManage = _canManage(circle);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            circle.isFavorites
                                ? Icons.star_outline_rounded
                                : Icons.group_work_outlined,
                          ),
                          title: Text(circle.name),
                          subtitle: Text(
                            [
                              '${circle.memberCount} чел.',
                              if ((circle.description ?? '').trim().isNotEmpty)
                                circle.description!.trim(),
                              if (!canManage) 'Только автор или владелец',
                            ].join(' · '),
                          ),
                          trailing: canManage
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: Key('circle-members-${circle.id}'),
                                      tooltip: 'Состав',
                                      onPressed: _mutating
                                          ? null
                                          : () => _editMembers(circle),
                                      icon: const Icon(Icons.group_outlined),
                                    ),
                                    IconButton(
                                      key: Key('circle-edit-${circle.id}'),
                                      tooltip: 'Изменить',
                                      onPressed: _mutating
                                          ? null
                                          : () => _openEditDialog(circle),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    if (!circle.isSystem && circle.isCustom)
                                      IconButton(
                                        key: Key('circle-delete-${circle.id}'),
                                        tooltip: 'Удалить',
                                        onPressed: _mutating
                                            ? null
                                            : () => _confirmAndDelete(circle),
                                        icon: Icon(
                                          Icons.delete_outline,
                                          color: theme.colorScheme.error,
                                        ),
                                      ),
                                  ],
                                )
                              : null,
                        );
                      },
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

class _CircleFormResult {
  const _CircleFormResult({
    required this.name,
    this.description,
  });

  final String name;
  final String? description;
}

class _CircleFormDialog extends StatefulWidget {
  const _CircleFormDialog({
    required this.title,
    required this.descriptionLabel,
    required this.submitLabel,
    this.initialName = '',
    this.initialDescription = '',
  });

  final String title;
  final String descriptionLabel;
  final String submitLabel;
  final String initialName;
  final String initialDescription;

  @override
  State<_CircleFormDialog> createState() => _CircleFormDialogState();
}

class _CircleFormDialogState extends State<_CircleFormDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _descController =
      TextEditingController(text: widget.initialDescription);

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nameController.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('circle-form-name'),
            controller: _nameController,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Название',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('circle-form-description'),
            controller: _descController,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: widget.descriptionLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const Key('circle-form-save'),
          onPressed: canSave
              ? () {
                  final rawDesc = _descController.text.trim();
                  Navigator.of(context).pop(
                    _CircleFormResult(
                      name: _nameController.text.trim(),
                      description: rawDesc.isEmpty ? null : rawDesc,
                    ),
                  );
                }
              : null,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}
