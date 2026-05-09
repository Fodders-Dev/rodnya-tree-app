import 'package:flutter/foundation.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../models/family_relation.dart';

/// In-memory undo/redo стек для мутаций дерева. Запись делается
/// СРАЗУ ПОСЛЕ успешной мутации UI-слоя; на undo/redo вызывается
/// inverse операция через тот же `FamilyTreeServiceInterface`,
/// что и оригинальная мутация — backend остаётся источником правды.
///
/// Scope первого выпуска (минимально полезный, без архитектурного
/// перепила): только relation create / delete — это то что чаще
/// всего ломается при ручной правке дерева. Другие операции
/// (add/edit/delete person, unlink user) добавлю когда станет
/// очевидно что нужно.
///
/// Ограничения, которые осознанно принимаются для v1:
/// * In-memory — стек теряется при перезагрузке вкладки или
///   уходе с экрана дерева (history сбрасывается через clear()).
/// * Однопользовательский — если кто-то ещё в этом дереве
///   отредактировал ту же связь, undo может упасть; ловим ошибку
///   в SnackBar.
/// * Лимит стека — 50 записей. Старые записи теряются.
///
/// User-reported: «надо в дереве сделать ctrl+z и ctrl+shift+z и
/// стрелочки чтобы изменения ворочить» — после переломаного дерева
/// не было пути откатиться.
class TreeMutationHistory extends ChangeNotifier {
  static const int _maxStackSize = 50;

  final List<_HistoryEntry> _undoStack = <_HistoryEntry>[];
  final List<_HistoryEntry> _redoStack = <_HistoryEntry>[];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoDepth => _undoStack.length;
  int get redoDepth => _redoStack.length;

  /// Записать что юзер только что СОЗДАЛ связь. На undo связь
  /// удалится; на redo создастся заново (с новым id).
  void recordRelationCreated({
    required String treeId,
    required FamilyRelation created,
  }) {
    _push(_HistoryEntry.relationCreated(treeId: treeId, relation: created));
  }

  /// Записать что юзер только что УДАЛИЛ связь. На undo связь
  /// создаётся заново (новый id); на redo удаляется.
  void recordRelationDeleted({
    required String treeId,
    required FamilyRelation deleted,
  }) {
    _push(_HistoryEntry.relationDeleted(treeId: treeId, relation: deleted));
  }

  void _push(_HistoryEntry entry) {
    _undoStack.add(entry);
    while (_undoStack.length > _maxStackSize) {
      _undoStack.removeAt(0);
    }
    // Любое новое действие сбрасывает redo — у нас линейная
    // история, как у CodeMirror'а / Telegram'а.
    _redoStack.clear();
    notifyListeners();
  }

