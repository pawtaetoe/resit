import 'dart:convert';

import 'package:resit/features/lms/domain/results.dart';
import 'package:resit/sites/xsite/brightspace_json.dart';

// Reading your results on xSiTe (assignment feedback, rubric assessments,
// quiz attempts) from Brightspace's documented "Valence" API replies.

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
double? _double(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
String _str(Object? v) => v is String ? v.trim() : '';
Map<String, Object?>? _map(Object? v) => v is Map ? v.cast<String, Object?>() : null;
List<Map<String, Object?>> _maps(Object? v) => [
      if (v is List)
        for (final o in v)
          if (o is Map) o.cast<String, Object?>(),
    ];

Object? _json(String body) => jsonDecode(stripGuard(body));

/// The rows of a reply: a bare array, or an ObjectListPage's "Objects".
List<Map<String, Object?>> _rows(Object? json) => _maps(json is Map ? (json['Objects'] ?? json['Items']) : json);

/// A reply that is one JSON object, or null.
Map<String, Object?>? decodeObject(String body) => _map(_json(body));

// --- Assignment feedback

/// Whether a DropboxFeedbackOut block is released to you: xSiTe sends draft
/// feedback with `IsGraded: false`, so only `true` counts.
bool isReleased(Map<String, Object?> feedback) => feedback['IsGraded'] == true;

/// Your EntityDropbox blocks from `mysubmissions`: who submitted (you or
/// your group) and the feedback block on them, if any.
List<({FeedbackEntity? entity, Map<String, Object?>? feedback})> parseEntityDropboxes(String body) => [
      for (final j in _rows(_json(body)))
        (entity: _entity(j['Entity']), feedback: _map(j['Feedback'])),
    ];

FeedbackEntity? _entity(Object? v) {
  final e = _map(v);
  final id = e?['EntityId'];
  if (e == null || (id is! num && id is! String) || '$id'.isEmpty) return null;
  return FeedbackEntity(isGroup: _str(e['EntityType']).toLowerCase() == 'group', id: '$id');
}

/// The rubric ids a feedback block's rubric assessments refer to.
Set<int> rubricIdsIn(Map<String, Object?> feedback) => {
      for (final r in _maps(feedback['RubricAssessments']))
        if (_int(r['RubricId']) case final id?) id,
    };

/// A released feedback block (DropboxFeedbackOut) as the app shows it, or
/// null if it isn't released. [rubrics] names the criteria and levels where
/// the rubric could be read.
AssignmentFeedback? feedbackFromJson(
  Map<String, Object?> j, {
  FeedbackEntity? entity,
  Map<int, RubricDefinition> rubrics = const {},
}) {
  if (!isReleased(j)) return null;
  final symbol = _str(j['GradedSymbol']);
  final feedback = AssignmentFeedback(
    score: _double(j['Score']),
    symbol: symbol.isEmpty ? null : symbol,
    comments: richText(j['Feedback']),
    rubrics: [
      for (final r in _maps(j['RubricAssessments']))
        if (_rubricResult(r, rubrics[_int(r['RubricId'])]) case final result?) result,
    ],
    attachments: [
      for (final f in _maps(j['Files']))
        if (_str(f['FileName']) case final name when name.isNotEmpty) name,
      for (final l in _maps(j['Links']))
        if (_str(l['LinkName']) case final name when name.isNotEmpty) name,
    ],
    entity: entity,
  );
  return feedback.isEmpty ? null : feedback;
}

RubricResult? _rubricResult(Map<String, Object?> r, RubricDefinition? def) {
  if (def != null && !def.visible) return null;
  final overall = _map(r['OverallOutcome']);
  final outcomes = _maps(r['CriteriaOutcome']);
  if (def != null) outcomes.sort((a, b) => def.order(_int(a['CriterionId'])).compareTo(def.order(_int(b['CriterionId']))));
  final criteria = [
    for (final (i, c) in outcomes.indexed)
      RubricCriterionResult(
        criterion: def?.criteria[_int(c['CriterionId'])] ?? 'Criterion ${i + 1}',
        level: def?.levels[_int(c['LevelId'])],
        score: _double(c['Score']),
        outOf: def?.outOf[_int(c['CriterionId'])],
        feedback: richText(c['Feedback']),
      ),
  ];
  final result = RubricResult(
    name: def?.name ?? 'Rubric',
    overallLevel: def?.overallLevels[_int(overall?['LevelId'])],
    score: _double(overall?['Score']),
    feedback: richText(overall?['Feedback']),
    criteria: criteria,
    showScores: def?.showScores ?? true,
  );
  final empty = criteria.isEmpty && result.overallLevel == null && result.score == null && result.feedback.isEmpty;
  return empty ? null : result;
}

/// What the app needs from a rubric's definition: names for its criteria
/// and levels, the most each criterion scores, and whether students may see
/// it and its scores.
class RubricDefinition {
  final int id;
  final String name;
  final bool visible;
  final bool showScores;
  final Map<int, String> criteria;
  final Map<int, double> outOf;
  final Map<int, String> levels;
  final Map<int, String> overallLevels;
  final List<int> _order;

  RubricDefinition({
    required this.id,
    required this.name,
    this.visible = true,
    this.showScores = true,
    this.criteria = const {},
    this.outOf = const {},
    this.levels = const {},
    this.overallLevels = const {},
    List<int> order = const [],
  }) : _order = order;

  /// Where a criterion comes in the rubric (unknown ones last).
  int order(int? criterionId) {
    final i = criterionId == null ? -1 : _order.indexOf(criterionId);
    return i < 0 ? _order.length : i;
  }
}

/// Rubrics (Rubric blocks) from `/rubrics/?objectType=…&objectId=…`.
List<RubricDefinition> parseRubrics(String body) {
  final out = <RubricDefinition>[];
  for (final j in _rows(_json(body))) {
    final id = _int(j['RubricId']);
    if (id == null) continue;
    final criteria = <int, String>{}, outOf = <int, double>{}, levels = <int, String>{}, order = <int>[];
    for (final g in _maps(j['CriteriaGroups'])) {
      final levelPoints = <double>[];
      for (final l in _maps(g['Levels'])) {
        if (_int(l['Id']) case final lid?) levels[lid] = _str(l['Name']);
        if (_double(l['Points']) case final p?) levelPoints.add(p);
      }
      for (final c in _maps(g['Criteria'])) {
        final cid = _int(c['Id']);
        if (cid == null) continue;
        order.add(cid);
        criteria[cid] = _str(c['Name']).isEmpty ? 'Criterion ${order.length}' : _str(c['Name']);
        final points = [
          for (final cell in _maps(c['Cells']))
            if (_double(cell['Points']) case final p?) p,
        ];
        final all = points.isNotEmpty ? points : levelPoints;
        if (all.isNotEmpty) outOf[cid] = all.reduce((a, b) => a > b ? a : b);
      }
    }
    out.add(RubricDefinition(
      id: id,
      name: _str(j['Name']).isEmpty ? 'Rubric' : _str(j['Name']),
      // VISIBILITY_M: 2 = never visible to the people assessed.
      visible: _int(j['Visibility']) != 2,
      showScores: j['IsScoreVisibleToAssessedUsers'] != false,
      criteria: criteria,
      outOf: outOf,
      levels: levels,
      overallLevels: {
        for (final l in _maps(j['OverallLevels']))
          if (_int(l['Id']) case final lid?) lid: _str(l['Name']),
      },
      order: order,
    ));
  }
  return out;
}

// --- Quiz attempts

/// Your attempts at a quiz (QuizAttemptData blocks in an ObjectListPage) and
/// the next page's address. Scores and feedback are kept only for attempts
/// xSiTe has released (`IsPublished`). Rows for another user than [userId]
/// (when given) are left out.
({List<QuizAttempt> attempts, String? next}) parseQuizAttempts(String body, {String userId = ''}) {
  final json = _json(body);
  final attempts = <QuizAttempt>[];
  for (final j in _rows(json)) {
    final number = _int(j['AttemptNumber']);
    if (number == null) continue;
    final user = j['UserId'];
    if (userId.isNotEmpty && user != null && '$user' != userId) continue;
    final released = j['IsPublished'] == true;
    attempts.add(QuizAttempt(
      number: number,
      started: _date(j['Started']),
      completed: _date(j['Completed']),
      released: released,
      score: released ? _double(j['Score']) : null,
      feedback: released ? richText(j['AttemptFeedback']) : '',
    ));
  }
  attempts.sort((a, b) => a.number.compareTo(b.number));
  final next = json is Map ? json['Next'] : null;
  return (attempts: attempts, next: next is String && next.isNotEmpty ? next : null);
}
