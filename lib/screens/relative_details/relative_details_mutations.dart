part of '../relative_details_screen.dart';

extension _RelativeDetailsMutations on _RelativeDetailsScreenState {
  Future<void> _showQuickAddRelativeSheet() async {
    if (_person == null || _currentTreeId == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Добавить к карточке',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Новый человек будет сразу привязан к ${_person!.displayName}.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 12),
                _buildQuickAddOption(
                  sheetContext: sheetContext,
                  icon: Icons.arrow_upward,
                  label: 'Добавить родителя',
                  relationType: RelationType.parent,
                ),
                _buildQuickAddOption(
                  sheetContext: sheetContext,
                  icon: Icons.favorite_border,
                  label: 'Добавить супруга или партнёра',
                  relationType: RelationType.spouse,
                ),
                _buildQuickAddOption(
                  sheetContext: sheetContext,
                  icon: Icons.arrow_downward,
                  label: 'Добавить ребёнка',
                  relationType: RelationType.child,
                ),
                _buildQuickAddOption(
                  sheetContext: sheetContext,
                  icon: Icons.people_outline,
                  label: 'Добавить брата или сестру',
                  relationType: RelationType.sibling,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickAddOption({
    required BuildContext sheetContext,
    required IconData icon,
    required String label,
    required RelationType relationType,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.of(sheetContext).pop();
        _openContextualAddRelative(relationType);
      },
    );
  }

  void _openContextualAddRelative(RelationType relationType) {
    if (_person == null || _currentTreeId == null) {
      return;
    }
    context.push(
      '/relatives/add/$_currentTreeId',
      extra: {
        'contextPersonId': _person!.id,
        'relationType': relationType,
        'quickAddMode': true,
      },
    );
  }

  /// Phase 3.4 chunk 5: открывает reusable conflict-resolution
  /// sheet для текущего person'а. После choice'а — refetch
  /// conflicts (and full data on overwrite, чтобы поля обновились).
  Future<void> _showPersonConflictsSheet() async {
    final treeId = _currentTreeId;
    final service = _familyService;
    if (treeId == null ||
        _person == null ||
        service is! IdentityConflictsCapableFamilyTreeService ||
        _personConflicts.isEmpty) {
      return;
    }
    final capable = service as IdentityConflictsCapableFamilyTreeService;
    await showIdentityConflictsSheet(
      context: context,
      conflicts: _personConflicts,
      onChoice: (sheetContext, conflict, choice) async {
        try {
          await capable.resolveIdentityConflict(
            treeId: treeId,
            conflictId: conflict.id,
            choice: choice,
          );
        } catch (error) {
          if (sheetContext.mounted) {
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(
                  content: Text(humanizeError(error,
                      fallback: 'Не удалось применить выбор.'))),
            );
          }
          return;
        }
        if (sheetContext.mounted) {
          Navigator.of(sheetContext).pop();
        }
        // overwrite → данные person'а изменились, full reload.
        // keep → достаточно re-fetch'а conflicts.
        if (choice == 'overwrite') {
          await _loadData();
        } else if (mounted) {
          try {
            final fresh = await capable.getIdentityConflictsForTree(
              treeId: treeId,
            );
            if (!mounted) return;
            _updateRelativeDetailsState(() {
              _personConflicts = fresh
                  .where(
                      (c) => c.targetPersonId == _person!.id && !c.isResolved)
                  .toList(growable: false);
            });
          } catch (_) {
            // best-effort: refetch failed — sheet всё равно закрыт,
            // badge обновится на следующем _loadData.
          }
        }
      },
    );
  }

  Future<void> _requestIdentityClaim() async {
    final service = _identityService;
    if (service == null || _currentTreeId == null || _person == null) {
      return;
    }

    _updateRelativeDetailsState(() {
      _isUpdatingIdentity = true;
    });
    try {
      final claim = await service.createIdentityClaim(
        treeId: _currentTreeId!,
        personId: _person!.id,
      );
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar(
        claim.isApproved
            ? 'Карточка привязана к вашему аккаунту.'
            : 'Запрос отправлен ответственным за карточку.',
      );
      await _loadData();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar(
        _describeRelativeActionError(
          error,
          fallbackMessage:
              'Не удалось отправить запрос личности. Попробуйте ещё раз.',
        ),
      );
    } finally {
      if (mounted) {
        _updateRelativeDetailsState(() {
          _isUpdatingIdentity = false;
        });
      }
    }
  }

  Future<void> _showPrivacySettings() async {
    final service = _identityService;
    if (service == null || _currentTreeId == null || _person == null) {
      return;
    }

    _updateRelativeDetailsState(() {
      _isUpdatingPrivacy = true;
    });

    try {
      final attributes = await service.getPersonAttributes(
        treeId: _currentTreeId!,
        personId: _person!.id,
      );
      if (!mounted) {
        return;
      }

      final fieldLabels = <String, String>{
        'name': 'Имя и фамилия',
        'photo': 'Фото',
        'birthDate': 'Полная дата рождения',
        'birthYear': 'Год рождения',
        'places': 'Места',
        'contacts': 'Контакты',
        'notes': 'Заметки',
        'relations': 'Связи',
      };
      final visibilityLabels = <String, String>{
        'private': 'Только ответственные',
        'tree': 'Участники дерева',
        'cross-tree': 'Связанные деревья',
        'public': 'Публично',
      };
      var cardVisibility = _person!.visibility;
      final fieldVisibility = <String, String>{
        for (final attribute in attributes)
          attribute.field: attribute.visibility,
      };

      final shouldSave = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Приватность карточки',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'По умолчанию живые люди закрыты. Для кросс-деревьев раскрывайте только то, что действительно можно показывать родственникам из другой ветки.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue:
                              visibilityLabels.containsKey(cardVisibility)
                                  ? cardVisibility
                                  : 'private',
                          decoration: const InputDecoration(
                            labelText: 'Видимость карточки',
                            border: OutlineInputBorder(),
                          ),
                          items: visibilityLabels.entries
                              .map(
                                (entry) => DropdownMenuItem<String>(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setSheetState(() => cardVisibility = value);
                          },
                        ),
                        const SizedBox(height: 16),
                        ...fieldLabels.entries.map((entry) {
                          final value = fieldVisibility[entry.key] ??
                              (entry.key == 'contacts'
                                  ? 'private'
                                  : cardVisibility);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: DropdownButtonFormField<String>(
                              initialValue: visibilityLabels.containsKey(value)
                                  ? value
                                  : 'private',
                              decoration: InputDecoration(
                                labelText: entry.value,
                                border: const OutlineInputBorder(),
                              ),
                              items: visibilityLabels.entries
                                  .map(
                                    (visibilityEntry) =>
                                        DropdownMenuItem<String>(
                                      value: visibilityEntry.key,
                                      child: Text(visibilityEntry.value),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (nextValue) {
                                if (nextValue == null) {
                                  return;
                                }
                                setSheetState(
                                  () => fieldVisibility[entry.key] = nextValue,
                                );
                              },
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(false),
                                child: const Text('Отмена'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(true),
                                child: const Text('Сохранить'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      if (shouldSave != true || !mounted) {
        return;
      }

      await service.updatePersonAttributeVisibility(
        treeId: _currentTreeId!,
        personId: _person!.id,
        visibility: cardVisibility,
        attributes: fieldVisibility,
      );
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar('Приватность карточки обновлена.');
      await _loadData();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar(
        _describeRelativeActionError(
          error,
          fallbackMessage:
              'Не удалось обновить приватность. Попробуйте ещё раз.',
        ),
      );
    } finally {
      if (mounted) {
        _updateRelativeDetailsState(() {
          _isUpdatingPrivacy = false;
        });
      }
    }
  }

  void _editRelative() {
    if (!_canDirectEditProfile() || _currentTreeId == null) return;

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

  Future<void> _suggestProfileChanges() async {
    if (!_canSuggestProfileEdits() ||
        _currentTreeId == null ||
        _person == null) {
      return;
    }

    final summaryController = TextEditingController(
      text: _dossier?.familySummary ?? '',
    );
    final bioController = TextEditingController(text: _dossier?.bio ?? '');
    final workController = TextEditingController(text: _dossier?.work ?? '');
    final messageController = TextEditingController();

    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Предложить правку профиля'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: summaryController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Семейная справка',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bioController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'О человеке',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: workController,
                decoration: const InputDecoration(
                  labelText: 'Работа и дело',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Комментарий для владельца',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );

    if (approved != true) {
      summaryController.dispose();
      bioController.dispose();
      workController.dispose();
      messageController.dispose();
      return;
    }

    try {
      await _familyService.proposePersonProfileContribution(
        treeId: _currentTreeId!,
        personId: _person!.id,
        fields: {
          'bio': bioController.text.trim(),
          'work': workController.text.trim(),
          'aboutFamily': summaryController.text.trim(),
        },
        message: messageController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar('Предложение отправлено владельцу профиля.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar(
        _describeRelativeActionError(
          error,
          fallbackMessage:
              'Не удалось отправить правку. Попробуйте ещё раз чуть позже.',
        ),
      );
    } finally {
      summaryController.dispose();
      bioController.dispose();
      workController.dispose();
      messageController.dispose();
    }
  }

  Future<void> _deleteRelative() async {
    if (!_canDirectEditProfile() || _currentTreeId == null) return;

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
      _updateRelativeDetailsState(() {
        _isLoading = true;
      });
      try {
        // Snapshot ДО удаления — для undo'а через
        // TreeMutationHistory. Связи каскадно стираются на
        // backend'е и undo их НЕ восстановит — только сам person
        // вернётся как новая карточка с новым id (пустыми связями).
        final personSnapshot = _person;
        await _familyService.deleteRelative(_currentTreeId!, widget.personId);
        if (personSnapshot != null &&
            GetIt.I.isRegistered<TreeMutationHistory>()) {
          GetIt.I<TreeMutationHistory>().recordPersonDeleted(
            treeId: _currentTreeId!,
            deleted: personSnapshot,
          );
        }
        if (mounted) {
          _showRelativeSnackBar('Карточка ${_person!.displayName} удалена.');
          _navigateBack();
        }
      } catch (e) {
        debugPrint('Ошибка удаления родственника: $e');
        if (mounted) {
          _showRelativeSnackBar(
            _describeRelativeActionError(
              e,
              fallbackMessage:
                  'Не удалось удалить карточку. Попробуйте ещё раз.',
            ),
          );
          _updateRelativeDetailsState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _unlinkUser() async {
    if (!_canUnlinkUser() || _currentTreeId == null) return;

    final personLabel = _person!.displayName.trim().isEmpty
        ? 'этого человека'
        : _person!.displayName;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отвязать пользователя?'),
        content: Text(
          'Аккаунт, привязанный к карточке «$personLabel», '
          'будет отвязан от дерева. Сама карточка останется на месте — '
          'имя, фото и связи не изменятся, можно будет пригласить '
          'другого человека или этого же заново.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Отвязать',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    _updateRelativeDetailsState(() {
      _isLoading = true;
    });

    try {
      final updated = await _familyService.unlinkUserFromPerson(
        treeId: _currentTreeId!,
        personId: _person!.id,
      );
      if (!mounted) return;
      _updateRelativeDetailsState(() {
        _person = updated;
        _isLoading = false;
      });
      _showRelativeSnackBar(
        'Аккаунт отвязан от карточки «$personLabel». '
        'Теперь можно пригласить нужного человека.',
      );
    } catch (error, stackTrace) {
      debugPrint('Ошибка отвязки пользователя: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      _updateRelativeDetailsState(() {
        _isLoading = false;
      });
      _showRelativeSnackBar(
        _describeRelativeActionError(
          error,
          fallbackMessage:
              'Не удалось отвязать пользователя. Попробуйте ещё раз.',
        ),
      );
    }
  }

  Future<Uri> _createCardInvitationUri({
    required String treeId,
    required String personId,
  }) async {
    final Object service = _familyService;
    if (service is SemyaCapableFamilyTreeService) {
      final semyi = await service.listMySemya();
      final matched = semyi.where((s) => s.treeId == treeId).toList();
      if (matched.isNotEmpty) {
        final invitation = await service.createInvitation(
          semyaId: matched.first.id,
          role: SemyaRole.editor,
          personId: personId,
        );
        return Uri.parse(invitation.shareUrl);
      }
    }
    return _invitationLinkService.buildInvitationLink(
      treeId: treeId,
      personId: personId,
    );
  }

  Future<void> _generateAndShareInviteLink() async {
    if (_person == null || _currentTreeId == null) return;

    _updateRelativeDetailsState(() {
      _isGeneratingLink = true;
    });

    try {
      final inviteUrl = await _createCardInvitationUri(
        treeId: _currentTreeId!,
        personId: _person!.id,
      );

      if (mounted) {
        final isFriendsTree = _isCurrentTreeFriends();
        await showInviteShareSheet(
          context,
          inviteUrl: inviteUrl,
          message: isFriendsTree
              ? 'Присоединяйтесь к нашему кругу друзей в Родне! ${inviteUrl.toString()}'
              : 'Присоединяйтесь к нашему семейному дереву в Родне! ${inviteUrl.toString()}',
          subject: isFriendsTree
              ? 'Приглашение в круг друзей'
              : 'Приглашение в Родню',
        );
      }
    } catch (e) {
      debugPrint('Ошибка при генерации или отправке ссылки: $e');
      if (mounted) {
        _showRelativeSnackBar(
          _describeRelativeActionError(
            e,
            fallbackMessage:
                'Не удалось подготовить приглашение. Попробуйте ещё раз.',
          ),
        );
      }
    } finally {
      if (mounted) {
        _updateRelativeDetailsState(() {
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
        '/chat/${_person!.userId}?name=$nameParam&photo=$photoParam&relativeId=$relativeIdParam',
      );
    } catch (e) {
      debugPrint('Ошибка при переходе в чат: $e');
      if (!mounted) {
        return;
      }
      _showRelativeSnackBar(
        _describeRelativeActionError(
          e,
          fallbackMessage: 'Не удалось открыть чат. Попробуйте ещё раз.',
        ),
      );
    }
  }
}
