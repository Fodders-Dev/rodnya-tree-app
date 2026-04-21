import 'package:image_picker/image_picker.dart';

import '../../models/profile_note.dart';
import '../../models/profile_contribution.dart';
import '../../models/account_linking_status.dart';
import '../../models/user_profile.dart';
import '../models/profile_form_data.dart';

abstract class ProfileServiceInterface {
  Future<UserProfile?> getUserProfile(String userId);
  Future<UserProfile?> getCurrentUserProfile();
  Future<ProfileFormData> getCurrentUserProfileFormData();
  Future<AccountLinkingStatus> getCurrentAccountLinkingStatus();
  Future<void> saveCurrentUserProfileFormData(ProfileFormData data);
  Future<String?> uploadProfilePhoto(XFile photo);
  Future<void> updateUserProfile(String userId, UserProfile profile);
  Future<List<ProfileContribution>> getPendingProfileContributions();
  Future<void> acceptProfileContribution(String contributionId);
  Future<void> rejectProfileContribution(String contributionId);
  Stream<List<ProfileNote>> getProfileNotesStream(String userId);
  Future<void> addProfileNote(String userId, String title, String content);
  Future<void> updateProfileNote(String userId, ProfileNote note);
  Future<void> deleteProfileNote(String userId, String noteId);
  Future<List<UserProfile>> searchUsersByField({
    required String field,
    required String value,
    int limit = 10,
  });
  Future<List<UserProfile>> searchUsers(String query, {int limit = 10});
}
