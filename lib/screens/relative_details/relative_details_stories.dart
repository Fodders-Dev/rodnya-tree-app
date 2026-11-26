part of '../relative_details_screen.dart';

extension _RelativeDetailsStories on _RelativeDetailsScreenState {
  Future<void> _openBiographyEditor({
    required String name,
    String? relation,
    String? gender,
    FamilyStoryQuestion? initialQuestion,
  }) async {
    final person = _person;
    if (person == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileArticleEditorScreen(
          personId: person.id,
          personName: name,
          personRelation: relation,
          personGender: gender,
          initialStoryTitle: initialQuestion?.title,
          initialStoryQuestion: initialQuestion?.question,
          initialStoryHint: initialQuestion == null
              ? null
              : buildFamilyStoryEditorHint(initialQuestion),
        ),
      ),
    );
    if (mounted) {
      _bumpBiographyRefreshVersion();
    }
  }

  /// MVP-1 «Спросить историю» (STORY-REQUEST-MVP1-BRIEF.md §3.3), extended
  /// MVP-1.1: candidates for the «Кого спросить» step — «сам(а) {герой}»
  /// (when the person being asked about has their own linked account and
  /// it isn't the viewer), then other tree members with an account, then
  /// remaining семья members who have no persona of their own in this
  /// tree (backend already accepts any семья member as addressee, see
  /// `store._isUserInTreeOrSemya` — no backend change needed here). Reuses
  /// `_treePeople`/`_semyaMembers` (already loaded in `_load` above), no
  /// separate fetch on tap. Empty when there's simply nobody to ask yet —
  /// the sheet then behaves exactly as before this feature existed.
  ///
  /// Delegates to the top-level `buildStoryAskTargets` so the merge/dedup
  /// logic is unit-testable without a widget tree (see
  /// test/family_story_ask_targets_test.dart).
  List<FamilyStoryAskTarget> _buildStoryAskTargets({
    required FamilyPerson person,
    required String heroDisplayName,
  }) {
    return buildStoryAskTargets(
      heroPerson: person,
      heroDisplayName: heroDisplayName,
      treePeople: _treePeople,
      semyaMembers: _semyaMembers,
      currentUserId: _authService.currentUserId,
    );
  }

  Future<void> _askFamilyStory({
    required String name,
    String? relation,
    String? gender,
  }) async {
    final person = _person;
    final treeId = _currentTreeId;
    final storyService = _familyService is StoryRequestCapableFamilyTreeService
        ? _familyService as StoryRequestCapableFamilyTreeService
        : null;
    final allAskTargets =
        (storyService == null || person == null || treeId == null)
            ? const <FamilyStoryAskTarget>[]
            : _buildStoryAskTargets(person: person, heroDisplayName: name);
    final canSaveAnswer = _canEditBiography();
    final canCreateGuestLink = _canEditBiography();
    final askTargets = _canEditOrDelete()
        ? allAskTargets
        : allAskTargets.where((t) => t.isHero).toList(growable: false);

    final action = await showFamilyStoryQuestionsSheet(
      context,
      personName: name,
      relation: relation,
      storyRequestService: storyService,
      treeId: treeId,
      personId: person?.id,
      askTargets: askTargets,
      canSaveAnswer: canSaveAnswer,
      canCreateGuestLink: canCreateGuestLink,
    );
    if (action == null || !mounted) return;
    switch (action.type) {
      case FamilyStoryQuestionActionType.share:
        await _shareFamilyStoryQuestion(
          question: action.question,
          name: name,
          relation: relation,
          gender: gender,
        );
        break;
      case FamilyStoryQuestionActionType.saveAnswer:
        if (!canSaveAnswer) break;
        await _openBiographyEditor(
          name: name,
          relation: relation,
          gender: gender,
          initialQuestion: action.question,
        );
        break;
      case FamilyStoryQuestionActionType.requestSent:
        // Forces StoryRequestStatusLine to remount and refetch so «Ждём
        // ответа …» shows up immediately instead of on next screen visit.
        _refreshStoryRequestStatus();
        break;
      case FamilyStoryQuestionActionType.guestLinkCreated:
        _refreshStoryRequestStatus();
        final shareUrl = action.request?.shareUrl;
        if (shareUrl != null && shareUrl.isNotEmpty) {
          await _shareGuestStoryLink(
            questionText: action.question.question,
            personName: name,
            shareUrl: shareUrl,
          );
        }
        break;
    }
  }

  Future<void> _shareGuestStoryLink({
    required String questionText,
    required String personName,
    required String shareUrl,
  }) async {
    final message = buildFamilyStoryGuestLinkShareMessage(
      questionText: questionText,
      personName: personName,
      shareUrl: shareUrl,
    );
    try {
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: 'Вопрос для семейной истории',
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Ссылка для ответа создана'),
        action: SnackBarAction(
          label: 'Скопировать',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: shareUrl));
          },
        ),
      ),
    );
  }

  Future<void> _shareFamilyStoryQuestion({
    required FamilyStoryQuestion question,
    required String name,
    String? relation,
    String? gender,
  }) async {
    final message = buildFamilyStoryShareMessage(
      question: question,
      personName: name,
      relation: relation,
    );
    try {
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: 'Вопрос для семейной истории',
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Вопрос готов к отправке.'),
          action: _canEditBiography()
              ? SnackBarAction(
                  label: 'Сохранить ответ',
                  onPressed: () => _openBiographyEditor(
                    name: name,
                    relation: relation,
                    gender: gender,
                    initialQuestion: question,
                  ),
                )
              : null,
        ),
      );
    } catch (error) {
      debugPrint('Не удалось открыть отправку семейного вопроса: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Не удалось открыть отправку.'),
          action: _canDirectEditProfile()
              ? SnackBarAction(
                  label: 'Сохранить ответ',
                  onPressed: () => _openBiographyEditor(
                    name: name,
                    relation: relation,
                    gender: gender,
                    initialQuestion: question,
                  ),
                )
              : null,
        ),
      );
    }
  }

  void _openVoiceRecordings() {
    final person = _person;
    if (person == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileVoiceRecordingsScreen(
          personId: person.id,
          personName: person.name,
          authorNames: _authorNamesMap(),
        ),
      ),
    );
  }

  void _openArticleHistory() {
    final person = _person;
    if (person == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileArticleHistoryScreen(
          personId: person.id,
          personName: person.name,
          actorNames: _authorNamesMap(),
        ),
      ),
    );
  }
}
