part of 'add_relative_screen.dart';

extension _AddRelativeScreenSections on _AddRelativeScreenState {
  Widget _buildEditMediaAndHistoryCard() {
    final theme = Theme.of(context);
    final person = widget.person!;
    final mediaCount = person.photoGallery.length;
    final hasPrimaryPhoto = person.primaryPhotoUrl != null;
    final photoActionLabel = mediaCount == 0 ? 'Медиа' : 'Медиа ($mediaCount)';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.perm_media_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Медиа и история',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickInfoChip(
                icon: Icons.photo_library_outlined,
                label: mediaCount == 0 ? 'Без медиа' : '$mediaCount в карточке',
              ),
              _QuickInfoChip(
                icon: hasPrimaryPhoto
                    ? Icons.star_outline
                    : Icons.image_not_supported_outlined,
                label: hasPrimaryPhoto
                    ? 'Основное фото есть'
                    : 'Основное фото не выбрано',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _draftMedia.isEmpty
                ? 'Основные факты редактируются здесь, а карточка и журнал открываются отдельными действиями.'
                : 'После сохранения в карточку уйдут и новые поля, и добавленные фото/видео.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Открыть карточку'),
                onPressed: _openEditingPersonCard,
              ),
              ActionChip(
                avatar: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(photoActionLabel),
                onPressed: _openEditingPersonCard,
              ),
              ActionChip(
                avatar: const Icon(Icons.history_outlined, size: 18),
                label: const Text('История'),
                onPressed: () => _showEditingPersonHistorySheet(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _buildScreenTitle() {
    if (widget.isEditing) {
      return 'Редактирование родственника';
    }
    if (_isCreatingFirstPerson) {
      return 'Первый человек в дереве';
    }
    if (widget.relatedTo != null) {
      return 'Добавление родственника к ${widget.relatedTo!.name}';
    }
    return 'Добавление родственника';
  }

  Widget _buildIntroCard() {
    final theme = Theme.of(context);
    final bool isContextAdd = _isContextualAdd;

    final String title = _isCreatingFirstPerson
        ? 'Начните дерево с одного человека'
        : _canUseQuickAddLoop
            ? 'Быстрое добавление в ветку'
            : isContextAdd
                ? 'Вы добавляете родственника к ${_anchorPerson!.name}'
                : 'Вы добавляете нового родственника в своё дерево';

    final String description = _isCreatingFirstPerson
        ? 'Сначала достаточно имени и пола. Родственную связь можно указать позже, когда в дереве появится опорный человек.'
        : _canUseQuickAddLoop
            ? 'Форма упрощена под серию добавлений. После сохранения можно сразу заполнить следующую карточку или вернуться на дерево к новому человеку.'
            : isContextAdd
                ? 'Заполните данные и проверьте связь. После сохранения человек сразу появится в схеме.'
                : 'Заполните карточку и укажите, кем этот человек является для вас.';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isCreatingFirstPerson
                      ? Icons.account_tree
                      : Icons.info_outline,
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequiredNowCard() {
    final theme = Theme.of(context);
    final relationType = _resolvedRelationType;
    final anchorPerson = _anchorPerson;
    final helperItems = [
      if (_isCreatingFirstPerson) 'Достаточно заполнить имя, фамилию и пол',
      if (anchorPerson != null && relationType != null)
        'Связь с ${anchorPerson.name} уже выбрана: ${_relationTypeToActionObject(relationType)}',
      if (_canUseQuickAddLoop)
        'После добавления можно сразу создать ещё одного родственника в этой же ветке',
      if (anchorPerson == null && !_isCreatingFirstPerson)
        'Связь можно указать после заполнения основной информации',
      _canUseQuickAddLoop
          ? 'Когда нужно вернуться к схеме, используйте кнопку "Добавить и открыть на дереве"'
          : 'После сохранения вы вернётесь обратно в дерево',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Что нужно сейчас',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _RequiredChip(label: 'Фамилия'),
              _RequiredChip(label: 'Имя'),
              _RequiredChip(label: 'Пол'),
            ],
          ),
          const SizedBox(height: 12),
          ...helperItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.arrow_right_alt,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorModeCard() {
    final theme = Theme.of(context);
    final isEditing = widget.isEditing;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEditing ? 'Режим редактирования' : 'Режим заполнения',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                label: const Text('Основное'),
                avatar: const Icon(Icons.bolt_outlined, size: 18),
                selected: _editorMode == _RelativeEditorMode.basic,
                onSelected: (_) {
                  _updateSectionState(() {
                    _editorMode = _RelativeEditorMode.basic;
                  });
                },
              ),
              ChoiceChip(
                label: const Text('Расширенно'),
                avatar: const Icon(Icons.library_books_outlined, size: 18),
                selected: _editorMode == _RelativeEditorMode.advanced,
                onSelected: (_) {
                  _updateSectionState(() {
                    _editorMode = _RelativeEditorMode.advanced;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBirthDateField() {
    return InkWell(
      onTap: () => _pickDate(true),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Дата рождения',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.cake_outlined),
          helperText: 'Нужна для дней рождения на главной',
        ),
        child: Text(
          _birthDate != null
              ? DateFormat('dd.MM.yyyy').format(_birthDate!)
              : 'Выберите дату',
        ),
      ),
    );
  }

  Widget _buildMediaSection() {
    final theme = Theme.of(context);
    final existingCount = _existingMediaEntries.length;
    final queuedCount = _draftMedia.length;
    final hasExistingPrimary = _existingMediaEntries.any(
      (entry) => entry['isPrimary'] == true,
    );
    final summary = <String>[
      if (existingCount > 0) '$existingCount в карточке',
      if (queuedCount > 0) '$queuedCount в очереди',
      if (existingCount == 0 && queuedCount == 0) 'пока пусто',
    ].join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.perm_media_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Фото и видео',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_isUpdatingMedia)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickInfoChip(
                icon: Icons.photo_library_outlined,
                label: summary,
              ),
              _QuickInfoChip(
                icon: hasExistingPrimary ||
                        _draftMedia.any((entry) => entry.isPrimary)
                    ? Icons.star_outline
                    : Icons.image_not_supported_outlined,
                label: hasExistingPrimary ||
                        _draftMedia.any((entry) => entry.isPrimary)
                    ? 'Основное медиа выбрано'
                    : 'Основное медиа ещё не выбрано',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _isUpdatingMedia
                    ? null
                    : () => _pickRelativeMedia(video: false),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Фото'),
              ),
              FilledButton.tonalIcon(
                onPressed: _isUpdatingMedia
                    ? null
                    : () => _pickRelativeMedia(video: true),
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('Видео'),
              ),
              if (widget.isEditing && widget.person != null)
                ActionChip(
                  avatar: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Открыть карточку'),
                  onPressed: _openEditingPersonCard,
                ),
            ],
          ),
          if (_draftMedia.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _draftMedia
                  .map(
                    (entry) => InputChip(
                      avatar: Icon(entry.icon, size: 18),
                      label: Text(
                        '${entry.label}: ${entry.file.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      onDeleted: () => _removeDraftMedia(entry.id),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdvancedHintCard() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.library_add_check_outlined,
              color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'В расширенном режиме можно заполнить биографию, события, дополнительные даты и заметки.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: () {
              _updateSectionState(() {
                _editorMode = _RelativeEditorMode.advanced;
              });
            },
            child: const Text('Показать'),
          ),
        ],
      ),
    );
  }

  Widget _buildImportantEventsSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Важные события',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _addImportantEventDraft,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Событие'),
            ),
          ],
        ),
        if (_importantEventDrafts.isEmpty)
          Text(
            'Сюда можно добавить семейные даты, которые должны появляться на главной.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          )
        else
          Column(
            children: _importantEventDrafts.map((draft) {
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: draft.titleController,
                        decoration: InputDecoration(
                          labelText: 'Название события',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.event_note_outlined),
                          suffixIcon: IconButton(
                            tooltip: 'Удалить событие',
                            onPressed: () => _removeImportantEventDraft(draft),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () => _pickImportantEventDate(draft),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Дата события',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                          child: Text(
                            draft.date != null
                                ? DateFormat('dd.MM.yyyy').format(draft.date!)
                                : 'Выберите дату',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildOptionalDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Расширенные сведения',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 8),
        Text(
          'Дополнительные даты, биография и семейные события.',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        if (_selectedGender == Gender.female) ...[
          TextFormField(
            controller: _maidenNameController,
            decoration: const InputDecoration(
              labelText: 'Девичья фамилия',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
        ],
        InkWell(
          onTap: () => _pickDate(false),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Дата смерти',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.event_outlined),
              helperText: 'Оставьте пустым, если человек жив',
            ),
            child: Text(
              _deathDate != null
                  ? DateFormat('dd.MM.yyyy').format(_deathDate!)
                  : 'Не указано',
            ),
          ),
        ),
        if (_resolvedRelationType == RelationType.spouse) ...[
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickMarriageDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Дата свадьбы',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.favorite_outline),
                helperText: 'Попадёт в семейный календарь',
              ),
              child: Text(
                _marriageDate != null
                    ? DateFormat('dd.MM.yyyy').format(_marriageDate!)
                    : 'Не указано',
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextFormField(
          controller: _birthPlaceController,
          decoration: const InputDecoration(
            labelText: 'Место рождения',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _educationController,
          decoration: const InputDecoration(
            labelText: 'Образование',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.school_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _bioController,
          decoration: const InputDecoration(
            labelText: 'Семейная справка',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          maxLines: 4,
        ),
        const SizedBox(height: 20),
        _buildImportantEventsSection(),
      ],
    );
  }

  void _disposeExtractedControllers() {
    _lastNameController.removeListener(_updateRelationshipWidget);
    _firstNameController.removeListener(_updateRelationshipWidget);
    _lastNameController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _maidenNameController.dispose();
    _birthPlaceController.dispose();
    _educationController.dispose();
    _bioController.dispose();
    _notesController.dispose();
    for (final draft in _importantEventDrafts) {
      draft.dispose();
    }
  }

  Widget _buildRelationshipSelector() {
    // Используем _contextPerson если он есть, иначе widget.relatedTo
    final FamilyPerson? anchorPerson = _anchorPerson;
    final bool addingFromContext = _contextPerson != null;
    final bool isEditingMode = widget.isEditing;
    final bool isAddingToSelf = anchorPerson == null && !isEditingMode;
    final RelationType? fixedRelationType =
        _contextRelationType ?? widget.predefinedRelation;
    final bool hasFixedRelation =
        anchorPerson != null && fixedRelationType != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Родственная связь',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        SizedBox(height: 16),

        // ---- Виджет связи с КОНКРЕТНЫМ человеком (контекстным или relatedTo) ----
        if (anchorPerson != null)
          hasFixedRelation
              ? _buildFixedRelationshipCard(
                  anchorPerson: anchorPerson,
                  relationType: fixedRelationType,
                  addingFromContext: addingFromContext,
                )
              : _buildEditableRelationshipCard(anchorPerson: anchorPerson),

        SizedBox(height: 24),

        // ---- Виджет связи с ТЕКУЩИМ ПОЛЬЗОВАТЕЛЕМ (если нет anchorPerson ИЛИ режим редактирования) ----
        if (anchorPerson == null || isEditingMode)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isCreatingFirstPerson
                    ? 'Связь с вами'
                    : isAddingToSelf
                        ? 'Кем этот человек является для вас?'
                        : 'Кем этот человек является для вас?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              DropdownButtonFormField<RelationType>(
                initialValue: _selectedRelationType,
                decoration: InputDecoration(
                  labelText: _isCreatingFirstPerson
                      ? 'Связь с вами, если хотите указать сразу'
                      : 'Родственная связь с вами',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.family_restroom),
                  helperText: _isCreatingFirstPerson
                      ? 'Поле необязательное. Связать себя с деревом можно позже прямо из схемы.'
                      : null,
                ),
                // Передаем пол ТЕКУЩЕГО пользователя для фильтрации
                items: _getRelationTypeItems(_gender), // Используем _gender
                onChanged: (newValue) {
                  _updateSectionState(() {
                    _selectedRelationType = newValue;
                    // Предзаполняем пол нового на основе связи с пользователем
                    // Создаем временный объект FamilyPerson для текущего пользователя
                    final currentUserAsPerson = FamilyPerson(
                      id: _authService.currentUserId ?? '',
                      treeId: widget.treeId,
                      name: 'Вы', // Имя не так важно здесь
                      gender: _gender,
                      isAlive: true, // Предполагаем
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    );
                    _prefillGenderBasedOnRelation(
                      currentUserAsPerson,
                      newValue,
                    );
                  });
                },
                validator: (value) {
                  // Валидация нужна только если добавляем к себе
                  if (isAddingToSelf &&
                      !_isCreatingFirstPerson &&
                      value == null) {
                    return 'Пожалуйста, выберите родственную связь';
                  }
                  return null;
                },
              ),
              SizedBox(height: 24), // Добавим отступ
            ],
          ),
      ],
    );
  }

  // Обновляем _getRelationTypeDescription для использования FamilyRelation
  String _getRelationTypeDescription(RelationType type) {
    // Используем пол НОВОГО человека (_selectedGender)
    return FamilyRelation.getRelationDescription(type, _selectedGender);
  }

  Widget _buildFixedRelationshipCard({
    required FamilyPerson anchorPerson,
    required RelationType relationType,
    required bool addingFromContext,
  }) {
    final theme = Theme.of(context);
    final relationText = _getRelationTypeDescription(relationType);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.family_restroom, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Связь уже определена',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  relationText,
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: anchorPerson.gender == Gender.male
                    ? Colors.blue.shade100
                    : Colors.pink.shade100,
                child: Icon(
                  Icons.person,
                  color: anchorPerson.gender == Gender.male
                      ? Colors.blue
                      : Colors.pink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anchorPerson.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      addingFromContext
                          ? 'Новый человек будет добавлен относительно этой карточки'
                          : 'Связь для нового человека уже выбрана',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            addingFromContext
                ? 'После сохранения схема обновится автоматически.'
                : 'Если нужно другое родство, вернитесь и выберите другое действие из дерева.',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAddToolbar() {
    if (!_canUseQuickAddLoop) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final anchorPerson = _anchorPerson;
    final relationType = _resolvedRelationType;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.secondary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, color: theme.colorScheme.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Режим быстрого ввода',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (anchorPerson != null)
                _QuickInfoChip(
                  icon: Icons.person_pin_circle_outlined,
                  label: anchorPerson.name,
                ),
              if (relationType != null)
                _QuickInfoChip(
                  icon: Icons.family_restroom,
                  label: _relationTypeToActionObject(relationType),
                ),
              const _QuickInfoChip(
                icon: Icons.restart_alt,
                label: 'Серия добавлений',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Подходит для сценария, когда вы по очереди вносите детей, братьев, родителей или всю ветку одной семьи.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitSection() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isBusy ? null : () => _savePerson(),
            child: Text(
              _buildPrimaryActionLabel(),
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        if (_canUseQuickAddLoop) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _isBusy
                    ? null
                    : () => _savePerson(action: _PostSaveAction.stayInQuickAdd),
                icon: const Icon(Icons.playlist_add),
                label: const Text('Добавить ещё одного'),
              ),
              OutlinedButton.icon(
                onPressed: _isBusy
                    ? null
                    : () => _savePerson(action: _PostSaveAction.openInTree),
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Добавить и открыть на дереве'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text(
          _buildPrimaryActionHint(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildEditableRelationshipCard({
    required FamilyPerson anchorPerson,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: anchorPerson.gender == Gender.male
                    ? Colors.blue.shade100
                    : Colors.pink.shade100,
                child: Icon(
                  Icons.person,
                  color: anchorPerson.gender == Gender.male
                      ? Colors.blue
                      : Colors.pink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Связь с ${anchorPerson.name}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Выберите, кем будет новый человек для этой карточки.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<RelationType>(
            initialValue: _selectedRelationType,
            decoration: const InputDecoration(
              labelText: 'Связь с этим человеком',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.family_restroom),
            ),
            items: _getRelationTypeItems(_selectedGender),
            onChanged: (newValue) {
              _updateSectionState(() {
                _selectedRelationType = newValue;
                _prefillGenderBasedOnRelation(anchorPerson, newValue);
              });
            },
          ),
        ],
      ),
    );
  }

  String _buildPrimaryActionLabel() {
    if (widget.isEditing) {
      return 'Сохранить изменения';
    }
    if (_isCreatingFirstPerson) {
      return 'Добавить первого человека';
    }

    final relationType = _contextRelationType ??
        widget.predefinedRelation ??
        _selectedRelationType;
    if (relationType != null) {
      return 'Добавить ${_relationTypeToActionObject(relationType)}';
    }
    return 'Добавить родственника';
  }

  String _buildPrimaryActionHint() {
    if (widget.isEditing) {
      return 'После сохранения карточка обновится, и вы вернётесь назад.';
    }
    if (_isCreatingFirstPerson) {
      return 'Этого достаточно, чтобы начать дерево. Остальные данные можно заполнить позже.';
    }
    if (_contextPerson != null || widget.relatedTo != null) {
      return 'Связь будет создана автоматически, и новый человек сразу появится в схеме.';
    }
    return 'После сохранения человек появится в дереве, а связь сохранится в профиле.';
  }

  String _relationTypeToActionObject(RelationType type) {
    switch (type) {
      case RelationType.parent:
        return 'родителя';
      case RelationType.child:
        return 'ребёнка';
      case RelationType.spouse:
      case RelationType.partner:
        return 'супруга или партнёра';
      case RelationType.sibling:
        return 'брата или сестру';
      default:
        return FamilyRelation.getGenericRelationTypeStringRu(type)
            .toLowerCase();
    }
  }
}
