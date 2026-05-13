import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/interfaces/extended_network_capable_family_tree_service.dart';
import '../backend/models/extended_network_slice.dart';

/// Phase 4 chunk 2 (PHASE-4-PROPOSAL.md §3.3 + DECISIONS.md 2026-05-12
/// Q8.A): per-tree state controller для extended-network view mode +
/// filter values. Lifecycle: создаётся при entry на tree_view_screen,
/// dispose'ится при exit'е.
///
/// Persistence через SharedPreferences с ключами:
///   • `extended_mode_${treeId}` — `'mine'` / `'extended'`. Default
///     `'mine'` при отсутствии ключа (opt-in явный, Q8.A).
///   • `extended_max_hops_${treeId}` — int 2..4. Default 4
///     (== privacy fence, Q6.A).
///   • `extended_include_anonymous_${treeId}` — bool. Default true.
///   • `extended_branch_filter_${treeId}` — csv treeIds. Default '' (all).
///
/// Backend fetch'и идут через [ExtendedNetworkCapableFamilyTreeService]
/// — если host service не implements capability, [isCapable] = false,
/// UI gracefully disable'ит mode toggle.
enum ExtendedNetworkMode {
  mine,
  extended;

  String get serverValue {
    switch (this) {
      case ExtendedNetworkMode.mine:
        return 'mine';
      case ExtendedNetworkMode.extended:
        return 'extended';
    }
  }

  String get russianLabel {
    switch (this) {
      case ExtendedNetworkMode.mine:
        return 'Моё дерево';
      case ExtendedNetworkMode.extended:
        return 'Все';
    }
  }

  String get russianLongLabel {
    switch (this) {
      case ExtendedNetworkMode.mine:
        return 'Моё дерево';
      case ExtendedNetworkMode.extended:
        return 'Расширенная сеть';
    }
  }

  static ExtendedNetworkMode fromServerValue(Object? raw) {
    if (raw?.toString() == 'extended') return ExtendedNetworkMode.extended;
    return ExtendedNetworkMode.mine;
  }
}

class ExtendedNetworkController extends ChangeNotifier {
  ExtendedNetworkController({
    required this.treeId,
    required ExtendedNetworkCapableFamilyTreeService? service,
    SharedPreferences? preferences,
  })  : _service = service,
        _preferencesFuture = preferences != null
            ? Future.value(preferences)
            : SharedPreferences.getInstance() {
    _loadTask = _loadPersistedState();
  }

  final String treeId;
  final ExtendedNetworkCapableFamilyTreeService? _service;
  final Future<SharedPreferences> _preferencesFuture;
  late final Future<void> _loadTask;

  ExtendedNetworkMode _mode = ExtendedNetworkMode.mine;
  int _maxHops = 4;
  bool _includeAnonymous = true;
  Set<String> _branchFilter = <String>{};

  ExtendedNetworkSlice? _slice;
  bool _isFetching = false;
  String? _error;

  /// Getters — UI читает реактивно.
  ExtendedNetworkMode get mode => _mode;
  int get maxHops => _maxHops;
  bool get includeAnonymous => _includeAnonymous;
  Set<String> get branchFilter => Set<String>.unmodifiable(_branchFilter);
  ExtendedNetworkSlice? get slice => _slice;
  bool get isFetching => _isFetching;
  String? get error => _error;

  /// True если backend service implements capability. False — Mode
  /// toggle UI отключает себя через tooltip «Обновите приложение».
  bool get isCapable => _service != null;

  Future<void> get ready => _loadTask;

  /// Toggle между `mine` ↔ `extended`. При переходе в extended
  /// триггерит fetch если slice ещё не получен / устарел (60s server
  /// cache — если попадаем в окно, повторный fetch вернёт same).
  Future<void> setMode(ExtendedNetworkMode next) async {
    if (_mode == next) return;
    _mode = next;
    notifyListeners();
    await _persistMode();
    if (next == ExtendedNetworkMode.extended && _slice == null) {
      await _fetchSlice();
    }
  }

