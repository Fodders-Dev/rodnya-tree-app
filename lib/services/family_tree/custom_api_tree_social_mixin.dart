part of '../custom_api_family_tree_service.dart';

mixin _CustomApiTreeSocialMixin on _CustomApiFamilyTreeHost {
  @override
  Future<BranchDigest?> getBranchDigest({
    required String treeId,
    int days = 7,
  }) async {
    final params = <String, String>{
      if (days > 0 && days != 7) 'days': days.toString(),
    };
    final path = params.isEmpty
        ? '/v1/trees/$treeId/digest'
        : _buildPathWithQuery('/v1/trees/$treeId/digest', params);
    try {
      final response = await _requestJson(method: 'GET', path: path);
      final raw = response['digest'];
      if (raw is! Map) return null;
      return BranchDigest.fromJson(Map<String, dynamic>.from(raw));
    } on CustomApiException catch (error) {
      // 404 → branch unknown to this caller. Surface as null so
      // the home widget gracefully hides itself; treat anything
      // else as a real failure the caller can show in UI.
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<BulkImportResult> bulkImportPersonsToTree({
    required String sourceTreeId,
    required String targetTreeId,
    required List<String> sourcePersonIds,
  }) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/trees/$targetTreeId/persons/import',
      body: <String, dynamic>{
        'sourceTreeId': sourceTreeId,
        'sourcePersonIds': sourcePersonIds,
      },
    );
    final rawPersons = response['persons'];
    final persons = rawPersons is List
        ? rawPersons
            .whereType<Map>()
            .map(
              (raw) => _personFromJson(
                Map<String, dynamic>.from(raw),
                fallbackTreeId: targetTreeId,
              ),
            )
            .toList(growable: false)
        : const <FamilyPerson>[];
    final rawRelations = response['relations'];
    final bridgedRelationCount = rawRelations is List ? rawRelations.length : 0;
    _invalidateTreeCaches(targetTreeId);
    return BulkImportResult(
      persons: persons,
      bridgedRelationCount: bridgedRelationCount,
    );
  }

  // ── MVP-1 (STORY-REQUEST-MVP1-BRIEF.md §3.2): «Спросить историю» ──

  @override
  Future<StoryRequest?> createStoryRequest({
    required String treeId,
    required String personId,
    String? targetUserId,
    String deliveryMode = 'in_app',
    String? targetName,
    required StoryRequestQuestion question,
  }) async {
    try {
      final cleanTarget = targetUserId?.trim();
      final cleanTargetName = targetName?.trim();
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/story-requests',
        body: {
          'treeId': treeId,
          'personId': personId,
          if (deliveryMode != 'in_app') 'deliveryMode': deliveryMode,
          if (cleanTarget != null && cleanTarget.isNotEmpty)
            'targetUserId': cleanTarget,
          if (cleanTargetName != null && cleanTargetName.isNotEmpty)
            'targetName': cleanTargetName,
          'question': question.toJson(),
        },
      );
      final requestRaw = response['request'];
      if (requestRaw is! Map) return null;
      return StoryRequest.fromJson(Map<String, dynamic>.from(requestRaw));
    } on CustomApiException catch (e) {
      throw _mapStoryRequestException(e, endpoint: 'create');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<StoryRequest>> listStoryRequests({
    required String role,
    StoryRequestStatus? status,
  }) async {
    try {
      final path = _buildPathWithQuery('/v1/me/story-requests', {
        'role': role,
        if (status != null) 'status': status.serverValue,
      });
      final response = await _requestJson(method: 'GET', path: path);
      final rawList = response['requests'];
      if (rawList is! List) return const <StoryRequest>[];
      return rawList
          .whereType<Map>()
          .map((e) => StoryRequest.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const <StoryRequest>[];
    }
  }

  @override
  Future<StoryRequest?> getStoryRequest({required String requestId}) async {
    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/story-requests/$requestId',
      );
      final requestRaw = response['request'];
      if (requestRaw is! Map) return null;
      return StoryRequest.fromJson(Map<String, dynamic>.from(requestRaw));
    } on CustomApiException catch (e) {
      throw _mapStoryRequestException(e, endpoint: 'get');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StoryRequest?> answerStoryRequest({
    required String requestId,
    required StoryRequestAnswerInput answer,
  }) async {
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/story-requests/$requestId/answer',
        body: answer.toJson(),
      );
      final requestRaw = response['request'];
      if (requestRaw is! Map) return null;
      return StoryRequest.fromJson(Map<String, dynamic>.from(requestRaw));
    } on CustomApiException catch (e) {
      throw _mapStoryRequestException(e, endpoint: 'answer');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StoryRequest?> declineStoryRequest({required String requestId}) async {
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/story-requests/$requestId/decline',
      );
      final requestRaw = response['request'];
      if (requestRaw is! Map) return null;
      return StoryRequest.fromJson(Map<String, dynamic>.from(requestRaw));
    } on CustomApiException catch (e) {
      throw _mapStoryRequestException(e, endpoint: 'decline');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StoryRequest?> revokeStoryRequest({required String requestId}) async {
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/story-requests/$requestId/revoke',
      );
      final requestRaw = response['request'];
      if (requestRaw is! Map) return null;
      return StoryRequest.fromJson(Map<String, dynamic>.from(requestRaw));
    } on CustomApiException catch (e) {
      throw _mapStoryRequestException(e, endpoint: 'revoke');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StoryRequest?> updateStoryRequest({
    required String requestId,
    String? questionText,
    String? targetName,
  }) async {
    try {
      final response = await _requestJson(
        method: 'PATCH',
        path: '/v1/story-requests/$requestId',
        body: <String, dynamic>{
          if (questionText != null) 'questionText': questionText.trim(),
          if (targetName != null) 'targetName': targetName.trim(),
        },
      );
      final requestRaw = response['request'];
      if (requestRaw is! Map) return null;
      return StoryRequest.fromJson(Map<String, dynamic>.from(requestRaw));
    } on CustomApiException catch (e) {
      throw _mapStoryRequestException(e, endpoint: 'update');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StoryUploadedMedia?> uploadStoryRequestMedia({
    required String requestId,
    required String kind,
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      final uri = _buildUri(
        _buildPathWithQuery(
          '/v1/story-requests/$requestId/media',
          {'kind': kind},
        ),
      );
      final response = await _httpClient.put(
        uri,
        headers: <String, String>{
          ..._headers(),
          'Content-Type': contentType,
        },
        body: bytes,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final payload = tryDecodeJsonMap(response.body);
      final url = payload?['url']?.toString().trim();
      if (url == null || url.isEmpty) return null;
      final transcript = payload?['transcript']?.toString().trim();
      return StoryUploadedMedia(
        url: url,
        transcript:
            transcript != null && transcript.isNotEmpty ? transcript : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Map [CustomApiException.statusCode] к [StoryRequestError]. Verified
  /// 2026-09-13 against the merged backend (story-request-routes.js) —
  /// it sends only `{message}` on error (no machine `error` field, same
  /// as kinship-checks), so `code` is coarse wherever two business errors
  /// share a status: create's 400 covers both SELF_REQUEST_FORBIDDEN and
  /// INVALID_QUESTION, its 404 covers both PERSON_NOT_FOUND and
  /// TARGET_NOT_IN_TREE. The server-authored `message` always carries the
  /// precise, user-facing text regardless.
  StoryRequestError _mapStoryRequestException(
    CustomApiException e, {
    required String endpoint,
  }) {
    final status = e.statusCode;
    String code;
    String fallback;
    switch (endpoint) {
      case 'create':
        switch (status) {
          case 400:
            code = 'INVALID_REQUEST';
            fallback = 'Проверьте вопрос и адресата и попробуйте снова.';
            break;
          case 403:
            code = 'FORBIDDEN';
            fallback = 'Нет прав задать вопрос об этом человеке.';
            break;
          case 404:
            code = 'NOT_FOUND';
            fallback = 'Не нашли человека или адресата в этом дереве.';
            break;
          case 409:
            code = 'DUPLICATE_PENDING';
            fallback = 'Такой вопрос уже ждёт ответа.';
            break;
          case 429:
            code = 'TOO_MANY_PENDING';
            fallback = 'Слишком много открытых вопросов — дождитесь ответов.';
            break;
          default:
            code = 'UNKNOWN';
            fallback = 'Не удалось отправить вопрос. Попробуйте позже.';
        }
        break;
      case 'answer':
        switch (status) {
          case 400:
            code = 'INVALID_ANSWER';
            fallback = 'Не получилось сохранить ответ — попробуйте ещё раз.';
            break;
          case 403:
            code = 'NOT_TARGET';
            fallback = 'Ответить может только тот, кому задали вопрос.';
            break;
          case 404:
            code = 'NOT_FOUND';
            fallback = 'Запрос не найден — возможно, его уже удалили.';
            break;
          case 409:
            code = 'NOT_PENDING';
            fallback = 'На этот вопрос уже ответили или он закрыт.';
            break;
          default:
            code = 'UNKNOWN';
            fallback = 'Не удалось отправить ответ. Попробуйте позже.';
        }
        break;
      case 'decline':
        switch (status) {
          case 403:
            code = 'NOT_TARGET';
            fallback = 'Отклонить может только тот, кому задали вопрос.';
            break;
          case 404:
            code = 'NOT_FOUND';
            fallback = 'Запрос не найден — возможно, его уже удалили.';
            break;
          case 409:
            code = 'NOT_PENDING';
            fallback = 'Вопрос уже закрыт.';
            break;
          default:
            code = 'UNKNOWN';
            fallback = 'Не получилось отклонить вопрос. Попробуйте позже.';
        }
        break;
      case 'revoke':
        switch (status) {
          case 403:
            code = 'NOT_INITIATOR';
            fallback = 'Отозвать вопрос может только тот, кто его задал.';
            break;
          case 404:
            code = 'NOT_FOUND';
            fallback = 'Запрос не найден — возможно, его уже удалили.';
            break;
          case 409:
            code = 'NOT_PENDING';
            fallback = 'Вопрос уже закрыт.';
            break;
          default:
            code = 'UNKNOWN';
            fallback = 'Не получилось отозвать вопрос. Попробуйте позже.';
        }
        break;
      case 'update':
        switch (status) {
          case 400:
            code = 'INVALID_QUESTION';
            fallback = 'Вопрос должен содержать от 3 до 500 символов.';
            break;
          case 403:
            code = 'NOT_INITIATOR';
            fallback = 'Редактировать вопрос может только тот, кто его задал.';
            break;
          case 404:
            code = 'NOT_FOUND';
            fallback = 'Запрос не найден — возможно, его уже удалили.';
            break;
          case 409:
            code = 'NOT_PENDING';
            fallback = 'Вопрос уже обработан или такой же вопрос уже открыт.';
            break;
          default:
            code = 'UNKNOWN';
            fallback = 'Не получилось обновить вопрос. Попробуйте позже.';
        }
        break;
      default: // 'get'
        code = status == 404 ? 'NOT_FOUND' : 'UNKNOWN';
        fallback = 'Не удалось загрузить вопрос.';
    }

    final serverMessage = e.message.trim();
    final looksGeneric = serverMessage.isEmpty ||
        serverMessage.startsWith('Ошибка backend') ||
        serverMessage == 'Пустой ответ от backend';
    return StoryRequestError(
      code: code,
      message: looksGeneric ? fallback : serverMessage,
      statusCode: status,
    );
  }
}
