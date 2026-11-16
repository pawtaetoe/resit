import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as parser;
import 'package:resit/sites/adfs/adfs_pages.dart';
import 'package:resit/sites/adfs/sit_hosts.dart';

void main() {
  final adfs = Uri.parse('https://fs.singaporetech.edu.sg/adfs/ls/');

  test('relay form: the form carrying the sign-in token, action resolved', () {
    final form = extractRelayForm(
      '<form action="/Account/LoginCallbak"><input name="wa" value="wsignin1.0"><input name="wresult" value="t"></form>',
      Uri.parse('https://rbs.singaporetech.edu.sg/x'),
    );
    expect(form?.action.toString(), 'https://rbs.singaporetech.edu.sg/Account/LoginCallbak');
    expect(form?.fields, {'wa': 'wsignin1.0', 'wresult': 't'});
    expect(extractRelayForm('<form><input name="q"></form>', adfs), isNull);
  });

  test('error message: the scripted one first, never the details link', () {
    final scripted = parser.parse(
        '<div id="errorText"></div><script>delayPopulate(\'errorText\', "Incorrect user ID or password.")</script>');
    expect(extractError(scripted), 'Incorrect user ID or password.');
    final detailsOnly = parser.parse('<div id="detailsDiv" class="error"><a id="viewDetailsLink">View details</a></div>');
    expect(extractError(detailsOnly), isNull);
  });

  test('password page vs MFA page', () {
    expect(asksForPassword('<form><input type="password" name="Password"></form>'), isTrue);
    expect(isMfaPage('<form><input type="hidden" name="Context" value="c"></form>'), isTrue);
    expect(isMfaPage('<form><input type="password" name="Password"></form>'), isFalse);
  });

  test('code box found by name, hints or as the only text box', () {
    expect(findCodeForm(parser.parse('<form><input name="VerificationCode"></form>'))?.name, 'VerificationCode');
    expect(findCodeForm(parser.parse('<form><input name="x" inputmode="numeric"></form>'))?.name, 'x');
    expect(findCodeForm(parser.parse('<form><input name="only"></form>'))?.name, 'only');
    expect(findCodeForm(parser.parse('<form><input type="password" name="p"><input name="u"></form>')), isNull);
  });

  test('number matching: the number to enter in Authenticator', () {
    expect(extractMfaNumber(parser.parse('<p>Enter the number 57 in the app</p>')), '57');
    expect(extractMfaNumber(parser.parse('<span class="number">83</span>')), '83');
  });

  test('form fields: what a browser would submit, push approval preferred', () {
    final form = parser.parse('''
      <form>
        <input type="hidden" name="Context" value="c">
        <label><input type="radio" name="AuthMethod" value="SmsAuthentication">Text</label>
        <label><input type="radio" name="AuthMethod" value="AzureMfaAuthentication">Approve a notification</label>
        <input type="submit" name="Continue" value="Continue">
      </form>''').querySelector('form')!;
    expect(formFields(form), {'Context': 'c', 'AuthMethod': 'AzureMfaAuthentication', 'Continue': 'Continue'});
  });

  test('host checks', () {
    expect(SitHosts.isAdfs(adfs), isTrue);
    expect(SitHosts.isAdfs(Uri.parse('http://fs.singaporetech.edu.sg/')), isFalse);
    expect(SitHosts.isSitHost(Uri.parse('https://xsite.singaporetech.edu.sg/')), isTrue);
    expect(SitHosts.isSitHost(Uri.parse('https://singaporetech.edu.sg.evil.example/')), isFalse);
  });
}
