import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../backend/interfaces/storage_service_interface.dart';
import '../utils/user_facing_error.dart';
import '../widgets/custom_relation_label_dialog.dart';
import '../widgets/tree_history_sheet.dart';

part 'add_relative_screen_sections.dart';

enum _PostSaveAction { close, stayInQuickAdd, openInTree }

enum _RelativeEditorMode { basic, advanced }

class _RelativeImportantEventDraft {
  _RelativeImportantEventDraft({
    String title = '',
    this.date,
  }) : titleController = TextEditingController(text: title);

  final TextEditingController titleController;
  DateTime? date;

  bool get isMeaningful =>
      titleController.text.trim().isNotEmpty || date != null;

  Event? toEvent() {
    final title = titleController.text.trim();
    if (title.isEmpty || date == null) {
      return null;
    }
    return Event(title: title, date: date!);
  }

  void dispose() {
    titleController.dispose();
  }
}

class _RelativeDraftMedia {
  const _RelativeDraftMedia({
    required this.id,
    required this.file,
    required this.type,
    required this.contentType,
    required this.isPrimary,
  });

  final String id;
  final XFile file;
  final String type;
  final String? contentType;
  final bool isPrimary;

  IconData get icon =>
      type == 'video' ? Icons.videocam_outlined : Icons.photo_outlined;

  String get label => type == 'video' ? 'Видео' : 'Фото';
}

class AddRelativeScreen extends StatefulWidget {
  final String treeId;
  final FamilyPerson? person;
  final FamilyPerson? relatedTo;
  final bool isEditing;
  final RelationType? predefinedRelation;
  final bool quickAddMode;
  final Map<String, dynamic>? routeExtra;
  final Map<String, String> routeQueryParameters;

  const AddRelativeScreen({
    super.key,
    required this.treeId,
    this.person,
    this.relatedTo,
    this.isEditing = false,
    this.predefinedRelation,
    this.quickAddMode = false,
    this.routeExtra,
    this.routeQueryParameters = const <String, String>{},
  });

  @override
  State<AddRelativeScreen> createState() => _AddRelativeScreenState();
}

class _AddRelativeScreenState extends State<AddRelativeScreen> {
  final _formKey = GlobalKey<FormState>();
  final FamilyTreeServiceInterface _familyService =
      GetIt.I<FamilyTreeServiceInterface>();
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final ProfileServiceInterface _profileService =
      GetIt.I<ProfileServiceInterface>();
  final StorageServiceInterface _storageService =
      GetIt.I<StorageServiceInterface>();
  final ImagePicker _imagePicker = ImagePicker();

  // Контроллеры для полей формы
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _maidenNameController = TextEditingController();
  final _birthPlaceController = TextEditingController();
  final _educationController = TextEditingController();
  final _bioController = TextEditingController();
  final _notesController = TextEditingController();

  // Состояние формы
  DateTime? _birthDate;
  DateTime? _deathDate;
  DateTime? _marriageDate;
  Gender? _selectedGender;
  RelationType? _selectedRelationType;
  RelationType? _initialRelationType;
  Gender _gender = Gender.unknown; // Пол текущего пользователя
  bool _isLoading = false;
  bool _isCheckingTreeState = true;
  bool _isFirstPersonInTree = false;
  bool _isUpdatingMedia = false;
  _RelativeEditorMode _editorMode = _RelativeEditorMode.basic;
  final List<_RelativeImportantEventDraft> _importantEventDrafts =
      <_RelativeImportantEventDraft>[];
  final List<_RelativeDraftMedia> _draftMedia = <_RelativeDraftMedia>[];

  // Переменные для контекста из дерева
  FamilyPerson? _contextPerson;
  RelationType? _contextRelationType;
  bool _isLoadingContext = false;
  bool _isQuickAddMode = false;

  void _updateSectionState(VoidCallback update) {
    setState(update);
  }

