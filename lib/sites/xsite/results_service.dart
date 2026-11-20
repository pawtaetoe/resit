import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/results.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/xsite/results_parsers.dart';
import 'package:resit/sites/xsite/xsite_client.dart';
import 'package:resit/sites/xsite/xsite_service.dart';

/// Reads your results on xSiTe: released feedback on assignments (with
/// rubric results) and your quiz attempts. GETs only, through the shared
/// xSiTe client and its request limit.
class XsiteResults {
  static const _le = '$xsiteBase/d2l/api/le/1.75';

  /// Rubric definitions only exist from LE 1.93.
  static const _rubricsLe = '$xsiteBase/d2l/api/le/1.93';

  final XsiteClient _xsite;
  final Future<String> Function(void Function(MfaChallenge)?) _myId;

  /// [myId] gives your xSiTe user id (from /users/whoami).
  XsiteResults(this._xsite, {required Future<String> Function(void Function(MfaChallenge)?) myId}) : _myId = myId;

  Future<String> _get(Uri url, void Function(MfaChallenge)? onMfaChallenge) =>
      _xsite.getJson(url, onMfaChallenge, limited: true);

  /// Your released feedback on an assignment, or null if there is none yet.
  ///
  /// `mysubmissions` carries published feedback with your submissions; when
  /// it has none (e.g. nothing submitted), the folder's feedback entry for
  /// you (or your group) is asked for directly. Either way only feedback
  /// marked graded is kept. Rubric names come from the folder's rubrics when
  /// xSiTe lets students read them.
  Future<AssignmentFeedback?> feedback(Assignment a, {void Function(MfaChallenge)? onMfaChallenge}) async {
    final folder = '$_le/${a.orgUnitId}/dropbox/folders/${a.id}';
    var mine = const <({FeedbackEntity? entity, Map<String, Object?>? feedback})>[];
    try {
      mine = parseEntityDropboxes(await _get(Uri.parse('$folder/submissions/mysubmissions/'), onMfaChallenge));
    } on LmsUnavailableException {
      // Submissions closed to the app: the feedback entry may still be readable.
    }

    FeedbackEntity? entity;
    Map<String, Object?>? block;
    for (final e in mine) {
      entity ??= e.entity;
      final f = e.feedback;
      if (f != null && isReleased(f)) {
        block = f;
        entity = e.entity ?? entity;
        break;
      }
    }
    if (block == null) {
      if (entity == null && !a.isGroup) {
        final me = await _myId(onMfaChallenge);
        if (me.isNotEmpty) entity = FeedbackEntity(isGroup: false, id: me);
      }
      if (entity == null) return null;
      try {
        final type = entity.isGroup ? 'group' : 'user';
        final f = decodeObject(await _get(Uri.parse('$folder/feedback/$type/${Uri.encodeComponent(entity.id)}'), onMfaChallenge));
        if (f != null && isReleased(f)) block = f;
      } on LmsUnavailableException {
        // No feedback entry (404) or not for students to read (403).
      }
    }
    if (block == null) return null;

    final rubrics = <int, RubricDefinition>{};
    if (rubricIdsIn(block).isNotEmpty) {
      try {
        final url = Uri.parse('$_rubricsLe/${a.orgUnitId}/rubrics/')
            .replace(queryParameters: {'objectType': 'Dropbox', 'objectId': '${a.id}'});
        for (final r in parseRubrics(await _get(url, onMfaChallenge))) {
          rubrics[r.id] = r;
        }
      } catch (_) {
        // Rubric closed to students, or this xSiTe is older: results show
        // without criterion names.
      }
    }
    return feedbackFromJson(block, entity: entity, rubrics: rubrics);
  }

  /// Your attempts at a quiz, first attempt first. Scores and feedback only
  /// for attempts whose results xSiTe has released.
  Future<List<QuizAttempt>> quizAttempts(Quiz q, {void Function(MfaChallenge)? onMfaChallenge}) async {
    final me = await _myId(onMfaChallenge);
    final all = <QuizAttempt>[];
    Uri? url = Uri.parse('$_le/${q.orgUnitId}/quizzes/${q.id}/attempts/')
        .replace(queryParameters: me.isEmpty ? null : {'userId': me});
    for (var page = 0; page < 10 && url != null; page++) {
      final parsed = parseQuizAttempts(await _get(url, onMfaChallenge), userId: me);
      all.addAll(parsed.attempts);
      final next = parsed.next;
      url = next == null ? null : LmsService.onXsite(next);
    }
    return all..sort((a, b) => a.number.compareTo(b.number));
  }
}
