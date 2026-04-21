import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:country_picker/country_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../models/account_linking_status.dart';
import '../models/family_person.dart';
import '../models/family_tree.dart';
import 'package:get_it/get_it.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../backend/models/profile_form_data.dart';
import '../services/custom_api_auth_service.dart';
import '../widgets/glass_panel.dart';
import '../widgets/flow_overlays.dart';
import '../widgets/google_sign_in_action.dart';

part 'profile_edit_screen_sections.dart';

class _ProfileVisibilityOptions {
  const _ProfileVisibilityOptions({
    this.trees = const [],
    this.branches = const [],
    this.users = const [],
  });

  final List<FamilyTree> trees;
  final List<_VisibilityBranchTarget> branches;
  final List<_VisibilityUserTarget> users;
}

class _VisibilityBranchTarget {
  const _VisibilityBranchTarget({
    required this.personId,
    required this.displayName,
    required this.treeId,
    required this.treeName,
  });

  final String personId;
  final String displayName;
  final String treeId;
  final String treeName;
}

class _VisibilityUserTarget {
  const _VisibilityUserTarget({
    required this.userId,
    required this.displayName,
    this.treeNames = const [],
  });

  final String userId;
  final String displayName;
  final List<String> treeNames;
}

class _VisibilityTargetOption {
  const _VisibilityTargetOption({
    required this.id,
    required this.title,
    this.subtitle = '',
  });

