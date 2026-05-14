import 'package:flutter/material.dart';

import '../backend/models/blood_relation.dart';

/// Phase 6 chunk 3 (PHASE-6-PROPOSAL.md §2.4 + §5): horizontal strip
/// of avatars + edge labels rendering [BloodRelation.chain]. Each
/// node:
///   • visible (name non-null) → avatar circle + name pill.
///   • invisible (name null per privacy fence §5) → «?» placeholder.
///
/// Used:
///   • Discover screen «Step 4: Result» — accepted kinship check.
///   • Future: any place needing BFS chain render (extended view,
///     pinch-zoom person card).
class RelationChainStrip extends StatelessWidget {
  const RelationChainStrip({
    super.key,
    required this.chain,
    this.edges = const <String>[],
    this.minAvatarRadius = 22,
  });

  /// Hydrated chain previews — anonymized nodes have `name == null`.
  final List<BloodRelationPersonPreview> chain;

  /// Edge labels between chain nodes (length = chain.length - 1).
  /// Values: 'parent' | 'child' | 'sibling'. Translated to Russian
  /// inline. Если пустой — рендерится только `→` arrow.
  final List<String> edges;

  final double minAvatarRadius;

  @override
  Widget build(BuildContext context) {
    if (chain.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    final widgets = <Widget>[];
    for (var i = 0; i < chain.length; i++) {
      widgets.add(_buildNode(theme, chain[i]));
      if (i < chain.length - 1) {
        final edgeLabel = i < edges.length
            ? _russianEdgeLabel(edges[i])
            : null;
        widgets.add(_buildEdge(theme, edgeLabel));
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: widgets,
      ),
    );
  }

  Widget _buildNode(ThemeData theme, BloodRelationPersonPreview node) {
    final isAnonymized = node.name == null || node.name!.trim().isEmpty;
    final displayName = isAnonymized ? '?' : _firstNameOnly(node.name!);
    final hasPhoto = !isAnonymized &&
        node.photoUrl != null &&
        node.photoUrl!.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: minAvatarRadius,
          backgroundColor: isAnonymized
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.primaryContainer,
          backgroundImage: hasPhoto ? NetworkImage(node.photoUrl!) : null,
          child: hasPhoto
              ? null
              : Text(
                  isAnonymized
                      ? '?'
                      : _initialFromName(node.name!),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isAnonymized
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 84),
          child: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: isAnonymized
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEdge(ThemeData theme, String? russianLabel) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          if (russianLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              russianLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _firstNameOnly(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return trimmed;
    final firstSpace = trimmed.indexOf(' ');
    if (firstSpace == -1) return trimmed;
    return trimmed.substring(0, firstSpace);
  }

  static String _initialFromName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  /// Russian edge label mapping. Phase 4 privacy language matrix
  /// (PHASE-6-PROPOSAL.md §4) — no technical terms; everyday родственные
  /// слова.
  static String? _russianEdgeLabel(String edge) {
    switch (edge) {
      case 'parent':
        return 'родитель';
      case 'child':
        return 'ребёнок';
      case 'sibling':
        return 'брат/сестра';
      default:
        return null;
    }
  }
}
