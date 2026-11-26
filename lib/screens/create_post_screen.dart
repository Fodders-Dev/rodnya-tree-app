import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/attachment_picker_sheet.dart';
import '../widgets/kruzhok_recorder_screen.dart';
import 'package:provider/provider.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/circle_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/post_service_interface.dart';
import '../models/audience_preset.dart';
import '../models/circle.dart';
import '../models/family_person.dart';
import '../models/family_tree.dart';
import '../models/post.dart';
import '../providers/tree_provider.dart';
import '../services/app_status_service.dart';
import '../services/local_storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/user_facing_error.dart';
import '../widgets/audience_picker.dart';
import '../widgets/glass_panel.dart';
import '../models/media_upload_progress.dart';
import '../services/gallery_media_picker.dart';
import '../services/post_publish_queue.dart';
import '../widgets/person_multi_picker_sheet.dart';

part 'create_post/create_post_media.dart';
part 'create_post/create_post_audience.dart';
part 'create_post/create_post_submit.dart';
part 'create_post/create_post_sections.dart';
part 'create_post/create_post_widgets.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, this.initialAction});

  /// Optional CTA passed in via `?action=` from the home-screen
  /// teaser icons. `'photo'` auto-opens the gallery picker on mount,
  /// `'video'` auto-opens the video picker. Anything else is a no-op
  /// (user gets the regular composer).
  final String? initialAction;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentController = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();

  final FamilyTreeServiceInterface _familyTreeService =
      GetIt.I<FamilyTreeServiceInterface>();

  final PostServiceInterface _postService = GetIt.I<PostServiceInterface>();

  final CircleServiceInterface? _circleService =
      GetIt.I.isRegistered<CircleServiceInterface>()
          ? GetIt.I<CircleServiceInterface>()
          : null;

  final LocalStorageService _localStorageService =
      GetIt.I<LocalStorageService>();

  final AppStatusService _appStatusService = GetIt.I<AppStatusService>();

  bool _isPublic = false;

  bool _isLoading = false;

  /// Прогресс загрузки медиа во время публикации (шаг 3 плана массовой
  /// загрузки): 30 фото едут не мгновенно, и замерший спиннер читается как
  /// «приложение зависло». Null — пока публикация не идёт.
  MediaUploadProgress? _uploadProgress;

  bool _isLoadingCircles = false;

  bool _isLoadingPeople = false;

  bool _circlesUnavailable = false;

  bool _branchCandidatesUnavailable = false;

  // Phase 3.4 multi-branch posts: list of the user's OTHER trees
  // (excluding the primary one driving this composer) that the
  // post can be cross-posted to. The primary tree is always
  // implicit — `_additionalBranchIds` only tracks the extras.
  // When empty, the post is single-branch (legacy behavior).
  List<FamilyTree> _otherUserTrees = <FamilyTree>[];

  final Set<String> _additionalBranchIds = <String>{};

  // Mixed photos + videos. The Post model still stores everything as
  // imageUrls (server-side blob, no schema change needed), but locally
  // we track the kind so the preview tile can render a video poster
  // with a play overlay instead of trying to decode an image header
  // out of an .mp4.
  List<_PostMedia> _selectedMedia = <_PostMedia>[];

  List<FamilyCircle> _audienceCircles = <FamilyCircle>[];

  AudiencePresetsResponse _audiencePresets = AudiencePresetsResponse.empty;

  /// `'core_family'` / `'close'` while one of the smart-tile presets
  /// is active. Cleared the moment the user picks any non-preset
  /// option (a regular circle / their own custom branch list).
  String? _selectedPresetKey;

  List<FamilyPerson> _availablePeople = <FamilyPerson>[];

  final Set<String> _selectedBranchPersonIds = <String>{};

  TreeContentScopeType _scopeType = TreeContentScopeType.wholeTree;

  String? _selectedCircleId;

  String? _currentTreeId;

  FamilyTree? _currentTreeMeta;

  bool get _isFriendsTree => _currentTreeMeta?.isFriendsTree == true;

  /// Live audience footprint based on the currently-selected branches.
  /// Counts the union of `memberIds` across the primary branch
  /// (`_currentTreeMeta`) and every branch the user toggled on in the
  /// "Опубликовать также в" strip. The author is included — the
  /// "увидят X человек" copy is read as "audience size" and pretending
  /// the author isn't part of the audience confuses the count when
  /// the user opens their own post a moment later.
  ///
  /// Returns `null` until the primary tree metadata loaded; the badge
  /// stays hidden until then so we don't flash a misleading "0 человек".
  _AudienceSummary? get _audienceSummary {
    if (_currentTreeMeta == null) return null;
    final viewers = <String>{..._currentTreeMeta!.memberIds};
    var branches = 1;
    for (final tree in _otherUserTrees) {
      if (_additionalBranchIds.contains(tree.id)) {
        viewers.addAll(tree.memberIds);
        branches += 1;
      }
    }
    return _AudienceSummary(viewers: viewers.length, branches: branches);
  }

  AudiencePreset? get _activePreset {
    final key = _selectedPresetKey;
    if (key == null) return null;
    for (final p in _audiencePresets.presets) {
      if (p.key == key) return p;
    }
    return null;
  }

  FamilyCircle? get _selectedCircle {
    final selectedId = _selectedCircleId;
    if (selectedId == null) {
      return null;
    }
    for (final circle in _audienceCircles) {
      if (circle.id == selectedId) {
        return circle;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Q1: the publish button enables only when there's something to post,
    // so rebuild the topbar as the text field gains/loses content. Media
    // changes already flow through setState.
    _contentController.addListener(_handleComposerChanged);
    _currentTreeId = Provider.of<TreeProvider>(
      context,
      listen: false,
    ).selectedTreeId;
    _loadCurrentTreeMeta();
    _loadAudienceCircles();
    _loadBranchCandidates();
    _loadOtherUserTrees();
    // Honor the action hint coming from the home teaser icons. The
    // post-frame callback gives the navigator a chance to settle so
    // the picker sheet appears on top of the actually-mounted
    // composer instead of fighting with the page transition.
    final action = widget.initialAction;
    if (action == 'photo' || action == 'video') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (action == 'photo') {
          _pickImages();
        } else {
          _pickVideoFromGallery();
        }
      });
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWideLayout = width >= 900;
    final composeTheme = Theme.of(context).copyWith(
      splashFactory: InkRipple.splashFactory,
    );

    final composeTokens = composeTheme.extension<RodnyaDesignTokens>() ??
        (composeTheme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Theme(
      data: composeTheme,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(AppTheme.topbarHeight(context)),
          child: _buildComposeTopbar(
            theme: composeTheme,
            tokens: composeTokens,
          ),
        ),
        body: _currentTreeId == null
            ? _buildMissingTreeState()
            : SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
                      // Align to topCenter (not Center) so the
                      // composer card anchors to the top of the
                      // viewport. Center vertically-centred a short
                      // SingleChildScrollView, which on desktop pushed
                      // the editor card halfway down the screen.
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isWideLayout ? 1180 : 680,
                          ),
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              isWideLayout ? 24 : 14,
                              isWideLayout ? 18 : 12,
                              isWideLayout ? 24 : 14,
                              116,
                            ),
                            child: isWideLayout
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: _buildEditorCard(compact: false),
                                      ),
                                      const SizedBox(width: 16),
                                      SizedBox(
                                        width: 370,
                                        child: _buildAudiencePanel(),
                                      ),
                                    ],
                                  )
                                : _buildEditorCard(compact: true),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _buildComposeToolDock(compact: !isWideLayout),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  IconData _circleIcon(FamilyCircle circle) {
    switch (circle.kind) {
      case FamilyCircleKind.allTree:
        return Icons.account_tree_outlined;
      case FamilyCircleKind.favorites:
        return Icons.favorite_border;
      case FamilyCircleKind.descendantsOf:
      case FamilyCircleKind.ancestorsOf:
        return Icons.alt_route_outlined;
      case FamilyCircleKind.pair:
        return Icons.people_outline;
      case FamilyCircleKind.custom:
        return Icons.group_work_outlined;
    }
  }

  Color _circleAccent(FamilyCircle circle, RodnyaDesignTokens tokens) {
    switch (circle.kind) {
      case FamilyCircleKind.favorites:
        return tokens.warm;
      case FamilyCircleKind.descendantsOf:
      case FamilyCircleKind.ancestorsOf:
      case FamilyCircleKind.pair:
        return tokens.accentStrong;
      case FamilyCircleKind.allTree:
      case FamilyCircleKind.custom:
        return tokens.accent;
    }
  }

  void _updateCreatePostState(VoidCallback fn) {
    setState(fn);
  }
}
