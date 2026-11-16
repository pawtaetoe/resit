import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/in4sit/peoplesoft.dart';
import 'package:resit/features/exams/domain/exam_results.dart';

// Reading in4SIT's "View My Exam Results" page: the term list and a term's
// result slip. Pure functions of the HTML, so they can run on an isolate
// and are tested on saved pages.

/// The page's View button ("View Other Term" on a result slip), which goes
/// back to the term list.
const examViewAction = 'N_RSLT_SLIP_WRK_VIEW_PB';

/// The name of the term list's radio buttons.
const examTermRadio = r'N_EX_PRVRSL_TBL$sels$0';

/// The term list on a parsed page, and a description of the page when it
/// has none (for troubleshooting). Pure, so it can run on an isolate.
({List<ExamTerm> terms, String? description}) readExamTermList(dom.Document doc, String html) {
  final terms = parseExamTermsDoc(doc);
  // The page's structure only: its text can include the student's name and ID.
  return (terms: terms, description: terms.isEmpty ? describeHtmlPage(html, includeText: false) : null);
}

typedef ExamSlipReply = ({ExamResults results, bool isSlip});

const _noTerm = ExamTerm(index: -1, name: '');

/// The slip on a parsed reply, and whether the reply is the result slip
/// page at all (it has the "View Other Term" link). Pure.
ExamSlipReply readExamSlip(dom.Document doc, String html) => (
      results: parseExamResultsDoc(doc, _noTerm),
      isSlip: html.contains(examViewAction) || html.contains('Result Slip'),
    );

/// The terms in the "Select a Term then click Continue" grid.
List<ExamTerm> parseExamTerms(String body) => parseExamTermsDoc(parser.parse(unwrapPeopleSoft(body)));

/// [parseExamTerms] for an already parsed page.
List<ExamTerm> parseExamTermsDoc(dom.Document doc) {
  final byId = elementsById(doc);
  final terms = <ExamTerm>[];
  for (final radio in doc.querySelectorAll('input[type="radio"]')) {
    if (radio.attributes['name'] != examTermRadio) continue;
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
ExamResults parseExamResults(String body, ExamTerm term) =>
    parseExamResultsDoc(parser.parse(unwrapPeopleSoft(body)), term);

/// [parseExamResults] for an already parsed page.
ExamResults parseExamResultsDoc(dom.Document doc, ExamTerm term) {

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