  /// Clamp 2..4 (DECISIONS.md 2026-05-12 Q6.A). Triggers refetch
  /// только если mode = extended (иначе persist но без fetch'а).
  Future<void> setMaxHops(int hops) async {
    final clamped = hops.clamp(2, 4);
    if (_maxHops == clamped) return;
    _maxHops = clamped;
    notifyListeners();
    await _persistMaxHops();
    if (_mode == ExtendedNetworkMode.extended) {
      await _fetchSlice();
    }
  }

  Future<void> setIncludeAnonymous(bool value) async {
    if (_includeAnonymous == value) return;
    _includeAnonymous = value;
    notifyListeners();
    await _persistIncludeAnonymous();
    if (_mode == ExtendedNetworkMode.extended) {
      await _fetchSlice();
    }
  }

  Future<void> setBranchFilter(Set<String> filter) async {
    if (_branchFilter.length == filter.length &&
        _branchFilter.containsAll(filter)) {
      return;
    }
    _branchFilter = Set<String>.from(filter);
    notifyListeners();
    await _persistBranchFilter();
    if (_mode == ExtendedNetworkMode.extended) {
      await _fetchSlice();
    }
  }

  /// Manual refresh — force refetch'и (e.g. pull-to-refresh).
  /// Игнорируется в `mine` mode'е.
  Future<void> refresh() async {
    if (_mode != ExtendedNetworkMode.extended) return;
    await _fetchSlice();
  }

  Future<void> _fetchSlice() async {
    final svc = _service;
    if (svc == null) return;
    _isFetching = true;
    _error = null;
    notifyListeners();
    try {
      final result = await svc.getExtendedNetworkSlice(
        treeId: treeId,
        maxHops: _maxHops,
        includeAnonymous: _includeAnonymous,
        branchIds: _branchFilter.isEmpty ? null : _branchFilter.toList(),
      );
      _slice = result;
    } catch (e) {
      _error = '$e';
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }

  // ── SharedPreferences keys ──────────────────────────────────────

  String get _modeKey => 'extended_mode_$treeId';
  String get _maxHopsKey => 'extended_max_hops_$treeId';
  String get _includeAnonymousKey => 'extended_include_anonymous_$treeId';
  String get _branchFilterKey => 'extended_branch_filter_$treeId';

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await _preferencesFuture;
      final storedMode = prefs.getString(_modeKey);
      if (storedMode != null) {
        _mode = ExtendedNetworkMode.fromServerValue(storedMode);
      }
      final storedHops = prefs.getInt(_maxHopsKey);
      if (storedHops != null) {
        _maxHops = storedHops.clamp(2, 4);
      }
      final storedAnon = prefs.getBool(_includeAnonymousKey);
      if (storedAnon != null) {
        _includeAnonymous = storedAnon;
      }
      final storedBranch = prefs.getStringList(_branchFilterKey);
      if (storedBranch != null) {
        _branchFilter = storedBranch.toSet();
      }
      if (_mode == ExtendedNetworkMode.extended && _service != null) {
        // Resume extended view — load slice сразу чтобы UI не
        // flash'ил «empty extended state».
        await _fetchSlice();
        return;
      }
      notifyListeners();
    } catch (_) {
      // Defensive — pref read fail НЕ должен ломать controller.
      // Используем defaults.
    }
  }

  Future<void> _persistMode() async {
    final prefs = await _preferencesFuture;
    await prefs.setString(_modeKey, _mode.serverValue);
  }

  Future<void> _persistMaxHops() async {
    final prefs = await _preferencesFuture;
    await prefs.setInt(_maxHopsKey, _maxHops);
  }

  Future<void> _persistIncludeAnonymous() async {
    final prefs = await _preferencesFuture;
    await prefs.setBool(_includeAnonymousKey, _includeAnonymous);
  }

  Future<void> _persistBranchFilter() async {
    final prefs = await _preferencesFuture;
    await prefs.setStringList(
      _branchFilterKey,
      _branchFilter.toList(growable: false),
    );
  }
}
