// ignore_for_file: library_private_types_in_public_api
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // Для форматирования дат
import 'package:lineage/models/family_person.dart';
import '../models/family_relation.dart'; // Добавляем импорт

import '../models/user_profile.dart';
import '../providers/tree_provider.dart'; // Для treeId
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:get_it/get_it.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/invitation_link_service_interface.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../backend/interfaces/storage_service_interface.dart';
import '../models/tree_change_record.dart';
import '../widgets/tree_history_sheet.dart';

class _RelativeContactStatus {
  const _RelativeContactStatus({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
}

enum _RelativeGalleryAction {
  makePrimary,
  delete,
}

class RelativeDetailsScreen extends StatefulWidget {
  final String personId;

  const RelativeDetailsScreen({required this.personId, super.key});

  @override
  _RelativeDetailsScreenState createState() => _RelativeDetailsScreenState();
}

class _RelativeDetailsScreenState extends State<RelativeDetailsScreen> {
  // Используем widget.personId для доступа к ID
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final FamilyTreeServiceInterface _familyService =
      GetIt.I<FamilyTreeServiceInterface>();
  final ProfileServiceInterface _profileService =
      GetIt.I<ProfileServiceInterface>();
  final InvitationLinkServiceInterface _invitationLinkService =
      GetIt.I<InvitationLinkServiceInterface>();
  final StorageServiceInterface _storageService =
      GetIt.I<StorageServiceInterface>();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isGeneratingLink = false;
  bool _isUpdatingGallery = false;
  bool _isLoadingHistory = false;

  FamilyPerson? _person;
  List<FamilyPerson> _treePeople = [];
  List<FamilyRelation> _relations = [];
  List<TreeChangeRecord> _historyRecords = [];
  UserProfile? _userProfile;
  RelationType? _relationToCurrentUser;
  bool _isLoading = true;
  String _errorMessage = '';
  String? _currentTreeId;
  String? _currentUserPersonId;

  @override
  void initState() {
    super.initState();
    // Получаем treeId из провайдера ПОСЛЕ построения виджета
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _currentTreeId = Provider.of<TreeProvider>(
        context,
        listen: false,
      ).selectedTreeId;
      _loadData();
    });
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _person = null;
      _treePeople = [];
      _relations = [];
      _historyRecords = [];
      _userProfile = null;
      _relationToCurrentUser = null;
      _currentUserPersonId = null;
      _isLoadingHistory = true;
    });

    if (_currentTreeId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ошибка: Не удалось определить текущее дерево.';
      });
      return;
    }

    try {
      // 0. Загружаем профиль ТЕКУЩЕГО пользователя (нужен для getReciprocalType)
      final currentUserId = _authService.currentUserId;
      if (currentUserId != null) {
        try {
          await _profileService.getUserProfile(currentUserId);
        } catch (profileError) {
          debugPrint(
            'Не удалось загрузить профиль текущего пользователя: $profileError',
          );
          // Не считаем критичной ошибкой для отображения деталей родственника
        }
      }

      final relatives = await _familyService.getRelatives(_currentTreeId!);
      _relations = await _familyService.getRelations(_currentTreeId!);
      _treePeople = relatives;
      final currentUserPerson =
          relatives.where((p) => p.userId == currentUserId);
      _currentUserPersonId =
          currentUserPerson.isNotEmpty ? currentUserPerson.first.id : null;

      _person =
          await _familyService.getPersonById(_currentTreeId!, widget.personId);

      // 2. Если есть userId, пытаемся загрузить UserProfile
      if (_person!.userId != null && _person!.userId!.isNotEmpty) {
        _userProfile = await _profileService.getUserProfile(_person!.userId!);
        // Ошибку загрузки профиля пока не считаем критичной
      }

      // 3. Определяем родственную связь с текущим пользователем
      if (_currentUserPersonId != null && _person != null) {
        _relationToCurrentUser = await _familyService.getRelationBetween(
          _currentTreeId!,
          _currentUserPersonId!,
          _person!.id,
        );
        debugPrint(
          'Связь ${widget.personId} с текущим пользователем ($_currentUserPersonId): $_relationToCurrentUser',
        );
        debugPrint('Пол родственника ${_person!.id}: ${_person!.gender}');
      }

      try {
        if (_person != null) {
          _historyRecords = await _familyService.getTreeHistory(
            treeId: _currentTreeId!,
            personId: _person!.id,
          );
        }
      } catch (historyError) {
        debugPrint(
          'Не удалось загрузить историю изменений для ${widget.personId}: $historyError',
        );
        _historyRecords = [];
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки данных родственника ${widget.personId}: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingHistory = false;
          _errorMessage = 'Не удалось загрузить данные родственника.';
        });
      }
    }
  }

  // Форматирование даты
  String _formatDate(DateTime? date) {
    if (date == null) return 'Неизвестно';
    return DateFormat.yMMMMd('ru').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_person?.displayName ?? 'Профиль'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_canEditOrDelete())
            IconButton(
              icon: Icon(Icons.edit_outlined),
              tooltip: 'Редактировать профиль',
              onPressed: _editRelative,
            ),
          if (_canEditOrDelete())
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Удалить профиль',
              onPressed: _deleteRelative,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_errorMessage, textAlign: TextAlign.center),
        ),
      );
    }
    if (_person == null) {
      // Эта ситуация не должна возникать, если _loadData отработал без ошибок
      return const Center(child: Text('Данные родственника не найдены.'));
    }

    // Определяем, онлайн ли пользователь
    // Используем данные UserProfile если они есть, иначе данные FamilyPerson
    final String displayName =
        _userProfile?.displayName ?? _person!.displayName;
    final String? photoUrl = _person!.primaryPhotoUrl ?? _userProfile?.photoURL;
    final String? city = _userProfile?.city;
    final String? country = _userProfile?.country;
    final String? placeLabel = _buildPlaceLabel(city, country);
    final bool canStartChat = _canStartChatWithPerson();
    final bool canInvite = _canInvitePerson();
    final contactStatus = _getContactStatus();
    final directRelationLabel = _getDirectRelationLabel();
    final galleryEntries = _person!.photoGallery;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundImage:
                          photoUrl != null ? NetworkImage(photoUrl) : null,
                      child: photoUrl == null
                          ? Text(
                              _person!.initials,
                              style: const TextStyle(fontSize: 22),
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildStatusChip(contactStatus),
                              if (directRelationLabel != null)
                                Chip(
                                  avatar: const Icon(
                                    Icons.family_restroom_outlined,
                                    size: 18,
                                  ),
                                  label: Text('Для вас: $directRelationLabel'),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                          if (placeLabel != null) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 16,
                                  color: Colors.grey[700],
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    placeLabel,
                                    style: TextStyle(color: Colors.grey[700]),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  contactStatus.description,
                  style: TextStyle(color: Colors.grey[800], height: 1.35),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (canStartChat)
                      FilledButton.icon(
                        onPressed: _openChatWithPerson,
                        icon: const Icon(Icons.message_outlined, size: 18),
                        label: const Text('Написать'),
                      ),
                    if (canInvite)
                      OutlinedButton.icon(
                        onPressed: _isGeneratingLink
                            ? null
                            : _generateAndShareInviteLink,
                        icon: _isGeneratingLink
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Пригласить в Родню'),
                      ),
                    if (_canEditOrDelete())
                      OutlinedButton.icon(
                        onPressed: _editRelative,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Редактировать'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (galleryEntries.isNotEmpty || _canEditOrDelete()) ...[
            const SizedBox(height: 20),
            _buildGallerySection(galleryEntries),
          ],
          if (_person != null) ...[
            const SizedBox(height: 20),
            _buildHistorySection(),
          ],
          const Divider(height: 32),

          // --- Основная информация ---
          _buildInfoSection('Основная информация', [
            _buildInfoRow('Пол:', _genderToString(_person!.gender)),
            if (_person!.maidenName != null && _person!.maidenName!.isNotEmpty)
              _buildInfoRow('Девичья фамилия:', _person!.maidenName!),
            if (_relationToCurrentUser != null &&
                _relationToCurrentUser != RelationType.other)
              _buildInfoRow('Родственная связь:', () {
                // Отношение пользователя к родственнику (результат getRelationBetween)
                final relationUserToRelative = _relationToCurrentUser!;
                // Получаем зеркальное отношение (родственника к пользователю)
                final relationRelativeToUser = FamilyRelation.getMirrorRelation(
                  relationUserToRelative,
                );
                debugPrint(
                  'Отображаемая связь (пользователь -> ${_person!.id}): $relationUserToRelative',
                );
                debugPrint(
                  'Зеркальная связь (${_person!.id} -> пользователь): $relationRelativeToUser',
                );
                // Используем ЗЕРКАЛЬНОЕ отношение и ПОЛ РОДСТВЕННИКА для имени
                return FamilyRelation.getRelationName(
                  relationRelativeToUser,
                  _person!.gender,
                );
              }()),
          ]),

          // --- Даты жизни ---
          _buildInfoSection('Даты жизни', [
            _buildInfoRow('Дата рождения:', _formatDate(_person!.birthDate)),
            if (_person!.birthPlace != null && _person!.birthPlace!.isNotEmpty)
              _buildInfoRow('Место рождения:', _person!.birthPlace!),
            if (!_person!.isAlive) ...[
              _buildInfoRow('Дата смерти:', _formatDate(_person!.deathDate)),
              if (_person!.deathPlace != null &&
                  _person!.deathPlace!.isNotEmpty)
                _buildInfoRow('Место смерти:', _person!.deathPlace!),
            ] else
              _buildInfoRow('Статус:', 'Жив(а)'),
          ]),

          // --- Заметки ---
          if (_person!.notes != null && _person!.notes!.isNotEmpty)
            _buildInfoSection('Заметки', [
              Text(
                _person!.notes!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ]),

          if (_buildDirectFamilyRows().isNotEmpty)
            _buildInfoSection('Семья', _buildDirectFamilyRows()),
          const SizedBox(height: 20), // Отступ снизу
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120, // Фиксированная ширина для метки
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _buildGallerySection(List<Map<String, dynamic>> galleryEntries) {
    final canManageGallery = _canEditOrDelete();
    final countLabel = galleryEntries.isEmpty
        ? 'Фотографий пока нет'
        : galleryEntries.length == 1
            ? '1 фото'
            : '${galleryEntries.length} фото';

    return _buildInfoSection('Фотографии', [
      Row(
        children: [
          Expanded(
            child: Text(
              countLabel,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
          if (_isUpdatingGallery)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (canManageGallery)
            OutlinedButton.icon(
              onPressed: _pickAndUploadGalleryImage,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Добавить фото'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (galleryEntries.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            canManageGallery
                ? 'Добавьте первое фото, чтобы у родственника появилась медиакарточка.'
                : 'У этого родственника пока нет загруженных фотографий.',
            style: TextStyle(color: Colors.grey[700], height: 1.35),
          ),
        )
      else
        SizedBox(
          height: 146,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: galleryEntries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final media = galleryEntries[index];
              final mediaUrl = media['url']?.toString() ?? '';
              final isPrimary = media['isPrimary'] == true;

              return InkWell(
                onTap: mediaUrl.isEmpty
                    ? null
                    : () => _openGalleryViewer(
                          galleryEntries,
                          initialIndex: index,
                        ),
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: 116,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isPrimary
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                  width: isPrimary ? 2 : 1,
                                ),
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLowest,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: mediaUrl.isEmpty
                                  ? Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.grey[600],
                                      ),
                                    )
                                  : Image.network(
                                      mediaUrl,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Center(
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                            ),
                            Positioned(
                              left: 8,
                              top: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.58),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    isPrimary ? 'Основное' : 'Фото',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (canManageGallery)
                              Positioned(
                                right: 4,
                                top: 4,
                                child: PopupMenuButton<_RelativeGalleryAction>(
                                  tooltip: 'Действия с фото',
                                  onSelected: (action) {
                                    switch (action) {
                                      case _RelativeGalleryAction.makePrimary:
                                        _setPrimaryGalleryMedia(media);
                                        break;
                                      case _RelativeGalleryAction.delete:
                                        _deleteGalleryMedia(media);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    if (!isPrimary)
                                      const PopupMenuItem<
                                          _RelativeGalleryAction>(
                                        value:
                                            _RelativeGalleryAction.makePrimary,
                                        child: Text('Сделать основным'),
                                      ),
                                    const PopupMenuItem<_RelativeGalleryAction>(
                                      value: _RelativeGalleryAction.delete,
                                      child: Text('Удалить фото'),
                                    ),
                                  ],
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.55),
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(6),
                                    child: const Icon(
                                      Icons.more_vert,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isPrimary ? 'Используется в дереве' : 'Дополнительное',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[800],
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _buildHistorySection() {
    final latestRecord =
        _historyRecords.isNotEmpty ? _historyRecords.first : null;
    final summaryLabel = _historyRecords.isEmpty
        ? 'Журнал пока пуст'
        : _historyRecords.length == 1
            ? '1 запись'
            : '${_historyRecords.length} записей';

    return _buildInfoSection('История изменений', [
      if (_isLoadingHistory)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        )
      else
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      latestRecord == null
                          ? Icons.history_outlined
                          : _historyIcon(latestRecord),
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          latestRecord == null
                              ? 'Для этой карточки пока нет записей.'
                              : _historyTitle(latestRecord),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          latestRecord == null
                              ? 'Журнал появится после первых изменений профиля, связей или фотографий.'
                              : _historySubtitle(latestRecord),
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.summarize_outlined, size: 16),
                    label: Text(summaryLabel),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _openHistorySheet,
                    icon: const Icon(Icons.history_outlined, size: 18),
                    label: const Text('Открыть историю'),
                  ),
                ],
              ),
            ],
          ),
        ),
    ]);
  }

  String _genderToString(Gender gender) {
    switch (gender) {
      case Gender.male:
        return 'Мужской';
      case Gender.female:
        return 'Женский';
      case Gender.other:
        return 'Другой';
      case Gender.unknown:
        return 'Не указан';
    }
  }

  bool _canEditOrDelete() {
    return _person != null &&
        (_person!.userId == null || _person!.userId!.isEmpty) &&
        _person!.creatorId == _authService.currentUserId;
  }

  bool _canStartChatWithPerson() {
    final userId = _person?.userId;
    return userId != null &&
        userId.isNotEmpty &&
        userId != _authService.currentUserId;
  }

  bool _canInvitePerson() {
    final userId = _person?.userId;
    return _person != null &&
        (userId == null || userId.isEmpty) &&
        _person!.id != _currentUserPersonId;
  }

  String? _buildPlaceLabel(String? city, String? country) {
    final hasCity = city != null && city.isNotEmpty;
    final hasCountry = country != null && country.isNotEmpty;
    if (!hasCity && !hasCountry) {
      return null;
    }

    if (hasCity && hasCountry) {
      return '$city, $country';
    }

    return city ?? country;
  }

  _RelativeContactStatus _getContactStatus() {
    if (_person?.id == _currentUserPersonId) {
      return const _RelativeContactStatus(
        label: 'Это вы',
        description:
            'Эта карточка привязана к вашему профилю в текущем дереве.',
        icon: Icons.person,
        color: Colors.blue,
      );
    }

    if (_canStartChatWithPerson()) {
      return _RelativeContactStatus(
        label: 'Есть аккаунт в Родне',
        description:
            'С этим родственником уже можно общаться в личных сообщениях.',
        icon: Icons.verified_user_outlined,
        color: Colors.green.shade700,
      );
    }

    if (_canInvitePerson()) {
      return _RelativeContactStatus(
        label: 'Пока без аккаунта',
        description:
            'Отправьте приглашение, чтобы родственник подключился к дереву и чату.',
        icon: Icons.person_add_alt_1_outlined,
        color: Colors.orange.shade700,
      );
    }

    return _RelativeContactStatus(
      label: 'Карточка в дереве',
      description:
          'Профиль доступен для просмотра в дереве, даже если аккаунт ещё не привязан.',
      icon: Icons.visibility_outlined,
      color: Colors.grey.shade700,
    );
  }

  String? _getDirectRelationLabel() {
    if (_person == null ||
        _relationToCurrentUser == null ||
        _relationToCurrentUser == RelationType.other) {
      return null;
    }

    final relationRelativeToUser = FamilyRelation.getMirrorRelation(
      _relationToCurrentUser!,
    );
    return FamilyRelation.getRelationName(
      relationRelativeToUser,
      _person!.gender,
    );
  }

  Widget _buildStatusChip(_RelativeContactStatus status) {
    return Chip(
      avatar: Icon(status.icon, size: 18, color: status.color),
      label: Text(status.label),
      labelStyle: TextStyle(
        color: status.color,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: status.color.withValues(alpha: 0.1),
      side: BorderSide(color: status.color.withValues(alpha: 0.18)),
      visualDensity: VisualDensity.compact,
    );
  }

  List<Widget> _buildDirectFamilyRows() {
    if (_person == null) {
      return const [];
    }

    final peopleById = {for (final person in _treePeople) person.id: person};
    final rows = <Widget>[];

    for (final relation in _relations) {
      late final String relatedPersonId;
      late final RelationType relationFromRelatedPerson;

      if (relation.person1Id == _person!.id) {
        relatedPersonId = relation.person2Id;
        relationFromRelatedPerson = relation.relation2to1;
      } else if (relation.person2Id == _person!.id) {
        relatedPersonId = relation.person1Id;
        relationFromRelatedPerson = relation.relation1to2;
      } else {
        continue;
      }

      final relatedPerson = peopleById[relatedPersonId];
      if (relatedPerson == null) {
        continue;
      }

      rows.add(
        InkWell(
          onTap: () => context.push('/relative/details/${relatedPerson.id}'),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    relatedPerson.displayName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  FamilyRelation.getRelationName(
                    relationFromRelatedPerson,
                    relatedPerson.gender,
                  ),
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      );
    }

    return rows;
  }

  void _editRelative() {
    if (!_canEditOrDelete() || _currentTreeId == null) return;

    debugPrint(
      'Переход на редактирование: personId=${_person!.id}, treeId=$_currentTreeId',
    );
    context
        .push(
      '/relatives/edit/${_currentTreeId!}/${_person!.id}',
      extra: _person,
    )
        .then((result) {
      if (result == true && mounted) {
        debugPrint('Возврат с экрана редактирования, перезагрузка данных...');
        _loadData();
      }
    });
  }

  Future<void> _deleteRelative() async {
    if (!_canEditOrDelete() || _currentTreeId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтверждение удаления'),
        content: Text(
          'Вы уверены, что хотите удалить профиль '
          '${_person!.displayName}'
          '? Это действие необратимо.',
        ),
        actions: [
          TextButton(
            child: const Text('Отмена'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.redAccent),
            ),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
      });
      try {
        await _familyService.deleteRelative(_currentTreeId!, widget.personId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Профиль '
                '${_person!.displayName}'
                ' удален.',
              ),
            ),
          );
          context.pop();
        }
      } catch (e) {
        debugPrint('Ошибка удаления родственника: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка при удалении профиля: $e')),
          );
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _generateAndShareInviteLink() async {
    if (_person == null || _currentTreeId == null) return;

    setState(() {
      _isGeneratingLink = true;
    });

    try {
      final inviteUrl = _invitationLinkService.buildInvitationLink(
        treeId: _currentTreeId!,
        personId: _person!.id,
      );

      if (mounted) {
        final box = context.findRenderObject() as RenderBox?;
        // Используем share_plus для отправки ссылки
        await Share.share(
          'Присоединяйтесь к нашему семейному древу в Родне! ${inviteUrl.toString()}',
          subject: 'Приглашение в Родню',
          sharePositionOrigin:
              box!.localToGlobal(Offset.zero) & box.size, // Позиция для iPad
        );
      }
    } catch (e) {
      debugPrint('Ошибка при генерации или отправке ссылки: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingLink = false;
        });
      }
    }
  }

  void _openChatWithPerson() {
    if (!_canStartChatWithPerson() || _person == null) {
      return;
    }

    final displayName = _userProfile?.displayName ?? _person!.displayName;
    final photoUrl = _person!.primaryPhotoUrl ?? _userProfile?.photoURL;

    try {
      final nameParam = Uri.encodeComponent(displayName);
      final photoParam = photoUrl != null ? Uri.encodeComponent(photoUrl) : '';
      final relativeIdParam = Uri.encodeComponent(_person!.id);
      context.push(
        '/relatives/chat/${_person!.userId}?name=$nameParam&photo=$photoParam&relativeId=$relativeIdParam',
      );
    } catch (e) {
      debugPrint('Ошибка при переходе в чат: $e');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка при открытии чата.'),
        ),
      );
    }
  }

  Future<void> _pickAndUploadGalleryImage() async {
    if (_person == null ||
        _currentTreeId == null ||
        !_canEditOrDelete() ||
        _isUpdatingGallery) {
      return;
    }

    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (image == null) {
      return;
    }

    setState(() {
      _isUpdatingGallery = true;
    });

    try {
      final uploadedUrl = await _storageService.uploadImage(image, 'relatives');
      if (uploadedUrl == null || uploadedUrl.isEmpty) {
        throw Exception('backend не вернул URL после загрузки фото');
      }

      final updatedPerson = await _familyService.addRelativeMedia(
        treeId: _currentTreeId!,
        personId: _person!.id,
        mediaData: {
          'url': uploadedUrl,
          'type': 'image',
          'contentType': image.mimeType,
          'isPrimary': _person!.photoGallery.isEmpty,
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _person = updatedPerson;
      });
      await _refreshHistory();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Фото добавлено в галерею.')),
      );
    } catch (e) {
      debugPrint('Ошибка загрузки фото родственника: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось добавить фото: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingGallery = false;
        });
      }
    }
  }

  Future<void> _setPrimaryGalleryMedia(Map<String, dynamic> media) async {
    final mediaId = media['id']?.toString();
    if (_person == null ||
        _currentTreeId == null ||
        !_canEditOrDelete() ||
        _isUpdatingGallery ||
        mediaId == null ||
        mediaId.isEmpty ||
        media['isPrimary'] == true) {
      return;
    }

    setState(() {
      _isUpdatingGallery = true;
    });

    try {
      final updatedPerson = await _familyService.updateRelativeMedia(
        treeId: _currentTreeId!,
        personId: _person!.id,
        mediaId: mediaId,
        mediaData: const {'isPrimary': true},
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _person = updatedPerson;
      });
      await _refreshHistory();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Основное фото обновлено.')),
      );
    } catch (e) {
      debugPrint('Ошибка обновления основного фото: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сменить основное фото: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingGallery = false;
        });
      }
    }
  }

  Future<void> _deleteGalleryMedia(Map<String, dynamic> media) async {
    final mediaId = media['id']?.toString();
    if (_person == null ||
        _currentTreeId == null ||
        !_canEditOrDelete() ||
        _isUpdatingGallery ||
        mediaId == null ||
        mediaId.isEmpty) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить фото?'),
        content: const Text(
          'Фотография исчезнет из карточки родственника и из списка дерева.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    setState(() {
      _isUpdatingGallery = true;
    });

    try {
      final updatedPerson = await _familyService.deleteRelativeMedia(
        treeId: _currentTreeId!,
        personId: _person!.id,
        mediaId: mediaId,
      );

      final deletedUrl = media['url']?.toString();
      if (deletedUrl != null && deletedUrl.isNotEmpty) {
        try {
          await _storageService.deleteImage(deletedUrl);
        } catch (storageError) {
          debugPrint('Не удалось удалить файл из storage: $storageError');
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _person = updatedPerson;
      });
      await _refreshHistory();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Фото удалено из галереи.')),
      );
    } catch (e) {
      debugPrint('Ошибка удаления фото родственника: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось удалить фото: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingGallery = false;
        });
      }
    }
  }

  Future<void> _refreshHistory() async {
    if (_currentTreeId == null || _person == null) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingHistory = true;
      });
    }

    try {
      final records = await _familyService.getTreeHistory(
        treeId: _currentTreeId!,
        personId: _person!.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _historyRecords = records;
        _isLoadingHistory = false;
      });
    } catch (e) {
      debugPrint('Ошибка обновления истории изменений: $e');
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  void _openHistorySheet() {
    if (_currentTreeId == null || _person == null) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return TreeHistorySheet(
          historyFuture: _historyRecords.isNotEmpty && !_isLoadingHistory
              ? Future.value(_historyRecords)
              : _familyService.getTreeHistory(
                  treeId: _currentTreeId!,
                  personId: _person!.id,
                ),
          title: 'История изменений',
          subtitle: _person!.displayName,
          currentUserId: _authService.currentUserId,
          emptyMessage: 'Для этой карточки пока нет записей в журнале.',
          onOpenPerson: (personId) {
            Navigator.of(sheetContext).pop();
            if (!mounted || personId == _person!.id) {
              return;
            }
            context.push('/relative/details/$personId');
          },
        );
      },
    );
  }

  void _openGalleryViewer(
    List<Map<String, dynamic>> galleryEntries, {
    required int initialIndex,
  }) {
    if (galleryEntries.isEmpty) {
      return;
    }

    final pageController = PageController(initialPage: initialIndex);
    var currentIndex = initialIndex;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final media = galleryEntries[currentIndex];
            final caption = media['caption']?.toString();

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              backgroundColor: Colors.black,
              child: SizedBox(
                width: 520,
                height: 520,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              media['isPrimary'] == true
                                  ? 'Основное фото'
                                  : 'Фото',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: pageController,
                        itemCount: galleryEntries.length,
                        onPageChanged: (index) {
                          setDialogState(() {
                            currentIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final itemUrl =
                              galleryEntries[index]['url']?.toString() ?? '';
                          return InteractiveViewer(
                            child: itemUrl.isEmpty
                                ? const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  )
                                : Image.network(
                                    itemUrl,
                                    fit: BoxFit.contain,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        children: [
                          Text(
                            '${currentIndex + 1} из ${galleryEntries.length}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          if (caption != null && caption.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              caption,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                          if (galleryEntries.length > 1) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 52,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: galleryEntries.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final itemUrl = galleryEntries[index]['url']
                                          ?.toString() ??
                                      '';
                                  final isSelected = index == currentIndex;

                                  return InkWell(
                                    onTap: () {
                                      pageController.jumpToPage(index);
                                      setDialogState(() {
                                        currentIndex = index;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 52,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.white24,
                                          width: isSelected ? 2 : 1,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: itemUrl.isEmpty
                                          ? const ColoredBox(
                                              color: Colors.black54,
                                              child: Icon(
                                                Icons.image_not_supported,
                                                color: Colors.white54,
                                              ),
                                            )
                                          : Image.network(
                                              itemUrl,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  IconData _historyIcon(TreeChangeRecord record) {
    switch (record.type) {
      case 'person_media.created':
        return Icons.add_photo_alternate_outlined;
      case 'person_media.updated':
        return Icons.star_outline;
      case 'person_media.deleted':
        return Icons.delete_outline;
      case 'person.created':
        return Icons.person_add_alt_1_outlined;
      case 'person.updated':
        return Icons.edit_outlined;
      case 'person.deleted':
        return Icons.person_remove_outlined;
      case 'relation.created':
        return Icons.device_hub_outlined;
      case 'relation.deleted':
        return Icons.link_off_outlined;
      default:
        return Icons.history_outlined;
    }
  }

  String _historyTitle(TreeChangeRecord record) {
    switch (record.type) {
      case 'person_media.created':
        return 'Добавлено фото';
      case 'person_media.updated':
        return 'Обновлено фото';
      case 'person_media.deleted':
        return 'Удалено фото';
      case 'person.created':
        return 'Создан профиль';
      case 'person.updated':
        return 'Обновлён профиль';
      case 'person.deleted':
        return 'Профиль удалён';
      case 'relation.created':
        return 'Добавлена связь';
      case 'relation.deleted':
        return 'Удалена связь';
      default:
        return 'Изменение в дереве';
    }
  }

  String _historySubtitle(TreeChangeRecord record) {
    final who = record.actorId == null || record.actorId!.isEmpty
        ? 'Действие в дереве'
        : record.actorId == _authService.currentUserId
            ? 'Вы'
            : 'Участник дерева';
    final when = DateFormat('d MMM, HH:mm', 'ru').format(record.createdAt);
    return '$who · $when';
  }
}
