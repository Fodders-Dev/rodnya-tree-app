part of 'profile_edit_screen.dart';

extension _ProfileEditScreenSections on _ProfileEditScreenState {
  Widget _buildAvatarCard() {
    final theme = Theme.of(context);
    return GlassPanel(
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundImage: _profileImageUrl != null
                      ? NetworkImage(_profileImageUrl!)
                      : null,
                  child: _profileImageUrl == null
                      ? const Icon(Icons.person, size: 42)
                      : null,
                ),
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.camera_alt_outlined,
                    color: theme.colorScheme.onPrimary,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Фото профиля',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Обновите аватар и основные данные.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Фото'),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentitySection() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('Основное'),
          const SizedBox(height: 14),
          TextFormField(
            controller: _firstNameController,
            decoration: _inputDecoration('Имя'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Введите имя';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _lastNameController,
            decoration: _inputDecoration('Фамилия'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Введите фамилию';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _middleNameController,
            decoration: _inputDecoration('Отчество'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _usernameController,
            decoration: _inputDecoration('Username'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailController,
            readOnly: true,
            decoration: _inputDecoration(
              'Email',
              suffixIcon: const Icon(Icons.lock_outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalSection(DateFormat dateFormat) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('Основное'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ChoiceChip(
                label: const Text('Мужской'),
                avatar: const Icon(Icons.male, size: 18),
                selected: _gender == Gender.male,
                onSelected: (_) {
                  _updateSectionState(() {
                    _gender = Gender.male;
                  });
                },
              ),
              ChoiceChip(
                label: const Text('Женский'),
                avatar: const Icon(Icons.female, size: 18),
                selected: _gender == Gender.female,
                onSelected: (_) {
                  _updateSectionState(() {
                    _gender = Gender.female;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildActionTile(
            icon: Icons.calendar_today_outlined,
            title: 'Дата рождения',
            subtitle: _birthDate != null
                ? dateFormat.format(_birthDate!)
                : 'Не указана',
            onTap: _pickDate,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _birthPlaceController,
            decoration: _inputDecoration(
              'Место рождения',
              hintText: 'Город, село или регион рождения.',
            ),
          ),
          if (_gender == Gender.female) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _maidenNameController,
              decoration: _inputDecoration('Девичья фамилия'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('О человеке'),
          const SizedBox(height: 8),
          Text(
            'Эти данные будут видны родственникам по вашим настройкам.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          _buildVisibilityScopeSelector(
            sectionKey: 'about',
            title: 'Кто видит блок',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _bioController,
            minLines: 3,
            maxLines: 5,
            decoration: _inputDecoration(
              'Коротко о себе',
              hintText: 'Чем живёте, что хотите рассказать близким.',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _familyStatusController,
            decoration: _inputDecoration(
              'Семейное положение',
              hintText: 'Например: женат, замужем, в отношениях.',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _aboutFamilyController,
            minLines: 2,
            maxLines: 4,
            decoration: _inputDecoration(
              'Что хотите рассказать семье',
              hintText:
                  'Например: о вашей семье, доме, близких традициях и том, что важно передать родственникам.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundSection() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('Учёба и дело'),
          const SizedBox(height: 8),
          Text(
            'Школа, вуз, работа, дело, проекты и опыт.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          _buildVisibilityScopeSelector(
            sectionKey: 'background',
            title: 'Кто видит блок',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _educationController,
            minLines: 2,
            maxLines: 4,
            decoration: _inputDecoration(
              'Учёба',
              hintText: 'Школа, вуз, курсы, важные этапы.',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _workController,
            minLines: 2,
            maxLines: 4,
            decoration: _inputDecoration(
              'Работа и дело',
              hintText: 'Чем занимаетесь сейчас или занимались раньше.',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _hometownController,
            decoration: _inputDecoration(
              'Родной город',
              hintText: 'Где ваши корни или какой город считаете родным.',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _languagesController,
            decoration: _inputDecoration(
              'Языки',
              hintText: 'Например: русский, татарский, английский.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorldviewSection() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('Ценности и взгляды'),
          const SizedBox(height: 8),
          Text(
            'То, что помогает родственникам лучше понимать вас.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          _buildVisibilityScopeSelector(
            sectionKey: 'worldview',
            title: 'Кто видит блок',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _valuesController,
            minLines: 2,
            maxLines: 4,
            decoration: _inputDecoration(
              'Ценности',
              hintText: 'Что для вас важно в семье и в жизни.',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _religionController,
            decoration: _inputDecoration(
              'Религия или мировоззрение',
              hintText: 'Можно оставить пустым.',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _interestsController,
            minLines: 2,
            maxLines: 4,
            decoration: _inputDecoration(
              'Интересы и увлечения',
              hintText:
                  'Чем любите заниматься, что собирает семью или радует вас.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsSection() {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle('Контакты и приватность'),
          const SizedBox(height: 8),
          Text(
            'Контакты, видимость профиля и помощь семьи с биографией.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          _buildVisibilityScopeSelector(
            sectionKey: 'contacts',
            title: 'Кто видит контакты',
          ),
          const SizedBox(height: 16),
          Text(
            'Правки от семьи',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Если включено, родственники смогут предложить дополнения к вашему профилю, а вы подтвердите их сами.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ChoiceChip(
                label: const Text('Разрешить предложения'),
                selected: _profileContributionPolicy == 'suggestions',
                onSelected: (_) {
                  _updateSectionState(() {
                    _profileContributionPolicy = 'suggestions';
                  });
                },
              ),
              ChoiceChip(
                label: const Text('Не принимать'),
                selected: _profileContributionPolicy == 'disabled',
                onSelected: (_) {
                  _updateSectionState(() {
                    _profileContributionPolicy = 'disabled';
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildActionTile(
            icon: Icons.public_outlined,
            title: 'Страна',
            subtitle: _countryName ?? 'Не указана',
            onTap: _selectCountry,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cityController,
            decoration: _inputDecoration('Город'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: _inputDecoration(
              'Телефон',
              hintText: 'Необязательно. Для связи, а не для подтверждения.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Телефон больше не считается подтверждённым каналом. Для доверия и входа используйте VK, Telegram, Google или MAX, а здесь оставьте номер только если семье удобно связываться с вами напрямую.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilityScopeSelector({
    required String sectionKey,
    required String title,
  }) {
    final currentScope = _profileVisibilityScopes[sectionKey] ?? 'shared_trees';
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildVisibilityChip(
                  sectionKey: sectionKey,
                  scope: 'public',
                  label: 'Все в Родне',
                ),
                _buildVisibilityChip(
                  sectionKey: sectionKey,
                  scope: 'shared_trees',
                  label: 'Мои деревья',
                ),
                _buildVisibilityChip(
                  sectionKey: sectionKey,
                  scope: 'private',
                  label: 'Только я',
                ),
                _buildVisibilityChip(
                  sectionKey: sectionKey,
                  scope: 'specific_trees',
                  label: 'Выбранные деревья',
                ),
                _buildVisibilityChip(
                  sectionKey: sectionKey,
                  scope: 'specific_branches',
                  label: 'Выбранные ветки',
                ),
                _buildVisibilityChip(
                  sectionKey: sectionKey,
                  scope: 'specific_users',
                  label: 'Конкретные люди',
                ),
              ],
            ),
            if (currentScope == 'specific_trees') ...[
              const SizedBox(height: 12),
              _buildSpecificTreeSelector(sectionKey),
            ],
            if (currentScope == 'specific_branches') ...[
              const SizedBox(height: 12),
              _buildSpecificBranchSelector(sectionKey),
            ],
            if (currentScope == 'specific_users') ...[
              const SizedBox(height: 12),
              _buildSpecificUserSelector(sectionKey),
            ],
            const SizedBox(height: 8),
            Text(
              _visibilityScopeDescription(currentScope),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisibilityChip({
    required String sectionKey,
    required String scope,
    required String label,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected:
          (_profileVisibilityScopes[sectionKey] ?? 'shared_trees') == scope,
      onSelected: (_) {
        _updateSectionState(() {
          _profileVisibilityScopes = {
            ..._profileVisibilityScopes,
            sectionKey: scope,
          };
        });
      },
    );
  }

  Widget _buildSpecificTreeSelector(String sectionKey) {
    final selectedIds =
        _profileVisibilityTreeIds[sectionKey] ?? const <String>[];
    final selectedTrees = _availableVisibilityTrees
        .where((tree) => selectedIds.contains(tree.id))
        .toList();

    return _buildVisibilityTargetSelector(
      title: 'Доступ по выбранным деревьям',
      buttonLabel: 'Выбрать деревья',
      emptyState: _availableVisibilityTrees.isEmpty
          ? 'Сначала нужно состоять хотя бы в одном дереве.'
          : 'Выберите деревья, участники которых увидят этот блок.',
      onPressed: () => _pickVisibilityTrees(sectionKey),
      selectedLabels: [
        for (final tree in selectedTrees) tree.name,
        for (final treeId in selectedIds)
          if (!selectedTrees.any((tree) => tree.id == treeId)) 'Дерево $treeId',
      ],
      onRemove: (label) {
        String treeId = '';
        for (final tree in selectedTrees) {
          if (tree.name == label) {
            treeId = tree.id;
            break;
          }
        }
        if (treeId.isEmpty) {
          treeId = selectedIds.firstWhere(
            (value) => 'Дерево $value' == label,
            orElse: () => '',
          );
        }
        if (treeId.isEmpty) {
          return;
        }
        _updateSectionState(() {
          _profileVisibilityTreeIds = {
            ..._profileVisibilityTreeIds,
            sectionKey: selectedIds.where((id) => id != treeId).toList(),
          };
        });
      },
    );
  }

  Widget _buildSpecificUserSelector(String sectionKey) {
    final selectedIds =
        _profileVisibilityUserIds[sectionKey] ?? const <String>[];
    final selectedUsers = _availableVisibilityUsers
        .where((user) => selectedIds.contains(user.userId))
        .toList();

    return _buildVisibilityTargetSelector(
      title: 'Доступ по конкретным людям',
      buttonLabel: 'Выбрать людей',
      emptyState: _availableVisibilityUsers.isEmpty
          ? 'Пока нет родственников с аккаунтом, которых можно выбрать.'
          : 'Выберите конкретных пользователей Родни, которым откроется этот блок.',
      onPressed: () => _pickVisibilityUsers(sectionKey),
      selectedLabels: [
        for (final user in selectedUsers) user.displayName,
        for (final userId in selectedIds)
          if (!selectedUsers.any((user) => user.userId == userId))
            'Пользователь $userId',
      ],
      onRemove: (label) {
        String userId = '';
        for (final user in selectedUsers) {
          if (user.displayName == label) {
            userId = user.userId;
            break;
          }
        }
        if (userId.isEmpty) {
          userId = selectedIds.firstWhere(
            (value) => 'Пользователь $value' == label,
            orElse: () => '',
          );
        }
        if (userId.isEmpty) {
          return;
        }
        _updateSectionState(() {
          _profileVisibilityUserIds = {
            ..._profileVisibilityUserIds,
            sectionKey: selectedIds.where((id) => id != userId).toList(),
          };
        });
      },
    );
  }

  Widget _buildSpecificBranchSelector(String sectionKey) {
    final selectedIds =
        _profileVisibilityBranchRootIds[sectionKey] ?? const <String>[];
    final selectedBranches = _availableVisibilityBranches
        .where((branch) => selectedIds.contains(branch.personId))
        .toList();

    return _buildVisibilityTargetSelector(
      title: 'Доступ по выбранным веткам',
      buttonLabel: 'Выбрать ветки',
      emptyState: _availableVisibilityBranches.isEmpty
          ? 'Сначала нужно, чтобы в ваших деревьях были ветки с родственниками.'
          : 'Выберите ветки, внутри которых люди увидят этот блок.',
      onPressed: () => _pickVisibilityBranches(sectionKey),
      selectedLabels: [
        for (final branch in selectedBranches)
          '${branch.displayName} · ${branch.treeName}',
        for (final branchId in selectedIds)
          if (!selectedBranches.any((branch) => branch.personId == branchId))
            'Ветка $branchId',
      ],
      onRemove: (label) {
        String branchId = '';
        for (final branch in selectedBranches) {
          if ('${branch.displayName} · ${branch.treeName}' == label) {
            branchId = branch.personId;
            break;
          }
        }
        if (branchId.isEmpty) {
          branchId = selectedIds.firstWhere(
            (value) => 'Ветка $value' == label,
            orElse: () => '',
          );
        }
        if (branchId.isEmpty) {
          return;
        }
        _updateSectionState(() {
          _profileVisibilityBranchRootIds = {
            ..._profileVisibilityBranchRootIds,
            sectionKey: selectedIds.where((id) => id != branchId).toList(),
          };
        });
      },
    );
  }

  Widget _buildVisibilityTargetSelector({
    required String title,
    required String buttonLabel,
    required String emptyState,
    required VoidCallback onPressed,
    required List<String> selectedLabels,
    required ValueChanged<String> onRemove,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: const Icon(Icons.tune),
          label: Text(buttonLabel),
        ),
        const SizedBox(height: 10),
        if (selectedLabels.isEmpty)
          Text(
            emptyState,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final label in selectedLabels)
                InputChip(
                  label: Text(label),
                  onDeleted: () => onRemove(label),
                ),
            ],
          ),
      ],
    );
  }
}
