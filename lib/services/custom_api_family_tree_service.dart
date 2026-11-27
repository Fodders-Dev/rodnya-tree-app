import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/blood_relation_capable_family_tree_service.dart';
import '../backend/interfaces/branch_digest_capable_family_tree_service.dart';
import '../backend/interfaces/bulk_import_capable_family_tree_service.dart';
import '../backend/interfaces/cross_tree_person_search_capable_family_tree_service.dart';
import '../backend/interfaces/extended_network_capable_family_tree_service.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/graph_person_access_capable_family_tree_service.dart';
import '../backend/interfaces/identity_conflicts_capable_family_tree_service.dart';
import '../backend/interfaces/identity_duplicate_capable_family_tree_service.dart';
import '../backend/interfaces/identity_suggestions_capable_family_tree_service.dart';
import '../backend/interfaces/kinship_check_capable_family_tree_service.dart';
import '../backend/interfaces/person_tree_resolution_capable_family_tree_service.dart';
import '../backend/interfaces/relatives_cache_capable_family_tree_service.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/interfaces/semya_manage_capable_family_tree_service.dart';
import '../backend/interfaces/onboarding_capable_family_tree_service.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../backend/interfaces/story_request_capable_family_tree_service.dart';
import '../backend/interfaces/tree_graph_capable_family_tree_service.dart';
import '../backend/models/blood_relation.dart';
import '../backend/models/branch_digest.dart';
import '../backend/models/edit_grant.dart';
import '../backend/models/extended_network_slice.dart';
import '../backend/models/identity_field_conflict.dart';
import '../backend/models/identity_suggestion.dart';
import '../backend/models/cross_tree_person_suggestion.dart';
import '../backend/models/include_rules.dart';
import '../backend/models/kinship_check.dart';
import '../backend/models/onboarding_state.dart';
import '../backend/models/deleted_person.dart';
import '../backend/models/deleted_post.dart';
import '../backend/models/semya.dart';
import '../backend/models/semya_browse_token.dart';
import '../backend/models/semya_invitation.dart';
import '../backend/models/semya_pull_person_result.dart';
import '../backend/models/visibility_choice.dart';
import '../backend/models/selectable_tree.dart';
import '../backend/models/tree_invitation.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../models/family_tree.dart';
import '../models/person_dossier.dart';
import '../models/person_duplicate_suggestion.dart';
import '../models/relation_request.dart';
import '../models/story_request.dart';
import '../models/tree_graph_snapshot.dart';
import '../models/tree_change_record.dart';
import '../models/user_profile.dart';
import '../utils/safe_json_decode.dart';
import '../utils/startup_trace.dart';
import 'custom_api_auth_service.dart';
import 'local_storage_service.dart';
import 'tree_graph_cache.dart';

part 'family_tree/custom_api_family_tree_base.dart';
part 'family_tree/custom_api_family_tree_parsers.dart';
part 'family_tree/custom_api_tree_crud_mixin.dart';
part 'family_tree/custom_api_tree_graph_mixin.dart';
part 'family_tree/custom_api_tree_identity_mixin.dart';
part 'family_tree/custom_api_tree_invitations_mixin.dart';
part 'family_tree/custom_api_tree_social_mixin.dart';
part 'family_tree/custom_api_tree_semya_mixin.dart';
part 'family_tree/custom_api_tree_trash_mixin.dart';

class CustomApiFamilyTreeService extends _CustomApiFamilyTreeHost
    with
        _CustomApiTreeCrudMixin,
        _CustomApiTreeGraphMixin,
        _CustomApiTreeIdentityMixin,
        _CustomApiTreeInvitationsMixin,
        _CustomApiTreeSocialMixin,
        _CustomApiTreeSemyaMixin,
        _CustomApiTreeTrashMixin
    implements
        FamilyTreeServiceInterface,
        TreeGraphCapableFamilyTreeService,
        IdentityDuplicateCapableFamilyTreeService,
        CrossTreePersonSearchCapableFamilyTreeService,
        IdentitySuggestionsCapableFamilyTreeService,
        IdentityConflictsCapableFamilyTreeService,
        BloodRelationCapableFamilyTreeService,
        BranchDigestCapableFamilyTreeService,
        BulkImportCapableFamilyTreeService,
        GraphPersonAccessCapableFamilyTreeService,
        ExtendedNetworkCapableFamilyTreeService,
        OnboardingCapableFamilyTreeService,
        KinshipCheckCapableFamilyTreeService,
        StoryRequestCapableFamilyTreeService,
        PersonTreeResolutionCapableFamilyTreeService,
        RelativesCacheCapableFamilyTreeService,
        SemyaCapableFamilyTreeService,
        SemyaManageCapableFamilyTreeService {
  CustomApiFamilyTreeService({
    required super.authService,
    required super.runtimeConfig,
    super.httpClient,
    super.localStorageService,
    super.profileService,
    super.treeGraphCache,
    super.clock,
  });

  @override
  void invalidateRelativesCache(String treeId) {
    _invalidateTreeCaches(treeId);
  }

  Future<void> resetForSignOut() async {
    _invalidateAllTreeCaches();
    _personTreeIds.clear();
    _pendingInvitationsPollingTimer?.cancel();
    _pendingInvitationsPollingTimer = null;
    _pendingInvitationsPollingStarted = false;
  }
}
