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
    // flutter_contacts 2.x replaced the boolean
    // `requestPermission(readonly: true)` with a `PermissionStatus`
    // returning request via the new permissions namespace.
    final status =
        await FlutterContacts.permissions.request(PermissionType.read);
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  Future<List<PhoneContactEntry>> getPhoneContacts() async {
    if (!await isSupported()) {
      return const [];
    }

    // 2.x renamed `getContacts(withProperties: true)` to `getAll` with
    // an explicit ContactProperty set. We only need names + phone
    // numbers — skip photos / addresses / other properties to keep
    // the read fast on devices with thousands of contacts. The enum
    // member is `phone` (singular) in 2.x.
    final contacts = await FlutterContacts.getAll(
      properties: const {ContactProperty.phone},
    );
    final normalizedEntries = <String, PhoneContactEntry>{};

    for (final contact in contacts) {
      // displayName is nullable in 2.x — fall back to "Контакт" so
      // we always render something readable in the picker list.
      final rawName = contact.displayName?.trim() ?? '';
      final displayName = rawName.isNotEmpty ? rawName : 'Контакт';
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
