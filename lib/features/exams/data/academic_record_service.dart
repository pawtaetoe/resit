import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:resit/features/common/data/private_store.dart';
import 'package:resit/sites/in4sit/exam_service.dart';
import 'package:resit/features/exams/domain/exam_results.dart';
import 'package:resit/features/exams/data/exam_slip_store.dart';
import 'package:resit/features/exams/domain/academic_record.dart';

/// Builds the [AcademicRecord] from in4SIT's result slips and keeps a copy
/// (encrypted on the device), so Home shows it instantly and only re-reads
/// in4SIT once a day. Released slips are kept too (see [ExamSlipStore]), so
/// a re-read only fetches the newest term and terms that weren't released
/// last time.
class AcademicRecordService {
  static const _key = 'academic_record';
  static const maxAge = Duration(days: 1);

  final ExamService exams;
  final PrivateStore _store;
  final ValueNotifier<(int done, int total)?> _progress = ValueNotifier(null);
  Future<AcademicRecord?>? _loading;

  AcademicRecordService(this.exams, {PrivateStore? store}) : _store = store ?? PrivateStore();

  /// While [load] reads slips from in4SIT: how many of the slips it has to
  /// read are done, e.g. (2, 7) for "Reading term 3 of 7". Null otherwise.
  ValueListenable<(int done, int total)?> get progress => _progress;

  Future<AcademicRecord?> saved() async {
    try {
      final raw = await _store.read(_key);
      return raw == null ? null : AcademicRecord.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  /// The saved record if it's recent; otherwise reads the slips it needs
  /// (one at a time) and saves the totals. [force] skips the once-a-day
  /// check; slips already released are still not read again. Falls back to
  /// the saved record if in4SIT can't be reached.
  Future<AcademicRecord?> load({bool force = false}) {
    // One crawl at a time: a second caller shares the one running.
    return _loading ??= _load(force).whenComplete(() => _loading = null);
  }

  Future<AcademicRecord?> _load(bool force) async {
    final cached = await saved();
    // A record saved before per-term data existed is re-read once.
    // A record with the same term twice came from slips mixed up by an
    // earlier version: read it again rather than keep it for the day.
    final mixedUp = cached != null && cached.terms.map((t) => t.name).toSet().length != cached.terms.length;
    final fresh = cached != null &&
        DateTime.now().difference(cached.fetchedAt) < maxAge &&
        cached.terms.isNotEmpty &&
        !mixedUp;
    if (!force && fresh) return cached;
    try {
      final terms = await exams.terms(); // newest first
      // The newest term can still change; older released slips can't.
      final kept = <String, ExamResults>{};
      for (final term in terms.skip(1)) {
        final slip = await exams.slips.slip(term.name);
        if (slip != null) kept[term.name] = slip.withTerm(term);
      }
      final total = terms.length - kept.length;
      var done = 0;
      _progress.value = (done, total);

      final slips = <ExamResults>[];
      for (final term in terms) {
        var slip = kept[term.name];
        if (slip == null) {
          slip = await exams.results(term, refresh: true);
          _progress.value = (++done, total);
        }
        if (slip.released) slips.add(slip);
      }
      final record = AcademicRecord.fromSlips(slips, DateTime.now());
      try {
        await _store.write(_key, jsonEncode(record.toJson()));
      } catch (_) {
        // Shown now, read again next time.
      }
      return record;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    } finally {
      _progress.value = null;
    }
  }

  /// Deletes the saved record and every kept result slip.
  Future<void> clear() async {
    try {
      await _store.delete(_key);
    } catch (_) {}
    await exams.clearSaved();
  }
}
