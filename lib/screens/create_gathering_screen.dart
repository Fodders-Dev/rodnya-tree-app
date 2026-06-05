// Phase E2b: «Новая встреча» composer. Reuses the post-composer audience
// widgets (AudiencePicker for circles, cross-branch FilterChips, the
// PersonMultiPickerSheet for branch scope) so the gathering audience model
// (circleId / scopeType / anchorPersonIds / branchIds) matches posts. The
// post-specific extras (presets, public toggle, media) are dropped — a
// gathering has no media and is always within-audience.
//
// Event fields: title (required), startAt date+time (required), optional
// endAt, all-day toggle, place, description.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../backend/interfaces/circle_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/gathering_service_interface.dart';
import '../models/circle.dart';
import '../models/family_person.dart';
import '../models/family_tree.dart';
import '../models/post.dart' show TreeContentScopeType;
import '../providers/tree_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/audience_picker.dart';
import '../widgets/person_multi_picker_sheet.dart';

class CreateGatheringScreen extends StatefulWidget {
  const CreateGatheringScreen({
    super.key,
    this.serviceOverride,
    this.treeServiceOverride,
    this.circleServiceOverride,
    this.treeId,
    this.initialStartAt,
  });

  /// Test seams — production resolves these via GetIt / TreeProvider.
  final GatheringServiceInterface? serviceOverride;
  final FamilyTreeServiceInterface? treeServiceOverride;
  final CircleServiceInterface? circleServiceOverride;
  final String? treeId;
  final DateTime? initialStartAt;

  @override
  State<CreateGatheringScreen> createState() => _CreateGatheringScreenState();
}

class _CreateGatheringScreenState extends State<CreateGatheringScreen> {
  final _titleController = TextEditingController();
  final _placeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  static const int _maxImages = 5;
  List<XFile> _images = <XFile>[];

  late final GatheringServiceInterface _gatheringService =
      widget.serviceOverride ?? GetIt.I<GatheringServiceInterface>();

  String? _treeId;
  bool _isLoading = false;

  DateTime? _startAt;
  DateTime? _endAt;
  bool _isAllDay = false;

  // Audience (mirrors the post composer's four fields).
  TreeContentScopeType _scopeType = TreeContentScopeType.wholeTree;
  String? _selectedCircleId;
  List<FamilyCircle> _audienceCircles = const [];
  bool _isLoadingCircles = false;
  bool _circlesUnavailable = false;
  List<FamilyTree> _otherUserTrees = const [];
  final Set<String> _additionalBranchIds = <String>{};
  List<FamilyPerson> _availablePeople = const [];
  final Set<String> _selectedBranchPersonIds = <String>{};

  FamilyTreeServiceInterface? get _treeService =>
      widget.treeServiceOverride ??
      (GetIt.I.isRegistered<FamilyTreeServiceInterface>()
          ? GetIt.I<FamilyTreeServiceInterface>()
          : null);

  CircleServiceInterface? get _circleService =>
      widget.circleServiceOverride ??
      (GetIt.I.isRegistered<CircleServiceInterface>()
          ? GetIt.I<CircleServiceInterface>()
          : null);

