import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_contacts/flutter_contacts.dart';

import '../models/phone_contact_entry.dart';
import '../utils/phone_utils.dart';

class PhoneContactsService {
  Future<bool> isSupported() async =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<bool> requestAccess() async {
    if (!await isSupported()) {
      return false;
    }
    return FlutterContacts.requestPermission(readonly: true);
  }

  Future<List<PhoneContactEntry>> getPhoneContacts() async {
    if (!await isSupported()) {
      return const [];
    }

    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: false,
    );
    final normalizedEntries = <String, PhoneContactEntry>{};

    for (final contact in contacts) {
      final displayName = contact.displayName.trim().isNotEmpty
          ? contact.displayName.trim()
          : 'Контакт';
      for (final phone in contact.phones) {
        final rawPhoneNumber = phone.number.trim();
        final normalizedPhoneNumber = PhoneUtils.normalize(rawPhoneNumber);
        if (normalizedPhoneNumber == null ||
            normalizedEntries.containsKey(normalizedPhoneNumber)) {
          continue;
        }

        normalizedEntries[normalizedPhoneNumber] = PhoneContactEntry(
          displayName: displayName,
          phoneNumber: rawPhoneNumber,
          normalizedPhoneNumber: normalizedPhoneNumber,
        );
      }
    }

    return normalizedEntries.values.toList()
      ..sort(
        (left, right) => left.displayName.compareTo(right.displayName),
      );
  }
}
