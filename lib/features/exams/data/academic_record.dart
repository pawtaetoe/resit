import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:resit/features/common/data/private_store.dart';
import 'package:resit/sites/in4sit/exam_service.dart';

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