  @override
  void initState() {
    super.initState();
    _startAt = widget.initialStartAt;
    _treeId = widget.treeId;
    if (_treeId == null) {
      try {
        _treeId =
            Provider.of<TreeProvider>(context, listen: false).selectedTreeId;
      } catch (_) {
        _treeId = null;
      }
    }
    _loadAudienceCircles();
    _loadBranchCandidates();
    _loadOtherUserTrees();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _placeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadAudienceCircles() async {
    final treeId = _treeId;
    final circleService = _circleService;
    if (treeId == null || circleService == null) return;
    setState(() => _isLoadingCircles = true);
    try {
      final circles = await circleService.getCircles(treeId);
      if (!mounted) return;
      setState(() {
        _audienceCircles = circles;
        _selectedCircleId = _resolveSelectedCircleId(circles);
        _circlesUnavailable = false;
      });
    } catch (_) {
      if (mounted) setState(() => _circlesUnavailable = true);
    } finally {
      if (mounted) setState(() => _isLoadingCircles = false);
    }
  }

  String? _resolveSelectedCircleId(List<FamilyCircle> circles) {
    final current = _selectedCircleId;
    if (current != null && circles.any((c) => c.id == current)) return current;
    for (final circle in circles) {
      if (circle.isAllTree) return circle.id;
    }
    return circles.isEmpty ? null : circles.first.id;
  }

  Future<void> _loadBranchCandidates() async {
    final treeId = _treeId;
    final treeService = _treeService;
    if (treeId == null || treeService == null) return;
    try {
      final people = await treeService.getRelatives(treeId);
      if (!mounted) return;
      final sorted = List<FamilyPerson>.from(people)
        ..sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      setState(() => _availablePeople = sorted);
    } catch (_) {
      // Best-effort — the branch picker just stays empty.
    }
  }

  Future<void> _loadOtherUserTrees() async {
    final treeId = _treeId;
    final treeService = _treeService;
    if (treeId == null || treeService == null) return;
    try {
      final trees = await treeService.getUserTrees();
      if (!mounted) return;
      setState(() {
        _otherUserTrees =
            trees.where((t) => t.id != treeId).toList(growable: false);
      });
    } catch (_) {
      // Best-effort — cross-branch section stays hidden.
    }
  }

  Future<void> _pickStartAt() async {
    final base = _startAt ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    if (_isAllDay) {
      setState(() => _startAt = DateTime(date.year, date.month, date.day));
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (!mounted) return;
    setState(() {
      _startAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? base.hour,
        time?.minute ?? base.minute,
      );
    });
  }

  Future<void> _pickEndAt() async {
    final base = _endAt ?? _startAt ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    if (_isAllDay) {
      setState(() => _endAt = DateTime(date.year, date.month, date.day));
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (!mounted) return;
    setState(() {
      _endAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? base.hour,
        time?.minute ?? base.minute,
      );
    });
  }

  String _formatDateTime(DateTime value) {
    return _isAllDay
        ? DateFormat('d MMMM y', 'ru').format(value)
        : DateFormat('d MMMM y, HH:mm', 'ru').format(value);
  }

  Future<void> _pickImages() async {
    try {
      final picked = await _picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: 1080,
      );
      if (picked.isEmpty || !mounted) return;
      final willTrim = _images.length + picked.length > _maxImages;
      setState(() {
        _images = <XFile>[..._images, ...picked].take(_maxImages).toList();
      });
      if (willTrim) _showMessage('Можно прикрепить не более $_maxImages фото.');
    } catch (_) {
      if (mounted) _showMessage('Не удалось выбрать фото.');
    }
  }

  void _removeImage(int index) {
    setState(() {
      _images = <XFile>[..._images]..removeAt(index);
    });
  }

