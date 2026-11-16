import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/sites/in4sit/exam_parsers.dart';
import 'package:resit/sites/in4sit/exam_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resit/features/exams/domain/exam_results.dart';

// Cut-down copies of in4SIT's pages (structure kept, personal data replaced).

const _termList = r"""<?xml version='1.0' encoding='utf-8' ?>
<PAGE id='N_RSLT_SLIP'><GENSCRIPT id='onloadScript'><![CDATA[oDoc.win0.ICStateNum.value=18;]]></GENSCRIPT>
<FIELD id='win0divPSPAGECONTAINER'><![CDATA[<table>
<tr><td class='PSLEVEL1GRIDLABEL'>Select a Term then click Continue</td></tr>
<tr id='trN_EX_PRVRSL_TBL$0_row1'>
<td><input class='PSRADIOBUTTON' type='radio' name='N_EX_PRVRSL_TBL$sels$0' id='N_EX_PRVRSL_TBL$sels$0$$0' value='0'/></td>
<td><span class='PSEDITBOX_DISPONLY' id='N_XM_RSLT_WRK_DESCR$0'>2025/26 Trimester 1</span></td>
<td><span class='PSEDITBOX_DISPONLY' id='N_XM_RSLT_WRK_DESCR1$0'>Undergraduate</span></td>
<td><span class='PSEDITBOX_DISPONLY' id='N_XM_RSLT_WRK_INSTITUTION$0'>SIT01</span></td></tr>
<tr id='trN_EX_PRVRSL_TBL$0_row2'>
<td><input class='PSRADIOBUTTON' type='radio' name='N_EX_PRVRSL_TBL$sels$0' id='N_EX_PRVRSL_TBL$sels$1$$0' value='1'/></td>
<td><span class='PSEDITBOX_DISPONLY' id='N_XM_RSLT_WRK_DESCR$1'>2025/26 Trimester 2</span></td>
<td><span class='PSEDITBOX_DISPONLY' id='N_XM_RSLT_WRK_DESCR1$1'>Undergraduate</span></td>
<td><span class='PSEDITBOX_DISPONLY' id='N_XM_RSLT_WRK_INSTITUTION$1'>SIT01</span></td></tr>
<tr id='trN_EX_PRVRSL_TBL$0_row3'>
<td><input class='PSRADIOBUTTON' type='radio' name='N_EX_PRVRSL_TBL$sels$0' id='N_EX_PRVRSL_TBL$sels$2$$0' value='2'/></td>
<td><span class='PSEDITBOX_DISPONLY' id='N_XM_RSLT_WRK_DESCR$2'>2025/26 Trimester 3</span></td>
<td><span class='PSEDITBOX_DISPONLY' id='N_XM_RSLT_WRK_DESCR1$2'>Undergraduate</span></td>
<td><span class='PSEDITBOX_DISPONLY' id='N_XM_RSLT_WRK_INSTITUTION$2'>SIT01</span></td></tr>
</table>
<input type='button' name='N_RSLT_SLIP_WRK_CONTINUE_PB$0' id='N_RSLT_SLIP_WRK_CONTINUE_PB$0' value='Continue'/>]]></FIELD></PAGE>""";

const _slip = r"""<?xml version='1.0' encoding='utf-8' ?>
<PAGE id='N_RSLT_SLIP'><GENSCRIPT id='onloadScript'><![CDATA[oDoc.win0.ICStateNum.value=23;]]></GENSCRIPT>
<FIELD id='win0divPSPAGECONTAINER'><![CDATA[<table role='presentation' class='PSPAGECONTAINER'><tr><td></td><td>
<DIV id='win0divN_RSLT_SLIP_WRK_GROUPBOX5'><table class='PSGROUPBOXWBO'><tr><td>
<table role='presentation' class='PSGROUPBOX'><tr><td></td></tr><tr><td>
<font color='#3366FF'><strong>Examination Result Slip</strong></font>
<a name='N_RSLT_SLIP_WRK_VIEW_PB' id='N_RSLT_SLIP_WRK_VIEW_PB'>View Other Term</a>
<table border='0'>
<tr><th width ='30%'>Student Name </th><th width ='5%'> : </th><th width ='65%'> TEST STUDENT </th></tr>
<tr><th>Admit Term </th><th> : </th><th> September 2025 </th></tr>
<tr><th>Student Number</th><th> : </th><th>2100000</th></tr>
</table>
<table border='0'><tr><th>Programme </th><th> : </th><th> BSc (Hons) Computing Science</th></tr></table>
<table border='0'><tr><th>Release Date </th><th>:  </th><th> 31 August 2026</th></tr></table>
<u><strong> AY 2025/26 Trimester 3</strong></u><br><br>
<table id='t01' border='1'>
<tr ><th><strong>Course Code</strong></th><th><strong>Course Title</strong></th><th><strong>Credits</strong></th><th ><strong>Grade Points</strong></th>  <th ><strong>Grade </strong></th><th ><strong>Grading Remark</strong></th></tr><tr><td>CSC1106</td><td>Web Programming</td><td>6</td><td>3.5</td><td>B</td><td></td></tr><tr><td>CSC3102A</td><td>Integrated Work Study Programme (Career Skills)</td><td>0</td><td>0</td><td>IP</td><td></td></tr></table><br>
<div><font color=#FF0000>*NOTE: For modules which you have yet to clear, please view your past trimesters result slip to check the next offering.</font></div><br>
<table border='0'>
<tr><th width ='30%'>Trimester GPA </th><th width ='5%'> : </th><th width ='65%'>   3.50 </th></tr>
<tr><th>Cumulative GPA </th><th> : </th><th>   3.80 </th></tr>
<tr><th>Academic Standing </th><th> : </th><th> - </th></tr>
</table>
<table border="1"><tbody><tr><td><p><strong>Letter Grade</strong></p></td><td><p><strong>Grade Point</strong></p></td></tr>
<tr><td>A+</td><td>5.00</td></tr><tr><td>B+</td><td>4.00</td></tr></tbody></table>
</td></tr></table></td></tr></table></DIV></td></tr></table>
]]></FIELD></PAGE>""";

