import 'dart:async';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/network/peoplesoft.dart';

/// A term listed on in4SIT's "View My Exam Results" page.
class ExamTerm {
  /// Row number in the term grid; selecting it is how a term is picked.
  final int index;
  final String name; // e.g. "2025/26 Trimester 1"
  final String career; // e.g. "Undergraduate"
  final String institution;

  const ExamTerm({required this.index, required this.name, this.career = '', this.institution = ''});
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

  String? value(String label) {
    for (final (l, v) in [...standing, ...details]) {
      if (l.toLowerCase() == label.toLowerCase()) return v;
    }
    return null;
  }
}

/// Reads "View My Exam Results" on in4SIT. The page is stateful on the server
/// (PeopleSoft), so requests run one at a time, and each term's results are
/// fetched from a freshly opened page: open, View, pick the term, Continue.
class ExamService {
  final AuthService auth;

  ExamService(this.auth);

  static final pageUrl =
      Uri.parse('https://in4sit.singaporetech.edu.sg/psc/CSSISSTD/EMPLOYEE/SA/c/N_MANAGE_EXAMS.N_RSLT_SLIP_COMP.GBL');
  static const viewAction = 'N_RSLT_SLIP_WRK_VIEW_PB';
  static const continueAction = r'N_RSLT_SLIP_WRK_CONTINUE_PB$0';
  static const termRadio = r'N_EX_PRVRSL_TBL$sels$0';

  Future<void> _tail = Future.value();
  final Map<String, ExamResults> _cache = {};

  /// The terms that have results, latest first.
  Future<List<ExamTerm>> terms({void Function(MfaChallenge)? onMfaChallenge}) {
    return _serial(() async {
      final (_, terms) = await _openTermList(onMfaChallenge);
      return terms.reversed.toList();
    });
  }

  /// The results for [term]. Cached for the session; pass [refresh] to fetch
  /// again.
  Future<ExamResults> results(ExamTerm term, {bool refresh = false, void Function(MfaChallenge)? onMfaChallenge}) {
    return _serial(() async {
      final cached = _cache[term.name];
      if (cached != null && !refresh) return cached;

      final (page, terms) = await _openTermList(onMfaChallenge);
      // Rows can shift between visits; find the term by name.
      final row = terms.firstWhere((t) => t.name == term.name, orElse: () => term);
      // The browser sends the picked row under the radio's id
      // (N_EX_PRVRSL_TBL$sels$2$$0 = 2); the radio's name is sent too.
      final body = await page.press(continueAction, fields: {
        termRadio: '${row.index}',
        'N_EX_PRVRSL_TBL\$sels\$${row.index}\$\$0': '${row.index}',
      });
      final results = parseExamResults(body, term);
      _cache[term.name] = results;
      return results;
    });
  }

  /// Opens the page and gets to the term list (pressing View if the page
  /// doesn't show it straight away).
  Future<(PeopleSoftPage, List<ExamTerm>)> _openTermList(void Function(MfaChallenge)? onMfaChallenge) async {
    final page = PeopleSoftPage(auth, pageUrl);
    final opened = await page.open(onMfaChallenge: onMfaChallenge);
    var terms = parseExamTerms(opened);
    if (terms.isEmpty) {
      terms = parseExamTerms(await page.press(viewAction));
    }
    if (terms.isEmpty) {
      auth.note('Exam results: no term list. Page: ${describeHtmlPage(unwrapPeopleSoft(opened))}');
      throw Exception('in4SIT did not show the list of terms.');
    }
    return (page, terms);
  }

  Future<T> _serial<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }
}

/// The terms in the "Select a Term then click Continue" grid.
List<ExamTerm> parseExamTerms(String body) {
  final doc = parser.parse(unwrapPeopleSoft(body));
  final byId = elementsById(doc);
  final terms = <ExamTerm>[];
  for (final radio in doc.querySelectorAll('input[type="radio"]')) {
    if (radio.attributes['name'] != ExamService.termRadio) continue;
    final index = int.tryParse(radio.attributes['value'] ?? '');
    if (index == null) continue;
    String field(String id) {
      final el = byId['$id\$$index'];
      return el == null ? '' : cellText(el);
    }

    final name = field('N_XM_RSLT_WRK_DESCR');
    if (name.isEmpty) continue;
    terms.add(ExamTerm(
      index: index,
      name: name,
      career: field('N_XM_RSLT_WRK_DESCR1'),
      institution: field('N_XM_RSLT_WRK_INSTITUTION'),
    ));
  }
  return terms;
}

