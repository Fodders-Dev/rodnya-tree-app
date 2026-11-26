part of '../custom_api_family_tree_service.dart';

mixin _CustomApiTreeTrashMixin on _CustomApiFamilyTreeHost {
  @override
  Future<List<DeletedPerson>> listMyDeletedPersons() async {
    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/me/deleted-persons',
      );
      final raw = response['deletedPersons'];
      if (raw is! List) return const <DeletedPerson>[];
      return raw
          .whereType<Map>()
          .map((e) => DeletedPerson.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on CustomApiException {
      return const <DeletedPerson>[];
    }
  }

  @override
  Future<List<DeletedPerson>> listDeletedPersonsForSemya(
    String semyaId,
  ) async {
    final trimmed = semyaId.trim();
    if (trimmed.isEmpty) return const <DeletedPerson>[];
    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/semya/$trimmed/deleted-persons',
      );
      final raw = response['deletedPersons'];
      if (raw is! List) return const <DeletedPerson>[];
      return raw
          .whereType<Map>()
          .map((e) => DeletedPerson.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on CustomApiException catch (e) {
      throw _mapDeletedItemException(e);
    }
  }

  @override
  Future<void> restoreDeletedPerson(String deletedPersonId) async {
    final trimmed = deletedPersonId.trim();
    if (trimmed.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Некорректные параметры',
      );
    }
    try {
      await _requestJson(
        method: 'POST',
        path: '/v1/deleted-persons/$trimmed/restore',
      );
      _invalidateAllTreeCaches();
    } on CustomApiException catch (e) {
      throw _mapDeletedItemException(e);
    }
  }

  @override
  Future<void> permanentlyDeletePerson(String deletedPersonId) async {
    final trimmed = deletedPersonId.trim();
    if (trimmed.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Некорректные параметры',
      );
    }
    try {
      await _requestJson(
        method: 'DELETE',
        path: '/v1/deleted-persons/$trimmed',
      );
    } on CustomApiException catch (e) {
      throw _mapDeletedItemException(e);
    }
  }

  @override
  Future<List<DeletedPost>> listMyDeletedPosts() async {
    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/me/deleted-posts',
      );
      final raw = response['deletedPosts'];
      if (raw is! List) return const <DeletedPost>[];
      return raw
          .whereType<Map>()
          .map((e) => DeletedPost.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on CustomApiException {
      return const <DeletedPost>[];
    }
  }

  @override
  Future<void> restoreDeletedPost(String deletedPostId) async {
    final trimmed = deletedPostId.trim();
    if (trimmed.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Некорректные параметры',
      );
    }
    try {
      await _requestJson(
        method: 'POST',
        path: '/v1/deleted-posts/$trimmed/restore',
      );
    } on CustomApiException catch (e) {
      throw _mapDeletedItemException(e);
    }
  }

  @override
  Future<void> permanentlyDeletePost(String deletedPostId) async {
    final trimmed = deletedPostId.trim();
    if (trimmed.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Некорректные параметры',
      );
    }
    try {
      await _requestJson(
        method: 'DELETE',
        path: '/v1/deleted-posts/$trimmed',
      );
    } on CustomApiException catch (e) {
      throw _mapDeletedItemException(e);
    }
  }

  /// Ship Q4a (Ship 31): mapper для deleted-persons/deleted-posts
  /// endpoints. Backend status codes shared between persons + posts
  /// surfaces (same shape per Ship 30/30b). Maps к domain SemyaError
  /// codes для UI к render targeted copy.
  SemyaError _mapDeletedItemException(CustomApiException e) {
    final status = e.statusCode;
    final messageLower = e.message.toLowerCase();
    String code;
    switch (status) {
      case 400:
        code = 'INVALID_INPUT';
        break;
      case 403:
        code = 'FORBIDDEN';
        break;
      case 404:
        if (messageLower.contains('публикация')) {
          code = 'DELETED_POST_NOT_FOUND';
        } else {
          code = 'DELETED_PERSON_NOT_FOUND';
        }
        break;
      case 409:
        if (messageLower.contains('уже')) {
          code = 'ALREADY_RESTORED';
        } else if (messageLower.contains('подождите')) {
          code = 'FLOOR_NOT_MET';
        } else {
          code = 'CONFLICT';
        }
        break;
      case 410:
        if (messageLower.contains('семья')) {
          code = 'SEMYA_DELETED';
        } else {
          code = 'HARD_DELETE_ELAPSED';
        }
        break;
      default:
        code = 'UNKNOWN';
    }
    return SemyaError(code: code, message: e.message);
  }
}