void main() {
  const term = ExamTerm(index: 2, name: '2025/26 Trimester 3');

  test('reads the term list', () {
    final terms = parseExamTerms(_termList);
    expect(terms.map((t) => t.name), ['2025/26 Trimester 1', '2025/26 Trimester 2', '2025/26 Trimester 3']);
    expect(terms.last.index, 2);
    expect(terms.first.career, 'Undergraduate');
    expect(terms.first.institution, 'SIT01');
  });

  test('reads a result slip', () {
    final r = parseExamResults(_slip, term);
    expect(r.heading, 'AY 2025/26 Trimester 3');
    expect(r.courses, hasLength(2));
    final web = r.courses.first;
    expect([web.code, web.title, web.credits, web.gradePoints, web.grade],
        ['CSC1106', 'Web Programming', '6', '3.5', 'B']);
    expect(r.courses.last.inProgress, isTrue);
    expect(r.value('Trimester GPA'), '3.50');
    expect(r.value('Cumulative GPA'), '3.80');
    expect(r.value('Academic Standing'), '-');
    expect(r.value('Programme'), 'BSc (Hons) Computing Science');
    expect(r.standing.map((p) => p.$1), ['Trimester GPA', 'Cumulative GPA', 'Academic Standing']);
    expect(r.note, startsWith('NOTE: For modules'));
    expect(r.pageText, isNull);
  });

  test('recognises a term whose results are not released yet', () {
    const page = r"""<PAGE><FIELD id='x'><![CDATA[<strong>Examination Result Slip</strong>
<a id='N_RSLT_SLIP_WRK_VIEW_PB'>View Other Term</a><div>Exam Results has not been released.</div>]]></FIELD></PAGE>""";
    final r = parseExamResults(page, term);
    expect(r.courses, isEmpty);
    expect(r.notReleased, isTrue);
    expect(parseExamResults(_slip, term).notReleased, isFalse);
  });

  test('opens the page, views the terms and picks one like the browser does', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final posts = <Map<String, String>>[];

    final mock = MockClient((request) async {
      if (request.method == 'GET') {
        // The page opens on the latest slip, with no term list.
        return http.Response(
            '<form name="win0"><input name="ICSID" value="sid"><input name="ICStateNum" value="1"></form>'
            '<a id="N_RSLT_SLIP_WRK_VIEW_PB">View Other Term</a>',
            200,
            request: request);
      }
      posts.add(request.bodyFields);
      final action = request.bodyFields['ICAction'];
      if (action == ExamService.viewAction) return http.Response(_termList, 200, request: request);
      if (action == ExamService.continueAction) return http.Response(_slip, 200, request: request);
      return http.Response('?', 400, request: request);
    });

    final auth = AuthService(SessionClient(mock), SecureStorage());
    final service = ExamService(auth);

    final terms = await service.terms();
    expect(terms.first.name, '2025/26 Trimester 3', reason: 'latest first');

    final results = await service.results(terms.first);
    auth.dispose();

    expect(results.courses, hasLength(2));
    final pick = posts.last;
    expect(pick['ICAction'], r'N_RSLT_SLIP_WRK_CONTINUE_PB$0');
    expect(pick[r'N_EX_PRVRSL_TBL$sels$2$$0'], '2');
    expect(pick['ICSID'], 'sid');
    expect(pick['ICStateNum'], '18', reason: 'state carried from the term list');
  });
}
