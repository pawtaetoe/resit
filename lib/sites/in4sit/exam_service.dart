import 'dart:async';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/in4sit/peoplesoft.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/features/exams/domain/exam_results.dart';
import 'package:resit/features/exams/data/exam_slip_store.dart';

/// Reads "View My Exam Results" on in4SIT. The page is stateful on the server
/// (PeopleSoft), so requests go through the app's one [In4SitQueue]. The page
/// is kept open between calls: the term list, then Continue for a term's
/// slip, then "View Other Term" back to the list for the next one, so going
/// through several terms doesn't reopen the page (and sign in) for each.
class ExamService {
  final AuthService auth;

  /// Shared with every other in4SIT reader, so their requests take turns.
  final In4SitQueue queue;

  /// Released slips kept on the device.
  final ExamSlipStore slips;

  ExamService(this.auth, {In4SitQueue? queue, ExamSlipStore? slips})
      : queue = queue ?? In4SitQueue(),
        slips = slips ?? ExamSlipStore();

  static final pageUrl =
      Uri.parse('https://in4sit.singaporetech.edu.sg/psc/CSSISSTD/EMPLOYEE/SA/c/N_MANAGE_EXAMS.N_RSLT_SLIP_COMP.GBL');
  static const viewAction = 'N_RSLT_SLIP_WRK_VIEW_PB';
  static const continueAction = r'N_RSLT_SLIP_WRK_CONTINUE_PB$0';
  static const termRadio = r'N_EX_PRVRSL_TBL$sels$0';

  /// in4SIT drops a page left idle for about 20 minutes; reopen before then.
  static const _pageLife = Duration(minutes: 15);

  final Map<String, ExamResults> _cache = {};

  PeopleSoftPage? _page;
  DateTime _openedAt = DateTime(0);

  /// The term list the page shows now, or null when it shows a slip.
  List<ExamTerm>? _listed;

  /// The terms that have results, latest first.
  Future<List<ExamTerm>> terms({void Function(MfaChallenge)? onMfaChallenge}) {
    return queue.run(() async {
      final (terms, _) = await _termList(onMfaChallenge);
      final latestFirst = terms.reversed.toList();
      unawaited(slips.saveTerms(latestFirst));
      return latestFirst;
    });
  }

  /// The term list last read, latest first, to show before [terms] answers.
  Future<List<ExamTerm>> savedTerms() => slips.terms();

  /// The results for [term]. A released slip is kept on the device and
  /// returned from there; others are kept for the session. Pass [refresh] to
  /// read it from in4SIT again.
  Future<ExamResults> results(ExamTerm term, {bool refresh = false, void Function(MfaChallenge)? onMfaChallenge}) {
    return queue.run(() async {
      if (!refresh) {
        final cached = _cache[term.name] ?? await slips.slip(term.name);
        if (cached != null) return cached.withTerm(term);
      }
      final results = await _readSlip(term, onMfaChallenge);
      _cache[term.name] = results;
      await slips.save(results);
      return results;
    });
  }

  /// Forgets every slip kept, in memory and on the device.
  Future<void> clearSaved() async {
    _cache.clear();
    _page?.close();
    _page = null;
    _listed = null;
    await slips.clear();
  }

  bool get _pageUsable =>
      _page != null && _page!.isOpen && DateTime.now().difference(_openedAt) < _pageLife;

  /// Picks [term] in the term list and presses Continue. If the page kept
  /// from before turns out to be gone, opens it afresh and tries once more.
  Future<ExamResults> _readSlip(ExamTerm term, void Function(MfaChallenge)? onMfaChallenge) async {
    for (var attempt = 0;; attempt++) {
      final (terms, opened) = await _termList(onMfaChallenge);
      // Rows can shift between visits; find the term by name.
      final row = terms.firstWhere((t) => t.name == term.name, orElse: () => term);
      // The browser sends the picked row under the radio's id
      // (N_EX_PRVRSL_TBL$sels$2$$0 = 2); the radio's name is sent too.
      final ({String body, ExamSlipReply data}) reply;
      try {
        _listed = null;
        // Only this term's row is picked: a row picked on an earlier visit
        // stays in the form, and in4SIT would show that term's slip instead.
        _page!.removeFields((name) => name.startsWith(r'N_EX_PRVRSL_TBL$sels$'));
        reply = await _page!.pressWith(continueAction, readExamSlip, fields: {
          termRadio: '${row.index}',
          'N_EX_PRVRSL_TBL\$sels\$${row.index}\$\$0': '${row.index}',
        });
      } on In4SitHttpException {
        if (opened || attempt > 0) rethrow;
        _page?.close();
        continue;
      }
      if (!reply.data.isSlip && !opened && attempt == 0) {
        auth.note('Exam results: the kept page was gone; reopening');
        _page?.close();
        continue;
      }
      // A slip for another term (its heading names a different one): read
      // it again on a freshly opened page rather than keep the wrong one.
      if (reply.data.isSlip && !slipMatchesTerm(reply.data.results.heading, term.name)) {
        auth.note('Exam results: asked for ${term.name}, got ${reply.data.results.heading}');
        _page?.close();
        _page = null;
        if (attempt > 0) throw Exception('in4SIT showed the slip for another term.');
        continue;
      }
      return reply.data.results.withTerm(term);
    }
  }

  /// The term list, in grid order, and whether the page was opened afresh
  /// for it. Reuses the open page where it can: as is if it shows the list,
  /// or with "View Other Term" if it shows a slip.
  Future<(List<ExamTerm>, bool opened)> _termList(void Function(MfaChallenge)? onMfaChallenge) async {
    final page = _page;
    if (page != null && _pageUsable) {
      final listed = _listed;
      if (listed != null) return (listed, false);
      try {
        final viewed = await page.pressWith(viewAction, readExamTermList);
        if (viewed.data.terms.isNotEmpty) return (_listed = viewed.data.terms, false);
      } catch (_) {
        // Gone; open it afresh below.
      }
    }
    return (await _openTermList(onMfaChallenge), true);
  }

  /// Opens the page and gets to the term list (pressing View if the page
  /// doesn't show it straight away).
  Future<List<ExamTerm>> _openTermList(void Function(MfaChallenge)? onMfaChallenge) async {
    _listed = null;
    final page = _page ??= PeopleSoftPage(auth, pageUrl, queue: queue);
    final opened = await page.openWith(readExamTermList, onMfaChallenge: onMfaChallenge);
    _openedAt = DateTime.now();
    var list = opened.data;
    if (list.terms.isEmpty) {
      list = (await page.pressWith(viewAction, readExamTermList)).data;
    }
    if (list.terms.isEmpty) {
      auth.note('Exam results: no term list. Page: ${opened.data.description ?? ''}');
      throw Exception('in4SIT did not show the list of terms.');
    }
    debugLog('Exam results: ${list.terms.length} terms');
    return _listed = list.terms;
  }
}

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
      isSlip: html.contains(ExamService.viewAction) || html.contains('Result Slip'),
    );

/// The terms in the "Select a Term then click Continue" grid.
List<ExamTerm> parseExamTerms(String body) => parseExamTermsDoc(parser.parse(unwrapPeopleSoft(body)));

/// [parseExamTerms] for an already parsed page.
List<ExamTerm> parseExamTermsDoc(dom.Document doc) {
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
