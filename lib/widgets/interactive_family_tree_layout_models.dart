part of 'interactive_family_tree.dart';

class FamilyConnection {
  FamilyConnection({
    required this.fromId,
    required this.toId,
    required this.type,
    this.isPastUnion = false,
  });

  final String fromId;
  final String toId;
  final RelationType type;

  /// F2: бывший союз (развод/ex-партнёрство) — рисуется пунктиром.
  final bool isPastUnion;
}

class _TreeLayoutComputation {
  const _TreeLayoutComputation({
    required this.nodePositions,
    required this.connections,
    required this.treeSize,
  });

  final Map<String, Offset> nodePositions;
  final List<FamilyConnection> connections;
  final Size treeSize;
}

class _SpouseGroup {
  const _SpouseGroup({required this.memberIds});

  final List<String> memberIds;
}
