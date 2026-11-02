import 'dart:convert';

import 'package:resit/features/exams/data/exam_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  /// Adds up [slips], newest first.
  factory AcademicRecord.fromSlips(List<ExamResults> slips, DateTime fetchedAt) {
    var earned = 0.0, inProgress = 0.0, passed = 0;
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
        }
      }
    }
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

/// Builds the [AcademicRecord] from in4SIT's result slips and keeps a copy,
/// so Home shows it instantly and only re-reads in4SIT once a day.
class AcademicRecordService {
  static const _key = 'academic_record';
  static const maxAge = Duration(days: 1);

  final ExamService exams;

  AcademicRecordService(this.exams);

  Future<AcademicRecord?> saved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      return raw == null ? null : AcademicRecord.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  /// The saved record if it's recent; otherwise reads every released slip
  /// (one at a time) and saves the totals. Falls back to the saved record
  /// if in4SIT can't be reached.
  Future<AcademicRecord?> load({bool force = false}) async {
    final cached = await saved();
    if (!force && cached != null && DateTime.now().difference(cached.fetchedAt) < maxAge) return cached;
    try {
      final terms = await exams.terms(); // newest first
      final slips = <ExamResults>[];
      for (final term in terms) {
        final slip = await exams.results(term, refresh: force);
        if (!slip.notReleased && slip.courses.isNotEmpty) slips.add(slip);
      }
      final record = AcademicRecord.fromSlips(slips, DateTime.now());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(record.toJson()));
      return record;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
