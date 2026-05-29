// TEMPORARY — Profile Phase 2b-2 STT validation spike (2026-05-29).
//
// Throwaway screen to validate on-device Russian speech recognition
// quality BEFORE building the voice block. Reachable via a debug-only
// Settings tile («🎤 STT тест (dev)»). Once Артём reports go/no-go, this
// file + the speech_to_text dep + the settings tile get removed (go →
// replaced by the real voice block; no-go → reverted entirely).
//
// What to check on a real Android phone:
//   1. «Инициализация» → «доступно» (not «STT недоступно»).
//   2. Locales list contains ru_RU / ru.
//   3. Tap «Записать», speak the reference phrase, compare the
//      transcript to the эталон. Judge accuracy (>~80% слов = ok).

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

const _referencePhrase =
    'Лидия родилась в селе Иваново в тысяча девятьсот сорок девятом году';

class SttSpikeScreen extends StatefulWidget {
  const SttSpikeScreen({super.key});

  @override
  State<SttSpikeScreen> createState() => _SttSpikeScreenState();
}

class _SttSpikeScreenState extends State<SttSpikeScreen> {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;
  bool _initTried = false;
  bool _listening = false;
  String _status = 'не инициализировано';
  String _error = '';
  String _transcript = '';
  double _confidence = 0;
  List<String> _ruLocales = const [];
  int _localeCount = 0;
  String _selectedLocale = 'ru_RU';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (s) => setState(() => _status = s),
        onError: (e) => setState(() => _error = e.errorMsg),
      );
      final locales = ok ? await _speech.locales() : <LocaleName>[];
      final ru = locales
          .where((l) =>
              l.localeId.toLowerCase().startsWith('ru') ||
              l.name.toLowerCase().contains('рус') ||
              l.name.toLowerCase().contains('russ'))
          .map((l) => '${l.localeId} — ${l.name}')
          .toList();
      if (!mounted) return;
      setState(() {
        _available = ok;
        _initTried = true;
        _localeCount = locales.length;
        _ruLocales = ru;
        if (ru.isNotEmpty) {
          _selectedLocale = ru.first.split(' — ').first;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initTried = true;
        _error = e.toString();
      });
    }
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_available) return;
    setState(() {
      _transcript = '';
      _confidence = 0;
      _listening = true;
    });
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: _selectedLocale,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
      ),
      onResult: (SpeechRecognitionResult r) {
        if (!mounted) return;
        setState(() {
          _transcript = r.recognizedWords;
          _confidence = r.confidence;
          if (r.finalResult) _listening = false;
        });
      },
    );
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('STT тест (dev)')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card(theme, 'Статус', [
            _kv('Инициализация', _initTried ? 'выполнена' : '…'),
            _kv('Доступно', _available ? 'да ✓' : 'НЕТ ✗'),
            _kv('Статус движка', _status),
            if (_error.isNotEmpty) _kv('Ошибка', _error),
          ]),
          const SizedBox(height: 12),
          _card(theme, 'Локали', [
            _kv('Всего локалей', '$_localeCount'),
            _kv('Русские', _ruLocales.isEmpty ? 'НЕ НАЙДЕНЫ ✗' : ''),
            for (final l in _ruLocales)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text('• $l', style: theme.textTheme.bodySmall),
              ),
            _kv('Выбрана для теста', _selectedLocale),
          ]),
          const SizedBox(height: 12),
          _card(theme, 'Эталон (произнесите вслух)', [
            Text(_referencePhrase, style: theme.textTheme.bodyLarge),
          ]),
          const SizedBox(height: 12),
          _card(theme, 'Распознано', [
            Text(
              _transcript.isEmpty ? '—' : _transcript,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            _kv('Confidence', _confidence.toStringAsFixed(2)),
          ]),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _available ? _toggleListen : null,
            icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
            label: Text(_listening ? 'Стоп' : 'Записать и распознать'),
          ),
          const SizedBox(height: 8),
          Text(
            'Сравните «Распознано» с «Эталон». Сообщите worker: ru_RU '
            'доступен? сколько слов совпало? Это решает go/no-go голоса.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(ThemeData theme, String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text('$k: $v'),
    );
  }
}
