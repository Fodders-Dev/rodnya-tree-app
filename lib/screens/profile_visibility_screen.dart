// Viewer §3.2.2 (2026-06-02): «Кто видит карточку» — the card-visibility
// radio («Моим родственникам / Только мне / Всем») + the 100-year auto-
// public rule. Wraps the existing VisibilityToggleSection (graph-person
// visibility + setGraphPersonVisibility save) in a dedicated ⋯ screen, so
// it's no longer an inline section on the main card. Per-field visibility
// stays a separate «Видимость по полям» ⋯ entry — nothing is lost.

import 'package:flutter/material.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../widgets/visibility_toggle_section.dart';

class ProfileVisibilityScreen extends StatelessWidget {
  const ProfileVisibilityScreen({
    super.key,
    required this.graphPersonId,
    required this.viewerUserId,
    required this.familyTreeService,
  });

  final String graphPersonId;
  final String viewerUserId;
  final FamilyTreeServiceInterface familyTreeService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Кто видит карточку')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: VisibilityToggleSection(
          graphPersonId: graphPersonId,
          viewerUserId: viewerUserId,
          familyTreeService: familyTreeService,
        ),
      ),
    );
  }
}
