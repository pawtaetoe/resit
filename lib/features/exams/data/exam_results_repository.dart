import 'dart:async';

import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/in4sit/exam_service.dart';
import 'package:resit/features/exams/domain/exam_results.dart';
import 'package:resit/features/exams/data/exam_slip_store.dart';

/// The exam results the app shows: in4SIT's result slips, read through
/// [ExamService], with released slips kept on the device ([ExamSlipStore])
/// and the others kept for the session.
///
/// Each call looks in its copies and reads from in4SIT in one turn of the
/// service's queue, so a call waiting behind another read of the same term
/// gets that copy instead of asking in4SIT again.
class ExamResultsRepository {
  final ExamService _exams;

  /// Released slips kept on the device.
  final ExamSlipStore _slips;

  /// Slips read this session, released or not, by term name.
  final Map<String, ExamResults> _session = {};

  ExamResultsRepository(this._exams, {ExamSlipStore? slips}) : _slips = slips ?? ExamSlipStore();

  /// The terms that have results, latest first.
  Future<List<ExamTerm>> terms({void Function(MfaChallenge)? onMfaChallenge}) {
    return _exams.queue.run(() async {
      final latestFirst = await _exams.readTerms(onMfaChallenge: onMfaChallenge);
      unawaited(_slips.saveTerms(latestFirst));
      return latestFirst;
    });
  }

  /// The term list last read, latest first, to show before [terms] answers.
  Future<List<ExamTerm>> savedTerms() => _slips.terms();

  /// The released slip kept on the device for the term named [termName], if
  /// any (see [ExamSlipStore.slip]).
  Future<ExamResults?> savedSlip(String termName) => _slips.slip(termName);

  /// The results for [term]. A released slip is kept on the device and
  /// returned from there; others are kept for the session. Pass [refresh] to
  /// read it from in4SIT again.
  Future<ExamResults> results(ExamTerm term, {bool refresh = false, void Function(MfaChallenge)? onMfaChallenge}) {
    return _exams.queue.run(() async {
      if (!refresh) {
        final cached = _session[term.name] ?? await _slips.slip(term.name);
        if (cached != null) return cached.withTerm(term);
      }
      final results = await _exams.readResults(term, onMfaChallenge: onMfaChallenge);
      _session[term.name] = results;
      await _slips.save(results);
      return results;
    });
  }

  /// Forgets every slip kept, in memory and on the device.
  Future<void> clearSaved() async {
    _session.clear();
    _exams.closePage();
    await _slips.clear();
  }
}
