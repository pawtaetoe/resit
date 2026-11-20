import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';

/// Who an assignment's feedback is for: you, or your group.
class FeedbackEntity {
  final bool isGroup;
  final String id;
  const FeedbackEntity({required this.isGroup, required this.id});
}

/// One criterion's result on a rubric.
class RubricCriterionResult {
  /// The criterion's name, or "Criterion n" when the rubric couldn't be read.
  final String criterion;

  /// The level awarded (e.g. "Proficient"), when known.
  final String? level;
  final double? score;

  /// The most the criterion can score, when known.
  final double? outOf;
  final String feedback;

  const RubricCriterionResult({
    required this.criterion,
    this.level,
    this.score,
    this.outOf,
    this.feedback = '',
  });
}

/// A rubric assessment of your work.
class RubricResult {
  /// The rubric's name ("Rubric" when it couldn't be read).
  final String name;
  final String? overallLevel;
  final double? score;
  final String feedback;
  final List<RubricCriterionResult> criteria;

  /// False when the rubric says scores aren't shown to the people assessed.
  final bool showScores;

  const RubricResult({
    required this.name,
    this.overallLevel,
    this.score,
    this.feedback = '',
    this.criteria = const [],
    this.showScores = true,
  });
}

/// Released feedback on an assignment: score, comments, rubric results and
/// attachment names. Only feedback xSiTe marks as released (graded) is ever
/// built.
class AssignmentFeedback {
  final double? score;

  /// The grade scheme symbol, when the folder's grade uses one (e.g. "A").
  final String? symbol;

  /// The instructor's comments, as plain text.
  final String comments;
  final List<RubricResult> rubrics;

  /// Names of attached files and links (opened on xSiTe).
  final List<String> attachments;
  final FeedbackEntity? entity;

  const AssignmentFeedback({
    this.score,
    this.symbol,
    this.comments = '',
    this.rubrics = const [],
    this.attachments = const [],
    this.entity,
  });

  bool get isEmpty =>
      score == null && (symbol ?? '').isEmpty && comments.isEmpty && rubrics.isEmpty && attachments.isEmpty;

  /// The score in one line, e.g. "17 / 20" or "A (17 / 20)".
  String scoreLabel(double? outOf) {
    final s = score;
    final points = s == null ? null : (outOf != null && outOf > 0 ? '${fmtNumber(s)} / ${fmtNumber(outOf)}' : fmtNumber(s));
    final sym = symbol?.trim() ?? '';
    if (sym.isNotEmpty) return points == null ? sym : '$sym ($points)';
    return points ?? '–';
  }
}

/// "17", "8.5", "8.25": a score without needless decimals.
String fmtNumber(double v) {
  if (v == v.roundToDouble()) return '${v.round()}';
  final s = v.toStringAsFixed(2);
  return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
}

/// xSiTe's page with your feedback on an assignment (attachments open there).
Uri feedbackPage(Assignment a, [FeedbackEntity? entity]) {
  final group = entity != null && entity.isGroup ? entity.id : '0';
  return Uri.parse(
      '$xsiteBase/d2l/lms/dropbox/user/folder_user_view_feedback.d2l?db=${a.id}&grpid=$group&isprv=0&bp=0&ou=${a.orgUnitId}');
}

/// One of your attempts at a quiz.
class QuizAttempt {
  final int number;
  final DateTime? started;

  /// Null while the attempt is still in progress.
  final DateTime? completed;

  /// Whether xSiTe has released the attempt's results to you. [score] and
  /// [feedback] are only kept when it has.
  final bool released;
  final double? score;
  final String feedback;

  const QuizAttempt({
    required this.number,
    this.started,
    this.completed,
    this.released = false,
    this.score,
    this.feedback = '',
  });

  bool get inProgress => completed == null;
}
