class AccountLinkedIdentity {
  const AccountLinkedIdentity({
    required this.provider,
    this.linkedAt,
    this.lastUsedAt,
    this.emailMasked,
    this.phoneMasked,
    this.displayName,
  });

  final String provider;
  final DateTime? linkedAt;
  final DateTime? lastUsedAt;
  final String? emailMasked;
  final String? phoneMasked;
  final String? displayName;

  factory AccountLinkedIdentity.fromJson(Map<String, dynamic> json) {
    return AccountLinkedIdentity(
      provider: json['provider']?.toString() ?? '',
      linkedAt: DateTime.tryParse(json['linkedAt']?.toString() ?? ''),
      lastUsedAt: DateTime.tryParse(json['lastUsedAt']?.toString() ?? ''),
      emailMasked: json['emailMasked']?.toString(),
      phoneMasked: json['phoneMasked']?.toString(),
      displayName: json['displayName']?.toString(),
    );
  }
}

class AccountTrustedChannel {
  const AccountTrustedChannel({
    required this.provider,
    required this.label,
    required this.description,
    required this.verificationLabel,
    required this.isLinked,
    required this.isTrustedChannel,
    required this.isLoginMethod,
    required this.isPrimary,
    this.linkedAt,
    this.lastUsedAt,
    this.emailMasked,
    this.phoneMasked,
    this.displayName,
  });

  final String provider;
  final String label;
  final String description;
  final String verificationLabel;
  final bool isLinked;
  final bool isTrustedChannel;
  final bool isLoginMethod;
  final bool isPrimary;
  final DateTime? linkedAt;
  final DateTime? lastUsedAt;
  final String? emailMasked;
  final String? phoneMasked;
  final String? displayName;

  factory AccountTrustedChannel.fromJson(Map<String, dynamic> json) {
    return AccountTrustedChannel(
      provider: json['provider']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      verificationLabel: json['verificationLabel']?.toString() ?? '',
      isLinked: json['isLinked'] == true,
      isTrustedChannel: json['isTrustedChannel'] == true,
      isLoginMethod: json['isLoginMethod'] == true,
      isPrimary: json['isPrimary'] == true,
      linkedAt: DateTime.tryParse(json['linkedAt']?.toString() ?? ''),
      lastUsedAt: DateTime.tryParse(json['lastUsedAt']?.toString() ?? ''),
      emailMasked: json['emailMasked']?.toString(),
      phoneMasked: json['phoneMasked']?.toString(),
      displayName: json['displayName']?.toString(),
    );
  }
}

class AccountLinkingStatus {
  const AccountLinkingStatus({
    this.linkedProviderIds = const <String>[],
    this.identities = const <AccountLinkedIdentity>[],
    this.trustedChannels = const <AccountTrustedChannel>[],
    this.primaryTrustedChannel,
    this.summaryTitle,
    this.summaryDetail,
    this.discoveryModes = const <String>[],
    this.mergeStrategySummary,
  });

  final List<String> linkedProviderIds;
  final List<AccountLinkedIdentity> identities;
  final List<AccountTrustedChannel> trustedChannels;
  final AccountTrustedChannel? primaryTrustedChannel;
  final String? summaryTitle;
  final String? summaryDetail;
  final List<String> discoveryModes;
  final String? mergeStrategySummary;

  String? get primaryTrustedChannelProvider => primaryTrustedChannel?.provider;

  factory AccountLinkingStatus.fromJson(Map<String, dynamic> json) {
    final identitiesJson = json['identities'];
    final trustedChannelsJson = json['trustedChannels'];
    final primaryChannelJson = json['primaryTrustedChannel'];
    final summaryJson = json['verificationSummary'];
    final mergeStrategyJson = json['mergeStrategy'];

    return AccountLinkingStatus(
      linkedProviderIds: (json['linkedProviderIds'] as List<dynamic>? ??
              const <dynamic>[])
          .map((value) => value.toString())
          .toList(),
      identities: (identitiesJson as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AccountLinkedIdentity.fromJson)
          .toList(),
      trustedChannels:
          (trustedChannelsJson as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(AccountTrustedChannel.fromJson)
              .toList(),
      primaryTrustedChannel: primaryChannelJson is Map<String, dynamic>
          ? AccountTrustedChannel.fromJson(primaryChannelJson)
          : null,
      summaryTitle: summaryJson is Map<String, dynamic>
          ? summaryJson['title']?.toString()
          : null,
      summaryDetail: summaryJson is Map<String, dynamic>
          ? summaryJson['detail']?.toString()
          : null,
      discoveryModes: (json['discoveryModes'] as List<dynamic>? ??
              const <dynamic>[])
          .map((value) => value.toString())
          .toList(),
      mergeStrategySummary: mergeStrategyJson is Map<String, dynamic>
          ? mergeStrategyJson['summary']?.toString()
          : null,
    );
  }
}
