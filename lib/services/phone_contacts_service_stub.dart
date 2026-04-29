import '../models/phone_contact_entry.dart';

class PhoneContactsService {
  Future<bool> isSupported() async => false;

  Future<bool> requestAccess() async => false;

  Future<List<PhoneContactEntry>> getPhoneContacts() async => const [];
}
