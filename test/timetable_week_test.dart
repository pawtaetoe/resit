import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/timetable/data/timetable_service.dart';

String _td(String text, {int rowspan = 1}) =>
    "<td class='g' rowspan='$rowspan'><span>$text</span></td>";
const _e = "<td class='g'>&nbsp;</td>";
String _time(String t) => "<td class='g' scope='row'><span>$t</span></td>";

/// The structure of in4sit's weekly calendar (week of 5 Oct 2026): cells with
/// rowspan, and a coinciding-class cell with a warning icon between classes.
String _fixture() {
  final rows = [
    '<tr>${_time('8:00AM')}${_e * 7}</tr>',
    // 9:00: Mon L1 (2 rows), Tue Q1 (2 rows), Fri INF 2002 Q1
    '<tr>${_time('9:00AM')}'
        '${_td('CSC 2101 - L1<br>Lectorial<br>9:00AM - 11:00AM<br>Online', rowspan: 2)}'
        '${_td('CSC 2101 - Q1<br>Quiz<br>9:00AM - 11:00AM<br>E2-01-01-Lectorial 6', rowspan: 2)}'
        '$_e$_e${_td('INF 2002 - Q1<br>Quiz<br>9:00AM - 11:00AM<br>E2-05-07')}$_e$_e</tr>',
    // 10:00: Mon+Tue are covered by the rowspans above; Fri has two overlapping classes
    '<tr>${_time('10:00AM')}$_e$_e'
        "<td class='g'><span>INF 2002 - Q1<br>Quiz<br>9:00AM - 11:00AM<br>E2-05-07<br>"
        "<img alt='Coinciding class'><br>CSC 3104 - P2<br>Laboratory<br>10:00AM - 11:00AM<br>E6-2M-02-SR319</span></td>"
        '$_e$_e</tr>',
    // 11:00: Mon INF 2004 (2 rows), Wed P3 (2 rows), Thu P2 (2 rows)
    '<tr>${_time('11:00AM')}'
        '${_td('INF 2004 - ALL<br>Lecture<br>11:00AM - 1:00PM<br>Online', rowspan: 2)}'
        '$_e${_td('INF 2004 - P3<br>Laboratory<br>11:00AM - 1:00PM<br>E2-05-14', rowspan: 2)}'
        '${_td('INF 2002 - P2<br>Laboratory<br>11:00AM - 1:00PM<br>E2-07-14', rowspan: 2)}$_e$_e$_e</tr>',
    // 12:00: only Tue and the weekend are free
    '<tr>${_time('12:00PM')}$_e$_e$_e$_e</tr>',
    // 1:00: Tue tutorial (2 rows)
    '<tr>${_time('1:00PM')}$_e${_td('CSC 3104 - T1<br>Tutorial<br>1:00PM - 3:00PM<br>E2-01-01-Lectorial 6', rowspan: 2)}$_e$_e$_e$_e$_e</tr>',
  ];

  return '''
<table><tr><td class="PSGROUPBOXLABEL">Week of 5/10/2026 - 11/10/2026</td></tr></table>
<table id='WEEKLY_SCHED_HTMLAREA'>
<tr><th>Time</th><th>Monday<br>5 Oct</th><th>Tuesday<br>6 Oct</th><th>Wednesday<br>7 Oct</th>
<th>Thursday<br>8 Oct</th><th>Friday<br>9 Oct</th><th>Saturday<br>10 Oct</th><th>Sunday<br>11 Oct</th></tr>
${rows.join()}
</table>''';
}

void main() {
  String describe(ClassSession s) =>
      '${s.date.month}/${s.date.day} ${s.timeLabel} ${s.courseCode} ${s.section} ${s.component} @${s.location}';

  test('parses the weekly calendar with real dates, spans and overlaps', () {
    final week = parseWeek(_fixture())!;

    expect(week.monday, DateTime(2026, 10, 5));
    expect(week.sessions.map(describe).toList(), [
      '10/5 09:00 - 11:00 CSC 2101 L1 Lectorial @Online',
      '10/5 11:00 - 13:00 INF 2004 ALL Lecture @Online',
      '10/6 09:00 - 11:00 CSC 2101 Q1 Quiz @E2-01-01-Lectorial 6',
      '10/6 13:00 - 15:00 CSC 3104 T1 Tutorial @E2-01-01-Lectorial 6',
      '10/7 11:00 - 13:00 INF 2004 P3 Laboratory @E2-05-14',
      '10/8 11:00 - 13:00 INF 2002 P2 Laboratory @E2-07-14',
      '10/9 09:00 - 11:00 INF 2002 Q1 Quiz @E2-05-07',
      '10/9 10:00 - 11:00 CSC 3104 P2 Laboratory @E6-2M-02-SR319',
    ]);
  });

  test('flags overlapping classes and does not repeat a spanning class', () {
    final week = parseWeek(_fixture())!;

    // INF 2002 Q1 shows up in two grid rows on Friday but is one session.
    expect(week.sessions.where((s) => s.courseCode == 'INF 2002' && s.section == 'Q1'), hasLength(1));
    expect(week.sessions.where((s) => s.coinciding).map((s) => s.courseCode), unorderedEquals(['INF 2002', 'CSC 3104']));
  });

  test('forDay returns the sessions of one weekday', () {
    final week = parseWeek(_fixture())!;
    expect(week.forDay(0), hasLength(2)); // Monday
    expect(week.forDay(4), hasLength(2)); // Friday
    expect(week.forDay(5), isEmpty); // Saturday
  });

  test('wraps in the PeopleSoft XML envelope too', () {
    final xml = "<?xml version='1.0'?><PAGE><FIELD id='x'><![CDATA[${_fixture()}]]></FIELD></PAGE>";
    expect(parseWeek(xml)!.sessions, hasLength(8));
  });

  test('returns null for a page without the grid', () {
    expect(parseWeek('<html><body>Sign in</body></html>'), isNull);
  });

  test('reopens the page and asks again when in4SIT has dropped it', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    final page = Uri.parse(TimetableService.pageUrl);
    var gets = 0;
    var posts = 0;
    final mock = MockClient((request) async {
      if (request.method == 'GET') {
        gets++;
        return http.Response(
            "<form name='win0'><input name='ICStateNum' value='1'></form>${_fixture()}", 200,
            request: http.Request('GET', page));
      }
      posts++;
      // The first change of week finds the page gone, as after a long idle
      // or another in4SIT page opened with the same sign-in.
      return posts == 1
          ? http.Response('<html><body>This page is no longer available.</body></html>', 200, request: request)
          : http.Response(_fixture(), 200, request: request);
    });
    final service = TimetableService(AuthService(SessionClient(mock), SecureStorage()));

    final week = await service.week(DateTime(2026, 10, 12));

    expect(week.sessions, isNotEmpty);
    expect(gets, 2, reason: 'opened again after the page was lost');
    expect(posts, 2);
  });
}