  /// Откатить последнее действие. Возвращает описание для toast'а
  /// или null если стек пуст / откатить не удалось.
  Future<TreeMutationOutcome> undo(FamilyTreeServiceInterface service) async {
    if (_undoStack.isEmpty) {
      return TreeMutationOutcome.empty();
    }
    final entry = _undoStack.removeLast();
    notifyListeners();
    try {
      final inverse = await entry.applyInverse(service);
      if (inverse != null) {
        _redoStack.add(inverse);
        while (_redoStack.length > _maxStackSize) {
          _redoStack.removeAt(0);
        }
      }
      notifyListeners();
      return TreeMutationOutcome.success(entry.description);
    } catch (error, stackTrace) {
      // Откат не удался — возвращаем entry в стек чтобы юзер
      // мог попробовать ещё раз когда восстановится связь / свежий
      // снапшот. notifyListeners уже сработал на removeLast, нужно
      // пнуть ещё раз чтобы UI вернулся.
      _undoStack.add(entry);
      notifyListeners();
      debugPrint('TreeMutationHistory.undo failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return TreeMutationOutcome.failure(error);
    }
  }

  /// Повторить отменённое действие.
  Future<TreeMutationOutcome> redo(FamilyTreeServiceInterface service) async {
    if (_redoStack.isEmpty) {
      return TreeMutationOutcome.empty();
    }
    final entry = _redoStack.removeLast();
    notifyListeners();
    try {
      final inverse = await entry.applyInverse(service);
      if (inverse != null) {
        _undoStack.add(inverse);
        while (_undoStack.length > _maxStackSize) {
          _undoStack.removeAt(0);
        }
      }
      notifyListeners();
      return TreeMutationOutcome.success(entry.description);
    } catch (error, stackTrace) {
      _redoStack.add(entry);
      notifyListeners();
      debugPrint('TreeMutationHistory.redo failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return TreeMutationOutcome.failure(error);
    }
  }

  /// Сбросить стек. Зовётся при смене дерева, logout, dispose
  /// корневого экрана дерева — чтобы undo, относящееся к другому
  /// контексту, не зависало.
  void clear() {
    if (_undoStack.isEmpty && _redoStack.isEmpty) return;
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }
}

class TreeMutationOutcome {
  const TreeMutationOutcome._({
    required this.kind,
    this.description,
    this.error,
  });

  factory TreeMutationOutcome.empty() =>
      const TreeMutationOutcome._(kind: TreeMutationOutcomeKind.empty);

  factory TreeMutationOutcome.success(String description) =>
      TreeMutationOutcome._(
        kind: TreeMutationOutcomeKind.success,
        description: description,
      );

  factory TreeMutationOutcome.failure(Object error) =>
      TreeMutationOutcome._(kind: TreeMutationOutcomeKind.failure, error: error);

  final TreeMutationOutcomeKind kind;
  final String? description;
  final Object? error;

  bool get isEmpty => kind == TreeMutationOutcomeKind.empty;
  bool get isSuccess => kind == TreeMutationOutcomeKind.success;
  bool get isFailure => kind == TreeMutationOutcomeKind.failure;
}

enum TreeMutationOutcomeKind { empty, success, failure }

/// Один шаг истории. Inverse возвращает _новую_ запись для
/// противоположного стека (undo → redo и обратно).
class _HistoryEntry {
  const _HistoryEntry._({
    required this.description,
    required this.applyInverse,
  });

  final String description;
  final Future<_HistoryEntry?> Function(FamilyTreeServiceInterface service)
      applyInverse;

  /// Текущее состояние: связь была создана. Inverse — удалить её
  /// и вернуть запись «связь была удалена» для redo.
  factory _HistoryEntry.relationCreated({
    required String treeId,
    required FamilyRelation relation,
  }) {
    return _HistoryEntry._(
      description: 'Создание связи',
      applyInverse: (service) async {
        await service.disconnectRelation(
          treeId: treeId,
          relationId: relation.id,
        );
        return _HistoryEntry.relationDeleted(
          treeId: treeId,
          relation: relation,
        );
      },
    );
  }

  /// Связь была удалена. Inverse — создать заново с теми же
  /// параметрами и вернуть запись «связь создана» для redo.
  factory _HistoryEntry.relationDeleted({
    required String treeId,
    required FamilyRelation relation,
  }) {
    return _HistoryEntry._(
      description: 'Удаление связи',
      applyInverse: (service) async {
        final restored = await service.createRelation(
          treeId: treeId,
          person1Id: relation.person1Id,
          person2Id: relation.person2Id,
          relation1to2: relation.relation1to2,
          isConfirmed: relation.isConfirmed,
          marriageDate: relation.marriageDate,
          divorceDate: relation.divorceDate,
          customRelationLabel1to2: relation.customRelationLabel1to2,
          customRelationLabel2to1: relation.customRelationLabel2to1,
        );
        return _HistoryEntry.relationCreated(
          treeId: treeId,
          relation: restored,
        );
      },
    );
  }
}

/// Helper-extension для вызова из UI без типизации внутренних
/// `_OperationOutcome`. UI получает либо строку для тоаста, либо
/// `null` (стек пуст / ошибка) и может реагировать.
extension TreeMutationHistoryUiExtension on TreeMutationHistory {
  Future<String?> undoForUi(FamilyTreeServiceInterface service) async {
    final outcome = await undo(service);
    if (outcome.isSuccess) return outcome.description;
    return null;
  }

  Future<String?> redoForUi(FamilyTreeServiceInterface service) async {
    final outcome = await redo(service);
    if (outcome.isSuccess) return outcome.description;
    return null;
  }
}
