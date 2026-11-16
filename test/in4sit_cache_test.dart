import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/in4sit/peoplesoft.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/exams/data/academic_record.dart';
import 'package:resit/features/common/data/private_store.dart';
import 'package:resit/sites/in4sit/exam_service.dart';
import 'package:resit/sites/in4sit/timetable_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _ajax(String html, int state) => "<?xml version='1.0'?><PAGE>"
    "<GENSCRIPT id='onloadScript'><![CDATA[oDoc.win0.ICStateNum.value=$state;]]></GENSCRIPT>"
    "<FIELD id='win0divPSPAGECONTAINER'><![CDATA[$html]]></FIELD></PAGE>";

String _termList(int count) {
  final rows = StringBuffer();
  for (var i = 0; i < count; i++) {
    rows.write("<tr><td><input type='radio' name='N_EX_PRVRSL_TBL\$sels\$0' "
        "id='N_EX_PRVRSL_TBL\$sels\$$i\$\$0' value='$i'/></td>"
        "<td><span id='N_XM_RSLT_WRK_DESCR\$$i'>2025/26 Trimester ${i + 1}</span></td></tr>");
  }
  return '<table>$rows</table>';
}

String _slip(int i, {bool released = true}) {
  if (!released) {
    return "<a id='N_RSLT_SLIP_WRK_VIEW_PB'>View Other Term</a><div>Exam Results has not been released.</div>";
  }
  return "<a id='N_RSLT_SLIP_WRK_VIEW_PB'>View Other Term</a>"
      '<table><tr><th>Trimester GPA</th><th>:</th><th>3.${i}0</th></tr>'
      '<tr><th>Cumulative GPA</th><th>:</th><th>3.${i}5</th></tr></table>'
      '<u><strong>AY 2025/26 Trimester ${i + 1}</strong></u>'
      '<table><tr><th>Course Code</th><th>Course Title</th><th>Credits</th><th>Grade Points</th><th>Grade</th></tr>'
      '<tr><td>CSC10${i}0</td><td>Course $i</td><td>6</td><td>4</td><td>A</td></tr></table>';
}

/// A fake in4SIT exam results page with [terms] terms, counting what the
/// app asks for. [released] says which term rows have results out.
class _FakeExams {
  final int terms;
  final Set<int> released;
  var gets = 0;
  final continues = <int>[];
  var _state = 1;

  /// Like the real in4SIT: a row selection left in the form from an earlier
  /// visit (`N_EX_PRVRSL_TBL$sels$<row>$$0`) wins over the new radio value.
  final bool staleSelectionWins;

  _FakeExams(this.terms, this.released, {this.staleSelectionWins = false});

  http.Response? handle(http.Request request) {
    if (request.url.path != ExamService.pageUrl.path) return null;
    if (request.method == 'GET') {
      gets++;
      return http.Response(
          "<form name='win0'><input name='ICStateNum' value='1'></form><a id='N_RSLT_SLIP_WRK_VIEW_PB'>View</a>", 200,
          request: request);
    }
    final fields = request.bodyFields;
    _state++;
    switch (fields['ICAction']) {
      case ExamService.viewAction:
        return http.Response(_ajax(_termList(terms), _state), 200, request: request);
      case ExamService.continueAction:
        var row = int.parse(fields[ExamService.termRadio]!);
        if (staleSelectionWins) {
          final picked = fields.keys.where((k) => RegExp(r'^N_EX_PRVRSL_TBL\$sels\$\d+\$\$0$').hasMatch(k)).toList();
          if (picked.isNotEmpty) row = int.parse(fields[picked.first]!);
        }
        continues.add(row);
        return http.Response(_ajax(_slip(row, released: released.contains(row)), _state), 200, request: request);
    }
    return http.Response('?', 400, request: request);
  }
}