/// Reads a result slip. Its content is plain HTML tables inside an HTML
/// area: "label : value" rows (student details, GPA), a heading such as
/// "AY 2025/26 Trimester 3", and the course table, which is read by column
/// name. The grade legend at the bottom is skipped.
ExamResults parseExamResults(String body, ExamTerm term) {
  final doc = parser.parse(unwrapPeopleSoft(body));

  // "Label : value" rows, written as three <th> cells.
  final pairs = <(String, String)>[];
  for (final tr in doc.querySelectorAll('tr')) {
    final th = _cells(tr, 'th');
    if (th.length != 3 || cellText(th[1]) != ':') continue;
    final label = cellText(th[0]);
    final value = cellText(th[2]);
    if (label.isNotEmpty) pairs.add((label, value));
  }
  bool isStanding((String, String) p) => RegExp(r'gpa|standing', caseSensitive: false).hasMatch(p.$1);

  // The course table: a header row naming "Course Code".
  final courses = <CourseResult>[];
  for (final table in doc.querySelectorAll('table')) {
    final rows = _ownRows(table);
    if (rows.isEmpty) continue;
    final headers = _cells(rows.first, 'th').map((h) => cellText(h).toLowerCase()).toList();
    if (!headers.any((h) => h.contains('course code'))) continue;

    int col(String name) => headers.indexWhere((h) => h.contains(name));
    final iCode = col('course code'), iTitle = col('title'), iCredits = col('credit');
    final iPoints = col('grade point'), iRemark = col('remark');
    final iGrade = headers
        .indexWhere((h) => h == 'grade' || (h.startsWith('grade') && !h.contains('point') && !h.contains('remark')));

    for (final tr in rows.skip(1)) {
      final cells = _cells(tr, 'td').map(cellText).toList();
      String at(int i) => i >= 0 && i < cells.length ? cells[i] : '';
      if (at(iCode).isEmpty) continue;
      courses.add(CourseResult(
        code: at(iCode),
        title: at(iTitle),
        credits: at(iCredits),
        gradePoints: at(iPoints),
        grade: at(iGrade),
        remark: at(iRemark),
      ));
    }
    break;
  }

  final heading = doc.querySelectorAll('u strong, strong u').map(cellText).firstWhere(
        (t) => RegExp(r'trimester|term|semester|AY ', caseSensitive: false).hasMatch(t),
        orElse: () => term.name,
      );
  final note = doc
      .querySelectorAll('font[color]')
      .where((f) => (f.attributes['color'] ?? '').toUpperCase().contains('FF0000'))
      .map(cellText)
      .where((t) => t.isNotEmpty)
      .firstOrNull;

  return ExamResults(
    term: term,
    heading: heading,
    courses: courses,
    standing: pairs.where(isStanding).toList(),
    details: pairs.where((p) => !isStanding(p)).toList(),
    note: note?.replaceFirst(RegExp(r'^\*\s*'), ''),
    pageText: courses.isEmpty ? cellText(doc.body ?? doc.documentElement!) : null,
  );
}

/// The table's own rows, not those of tables nested inside it. The slip sits
/// inside PeopleSoft's layout tables, whose rows contain every other table.
List<dom.Element> _ownRows(dom.Element table) => [
      for (final tr in table.querySelectorAll('tr'))
        if (_closestTable(tr) == table) tr
    ];

/// A row's own cells of [tag] (th or td), not those of nested tables.
List<dom.Element> _cells(dom.Element tr, String tag) => [
      for (final c in tr.children)
        if (c.localName == tag) c
    ];

dom.Element? _closestTable(dom.Element el) {
  for (var p = el.parent; p != null; p = p.parent) {
    if (p.localName == 'table') return p;
  }
  return null;
}