  Future<void> _create() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage('Укажите название встречи');
      return;
    }
    if (_startAt == null) {
      _showMessage('Укажите дату и время встречи');
      return;
    }
    final treeId = _treeId;
    if (treeId == null) {
      _showMessage('Сначала выберите дерево на главной');
      return;
    }
    if (_scopeType == TreeContentScopeType.branches &&
        _selectedBranchPersonIds.isEmpty) {
      _showMessage('Выберите хотя бы одну ветку');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final branchIdsForRequest = _additionalBranchIds.isEmpty
          ? null
          : <String>{treeId, ..._additionalBranchIds}.toList();
      final description = _descriptionController.text.trim();
      final place = _placeController.text.trim();
      await _gatheringService.createGathering(
        treeId: treeId,
        title: title,
        description: description.isEmpty ? null : description,
        startAt: _startAt!,
        endAt: _endAt,
        isAllDay: _isAllDay,
        place: place.isEmpty ? null : place,
        images: _images,
        scopeType: _scopeType,
        anchorPersonIds: _selectedBranchPersonIds.toList(),
        circleId: _selectedCircleId,
        branchIds: branchIdsForRequest,
      );
      if (mounted) {
        _showMessage('Встреча создана');
        context.pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Не удалось создать встречу. Попробуйте ещё раз.');
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая встреча'),
        actions: [
          TextButton(
            key: const Key('gathering-submit'),
            onPressed: _isLoading ? null : _create,
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Создать'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            tokens.space16,
            tokens.space16,
            tokens.space16,
            tokens.space16 + MediaQuery.of(context).viewPadding.bottom,
          ),
          children: [
            TextField(
              key: const Key('gathering-title-field'),
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Название встречи',
                hintText: 'Например, шашлыки на даче',
              ),
            ),
            SizedBox(height: tokens.space16),
            _buildDateTimeSection(theme, tokens),
            SizedBox(height: tokens.space16),
            TextField(
              key: const Key('gathering-place-field'),
              controller: _placeController,
              decoration: const InputDecoration(
                labelText: 'Место (необязательно)',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            SizedBox(height: tokens.space16),
            TextField(
              key: const Key('gathering-description-field'),
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Описание (необязательно)',
                alignLabelWithHint: true,
              ),
            ),
            SizedBox(height: tokens.space16),
            _buildMediaSection(theme, tokens),
            SizedBox(height: tokens.space16),
            _buildAudienceSection(theme, tokens),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeSection(ThemeData theme, RodnyaDesignTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          key: const Key('gathering-allday-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Весь день'),
          value: _isAllDay,
          onChanged: (value) => setState(() => _isAllDay = value),
        ),
        ListTile(
          key: const Key('gathering-start-tile'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: const Text('Начало'),
          subtitle: Text(
            _startAt == null
                ? 'Выбрать дату и время'
                : _formatDateTime(_startAt!),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickStartAt,
        ),
        ListTile(
          key: const Key('gathering-end-tile'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_available_outlined),
          title: const Text('Конец (необязательно)'),
          subtitle: Text(
            _endAt == null ? 'Не задан' : _formatDateTime(_endAt!),
          ),
          trailing: _endAt == null
              ? const Icon(Icons.chevron_right)
              : IconButton(
                  tooltip: 'Убрать',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _endAt = null),
                ),
          onTap: _pickEndAt,
        ),
      ],
    );
  }

  Widget _buildMediaSection(ThemeData theme, RodnyaDesignTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Фото (необязательно)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: tokens.ink,
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('gathering-add-photo'),
              onPressed: _images.length >= _maxImages ? null : _pickImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                _images.isEmpty ? 'Добавить' : '${_images.length}/$_maxImages',
              ),
            ),
          ],
        ),
        if (_images.isNotEmpty) ...[
          SizedBox(height: tokens.space8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              separatorBuilder: (_, __) => SizedBox(width: tokens.space8),
              itemBuilder: (_, i) => _buildImageThumb(theme, tokens, i),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImageThumb(
    ThemeData theme,
    RodnyaDesignTokens tokens,
    int index,
  ) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          child: SizedBox(
            width: 96,
            height: 96,
            child: FutureBuilder<Uint8List>(
              future: _images[index].readAsBytes(),
              builder: (_, snapshot) {
                if (snapshot.hasData) {
                  return Image.memory(snapshot.data!, fit: BoxFit.cover);
                }
                return Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                );
              },
            ),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            key: Key('gathering-remove-photo-$index'),
            onTap: () => _removeImage(index),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudienceSection(ThemeData theme, RodnyaDesignTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Кого зовём?',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: tokens.ink,
          ),
        ),
        SizedBox(height: tokens.space8),
        AudiencePicker(
          circles: _audienceCircles,
          selectedCircleId: _selectedCircleId,
          onChanged: (circleId) {
            setState(() {
              _selectedCircleId = circleId;
              _selectedBranchPersonIds.clear();
              _scopeType = TreeContentScopeType.wholeTree;
            });
          },
          isLoading: _isLoadingCircles,
          isUnavailable: _circlesUnavailable,
          onRetry: _loadAudienceCircles,
        ),
        if (_availablePeople.isNotEmpty) ...[
          SizedBox(height: tokens.space12),
          _buildBranchPickerTile(theme, tokens),
        ],
        if (_otherUserTrees.isNotEmpty) ...[
          SizedBox(height: tokens.space12),
          _buildCrossBranchSection(theme, tokens),
        ],
      ],
    );
  }

  Widget _buildBranchPickerTile(ThemeData theme, RodnyaDesignTokens tokens) {
    final count = _selectedBranchPersonIds.length;
    return ListTile(
      key: const Key('gathering-branch-tile'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.alt_route_outlined),
      title: Text(count == 0 ? 'Отдельные ветки' : 'Выбрано: $count'),
      subtitle: const Text('Сузить до выбранных людей и их веток'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final result = await PersonMultiPickerSheet.show(
          context,
          people: _availablePeople,
          initialSelection: Set<String>.from(_selectedBranchPersonIds),
          title: 'Отдельные ветки',
        );
        if (result == null || !mounted) return;
        setState(() {
          _selectedCircleId = null;
          _selectedBranchPersonIds
            ..clear()
            ..addAll(result);
          _scopeType = _selectedBranchPersonIds.isEmpty
              ? TreeContentScopeType.wholeTree
              : TreeContentScopeType.branches;
        });
      },
    );
  }

  Widget _buildCrossBranchSection(ThemeData theme, RodnyaDesignTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Позвать также в:',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: tokens.ink,
          ),
        ),
        SizedBox(height: tokens.space8),
        Wrap(
          spacing: tokens.space8,
          runSpacing: tokens.space8,
          children: _otherUserTrees.map((tree) {
            final selected = _additionalBranchIds.contains(tree.id);
            return FilterChip(
              label: Text(tree.name),
              selected: selected,
              onSelected: (next) {
                setState(() {
                  if (next) {
                    _additionalBranchIds.add(tree.id);
                  } else {
                    _additionalBranchIds.remove(tree.id);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
