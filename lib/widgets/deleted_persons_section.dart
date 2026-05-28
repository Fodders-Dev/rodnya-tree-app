// Ship Q4a frontend (2026-05-28, Ship 31b): per-семя «Удалённые»
// entry tile для FE2 семя details screen. Self-loading counter →
// tap pushes SemyaDeletedPersonsScreen.
//
// Visibility: rendered ТОЛЬКО когда семья has ≥1 soft-deleted person.
// Empty семья → SizedBox.shrink (no noise — global Корзина в настройках
// остаётся always-available discovery path). Load failure → также
// silent (secondary feature; details screen НЕ должен ломаться из-за
// counter blip).
//
// Member-only by construction — parent details body render'ится только
// после successful findSemyaById (requires membership), и backend
// list endpoint enforces membership independently.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../screens/semya_deleted_persons_screen.dart';
import 'deleted_item_row.dart';

class DeletedPersonsSection extends StatefulWidget {
  const DeletedPersonsSection({
    super.key,
    required this.semyaId,
    this.semyaName,
    this.serviceOverride,
  });

  final String semyaId;
  final String? semyaName;

  /// Test seam — production resolves via GetIt.
  final SemyaCapableFamilyTreeService? serviceOverride;

  @override
  State<DeletedPersonsSection> createState() => _DeletedPersonsSectionState();
}

class _DeletedPersonsSectionState extends State<DeletedPersonsSection> {
  bool _hasLoaded = false;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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

  Future<void> _load() async {
    final svc = _resolveService();
    if (svc == null) {
      if (mounted) setState(() => _hasLoaded = true);
      return;
    }
    try {
      final rows = await svc.listDeletedPersonsForSemya(widget.semyaId);
      if (!mounted) return;
      setState(() {
        _count = rows.length;
        _hasLoaded = true;
      });
    } catch (_) {
      // Best-effort — secondary feature. Silent degrade: section
      // stays hidden, global Корзина handles management.
      if (!mounted) return;
      setState(() => _hasLoaded = true);
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SemyaDeletedPersonsScreen(
          semyaId: widget.semyaId,
          semyaName: widget.semyaName,
        ),
      ),
    );
    // Refresh counter — user may have restored/purged items on the
    // dedicated screen.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    // Hidden until we know there's something to manage.
    if (!_hasLoaded || _count == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return ListTile(
      key: const Key('semya-details-deleted-persons-section'),
      leading: Icon(
        Icons.delete_outline_rounded,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text('Удалённые родственники ($_count)'),
      subtitle: Text(
        'Восстановить или удалить навсегда · хранятся 30 ${deletedDaysLabel(30)}',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: _open,
    );
  }
}
