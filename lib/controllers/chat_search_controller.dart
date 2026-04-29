import 'package:flutter/widgets.dart';

class ChatSearchController extends ChangeNotifier {
  ChatSearchController() {
    textController.addListener(_handleTextChanged);
  }

  final TextEditingController textController = TextEditingController();
  bool _isSearchMode = false;
  bool _suppressTextNotification = false;

  bool get isSearchMode => _isSearchMode;

  String get query => textController.text.trim();

  String get normalizedQuery => query.toLowerCase();

  bool get hasQuery => query.isNotEmpty;

  void open() {
    if (_isSearchMode) {
      return;
    }
    _isSearchMode = true;
    notifyListeners();
  }

  void close() {
    final shouldNotify = _isSearchMode || textController.text.isNotEmpty;
    _isSearchMode = false;
    if (textController.text.isNotEmpty) {
      _suppressTextNotification = true;
      textController.clear();
      _suppressTextNotification = false;
    }
    if (shouldNotify) {
      notifyListeners();
    }
  }

  bool matches(String text) {
    final activeQuery = normalizedQuery;
    if (activeQuery.isEmpty) {
      return true;
    }
    return text.toLowerCase().contains(activeQuery);
  }

  void _handleTextChanged() {
    if (!_suppressTextNotification) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    textController.removeListener(_handleTextChanged);
    textController.dispose();
    super.dispose();
  }
}
