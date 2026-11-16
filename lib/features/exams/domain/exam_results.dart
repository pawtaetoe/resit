/// A term listed on in4SIT's "View My Exam Results" page.
class ExamTerm {
  /// Row number in the term grid; selecting it is how a term is picked.
  final int index;
  final String name; // e.g. "2025/26 Trimester 1"
  final String career; // e.g. "Undergraduate"
  final String institution;

  const ExamTerm({required this.index, required this.name, this.career = '', this.institution = ''});

  Map<String, Object?> toJson() => {'index': index, 'name': name, 'career': career, 'institution': institution};

  factory ExamTerm.fromJson(Map<String, Object?> j) => ExamTerm(
        index: (j['index'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        career: j['career'] as String? ?? '',
        institution: j['institution'] as String? ?? '',
      );
}

/// One course on a result slip.
class CourseResult {
  final String code; // e.g. "CSC1106"
  final String title;
  final String credits;
  final String gradePoints;
  final String grade; // e.g. "B+", "IP"
  final String remark;

  const CourseResult({
    required this.code,
    required this.title,
    this.credits = '',
    this.gradePoints = '',
    this.grade = '',
    this.remark = '',
  });

  /// Still in progress, so there's no grade yet.
  bool get inProgress => grade.toUpperCase() == 'IP';

  Map<String, Object?> toJson() => {
        'code': code,
        'title': title,
        'credits': credits,
        'gradePoints': gradePoints,
        'grade': grade,
        'remark': remark,
      };

  factory CourseResult.fromJson(Map<String, Object?> j) => CourseResult(
        code: j['code'] as String? ?? '',
        title: j['title'] as String? ?? '',
        credits: j['credits'] as String? ?? '',
        gradePoints: j['gradePoints'] as String? ?? '',
        grade: j['grade'] as String? ?? '',
        remark: j['remark'] as String? ?? '',
      );
}

/// One term's "Examination Result Slip" from in4SIT.
class ExamResults {
  final ExamTerm term;

  /// The slip's own heading, e.g. "AY 2025/26 Trimester 3".
  final String heading;
  final List<CourseResult> courses;

  /// "Trimester GPA", "Cumulative GPA", "Academic Standing", in page order.
  final List<(String label, String value)> standing;

  /// Student name, admit term, programme, release date and so on.
  final List<(String label, String value)> details;

  /// The slip's note, e.g. about modules yet to be cleared.
  final String? note;

  /// Text of the page when no course table was found, to show and
  /// troubleshoot.
  final String? pageText;

  const ExamResults({
    required this.term,
    required this.heading,
    required this.courses,
    this.standing = const [],
    this.details = const [],
    this.note,
    this.pageText,
  });

  /// in4SIT says this term's results haven't been released yet.
  bool get notReleased =>
      courses.isEmpty && RegExp(r'not (been |yet )?released', caseSensitive: false).hasMatch(pageText ?? '');

  /// A released slip with its courses. Released slips don't change, so these
  /// are kept and not read again (see [ExamSlipStore]).
  bool get released => !notReleased && courses.isNotEmpty;

  String? value(String label) {
    for (final (l, v) in [...standing, ...details]) {
      if (l.toLowerCase() == label.toLowerCase()) return v;
    }
    return null;
  }

  /// The same slip under [term] (e.g. with the term's current row number).
  ExamResults withTerm(ExamTerm term) => ExamResults(
        term: term,
        heading: heading.isEmpty ? term.name : heading,
        courses: courses,
        standing: standing,
        details: details,
        note: note,
        pageText: pageText,
      );

  Map<String, Object?> toJson() => {
        'term': term.toJson(),
        'heading': heading,
        'courses': [for (final c in courses) c.toJson()],
        'standing': [
          for (final (l, v) in standing) [l, v]
        ],
        'details': [
          for (final (l, v) in details) [l, v]
        ],
        'note': note,
        'pageText': pageText,
      };

  factory ExamResults.fromJson(Map<String, Object?> j) {
    List<(String, String)> pairs(Object? list) => [
          for (final p in (list as List?) ?? const [])
            if (p is List && p.length == 2) ('${p[0]}', '${p[1]}')
        ];
    return ExamResults(
      term: ExamTerm.fromJson(((j['term'] as Map?) ?? const {}).cast<String, Object?>()),
      heading: j['heading'] as String? ?? '',
      courses: [
        for (final c in (j['courses'] as List?) ?? const []) CourseResult.fromJson((c as Map).cast<String, Object?>())
      ],
      standing: pairs(j['standing']),
      details: pairs(j['details']),
      note: j['note'] as String?,
      pageText: j['pageText'] as String?,
    );
  }
}

/// Whether a slip's heading ("AY 2025/26 Trimester 3") is for the term named
/// [termName] ("2025/26 Trimester 3"). An empty heading can't be checked and
/// counts as a match.
bool slipMatchesTerm(String heading, String termName) {
  String norm(String s) => s.replaceFirst(RegExp(r'^\s*AY\s*', caseSensitive: false), '').replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  final h = norm(heading);
  return h.isEmpty || termName.trim().isEmpty || h == norm(termName);
}
