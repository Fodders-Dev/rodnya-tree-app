class PersonAttribute {
  const PersonAttribute({
    required this.id,
    required this.identityId,
    required this.sourcePersonId,
    required this.field,
    required this.visibility,
    required this.updatedAt,
    this.value,
  });

  final String id;
  final String identityId;
  final String sourcePersonId;
  final String field;
  final Object? value;
  final String visibility;
  final DateTime updatedAt;

  factory PersonAttribute.fromJson(Map<String, dynamic> json) {
    return PersonAttribute(
      id: json['id']?.toString() ?? '',
      identityId: json['identityId']?.toString() ?? '',
      sourcePersonId: json['sourcePersonId']?.toString() ?? '',
      field: json['field']?.toString() ?? '',
      value: json['value'],
      visibility: json['visibility']?.toString() ?? 'private',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
