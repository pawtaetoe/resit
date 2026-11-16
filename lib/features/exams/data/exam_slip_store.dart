import 'dart:convert';

import 'package:resit/features/common/data/private_store.dart';
import 'package:resit/features/exams/domain/exam_results.dart';

/// Released result slips, kept encrypted on the device: released slips don't
/// change, so each is read from in4SIT once. Also keeps the last term list.
class ExamSlipStore {
  static const _key = 'exam_slips';

  final PrivateStore _store;
  Future<_SlipData>? _data;
  Future<void> _writes = Future.value();

  ExamSlipStore([PrivateStore? store]) : _store = store ?? PrivateStore();

  Future<_SlipData> _load() => _data ??= () async {
        try {
          final raw = await _store.read(_key);
          if (raw == null) return _SlipData();
          final j = (jsonDecode(raw) as Map).cast<String, Object?>();
          return _SlipData(
            terms: [
              for (final t in (j['terms'] as List?) ?? const []) ExamTerm.fromJson((t as Map).cast<String, Object?>())
            ],
            slips: {
              for (final e in ((j['slips'] as Map?) ?? const {}).entries)
                e.key as String: ExamResults.fromJson((e.value as Map).cast<String, Object?>()),
            },
          );
        } catch (_) {
          return _SlipData();
        }
      }();

  Future<void> _save() {
    return _writes = _writes.then((_) async {
      final data = await _load();
      try {
        await _store.write(
            _key,
            jsonEncode({
              'terms': [for (final t in data.terms) t.toJson()],
              'slips': {for (final e in data.slips.entries) e.key: e.value.toJson()},
            }));
      } catch (_) {
        // Not kept this time; it is read from in4SIT again next time.
      }
    });
  }

  /// The kept released slip for the term named [termName], if any. A kept
  /// slip whose heading names another term (saved by an earlier version that
  /// could mix terms up) is dropped, so it's read again.
  Future<ExamResults?> slip(String termName) async {
    final data = await _load();
    final s = data.slips[termName];
    if (s != null && !slipMatchesTerm(s.heading, termName)) {
      data.slips.remove(termName);
      await _save();
      return null;
    }
    return s;
  }

  /// Keeps [slip] if it is released and is for its own term.
  Future<void> save(ExamResults slip) async {
    if (!slip.released || !slipMatchesTerm(slip.heading, slip.term.name)) return;
    (await _load()).slips[slip.term.name] = slip;
    await _save();
  }

  /// The term list last read from in4SIT, latest first (empty if none).
  Future<List<ExamTerm>> terms() async => List.of((await _load()).terms);

  Future<void> saveTerms(List<ExamTerm> terms) async {
    (await _load()).terms = List.of(terms);
    await _save();
  }

  Future<void> clear() async {
    final data = await _load();
    data.slips.clear();
    data.terms = [];
    await _writes;
    try {
      await _store.delete(_key);
    } catch (_) {}
  }
}

class _SlipData {
  List<ExamTerm> terms;
  final Map<String, ExamResults> slips;
  _SlipData({List<ExamTerm>? terms, Map<String, ExamResults>? slips})
      : terms = terms ?? [],
        slips = slips ?? {};
}