  final String id;
  final String title;
  final String subtitle;
}

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _maidenNameController = TextEditingController();
  final _birthPlaceController = TextEditingController();
  final _bioController = TextEditingController();
  final _familyStatusController = TextEditingController();
  final _aboutFamilyController = TextEditingController();
  final _educationController = TextEditingController();
  final _workController = TextEditingController();
  final _hometownController = TextEditingController();
  final _languagesController = TextEditingController();
  final _valuesController = TextEditingController();
  final _religionController = TextEditingController();
  final _interestsController = TextEditingController();

  DateTime? _birthDate;
  String? _countryCode;
  String? _countryName;
  String? _profileImageUrl;
  AccountLinkingStatus? _accountLinkingStatus;
  String? _primaryTrustedChannel;
  String _profileContributionPolicy = 'suggestions';
  Map<String, String> _profileVisibilityScopes = const {
    'contacts': 'private',
    'about': 'shared_trees',
    'background': 'shared_trees',
    'worldview': 'shared_trees',
  };
  Map<String, List<String>> _profileVisibilityTreeIds = const {
    'contacts': <String>[],
    'about': <String>[],
    'background': <String>[],
    'worldview': <String>[],
  };
  Map<String, List<String>> _profileVisibilityBranchRootIds = const {
    'contacts': <String>[],
    'about': <String>[],
    'background': <String>[],
    'worldview': <String>[],
  };
  Map<String, List<String>> _profileVisibilityUserIds = const {
    'contacts': <String>[],
    'about': <String>[],
    'background': <String>[],
    'worldview': <String>[],
  };
  List<FamilyTree> _availableVisibilityTrees = const [];
  List<_VisibilityBranchTarget> _availableVisibilityBranches = const [];
  List<_VisibilityUserTarget> _availableVisibilityUsers = const [];
  bool _isLoading = false;
  bool _isGoogleLinkLoading = false;
  bool _isTelegramLinkLoading = false;
  bool _isVkLinkLoading = false;
  bool _isMaxLinkLoading = false;
  Gender _gender = Gender.unknown;

  void _updateSectionState(VoidCallback update) {
    setState(update);
  }

  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final ProfileServiceInterface _profileService =
      GetIt.I<ProfileServiceInterface>();
  final FamilyTreeServiceInterface _familyTreeService =
      GetIt.I<FamilyTreeServiceInterface>();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _maidenNameController.dispose();
    _birthPlaceController.dispose();
    _bioController.dispose();
    _familyStatusController.dispose();
    _aboutFamilyController.dispose();
    _educationController.dispose();
    _workController.dispose();
    _hometownController.dispose();
    _languagesController.dispose();
    _valuesController.dispose();
    _religionController.dispose();
    _interestsController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_authService.currentUserId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: пользователь не авторизован')),
        );
        Navigator.pop(context);
        return;
      }

      final data = await _profileService.getCurrentUserProfileFormData();
      _ProfileVisibilityOptions visibilityOptions =
          const _ProfileVisibilityOptions();
      AccountLinkingStatus? linkingStatus;
      try {
        visibilityOptions = await _loadVisibilityOptions();
      } catch (error) {
        debugPrint('Не удалось загрузить варианты приватности профиля: $error');
      }
      try {
        linkingStatus = await _profileService.getCurrentAccountLinkingStatus();
      } catch (error) {
        debugPrint('Не удалось загрузить trusted channels: $error');
      }
      if (!mounted) return;

      // Разделяем displayName на компоненты, если отдельные поля не заполнены
      String displayName = data.displayName;
      List<String> nameParts = displayName.split(' ');

      setState(() {
        // Используем отдельные поля, если они есть
        _firstNameController.text = data.firstName.isNotEmpty
            ? data.firstName
            : (nameParts.isNotEmpty ? nameParts[0] : '');
        _lastNameController.text = data.lastName.isNotEmpty
            ? data.lastName
            : (nameParts.length > 1 ? nameParts.last : '');

        // Если есть отчество в отдельном поле или можно предположить из displayName
        _middleNameController.text = data.middleName.isNotEmpty
            ? data.middleName
            : (nameParts.length > 2
                ? nameParts.sublist(1, nameParts.length - 1).join(' ')
                : '');

        _usernameController.text = data.username;

        _emailController.text = data.email ?? '';
        _phoneController.text = data.phoneNumber;
        _cityController.text = data.city;
        _countryCode = data.countryCode;
        _countryName = data.countryName;
        _profileImageUrl = data.photoUrl;
        _accountLinkingStatus = linkingStatus;
        _primaryTrustedChannel =
            data.primaryTrustedChannel?.trim().isNotEmpty == true
                ? data.primaryTrustedChannel!.trim()
                : linkingStatus?.primaryTrustedChannelProvider;

        _gender = data.gender;

        _birthDate = data.birthDate;
        _birthPlaceController.text = data.birthPlace;
        _bioController.text = data.bio;
        _familyStatusController.text = data.familyStatus;
        _aboutFamilyController.text = data.aboutFamily;
        _educationController.text = data.education;
        _workController.text = data.work;
        _hometownController.text = data.hometown;
        _languagesController.text = data.languages;
        _valuesController.text = data.values;
        _religionController.text = data.religion;
        _interestsController.text = data.interests;
        _profileContributionPolicy = data.profileContributionPolicy;
        _profileVisibilityScopes = {
          'contacts': 'private',
          'about': 'shared_trees',
          'background': 'shared_trees',
          'worldview': 'shared_trees',
          ...data.profileVisibilityScopes,
        };
        _profileVisibilityTreeIds =
            _resolveVisibilityTargets(data.profileVisibilityTreeIds);
        _profileVisibilityBranchRootIds =
            _resolveVisibilityTargets(data.profileVisibilityBranchRootIds);
        _profileVisibilityUserIds =
            _resolveVisibilityTargets(data.profileVisibilityUserIds);
        _availableVisibilityTrees = visibilityOptions.trees;
        _availableVisibilityBranches = visibilityOptions.branches;
        _availableVisibilityUsers = visibilityOptions.users;

        if (_gender == Gender.female) {
          _maidenNameController.text = data.maidenName;
        }
      });
    } catch (e) {
      debugPrint('Ошибка при загрузке данных пользователя: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка при загрузке данных: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshAccountLinkingStatus() async {
    try {
      final linkingStatus =
          await _profileService.getCurrentAccountLinkingStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _accountLinkingStatus = linkingStatus;
        _primaryTrustedChannel =
            _sanitizeTrustedChannelProvider(_primaryTrustedChannel) ??
                linkingStatus.primaryTrustedChannelProvider;
      });
    } catch (error) {
      debugPrint('Не удалось обновить trusted channels: $error');
    }
  }

  String? _sanitizeTrustedChannelProvider(String? value) {
    switch ((value ?? '').trim()) {
      case 'google':
      case 'telegram':
      case 'vk':
      case 'max':
        return value!.trim();
      default:
        return null;
    }
  }

  bool _canSetPrimaryTrustedChannel(String provider) {
    return _accountLinkingStatus?.trustedChannels.any(
          (channel) =>
              channel.provider == provider &&
              channel.isLinked &&
              channel.isTrustedChannel,
        ) ==
        true;
  }

  Map<String, List<String>> _resolveVisibilityTargets(
    Map<String, List<String>> targets,
  ) {
    return {
      'contacts': List<String>.from(targets['contacts'] ?? const <String>[]),
      'about': List<String>.from(targets['about'] ?? const <String>[]),
      'background':
          List<String>.from(targets['background'] ?? const <String>[]),
      'worldview': List<String>.from(targets['worldview'] ?? const <String>[]),
    };
  }

  Future<_ProfileVisibilityOptions> _loadVisibilityOptions() async {
    final trees = await _familyTreeService.getUserTrees();
    final currentUserId = _authService.currentUserId;
    final labelsByUserId = <String, String>{};
    final treeNamesByUserId = <String, Set<String>>{};
    final branchesByPersonId = <String, _VisibilityBranchTarget>{};

    for (final tree in trees) {
      List<FamilyPerson> relatives;
      List<dynamic> relations;
      try {
        final loaded = await Future.wait<dynamic>([
          _familyTreeService.getRelatives(tree.id),
          _familyTreeService.getRelations(tree.id),
        ]);
        relatives = loaded[0] as List<FamilyPerson>;
        relations = loaded[1] as List<dynamic>;
      } catch (error) {
        debugPrint(
          'Не удалось загрузить варианты приватности для дерева ${tree.id}: $error',
        );
        continue;
      }

      for (final relative in relatives) {
        final userId = relative.userId?.trim();
        if (userId == null || userId.isEmpty || userId == currentUserId) {
          continue;
        }
        labelsByUserId.putIfAbsent(userId, () => relative.displayName);
        treeNamesByUserId.putIfAbsent(userId, () => <String>{}).add(tree.name);
      }

      for (final relative in relatives) {
        final displayName = relative.displayName.trim();
        if (displayName.isEmpty) {
          continue;
        }

        final hasRelations = relations.any(
          (entry) =>
              entry.person1Id == relative.id || entry.person2Id == relative.id,
        );
        if (!hasRelations && relatives.length > 1) {
          continue;
        }

        branchesByPersonId.putIfAbsent(
          relative.id,
          () => _VisibilityBranchTarget(
            personId: relative.id,
            displayName: displayName,
            treeId: tree.id,
            treeName: tree.name,
          ),
        );
      }
    }

    final branches = branchesByPersonId.values.toList()
      ..sort(
        (left, right) => left.displayName
            .toLowerCase()
            .compareTo(right.displayName.toLowerCase()),
      );
    final users = labelsByUserId.entries
        .map(
          (entry) => _VisibilityUserTarget(
            userId: entry.key,
            displayName: entry.value,
            treeNames:
                (treeNamesByUserId[entry.key] ?? const <String>{}).toList()
                  ..sort(),
          ),
        )
        .toList()
      ..sort(
        (left, right) => left.displayName
            .toLowerCase()
            .compareTo(right.displayName.toLowerCase()),
      );

    return _ProfileVisibilityOptions(
      trees: trees,
      branches: branches,
      users: users,
    );
  }

  bool _validateVisibilitySelections() {
    for (final sectionKey in _profileVisibilityScopes.keys) {
      final scope = _profileVisibilityScopes[sectionKey] ?? 'shared_trees';
      if (scope == 'specific_trees' &&
          (_profileVisibilityTreeIds[sectionKey] ?? const <String>[]).isEmpty) {
        _showVisibilityValidationError(
          'Для блока "${_visibilitySectionTitle(sectionKey)}" выберите хотя бы одно дерево.',
        );
        return false;
      }
      if (scope == 'specific_branches' &&
          (_profileVisibilityBranchRootIds[sectionKey] ?? const <String>[])
              .isEmpty) {
        _showVisibilityValidationError(
          'Для блока "${_visibilitySectionTitle(sectionKey)}" выберите хотя бы одну ветку.',
        );
        return false;
      }
      if (scope == 'specific_users' &&
          (_profileVisibilityUserIds[sectionKey] ?? const <String>[]).isEmpty) {
        _showVisibilityValidationError(
          'Для блока "${_visibilitySectionTitle(sectionKey)}" выберите хотя бы одного человека.',
        );
        return false;
      }
    }
    return true;
  }

  void _showVisibilityValidationError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        _isLoading = true;
      });

      try {
        final imageUrl = await _profileService.uploadProfilePhoto(image);
        if (!mounted) return;

        if (imageUrl != null) {
          setState(() {
            _profileImageUrl = imageUrl;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Не удалось получить URL изображения после загрузки.',
              ),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки изображения: $e')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _startTelegramLinking() async {
    if (!kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Пока привязка Telegram включена через web-версию Родни.',
          ),
        ),
      );
      return;
    }

    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Этот backend ещё не поддерживает Telegram link flow.'),
        ),
      );
      return;
    }

    setState(() {
      _isTelegramLinkLoading = true;
    });

    try {
      final launched = await launchUrl(
        Uri.parse(authService.telegramLinkStartUrl),
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось открыть Telegram link flow.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTelegramLinkLoading = false;
        });
      }
    }
  }

  Future<void> _startGoogleLinking() async {
    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Этот backend ещё не поддерживает Google link flow.'),
        ),
      );
      return;
    }
    if (!authService.isGoogleSignInConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Google sign-in ещё не настроен. Добавьте Web client ID на backend и во Flutter.',
          ),
        ),
      );
      return;
    }

    if (kIsWeb) {
      await _showGoogleLinkDialog(authService);
      return;
    }

    await _linkGoogleIdentity();
  }

  Future<void> _showGoogleLinkDialog(CustomApiAuthService authService) async {
    if (!mounted) {
      return;
    }

    try {
      final shouldContinue = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          return AlertDialog(
            title: const Text('Привязать Google'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Выберите Google-аккаунт, который хотите привязать к текущему аккаунту Родни.',
                ),
                const SizedBox(height: 16),
                Align(
                  child: buildGoogleSignInAction(
                    theme: theme,
                    isLoading: false,
                    enabled: true,
                    onPressed: () async {
                      await authService.resetGoogleSelection();
                      if (!dialogContext.mounted) {
                        return;
                      }
                      Navigator.of(dialogContext).pop(true);
                    },
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Отмена'),
              ),
            ],
          );
        },
      );

      if (shouldContinue == true) {
        await _linkGoogleIdentity();
      }
    } finally {}
  }

  Future<void> _linkGoogleIdentity() async {
    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      return;
    }

    if (_isGoogleLinkLoading) {
      return;
    }

    setState(() {
      _isGoogleLinkLoading = true;
    });

    try {
      await authService.linkGoogleIdentity();
      await _refreshAccountLinkingStatus();
      if (!mounted) {
        return;
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google привязан к аккаунту Родни.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authService.describeError(error)),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLinkLoading = false;
        });
      }
    }
  }

  Future<void> _startVkLinking() async {
    if (!kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Пока привязка VK ID включена через web-версию Родни.',
          ),
        ),
      );
      return;
    }

    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Этот backend ещё не поддерживает VK ID link flow.'),
        ),
      );
      return;
    }

    setState(() {
      _isVkLinkLoading = true;
    });

    try {
      final launched = await launchUrl(
        Uri.parse(authService.vkLinkStartUrl),
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось открыть VK ID link flow.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVkLinkLoading = false;
        });
      }
    }
  }

  Future<void> _startMaxLinking() async {
    if (!kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Пока привязка MAX включена через web-версию Родни.',
          ),
        ),
      );
      return;
    }

    final authService = _authService;
    if (authService is! CustomApiAuthService) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Этот backend ещё не поддерживает MAX link flow.'),
        ),
      );
      return;
    }

    setState(() {
      _isMaxLinkLoading = true;
    });

    try {
      final launched = await launchUrl(
        Uri.parse(authService.maxLinkStartUrl),
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось открыть MAX link flow.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMaxLinkLoading = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final DateTime? pickedDate = await showRodnyaDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      setState(() {
        _birthDate = pickedDate;
      });
    }
  }

  Future<void> _selectCountry() async {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      countryListTheme: CountryListThemeData(
        flagSize: 25,
        backgroundColor:
            Theme.of(context).colorScheme.surface.withValues(alpha: 0.98),
        textStyle: TextStyle(
          fontSize: 16,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
        bottomSheetHeight: 560,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28.0),
          topRight: Radius.circular(28.0),
        ),
        inputDecoration: InputDecoration(
          labelText: 'Поиск',
          hintText: 'Страна или код',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Theme.of(context)
              .colorScheme
              .surfaceContainerLowest
              .withValues(alpha: 0.92),
        ),
      ),
      onSelect: (Country country) {
        setState(() {
          _countryCode = country.phoneCode;
          _countryName = country.name;
        });
      },
    );
  }

  Future<void> _saveProfile({String? newPhotoUrl}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!_validateVisibilitySelections()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = _authService.currentUserId;
      if (userId == null) throw Exception('Пользователь не авторизован');

      // Создаем displayName из компонентов
      String displayName = [
        _firstNameController.text.trim(),
        _middleNameController.text.trim(),
        _lastNameController.text.trim(),
      ].where((part) => part.isNotEmpty).join(' ');

      await _profileService.saveCurrentUserProfileFormData(
        ProfileFormData(
          userId: userId,
          email: _emailController.text.trim(),
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          middleName: _middleNameController.text.trim(),
          displayName: displayName,
          username: _usernameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          countryCode: _countryCode,
          countryName: _countryName,
          city: _cityController.text.trim(),
          photoUrl: newPhotoUrl ?? _profileImageUrl,
          gender: _gender,
          maidenName:
              _gender == Gender.female ? _maidenNameController.text.trim() : '',
          birthDate: _birthDate,
          birthPlace: _birthPlaceController.text.trim(),
          bio: _bioController.text.trim(),
          familyStatus: _familyStatusController.text.trim(),
          aboutFamily: _aboutFamilyController.text.trim(),
          education: _educationController.text.trim(),
          work: _workController.text.trim(),
          hometown: _hometownController.text.trim(),
          languages: _languagesController.text.trim(),
          values: _valuesController.text.trim(),
          religion: _religionController.text.trim(),
          interests: _interestsController.text.trim(),
          profileContributionPolicy: _profileContributionPolicy,
          primaryTrustedChannel: _sanitizeTrustedChannelProvider(
            _primaryTrustedChannel,
          ),
          profileVisibilityScopes: _profileVisibilityScopes,
          profileVisibilityTreeIds: _profileVisibilityTreeIds,
          profileVisibilityBranchRootIds: _profileVisibilityBranchRootIds,
          profileVisibilityUserIds: _profileVisibilityUserIds,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Профиль успешно обновлен')));

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Ошибка при сохранении профиля: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка при сохранении: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMMd('ru');
    final isWide = MediaQuery.of(context).size.width >= 920;

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildAvatarCard(),
                        const SizedBox(height: 16),
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildIdentitySection()),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: _buildPersonalSection(dateFormat)),
                            ],
                          )
                        else ...[
                          _buildIdentitySection(),
                          const SizedBox(height: 16),
                          _buildPersonalSection(dateFormat),
                        ],
                        const SizedBox(height: 16),
                        _buildAboutSection(),
                        const SizedBox(height: 16),
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildBackgroundSection()),
                              const SizedBox(width: 16),
                              Expanded(child: _buildWorldviewSection()),
                            ],
                          )
                        else ...[
                          _buildBackgroundSection(),
                          const SizedBox(height: 16),
                          _buildWorldviewSection(),
                        ],
                        const SizedBox(height: 16),
                        _buildLinkedAuthMethodsSection(),
                        const SizedBox(height: 16),
                        _buildContactsSection(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _isLoading ? null : _saveProfile,
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Сохранить'),
        ),
      ),
    );
  }

  Future<void> _pickVisibilityTrees(String sectionKey) async {
    final selected = await _showVisibilityTargetDialog(
      title: 'Кто увидит "${_visibilitySectionTitle(sectionKey)}"',
      options: _availableVisibilityTrees
          .map(
            (tree) => _VisibilityTargetOption(
              id: tree.id,
              title: tree.name,
              subtitle: tree.description,
            ),
          )
          .toList(),
      initialSelection:
          _profileVisibilityTreeIds[sectionKey] ?? const <String>[],
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _profileVisibilityTreeIds = {
        ..._profileVisibilityTreeIds,
        sectionKey: selected,
      };
    });
  }

  Future<void> _pickVisibilityUsers(String sectionKey) async {
    final selected = await _showVisibilityTargetDialog(
      title: 'Кто увидит "${_visibilitySectionTitle(sectionKey)}"',
      options: _availableVisibilityUsers
          .map(
            (user) => _VisibilityTargetOption(
              id: user.userId,
              title: user.displayName,
              subtitle: user.treeNames.join(' • '),
            ),
          )
          .toList(),
      initialSelection:
          _profileVisibilityUserIds[sectionKey] ?? const <String>[],
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _profileVisibilityUserIds = {
        ..._profileVisibilityUserIds,
        sectionKey: selected,
      };
    });
  }

  Future<void> _pickVisibilityBranches(String sectionKey) async {
    final selected = await _showVisibilityTargetDialog(
      title: 'Кто увидит "${_visibilitySectionTitle(sectionKey)}"',
      options: _availableVisibilityBranches
          .map(
            (branch) => _VisibilityTargetOption(
              id: branch.personId,
              title: branch.displayName,
              subtitle: branch.treeName,
            ),
          )
          .toList(),
      initialSelection:
          _profileVisibilityBranchRootIds[sectionKey] ?? const <String>[],
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _profileVisibilityBranchRootIds = {
        ..._profileVisibilityBranchRootIds,
        sectionKey: selected,
      };
    });
  }

  Future<List<String>?> _showVisibilityTargetDialog({
    required String title,
    required List<_VisibilityTargetOption> options,
    required List<String> initialSelection,
  }) {
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) {
        final selectedIds = initialSelection.toSet();
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(title),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
              child: options.isEmpty
                  ? const Text('Пока нет доступных вариантов для выбора.')
                  : Scrollbar(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final option in options)
                            CheckboxListTile(
                              value: selectedIds.contains(option.id),
                              title: Text(option.title),
                              subtitle: option.subtitle.trim().isEmpty
                                  ? null
                                  : Text(option.subtitle),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selectedIds.add(option.id);
                                  } else {
                                    selectedIds.remove(option.id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(initialSelection),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(const <String>[]),
                child: const Text('Очистить'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(selectedIds.toList()),
                child: const Text('Готово'),
              ),
            ],
          ),
        );
      },
    );
  }

  String _visibilitySectionTitle(String sectionKey) {
    switch (sectionKey) {
      case 'contacts':
        return 'Контакты';
      case 'about':
        return 'О человеке';
      case 'background':
        return 'Учёба и дело';
      case 'worldview':
        return 'Ценности и взгляды';
      default:
        return sectionKey;
    }
  }

  String _visibilityScopeDescription(String scope) {
    switch (scope) {
      case 'public':
        return 'Блок видят все авторизованные пользователи Родни.';
      case 'specific_trees':
        return 'Блок увидят только участники выбранных деревьев, где вы с ними действительно пересекаетесь.';
      case 'specific_branches':
        return 'Блок увидят только те родственники, которые попадают в выбранные ветки внутри ваших общих деревьев.';
      case 'specific_users':
        return 'Блок откроется только выбранным людям, даже если они есть и в других ваших деревьях.';
      case 'private':
        return 'Блок останется только в вашем личном просмотре.';
      case 'shared_trees':
      default:
        return 'Блок увидят только люди, у которых с вами есть общее дерево.';
    }
  }

  Widget _buildLinkedAuthMethodsSection() {
    final customApiAuthService = _authService is CustomApiAuthService
        ? _authService as CustomApiAuthService
        : null;
    final linkingStatus = _accountLinkingStatus;
    final linkedProviderIds = linkingStatus?.linkedProviderIds.toSet() ??
        _authService.currentProviderIds.toSet();
    final trustedChannelsByProvider = {
      for (final channel
          in linkingStatus?.trustedChannels ?? const <AccountTrustedChannel>[])
        channel.provider: channel,
    };
    final primaryTrustedChannel =
        _sanitizeTrustedChannelProvider(_primaryTrustedChannel) ??
            linkingStatus?.primaryTrustedChannelProvider;
    final isGoogleReady =
        customApiAuthService?.isGoogleSignInConfigured ?? true;

    String providerLabel(String provider) {
      switch (provider) {
        case 'google':
          return 'Google';
        case 'telegram':
          return 'Telegram';
        case 'vk':
          return 'VK ID';
        case 'max':
          return 'MAX';
        case 'password':
        default:
          return 'Email и пароль';
      }
    }

    String providerDescription(String provider) {
      switch (provider) {
        case 'google':
          return isGoogleReady
              ? 'Вход и подтверждение личности через Google.'
              : 'Подключим после добавления client id для web и Android.';
        case 'telegram':
          return 'Подтверждённый канал связи и вход через Telegram.';
        case 'vk':
          return 'Подтверждённый профиль и вход через VK ID.';
        case 'max':
          return 'Подтверждённый канал связи через MAX.';
        case 'password':
        default:
          return 'Резервный вход для восстановления доступа.';
      }
    }

    Widget buildTrailing({
      required String provider,
      required bool isLinked,
      required bool isTrusted,
      required bool isPrimary,
    }) {
      if (isLinked && isPrimary) {
        return const Text('Основной');
      }
      if (isLinked && isTrusted) {
        return FilledButton.tonal(
          onPressed: _canSetPrimaryTrustedChannel(provider)
              ? () {
                  _updateSectionState(() {
                    _primaryTrustedChannel = provider;
                  });
                }
              : null,
          child: const Text('Сделать основным'),
        );
      }
      if (isLinked) {
        return const Text('Привязан');
      }
      if (provider == 'google') {
        return FilledButton.tonal(
          onPressed: isGoogleReady && !_isGoogleLinkLoading
              ? _startGoogleLinking
              : null,
          child: Text(_isGoogleLinkLoading ? 'Связываем...' : 'Привязать'),
        );
      }
      if (provider == 'telegram') {
        return FilledButton.tonal(
          onPressed: _isTelegramLinkLoading ? null : _startTelegramLinking,
          child: Text(_isTelegramLinkLoading ? 'Открываем...' : 'Привязать'),
        );
      }
      if (provider == 'vk') {
        return FilledButton.tonal(
          onPressed: _isVkLinkLoading ? null : _startVkLinking,
          child: Text(_isVkLinkLoading ? 'Открываем...' : 'Привязать'),
        );
      }
      if (provider == 'max') {
        return FilledButton.tonal(
          onPressed: _isMaxLinkLoading ? null : _startMaxLinking,
          child: Text(_isMaxLinkLoading ? 'Открываем...' : 'Привязать'),
        );
      }
      return Text(
        'Скоро',
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('Подтверждённые каналы'),
          const SizedBox(height: 8),
          Text(
            linkingStatus?.summaryTitle ??
                'Привяжите VK, Telegram, Google или MAX и выберите основной канал.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if ((linkingStatus?.summaryDetail ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              linkingStatus!.summaryDetail!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 14),
          ...['password', 'google', 'telegram', 'vk', 'max'].map(
            (provider) {
              final channel = trustedChannelsByProvider[provider];
              final isLinked =
                  channel?.isLinked ?? linkedProviderIds.contains(provider);
              final isTrusted = channel?.isTrustedChannel ??
                  (provider != 'password' && isLinked);
              final isPrimary = primaryTrustedChannel == provider && isTrusted;
              final subtitleParts = <String>[
                channel?.description ?? providerDescription(provider),
                if (isLinked &&
                    (channel?.verificationLabel ?? '').trim().isNotEmpty)
                  channel!.verificationLabel,
                if ((channel?.emailMasked ?? '').trim().isNotEmpty)
                  channel!.emailMasked!,
                if ((channel?.phoneMasked ?? '').trim().isNotEmpty)
                  channel!.phoneMasked!,
              ];

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerLowest
                        .withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ListTile(
                    leading: Icon(
                      isLinked
                          ? (isTrusted
                              ? Icons.verified_user_outlined
                              : Icons.login_outlined)
                          : Icons.link_outlined,
                      color: isLinked
                          ? (isTrusted
                              ? Colors.green
                              : Theme.of(context).colorScheme.primary)
                          : Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(channel?.label ?? providerLabel(provider)),
                    subtitle: Text(subtitleParts.join('\n')),
                    trailing: buildTrailing(
                      provider: provider,
                      isLinked: isLinked,
                      isTrusted: isTrusted,
                      isPrimary: isPrimary,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label, {
    String? hintText,
    Widget? suffixIcon,
    String? prefixText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      suffixIcon: suffixIcon,
      prefixText: prefixText,
      filled: true,
      fillColor: Theme.of(context)
          .colorScheme
          .surfaceContainerLowest
          .withValues(alpha: 0.88),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
