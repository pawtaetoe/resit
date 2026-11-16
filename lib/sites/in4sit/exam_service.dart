import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/in4sit/exam_parsers.dart';
import 'package:resit/sites/in4sit/peoplesoft.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/features/exams/domain/exam_results.dart';

/// Reads "View My Exam Results" on in4SIT. The page is stateful on the server
/// (PeopleSoft), so requests go through the app's one [In4SitQueue]. The page
/// is kept open between calls: the term list, then Continue for a term's
/// slip, then "View Other Term" back to the list for the next one, so going
/// through several terms doesn't reopen the page (and sign in) for each.
///
/// Like [PeopleSoftPage], its reads are not queued by the service itself:
/// run them inside [queue]. Keeping slips is the data layer's job (see
/// `ExamResultsRepository`).
class ExamService {
  final AuthService auth;

  /// Shared with every other in4SIT reader, so their requests take turns.
  final In4SitQueue queue;

  ExamService(this.auth, {In4SitQueue? queue}) : queue = queue ?? In4SitQueue();

  static final pageUrl =
      Uri.parse('https://in4sit.singaporetech.edu.sg/psc/CSSISSTD/EMPLOYEE/SA/c/N_MANAGE_EXAMS.N_RSLT_SLIP_COMP.GBL');
  static const viewAction = examViewAction;
  static const continueAction = r'N_RSLT_SLIP_WRK_CONTINUE_PB$0';
  static const termRadio = examTermRadio;

  /// in4SIT drops a page left idle for about 20 minutes; reopen before then.
  static const _pageLife = Duration(minutes: 15);

  PeopleSoftPage? _page;
  DateTime _openedAt = DateTime(0);

  /// The term list the page shows now, or null when it shows a slip.
  List<ExamTerm>? _listed;

  /// The terms that have results, latest first, read from in4SIT. Run
  /// inside [queue].
  Future<List<ExamTerm>> readTerms({void Function(MfaChallenge)? onMfaChallenge}) async {
    final (terms, _) = await _termList(onMfaChallenge);
    return terms.reversed.toList();
  }

  /// The result slip for [term], read from in4SIT. Run inside [queue].
  Future<ExamResults> readResults(ExamTerm term, {void Function(MfaChallenge)? onMfaChallenge}) =>
      _readSlip(term, onMfaChallenge);

  /// Closes the page kept open, so the next read opens it afresh.
  void closePage() {
    _page?.close();
    _page = null;
    _listed = null;
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
