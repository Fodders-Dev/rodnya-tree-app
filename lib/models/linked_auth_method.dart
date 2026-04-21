class LinkedAuthMethod {
  const LinkedAuthMethod({
    required this.id,
    required this.label,
    required this.isLinked,
    required this.isReady,
    required this.description,
  });

  final String id;
  final String label;
  final bool isLinked;
  final bool isReady;
  final String description;
}