String _week(DateTime monday) {
  final d = '${monday.day}/${monday.month}/${monday.year}';
  return "<table><tr><td>Week of&nbsp;<span>$d</span> - x</td></tr></table>"
      "<table id='WEEKLY_SCHED_HTMLAREA'><tr><th>Time</th><th>Mon</th><th>Tue</th><th>Wed</th><th>Thu</th>"
      '<th>Fri</th><th>Sat</th><th>Sun</th></tr>'
      "<tr><td>9:00AM</td><td><span>CSC 2101 - L1<br>Lectorial<br>9:00AM - 11:00AM<br>Online</span></td>"
      '<td></td><td></td><td></td><td></td><td></td><td></td></tr></table>';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('academic record: one open page for every term, then only new or unreleased terms', () async {
    // Rows 0..3, oldest first; row 3 (the newest) and row 1 aren't out yet.
    final fake = _FakeExams(4, {0, 2});
    final auth = AuthService(
        SessionClient(MockClient((r) async => fake.handle(r) ?? http.Response('nf', 404, request: r))), SecureStorage());
    final exams = ExamService(auth);
    final service = AcademicRecordService(exams);
    final progress = <(int, int)?>[];
    service.progress.addListener(() => progress.add(service.progress.value));

    final first = await service.load(force: true);
    expect(fake.gets, 1, reason: 'the page is opened once and kept for every term');
    expect(fake.continues, [3, 2, 1, 0]);
    expect(first!.terms.map((t) => t.name), ['AY 2025/26 Trimester 1', 'AY 2025/26 Trimester 3']);
    expect(progress.first, (0, 4));
    expect(progress.where((p) => p != null).last, (4, 4));
    expect(service.progress.value, isNull, reason: 'cleared when done');

    // Next day: term 2 (row 1) is out now; terms 1 and 3 are kept.
    fake.released.add(1);
    fake.continues.clear();
    progress.clear();
    final second = await service.load(force: true);
    expect(fake.continues, [3, 1], reason: 'only the newest term and the one not released last time');
    expect(progress.first, (0, 2));
    expect(second!.terms, hasLength(3));

    // The exam results screen gets kept slips without asking in4SIT.
    fake.continues.clear();
    final terms = await exams.terms();
    final kept = await exams.results(terms.last);
    expect(kept.courses.single.code, 'CSC1000');
    expect(fake.continues, isEmpty);
    expect(kept.term.index, 0);

    // Kept encrypted (not in plain preferences), and clear() removes the slips.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isNot(contains('academic_record')));
    expect(await exams.slips.slip('2025/26 Trimester 1'), isNotNull);
    await service.clear();
    expect(await service.saved(), isNull);
    expect(await exams.slips.slip('2025/26 Trimester 1'), isNull);
    auth.dispose();
  });

  test('each term gets its own slip even when an earlier row selection is still in the form', () async {
    final fake = _FakeExams(3, {0, 1, 2}, staleSelectionWins: true);
    final auth = AuthService(
        SessionClient(MockClient((r) async => fake.handle(r) ?? http.Response('nf', 404, request: r))), SecureStorage());
    final record = await AcademicRecordService(ExamService(auth)).load(force: true);
    expect(fake.continues, [2, 1, 0], reason: 'each term read is for that term');
    expect(record!.terms.map((t) => t.name),
        ['AY 2025/26 Trimester 1', 'AY 2025/26 Trimester 2', 'AY 2025/26 Trimester 3']);
    expect(record.terms.every((t) => t.creditsEarned == 6), isTrue);
    auth.dispose();
  });

  test('a slip saved under the wrong term (by an older version) is dropped and read again', () async {
    final store = ExamSlipStore();
    // A Trimester 2 slip, saved as if it were Trimester 1's.
    final wrong = parseExamResults(_ajax(_slip(1), 1), const ExamTerm(index: 0, name: '2025/26 Trimester 1'));
    await store.save(wrong);
    expect(await store.slip('2025/26 Trimester 1'), isNull, reason: 'not kept: its heading names another term');
    expect(slipMatchesTerm('AY 2025/26 Trimester 2', '2025/26 Trimester 2'), isTrue);
    expect(slipMatchesTerm('AY 2025/26 Trimester 2', '2025/26 Trimester 1'), isFalse);
    expect(slipMatchesTerm('', '2025/26 Trimester 1'), isTrue);
  });

  test('a saved record with the same term twice is rebuilt instead of kept for the day', () async {
    final fake = _FakeExams(2, {0, 1});
    final auth = AuthService(
        SessionClient(MockClient((r) async => fake.handle(r) ?? http.Response('nf', 404, request: r))), SecureStorage());
    final service = AcademicRecordService(ExamService(auth));
    await service.load(force: true);
    final good = (await service.saved())!;
    // Write a mixed-up copy (Trimester 2 twice), fetched just now.
    final mixed = AcademicRecord(
      creditsEarned: 6,
      creditsInProgress: 0,
      coursesPassed: 1,
      fetchedAt: DateTime.now(),
      terms: [good.terms.last, good.terms.last],
    );
    await PrivateStore().write('academic_record', jsonEncode(mixed.toJson()));
    final reloaded = await service.load();
    expect(reloaded!.terms.map((t) => t.name).toSet(), hasLength(2));
    auth.dispose();
  });

  test('exam results reuse the page opened for the term list', () async {
    final fake = _FakeExams(2, {0, 1});
    final auth = AuthService(
        SessionClient(MockClient((r) async => fake.handle(r) ?? http.Response('nf', 404, request: r))), SecureStorage());
    final exams = ExamService(auth);
    final terms = await exams.terms();
    final r = await exams.results(terms.first);
    expect(r.courses, isNotEmpty);
    expect(fake.gets, 1);
    // Another term: back to the list with View Other Term, not a reopen.
    await exams.results(terms.last);
    expect(fake.gets, 1);
    expect(fake.continues, [1, 0]);
    auth.dispose();
  });

  test('a saved record from plain preferences moves to secure storage', () async {
    SharedPreferences.setMockInitialValues({
      'academic_record': '{"creditsEarned": 12, "fetchedAt": 0, "terms": []}',
    });
    final service = AcademicRecordService(ExamService(AuthService(SessionClient(), SecureStorage())));
    expect((await service.saved())!.creditsEarned, 12);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('academic_record'), isNull);
    expect((await service.saved())!.creditsEarned, 12);
  });

  test('the timetable reopens its page straight away after exam results opened theirs', () async {
    final exams = _FakeExams(1, {0});
    var ttGets = 0;
    var ttPosts = 0;
    final ttPath = Uri.parse(TimetableService.pageUrl).path;
    final mock = MockClient((request) async {
      final handled = exams.handle(request);
      if (handled != null) return handled;
      if (request.url.path != ttPath) return http.Response('nf', 404, request: request);
      if (request.method == 'GET') {
        ttGets++;
        return http.Response("<form name='win0'><input name='ICStateNum' value='1'></form>${_week(DateTime(2026, 10, 5))}",
            200,
            request: request);
      }
      ttPosts++;
      final p = request.bodyFields['DERIVED_CLASS_S_START_DT']!.split('/').map(int.parse).toList();
      return http.Response(_ajax(_week(DateTime(p[2], p[1], p[0])), 5), 200, request: request);
    });
    final auth = AuthService(SessionClient(mock), SecureStorage());
    final queue = In4SitQueue();
    final timetable = TimetableService(auth, queue: queue);
    final examService = ExamService(auth, queue: queue);

    // Both at once, as at sign-in: they take turns.
    final results = await Future.wait([
      timetable.week(DateTime(2026, 10, 5)),
      examService.terms(),
    ]);
    expect((results[0] as WeekSchedule).sessions.single.courseCode, 'CSC 2101');
    expect(ttGets, 1);

    final next = await timetable.week(DateTime(2026, 10, 12));
    expect(next.monday, DateTime(2026, 10, 12));
    expect(ttGets, 2, reason: 'exam results took over in4SIT, so the page was opened again');
    expect(ttPosts, 1, reason: 'without first sending a request on the dropped page');
    auth.dispose();
  });

  test('big replies are parsed on another isolate with the same result', () async {
    final body = _ajax(_slip(1), 9);
    final inline = readPeopleSoftReply((body, false, readExamSlip));
    final isolate = await (() {
      final saved = offThreadParseThreshold;
      offThreadParseThreshold = 0;
      return parseOffThread(readPeopleSoftReply<ExamSlipReply>, (body, false, readExamSlip), size: body.length)
          .whenComplete(() => offThreadParseThreshold = saved);
    })();
    expect(isolate.stateNum, '9');
    expect(isolate.data.isSlip, isTrue);
    expect(isolate.data.results.courses.single.code, inline.data.results.courses.single.code);
  });

  test('result slips round-trip through JSON', () {
    final slip = parseExamResults(_ajax(_slip(2), 1), const ExamTerm(index: 2, name: 'T3'));
    final back = ExamResults.fromJson(slip.toJson());
    expect(back.term.name, 'T3');
    expect(back.heading, slip.heading);
    expect(back.courses.single.grade, 'A');
    expect(back.value('Cumulative GPA'), '3.25');
    expect(back.released, isTrue);
  });
}
