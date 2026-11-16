import 'package:resit/features/exams/domain/exam_results.dart';

/// One term's numbers, for the progress charts.
class TermSummary {
  /// Short label for a chart axis, e.g. "T1 25/26".
  final String label;
  final String name; // e.g. "AY 2025/26 Trimester 1"
  final double? termGpa;
  final double? cumulativeGpa;

  /// Credits earned from courses graded on this term's slip.
  final double creditsEarned;

  const TermSummary({
    required this.label,
    required this.name,
    this.termGpa,
    this.cumulativeGpa,
    this.creditsEarned = 0,
  });

  Map<String, Object?> toJson() => {
        'label': label,
        'name': name,
        'termGpa': termGpa,
        'cumulativeGpa': cumulativeGpa,
        'creditsEarned': creditsEarned,
      };

  factory TermSummary.fromJson(Map<String, Object?> j) => TermSummary(
        label: j['label'] as String? ?? '',
        name: j['name'] as String? ?? '',
        termGpa: (j['termGpa'] as num?)?.toDouble(),
        cumulativeGpa: (j['cumulativeGpa'] as num?)?.toDouble(),
        creditsEarned: (j['creditsEarned'] as num?)?.toDouble() ?? 0,
      );
}

/// "T1 25/26" from "AY 2025/26 Trimester 1" (or the name as is).
String shortTermLabel(String name) {
  final m = RegExp(r'(\d{2})(\d{2})\s*/\s*(\d{2}).*?(?:Trimester|Term|Semester)\s*(\d)', caseSensitive: false)
      .firstMatch(name);
  return m == null ? name : 'T${m[4]} ${m[2]}/${m[3]}';
}

/// Grades in the order they're shown, best first.
const gradeOrder = ['A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'D+', 'D', 'F'];

/// Totals across every released result slip, for the Home dashboard.
class AcademicRecord {
  /// Credits of courses passed with a grade (letter grades A–D, pass,
  /// exemption or credit transfer).
  final double creditsEarned;

  /// Credits of courses still in progress (IP).
  final double creditsInProgress;
  final int coursesPassed;
  final String? cumulativeGpa;
  final String? latestTermGpa;

  /// The newest term with released results, e.g. "AY 2025/26 Trimester 3".
  final String? latestTerm;
  final String? programme;
  final String? admitTerm;
  final DateTime fetchedAt;

  /// Each released term, oldest first.
  final List<TermSummary> terms;

  /// How many courses got each letter grade (newest attempt of each course).
  final Map<String, int> gradeCounts;

  const AcademicRecord({
    required this.creditsEarned,
    required this.creditsInProgress,
    required this.coursesPassed,
    this.cumulativeGpa,
    this.latestTermGpa,
    this.latestTerm,
    this.programme,
    this.admitTerm,
    required this.fetchedAt,
    this.terms = const [],
    this.gradeCounts = const {},
  });

  /// Adds up [slips], newest first.
  factory AcademicRecord.fromSlips(List<ExamResults> slips, DateTime fetchedAt) {
    var earned = 0.0, inProgress = 0.0, passed = 0;
    final grades = <String, int>{};
    final termCredits = <ExamResults, double>{};
    // A course can appear on several slips (e.g. in progress, then graded);
    // its newest entry counts.
    final seen = <String>{};
    for (final slip in slips) {
      for (final c in slip.courses) {
        if (!seen.add(c.code)) continue;
        final credits = double.tryParse(c.credits) ?? 0;
        if (c.inProgress) {
          inProgress += credits;
        } else if (isPassingGrade(c.grade)) {
          earned += credits;
          passed++;
          termCredits[slip] = (termCredits[slip] ?? 0) + credits;
        }
        final g = c.grade.trim().toUpperCase();
        if (gradeOrder.contains(g)) grades[g] = (grades[g] ?? 0) + 1;
      }
    }
    double? number(String? v) => v == null ? null : double.tryParse(v.trim());
    final latest = slips.isEmpty ? null : slips.first;
    String? find(String label) {
      for (final s in slips) {
        final v = s.value(label);
        if (v != null && v.isNotEmpty && v != '-') return v;
      }
      return null;
    }

    return AcademicRecord(
      creditsEarned: earned,
      creditsInProgress: inProgress,
      coursesPassed: passed,
      cumulativeGpa: latest?.value('Cumulative GPA'),
      latestTermGpa: latest?.value('Trimester GPA'),
      latestTerm: latest?.heading,
      programme: find('Programme'),
      admitTerm: find('Admit Term'),
      fetchedAt: fetchedAt,
      terms: [
        for (final slip in slips.reversed)
          TermSummary(
            label: shortTermLabel(slip.heading),
            name: slip.heading,
            termGpa: number(slip.value('Trimester GPA')),
            cumulativeGpa: number(slip.value('Cumulative GPA')),
            creditsEarned: termCredits[slip] ?? 0,
          ),
      ],
      gradeCounts: grades,
    );
  }

  Map<String, Object?> toJson() => {
        'creditsEarned': creditsEarned,
        'creditsInProgress': creditsInProgress,
        'coursesPassed': coursesPassed,
        'cumulativeGpa': cumulativeGpa,
        'latestTermGpa': latestTermGpa,
        'latestTerm': latestTerm,
        'programme': programme,
        'admitTerm': admitTerm,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
        'terms': [for (final t in terms) t.toJson()],
        'gradeCounts': gradeCounts,
      };

  factory AcademicRecord.fromJson(Map<String, Object?> j) => AcademicRecord(
        creditsEarned: (j['creditsEarned'] as num?)?.toDouble() ?? 0,
        creditsInProgress: (j['creditsInProgress'] as num?)?.toDouble() ?? 0,
        coursesPassed: (j['coursesPassed'] as num?)?.toInt() ?? 0,
        cumulativeGpa: j['cumulativeGpa'] as String?,
        latestTermGpa: j['latestTermGpa'] as String?,
        latestTerm: j['latestTerm'] as String?,
        programme: j['programme'] as String?,
        admitTerm: j['admitTerm'] as String?,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch((j['fetchedAt'] as num?)?.toInt() ?? 0),
        terms: [
          for (final t in (j['terms'] as List?) ?? const []) TermSummary.fromJson((t as Map).cast<String, Object?>()),
        ],
        gradeCounts: {
          for (final e in ((j['gradeCounts'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt(),
        },
      );
}

/// Grades that earn the course's credits: letter grades A to D (with + or -),
/// pass, exemption and credit transfer. Not F, in progress, withdrawn or
/// absent.
bool isPassingGrade(String grade) {
  final g = grade.trim().toUpperCase();
  if (g.isEmpty) return false;
  if (RegExp(r'^[A-D][+\-]?$').hasMatch(g)) return true;
  if (const {'P', 'PASS', 'S', 'EX', 'TC', 'CS', 'D^'}.contains(g)) return true;
  if (g.contains('#')) return true; // credit transfer within SIT
  return false;
}
