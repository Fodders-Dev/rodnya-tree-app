// «Спросить историю» MVP-1 (STORY-REQUEST-MVP1-BRIEF.md §3.6): for the
// INITIATOR only, a status line above «Семейные истории» tracking their
// own open questions about this person — «Ждём ответа: {имя} · Отозвать».
// Read-only viewers and the addressee never see this (it's the asker's
// own bookkeeping, not a public thing on the card).
//
// The contract has no personId filter on GET /v1/me/story-requests
// (§1 — role + status only), so this fetches the initiator's pending
// issued requests and filters by personId client-side; the list is
// small (a handful of open asks per person, ever) so this is cheap.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/story_request_capable_family_tree_service.dart';
import '../models/story_request.dart';

class StoryRequestStatusLine extends StatefulWidget {
  const StoryRequestStatusLine({
    super.key,
    required this.personId,
    this.serviceOverride,
    this.authServiceOverride,
  });

  final String personId;

  /// Test seam — production resolves via GetIt (and hides itself when
  /// the registered service doesn't implement the capability).
  final StoryRequestCapableFamilyTreeService? serviceOverride;
  final AuthServiceInterface? authServiceOverride;

  @override
  State<StoryRequestStatusLine> createState() =>
      _StoryRequestStatusLineState();
}

class _StoryRequestStatusLineState extends State<StoryRequestStatusLine> {
  bool _loaded = false;
  List<StoryRequest> _pendingForPerson = const <StoryRequest>[];
  final Set<String> _revoking = <String>{};

  StoryRequestCapableFamilyTreeService? _service() {
    if (widget.serviceOverride != null) return widget.serviceOverride;
    // Production registers ONE FamilyTreeServiceInterface singleton — new
    // capabilities are additive `implements`, not separate GetIt
    // registrations (see discover_relatives_screen.dart for the same
    // pattern with KinshipCheckCapableFamilyTreeService).
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) return null;
    final service = GetIt.I<FamilyTreeServiceInterface>();
    return service is StoryRequestCapableFamilyTreeService
        ? service as StoryRequestCapableFamilyTreeService
        : null;
  }

  AuthServiceInterface? _auth() {
    if (widget.authServiceOverride != null) return widget.authServiceOverride;
    if (GetIt.I.isRegistered<AuthServiceInterface>()) {
      return GetIt.I<AuthServiceInterface>();
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final service = _service();
    final currentUserId = _auth()?.currentUserId;
    if (service == null || currentUserId == null) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    try {
      final issued = await service.listStoryRequests(
        role: 'issued',
        status: StoryRequestStatus.pending,
      );
      if (!mounted) return;
      setState(() {
        _pendingForPerson = issued
            .where((r) =>
                r.personId == widget.personId &&
                r.requesterUserId == currentUserId)
            .toList(growable: false);
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _revoke(StoryRequest request) async {
    final service = _service();
    if (service == null || _revoking.contains(request.id)) return;
    setState(() => _revoking.add(request.id));
    try {
      final updated = await service.revokeStoryRequest(requestId: request.id);
      if (!mounted) return;
      setState(() {
        _revoking.remove(request.id);
        if (updated == null || !updated.isPending) {
          _pendingForPerson =
              _pendingForPerson.where((r) => r.id != request.id).toList();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _revoking.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _pendingForPerson.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      key: const Key('story-request-status-line'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final request in _pendingForPerson)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.hourglass_top_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ждём ответа: ${_targetName(request)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  _revoking.contains(request.id)
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : TextButton(
                          key: Key('story-request-revoke-${request.id}'),
                          onPressed: () => _revoke(request),
                          child: const Text('Отозвать'),
                        ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _targetName(StoryRequest request) {
    final name = request.target?.displayName?.trim();
    return (name != null && name.isNotEmpty) ? name : 'родного';
  }
}