  @override
  void initState() {
    super.initState();
    _isQuickAddMode = widget.quickAddMode;
    _editorMode = _RelativeEditorMode.basic;
    _loadUserGender();
    _loadTreeState();

    // Если редактируем существующего человека, заполняем форму его данными
    if (widget.isEditing && widget.person != null) {
      final nameParts = widget.person!.name.split(' ');
      String lastName = '';
      String firstName = '';
      String? middleName;
      if (nameParts.isNotEmpty) lastName = nameParts[0];
      if (nameParts.length >= 2) firstName = nameParts[1];
      if (nameParts.length >= 3) middleName = nameParts.sublist(2).join(' ');
      // -------------------------------------------------------------------
      _lastNameController.text = lastName;
      _firstNameController.text = firstName;
      _middleNameController.text = middleName ?? '';
      _maidenNameController.text = widget.person!.maidenName ?? '';
      _birthPlaceController.text = widget.person!.birthPlace ?? '';
      _educationController.text = widget.person!.details?.education ?? '';
      _bioController.text = widget.person!.familySummary ??
          widget.person!.notes ??
          widget.person!.bio ??
          '';
      _notesController.text = '';
      _selectedGender = widget.person!.gender;
      _birthDate = widget.person!.birthDate;
      _deathDate = widget.person!.deathDate;
      _seedImportantEventDrafts(widget.person!.details?.importantEvents);

      // Загружаем текущий тип отношения (правильно)
      _loadCurrentRelationType();
    }

    // Если добавляем к существующему родственнику, но не редактируем
    if (widget.relatedTo != null && !widget.isEditing) {
      // Используем predefinedRelation, если он есть
      if (widget.predefinedRelation != null) {
        setState(() {
          _selectedRelationType = widget.predefinedRelation;
          // Опционально: можно попытаться угадать пол на основе связи,
          // но это может быть не всегда точно (например, для spouse/sibling).
          // Пока оставим пол неопределенным.
          _selectedGender = null;
        });
      } else {
        // Если predefinedRelation нет, предлагаем тип по умолчанию (например, ребенок)
        _loadRelationType(); // Старая логика для RelationType по умолчанию
      }
    }

    // Обновляем виджет связи при изменении имени/фамилии или пола
    _firstNameController.addListener(_updateRelationshipWidget);
    _lastNameController.addListener(_updateRelationshipWidget);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final extra = widget.routeExtra;
      final query = widget.routeQueryParameters;
      debugPrint('AddRelativeScreen initState: extra = $extra');
      if (extra is Map<String, dynamic> &&
          extra.containsKey('contextPersonId') &&
          extra.containsKey('relationType')) {
        final quickAddMode = extra['quickAddMode'] == true;
        final String contextPersonId = extra['contextPersonId'];
        final RelationType relationType = extra['relationType'];
        debugPrint(
          "AddRelativeScreen initState: Found context from tree. Person ID: $contextPersonId, Relation: $relationType",
        );
        if (quickAddMode != _isQuickAddMode) {
          setState(() {
            _isQuickAddMode = quickAddMode;
          });
        }
        _loadContextPerson(contextPersonId, relationType);
      } else if ((query['contextPersonId']?.isNotEmpty ?? false) &&
          (query['relationType']?.isNotEmpty ?? false)) {
        final quickAddMode = query['quickAddMode'] == '1' ||
            query['quickAddMode']?.toLowerCase() == 'true';
        final contextPersonId = query['contextPersonId']!;
        final relationType =
            FamilyRelation.stringToRelationType(query['relationType']);
        debugPrint(
          "AddRelativeScreen initState: Found query context. Person ID: $contextPersonId, Relation: $relationType",
        );
        if (quickAddMode != _isQuickAddMode) {
          setState(() {
            _isQuickAddMode = quickAddMode;
          });
        }
        _loadContextPerson(contextPersonId, relationType);
      } else if (widget.relatedTo != null) {
        // Используем relatedTo и predefinedRelation, если они переданы (из Details)
        debugPrint(
          "AddRelativeScreen initState: Using relatedTo from widget: ${widget.relatedTo!.id}",
        );
        setState(() {
          _selectedRelationType = widget.predefinedRelation;
          // Предзаполнение пола на основе predefinedRelation и пола relatedTo
          _prefillGenderBasedOnRelation(
            widget.relatedTo!,
            widget.predefinedRelation,
          );
          _prefillLastNameFromAnchor(
            widget.relatedTo,
            widget.predefinedRelation,
          );
        });
      } else {
        // Добавление родственника к текущему пользователю
        debugPrint(
          'AddRelativeScreen initState: Adding relative to current user.',
        );
        // Оставляем _selectedRelationType = null, пользователь выберет сам
      }
    });
  }

  void _seedImportantEventDrafts(List<Event>? events) {
    for (final draft in _importantEventDrafts) {
      draft.dispose();
    }
    _importantEventDrafts
      ..clear()
      ..addAll(
        (events ?? const <Event>[])
            .map(
              (event) => _RelativeImportantEventDraft(
                title: event.title,
                date: event.date,
              ),
            )
            .toList(),
      );
  }

  bool get _isCreatingFirstPerson =>
      !widget.isEditing &&
      widget.relatedTo == null &&
      _contextPerson == null &&
      _isFirstPersonInTree;

  bool get _isBusy => _isLoading || _isLoadingContext || _isCheckingTreeState;

  bool get _isContextualAdd =>
      !widget.isEditing && (_contextPerson != null || widget.relatedTo != null);

  FamilyPerson? get _anchorPerson => _contextPerson ?? widget.relatedTo;

  RelationType? get _resolvedRelationType =>
      _contextRelationType ??
      widget.predefinedRelation ??
      _selectedRelationType;

  bool get _canUseQuickAddLoop => _isQuickAddMode && _isContextualAdd;

  bool get _isAdvancedMode => _editorMode == _RelativeEditorMode.advanced;

  List<Map<String, dynamic>> get _existingMediaEntries =>
      widget.person?.photoGallery ?? const <Map<String, dynamic>>[];

  String _describeActionError(
    Object error, {
    required String fallbackMessage,
  }) {
    return describeUserFacingError(
      authService: _authService,
      error: error,
      fallbackMessage: fallbackMessage,
    );
  }

  Future<void> _loadTreeState() async {
    try {
      final relatives = await _familyService.getRelatives(widget.treeId);
      if (!mounted) return;
      setState(() {
        _isFirstPersonInTree = relatives.isEmpty;
        _isCheckingTreeState = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingTreeState = false;
      });
      debugPrint('Ошибка при определении состояния дерева: $e');
    }
  }

  void _updateRelationshipWidget() {
    // Перерисовываем виджет связи, чтобы обновить имя "Новый родственник"
    setState(() {});
  }

  Future<void> _pickDate(bool isBirthDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isBirthDate
          ? (_birthDate ?? DateTime.now())
          : (_deathDate ?? DateTime.now()),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('ru', 'RU'),
    );

    if (picked != null) {
      setState(() {
        if (isBirthDate) {
          _birthDate = picked;
        } else {
          _deathDate = picked;
        }
      });
    }
  }

  Future<void> _pickMarriageDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _marriageDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('ru', 'RU'),
    );

    if (picked != null) {
      setState(() {
        _marriageDate = picked;
      });
    }
  }

  Future<void> _pickImportantEventDate(
      _RelativeImportantEventDraft draft) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: draft.date ?? _birthDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      locale: const Locale('ru', 'RU'),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      draft.date = picked;
    });
  }

  void _addImportantEventDraft() {
    setState(() {
      _importantEventDrafts.add(_RelativeImportantEventDraft());
      _editorMode = _RelativeEditorMode.advanced;
    });
  }

  void _removeImportantEventDraft(_RelativeImportantEventDraft draft) {
    setState(() {
      _importantEventDrafts.remove(draft);
      draft.dispose();
    });
  }

  Future<void> _pickRelativeMedia({required bool video}) async {
    if (_isUpdatingMedia) {
      return;
    }

    final XFile? picked = video
        ? await _imagePicker.pickVideo(source: ImageSource.gallery)
        : await _imagePicker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 88,
          );
    if (picked == null) {
      return;
    }

    final isFirstMedia = _existingMediaEntries.isEmpty && _draftMedia.isEmpty;
    setState(() {
      _draftMedia.add(
        _RelativeDraftMedia(
          id: 'draft-${DateTime.now().microsecondsSinceEpoch}',
          file: picked,
          type: video ? 'video' : 'image',
          contentType: picked.mimeType,
          isPrimary: isFirstMedia,
        ),
      );
    });
  }

  void _removeDraftMedia(String draftId) {
    setState(() {
      _draftMedia.removeWhere((entry) => entry.id == draftId);
    });
  }

  Future<void> _uploadQueuedMedia(String personId) async {
    if (_draftMedia.isEmpty) {
      return;
    }

    setState(() {
      _isUpdatingMedia = true;
    });

    try {
      for (final media in List<_RelativeDraftMedia>.from(_draftMedia)) {
        final uploadedUrl =
            await _storageService.uploadImage(media.file, 'relatives');
        if (uploadedUrl == null || uploadedUrl.isEmpty) {
          throw Exception(
              'backend не вернул URL после загрузки ${media.label.toLowerCase()}');
        }

        await _familyService.addRelativeMedia(
          treeId: widget.treeId,
          personId: personId,
          mediaData: {
            'url': uploadedUrl,
            'type': media.type,
            'contentType': media.contentType,
            'isPrimary': media.isPrimary,
          },
        );
      }

      _draftMedia.clear();
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingMedia = false;
        });
      }
    }
  }

  Future<void> _savePerson({
    _PostSaveAction action = _PostSaveAction.close,
  }) async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        String? createdPersonId;
        final importantEvents = _importantEventDrafts
            .map((draft) => draft.toEvent())
            .whereType<Event>()
            .toList();
        final details = <String, dynamic>{
          if (_educationController.text.trim().isNotEmpty)
            'education': _educationController.text.trim(),
          if (importantEvents.isNotEmpty)
            'importantEvents':
                importantEvents.map((event) => event.toMap()).toList(),
        };

        // Создаем объект с данными из формы
        final Map<String, dynamic> personData = {
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'middleName': _middleNameController.text.trim(),
          'gender': _selectedGender != null
              ? _genderToString(_selectedGender!)
              : 'unknown',
          'birthPlace': _birthPlaceController.text.trim(),
          'familySummary': _bioController.text.trim(),
          if (details.isNotEmpty) 'details': details,
        };

        // Добавляем даты, если они указаны
        if (_birthDate != null) {
          personData['birthDate'] = _birthDate;
        }

        if (_deathDate != null) {
          personData['deathDate'] = _deathDate;
        }

        // Добавляем девичью фамилию для женщин
        if (_selectedGender == Gender.female &&
            _maidenNameController.text.isNotEmpty) {
          personData['maidenName'] = _maidenNameController.text.trim();
        }

        // Если редактируем существующего человека
        if (widget.isEditing) {
          if (widget.person != null) {
            // 1. Обновляем данные самого человека
            debugPrint('Сохранение редактирования: ID=${widget.person!.id}');
            debugPrint(
              'Значение _selectedGender перед сохранением: $_selectedGender',
            );
            debugPrint('Данные для сохранения (personData): $personData');
            await _familyService.updateRelative(widget.person!.id, personData);
            await _uploadQueuedMedia(widget.person!.id);

            // 2. Обновляем связь, если она изменилась
            final userId = _authService.currentUserId;
            if (userId != null &&
                _selectedRelationType != null &&
                _selectedRelationType != _initialRelationType) {
              debugPrint(
                'Обновляем связь: $_selectedRelationType между ${widget.person!.id} и $userId',
              );
              try {
                CustomRelationLabels? customLabels;
                if (_selectedRelationType == RelationType.other) {
                  if (!mounted) {
                    return;
                  }
                  customLabels = await showCustomRelationLabelDialog(
                    context: context,
                    person1Name: _draftDisplayName,
                    person2Name: _authService.currentUserDisplayName
                                ?.trim()
                                .isNotEmpty ==
                            true
                        ? _authService.currentUserDisplayName!.trim()
                        : 'Вы',
                    person1Gender: _selectedGender ?? widget.person!.gender,
                    person2Gender: _gender,
                  );
                  if (!mounted) {
                    return;
                  }
                  if (customLabels == null) {
                    setState(() {
                      _isLoading = false;
                    });
                    return;
                  }
                }
                await _familyService.createRelation(
                  treeId: widget.treeId,
                  person1Id: widget.person!.id,
                  person2Id: userId,
                  relation1to2: _selectedRelationType!,
                  isConfirmed: true,
                  customRelationLabel1to2: customLabels?.relation1to2,
                  customRelationLabel2to1: customLabels?.relation2to1,
                );
                // Обновляем _initialRelationType после успешного сохранения
                _initialRelationType = _selectedRelationType;
                debugPrint('Связь успешно обновлена.');
              } catch (e) {
                debugPrint('Ошибка при обновлении связи: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Не удалось обновить связь: $e')),
                  );
                }
                // Не выходим из функции, так как данные человека могли обновиться
              }
            } else if (_selectedRelationType == _initialRelationType) {
              debugPrint('Связь не изменилась, обновление не требуется.');
            } else {
              debugPrint(
                'Связь не выбрана или не изменилась, обновление связи не выполняется.',
              );
            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Информация о родственнике обновлена')),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Ошибка: Не удалось определить ID редактируемого родственника',
                  ),
                ),
              );
            }
            return; // Выходим, если некого редактировать
          }
        } else {
          // 2. Добавление нового родственника
          // addRelative теперь принимает только treeId и personData
          final newPersonId = await _familyService.addRelative(
            widget.treeId,
            personData,
          );
          createdPersonId = newPersonId;
          await _uploadQueuedMedia(newPersonId);

          // Получаем ID текущего пользователя
          final userId = _authService.currentUserId;
          if (userId == null) {
            throw Exception('Не удалось получить ID текущего пользователя.');
          }

          // Получаем выбранный тип отношения
          final relationType = _getRelationType();

          // Определяем ID второго человека в связи (КОГО связываем с новым)
          final String person2Id;
          final String person2Name;
          final Gender? person2Gender;
          if (_contextPerson != null) {
            person2Id = _contextPerson!.id;
            person2Name = _contextPerson!.displayName;
            person2Gender = _contextPerson!.gender;
          } else if (widget.relatedTo != null) {
            person2Id = widget.relatedTo!.id;
            person2Name = widget.relatedTo!.displayName;
            person2Gender = widget.relatedTo!.gender;
          } else {
            person2Id = userId;
            person2Name =
                _authService.currentUserDisplayName?.trim().isNotEmpty == true
                    ? _authService.currentUserDisplayName!.trim()
                    : 'Вы';
            person2Gender = _gender;
          }

          // Если добавляем не к себе и не к текущему пользователю,
          // то создаем связь между новым человеком и тем, к кому добавляли (или с пользователем)
          if (newPersonId != person2Id) {
            try {
              CustomRelationLabels? customLabels;
              if (relationType == RelationType.other) {
                if (!mounted) {
                  return;
                }
                customLabels = await showCustomRelationLabelDialog(
                  context: context,
                  person1Name: _draftDisplayName,
                  person2Name: person2Name,
                  person1Gender: _selectedGender,
                  person2Gender: person2Gender,
                );
                if (!mounted) {
                  return;
                }
                if (customLabels == null) {
                  setState(() {
                    _isLoading = false;
                  });
                  return;
                }
              }

              await _familyService.createRelation(
                treeId: widget.treeId,
                person1Id: newPersonId,
                person2Id: person2Id,
                relation1to2: relationType,
                isConfirmed: true,
                marriageDate:
                    relationType == RelationType.spouse ? _marriageDate : null,
                customRelationLabel1to2: customLabels?.relation1to2,
                customRelationLabel2to1: customLabels?.relation2to1,
              );
              debugPrint(
                'Основная связь создана: $newPersonId ($relationType) -> $person2Id',
              );
            } catch (e) {
              debugPrint('Ошибка создания связи: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _describeActionError(
                        e,
                        fallbackMessage:
                            'Не удалось сохранить связь. Попробуйте ещё раз.',
                      ),
                    ),
                  ),
                );
              }
            }
          } else {
            debugPrint(
              "Попытка создать связь человека с самим собой проигнорирована.",
            );
          }
        }

        if (!mounted) {
          return;
        }

        if (!widget.isEditing &&
            createdPersonId != null &&
            action == _PostSaveAction.stayInQuickAdd &&
            _canUseQuickAddLoop) {
          _prepareForNextQuickAddCycle();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Человек добавлен. Можно сразу заполнить следующую карточку.',
              ),
            ),
          );
          return;
        }

        if (!widget.isEditing &&
            createdPersonId != null &&
            action == _PostSaveAction.openInTree) {
          Navigator.pop(context, <String, dynamic>{
            'updated': true,
            'createdPersonId': createdPersonId,
            'focusPersonId': createdPersonId,
            'keepEditMode': true,
          });
          return;
        }

        Navigator.pop(
          context,
          true,
        ); // Возвращаем true для обновления предыдущего экрана
      } catch (e) {
        debugPrint('Ошибка при сохранении: $e');
        if (mounted) {
          // Проверяем mounted перед показом SnackBar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _describeActionError(
                  e,
                  fallbackMessage:
                      'Не удалось сохранить карточку. Проверьте данные и попробуйте ещё раз.',
                ),
              ),
            ),
          );
        }
      } finally {
        if (mounted) {
          // Проверяем mounted перед setState
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  void _prepareForNextQuickAddCycle() {
    _firstNameController.clear();
    _middleNameController.clear();
    _maidenNameController.clear();
    _birthPlaceController.clear();
    _educationController.clear();
    _bioController.clear();
    _notesController.clear();
    _birthDate = null;
    _deathDate = null;
    _marriageDate = null;
    _selectedGender = null;
    for (final draft in _importantEventDrafts) {
      draft.dispose();
    }
    _importantEventDrafts.clear();
    _draftMedia.clear();
    if (_lastNameController.text.trim().isEmpty) {
      _prefillLastNameFromAnchor(_anchorPerson, _resolvedRelationType);
    }
    final anchorPerson = _anchorPerson;
    if (anchorPerson != null) {
      _prefillGenderBasedOnRelation(anchorPerson, _resolvedRelationType);
    }
    _formKey.currentState?.reset();
    setState(() {});
  }

  void _prefillLastNameFromAnchor(
    FamilyPerson? anchorPerson,
    RelationType? relationType,
  ) {
    if (anchorPerson == null || _lastNameController.text.trim().isNotEmpty) {
      return;
    }
    if (relationType == RelationType.spouse ||
        relationType == RelationType.partner) {
      return;
    }
    final surname = _extractSurname(anchorPerson.name);
    if (surname.isNotEmpty) {
      _lastNameController.text = surname;
    }
  }

  String _extractSurname(String fullName) {
    final parts = fullName
        .split(' ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '';
    }
    return parts.first;
  }

  List<DropdownMenuItem<RelationType>> _getRelationTypeItems(
    Gender? anchorGender,
  ) {
    // Используем статический метод из FamilyRelation для получения и фильтрации связей
    return FamilyRelation.getAvailableRelationTypes(anchorGender)
        .map(
          (type) => DropdownMenuItem(
            value: type,
            // Используем статический метод для получения описания
            // Передаем пол *нового* человека (_selectedGender)
            child: Text(
              FamilyRelation.getRelationDescription(type, _selectedGender),
            ),
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _disposeExtractedControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_buildScreenTitle()),
        actions: [
          if (widget.isEditing)
            IconButton(
              icon: Icon(Icons.person_add),
              tooltip: 'Добавить родственника',
              onPressed: () {
                _showAddRelativeDialog();
              },
            ),
          if (widget.isEditing)
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Удаление родственника'),
                    content: Text(
                      'Вы уверены, что хотите удалить этого родственника?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _deletePerson();
                        },
                        child: Text(
                          'Удалить',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: _isBusy
          ? Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.isEditing) _buildIntroCard(),

                    if (!widget.isEditing) SizedBox(height: 16),

                    if (!widget.isEditing) _buildRequiredNowCard(),

                    SizedBox(height: 24),

                    if (!widget.isEditing && _canUseQuickAddLoop) ...[
                      _buildQuickAddToolbar(),
                      SizedBox(height: 24),
                    ],

                    _buildEditorModeCard(),
                    SizedBox(height: 24),

                    // Фамилия
                    TextFormField(
                      controller: _lastNameController,
                      decoration: InputDecoration(
                        labelText: 'Фамилия',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Пожалуйста, введите фамилию';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16),

                    // Имя
                    TextFormField(
                      controller: _firstNameController,
                      autofocus: !widget.isEditing,
                      decoration: InputDecoration(
                        labelText: 'Имя',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Пожалуйста, введите имя';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16),

                    // Отчество
                    TextFormField(
                      controller: _middleNameController,
                      decoration: InputDecoration(
                        labelText: 'Отчество',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    SizedBox(height: 24),

                    // Пол
                    Text(
                      'Пол',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ChoiceChip(
                          label: const Text('Мужской'),
                          avatar: const Icon(Icons.male, size: 18),
                          selected: _selectedGender == Gender.male,
                          selectedColor: Colors.blue.shade100,
                          onSelected: (_) {
                            setState(() {
                              _selectedGender = Gender.male;
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Женский'),
                          avatar: const Icon(Icons.female, size: 18),
                          selected: _selectedGender == Gender.female,
                          selectedColor: Colors.pink.shade100,
                          onSelected: (_) {
                            setState(() {
                              _selectedGender = Gender.female;
                            });
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 24),

                    // Виджет выбора родственной связи
                    _buildRelationshipSelector(),
                    SizedBox(height: 24),

                    _buildBirthDateField(),
                    SizedBox(height: 24),

                    _buildMediaSection(),
                    SizedBox(height: 24),

                    if (widget.isEditing && widget.person != null) ...[
                      _buildEditMediaAndHistoryCard(),
                      SizedBox(height: 24),
                    ],

                    if (_isAdvancedMode)
                      _buildOptionalDetailsSection()
                    else
                      _buildAdvancedHintCard(),
                    SizedBox(height: 24),

                    _buildSubmitSection(),
                    SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  void _openEditingPersonCard() {
    final person = widget.person;
    if (person == null) {
      return;
    }
    context.push('/relative/details/${person.id}');
  }

  Future<void> _showEditingPersonHistorySheet() async {
    final person = widget.person;
    if (person == null) {
      return;
    }

    final historyFuture = _familyService.getTreeHistory(
      treeId: widget.treeId,
      personId: person.id,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return TreeHistorySheet(
          historyFuture: historyFuture,
          title: 'История изменений',
          subtitle: person.name,
          currentUserId: _authService.currentUserId,
          emptyMessage: 'Для этой карточки пока нет записей в журнале.',
          errorBuilder: (error) => _describeActionError(
            error,
            fallbackMessage: 'Не удалось загрузить историю.',
          ),
          onOpenPerson: (personId) {
            Navigator.of(sheetContext).pop();
            if (!mounted) {
              return;
            }
            context.push('/relative/details/$personId');
          },
        );
      },
    );
  }

  Future<void> _deletePerson() async {
    if (widget.person == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Удаляем человека и все его связи
      await _familyService.deleteRelative(widget.treeId, widget.person!.id);
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Родственник удален')));

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Ошибка при удалении: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _describeActionError(
              e,
              fallbackMessage:
                  'Не удалось удалить карточку. Попробуйте ещё раз.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserGender() async {
    try {
      final currentUserProfile = await _profileService.getCurrentUserProfile();
      final genderStr = currentUserProfile?.gender;
      if (genderStr != null) {
        setState(() {
          _gender = genderStr;
        });
      }
    } catch (e) {
      debugPrint('Ошибка при загрузке пола пользователя: $e');
    }
  }

  Future<void> _loadRelationType() async {
    if (widget.relatedTo == null) return;

    try {
      // Если есть начальный тип отношения, используем его
      if (widget.predefinedRelation != null) {
        setState(() {
          _selectedRelationType = widget.predefinedRelation;

          // Автоматически определяем пол на основе выбранной связи
          if (_selectedRelationType == RelationType.spouse) {
            // Для супруга/супруги определяем противоположный пол
            _selectedGender = widget.relatedTo!.gender == Gender.male
                ? Gender.female
                : Gender.male;
          } else {
            // Для других типов связей не предполагаем конкретный пол
            _selectedGender = null;
          }
        });
      } else if (widget.relatedTo != null) {
        // Если нет начального типа отношения, предлагаем наиболее вероятный
        setState(() {
          // По умолчанию предлагаем "ребенок" для добавления к родственнику
          _selectedRelationType = RelationType.child;

          // Автоматически определяем пол на основе выбранной связи
          // Для ребенка не предполагаем конкретный пол
          _selectedGender = null;
        });
        _prefillLastNameFromAnchor(widget.relatedTo, RelationType.child);
      }
    } catch (e) {
      debugPrint('Ошибка при загрузке типа отношения: $e');
    }
  }

  // Метод для загрузки текущего типа отношения при редактировании
  Future<void> _loadCurrentRelationType() async {
    final userId = _authService.currentUserId;
    if (userId == null || widget.person == null || !widget.isEditing) return;

    try {
      // getRelationToUser уже возвращает, кем редактируемый человек является
      // для текущего пользователя.
      final relationPersonToUser = await _familyService.getRelationToUser(
        widget.treeId,
        widget.person!.id, // ID редактируемого человека
      );

      debugPrint(
        'Загружен текущий тип отношения (от ${widget.person!.id} к $userId): $relationPersonToUser',
      );

      if (mounted) {
        setState(() {
          _selectedRelationType = relationPersonToUser;
          _initialRelationType =
              relationPersonToUser; // Сохраняем для сравнения
        });
      }
    } catch (e) {
      debugPrint('Ошибка при загрузке типа текущего отношения: $e');
      if (mounted) {
        setState(() {
          _selectedRelationType =
              RelationType.other; // Ставим other в случае ошибки
          _initialRelationType = RelationType.other;
        });
      }
    }
  }

  // Метод для показа диалога добавления родственника
  void _showAddRelativeDialog() {
    if (widget.person == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Добавить родственника'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Кого вы хотите добавить для ${widget.person!.name}?'),
            SizedBox(height: 15),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToAddRelative(RelationType.parent);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 40),
              ),
              child: Text('Родителя'),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToAddRelative(RelationType.child);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 40),
              ),
              child: Text('Ребенка'),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToAddRelative(RelationType.spouse);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 40),
              ),
              child: Text('Супруга/Супругу'),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToAddRelative(RelationType.sibling);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 40),
              ),
              child: Text('Брата/Сестру'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'),
          ),
        ],
      ),
    );
  }

  // Метод для перехода на экран добавления родственника
  Future<void> _navigateToAddRelative(RelationType relationType) async {
    final success = await context.push(
      '/relatives/add/${widget.treeId}',
      extra: {
        'contextPersonId': widget.person!.id,
        'relationType': relationType,
        'quickAddMode': true,
      },
    );
    if (!mounted) return;

    if (success == true ||
        (success is Map<String, dynamic> && success['updated'] == true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Родственник успешно добавлен'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // Вспомогательный метод для преобразования Gender в строку
  String _genderToString(Gender gender) {
    switch (gender) {
      case Gender.male:
        return 'male';
      case Gender.female:
        return 'female';
      case Gender.other:
        return 'other';
      case Gender.unknown:
        return 'unknown';
    }
  }

  // Добавляем недостающий метод
  RelationType _getRelationType() {
    return _selectedRelationType ?? RelationType.other;
  }

  String get _draftDisplayName {
    final parts = <String>[
      _lastNameController.text.trim(),
      _firstNameController.text.trim(),
      _middleNameController.text.trim(),
    ].where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return 'Новый родственник';
    }
    return parts.join(' ');
  }

  // Загрузка данных Person из контекста дерева
  Future<void> _loadContextPerson(
    String personId,
    RelationType relationType,
  ) async {
    if (!mounted) return;
    setState(() {
      _isLoadingContext = true;
      _contextRelationType = relationType;
      _selectedRelationType = relationType; // Сразу выбираем отношение
    });
    debugPrint(
        'AddRelativeScreen _loadContextPerson: Loading person $personId');
    try {
      final person = await _familyService.getPersonById(
        widget.treeId,
        personId,
      );
      if (!mounted) return;
      setState(() {
        _contextPerson = person;
        _isLoadingContext = false;
        // Предзаполнение пола на основе relationType и пола _contextPerson
        _prefillGenderBasedOnRelation(_contextPerson!, _contextRelationType);
        _prefillLastNameFromAnchor(_contextPerson, _contextRelationType);
      });
      debugPrint(
        'AddRelativeScreen _loadContextPerson: Loaded person ${_contextPerson?.name}',
      );
    } catch (e) {
      debugPrint('Ошибка при загрузке Person из контекста: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingContext = false;
        // TODO: Показать ошибку пользователю?
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось загрузить данные родственника для контекста.',
          ),
        ),
      );
    }
  }

  // Предзаполнение пола на основе существующего родственника и типа связи
  void _prefillGenderBasedOnRelation(
    FamilyPerson anchorPerson,
    RelationType? relation,
  ) {
    if (relation == null) return;

    Gender? prefilledGender;
    // Логика определения пола нового родственника
    switch (relation) {
      case RelationType.parent:
      case RelationType.child:
      case RelationType.sibling:
      case RelationType.grandparent:
      case RelationType.grandchild:
        // Для этих связей пол не очевиден
        prefilledGender = null;
        break;
      case RelationType.spouse:
      case RelationType.partner: // Добавлено
      case RelationType.ex_spouse: // Добавлено
      case RelationType.ex_partner: // Добавлено
        // Пол противоположный
        prefilledGender =
            (anchorPerson.gender == Gender.male) ? Gender.female : Gender.male;
        break;
      // Для других типов (friend, colleague, other) пол не определяем
      default:
        prefilledGender = null;
    }

    // Устанавливаем только если пол еще не выбран
    if (_selectedGender == null && prefilledGender != null) {
      debugPrint(
        "AddRelativeScreen _prefillGenderBasedOnRelation: Pre-filling gender to $prefilledGender based on relation $relation and anchor person gender ${anchorPerson.gender}",
      );
      _selectedGender = prefilledGender;
    }
  }
}

class _RequiredChip extends StatelessWidget {
  final String label;

  const _RequiredChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.check_circle_outline, size: 18),
      label: Text(label),
    );
  }
}

class _QuickInfoChip extends StatelessWidget {
  const _QuickInfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}
