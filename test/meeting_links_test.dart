import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/meeting_links.dart';
import 'package:resit/sites/xsite/activity_parsers.dart';

MeetingService? _service(String url) => meetingServiceOf(Uri.parse(url));

void main() {
  group('which links are meetings', () {
    test('Zoom: join, webinar, personal room and web-client links on zoom.us and its subdomains', () {
      for (final url in [
        'https://zoom.us/j/1234567890',
        'https://zoom.us/j/1234567890?pwd=abcDEF123',
        'https://us02web.zoom.us/j/81234567890?pwd=xyz',
        'https://SIT-edu.zoom.us/j/91234567890',
        'https://singaporetech.zoom.us/my/prof.tan',
        'https://zoom.us/w/91234567890?tk=abc',
        'https://zoom.us/wc/join/1234567890',
        'https://zoom.us/wc/1234567890/join',
      ]) {
        expect(_service(url), MeetingService.zoom, reason: url);
      }
    });

    test('Teams, Meet and Webex meeting links', () {
      expect(_service('https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d'),
          MeetingService.teams);
      expect(_service('https://teams.microsoft.com/meet/123456789?p=abc'), MeetingService.teams);
      expect(_service('https://teams.live.com/meet/9876543210'), MeetingService.teams);
      expect(_service('https://meet.google.com/abc-defg-hij'), MeetingService.meet);
      expect(_service('https://meet.google.com/lookup/abcdef'), MeetingService.meet);
      expect(_service('https://sit.webex.com/meet/jtan'), MeetingService.webex);
      expect(_service('https://sit.webex.com/sit/j.php?MTID=m0123456789abcdef'), MeetingService.webex);
      expect(_service('https://sit.webex.com/wbxmjs/joinservice/sites/sit/meeting/download/abc'), MeetingService.webex);
    });

    test('look-alike hosts are not meetings', () {
      for (final url in [
        'https://zoom.us.evil.com/j/1234567890',
        'https://notzoom.us/j/1234567890',
        'https://evilzoom.us/j/1234567890',
        'https://zoom.us.example/j/1234567890',
        'https://example.com/zoom.us/j/1234567890',
        'https://example.com/?u=https://zoom.us/j/1234567890',
        'https://zoom.us@evil.com/j/1234567890',
        'https://user:pass@zoom.us/j/1234567890',
        'https://zoom.us:8443/j/1234567890',
        'https://teams.microsoft.com.evil.io/l/meetup-join/abc',
        'https://evilteams.microsoft.com/l/meetup-join/abc',
        'https://meet.google.com.evil.com/abc-defg-hij',
        'https://notmeet.google.com/abc-defg-hij',
        'https://webex.com.evil.com/meet/jtan',
        'https://fakewebex.com/meet/jtan',
        'https://zoom-us.com/j/1234567890',
      ]) {
        expect(_service(url), isNull, reason: url);
      }
    });

    test('plain http and other schemes are not offered', () {
      for (final url in [
        'http://zoom.us/j/1234567890',
        'http://teams.microsoft.com/l/meetup-join/abc',
        'http://meet.google.com/abc-defg-hij',
        'zoommtg://zoom.us/join?confno=1234567890',
        'javascript:alert(1)//zoom.us/j/1',
      ]) {
        expect(_service(url), isNull, reason: url);
      }
    });

    test('pages that are not meetings: home pages, recordings, start links, downloads', () {
      for (final url in [
        'https://zoom.us/',
        'https://zoom.us/download',
        'https://zoom.us/rec/share/abcdef',
        'https://sit-edu.zoom.us/rec/play/xyz',
        'https://zoom.us/s/1234567890',
        'https://teams.microsoft.com/',
        'https://teams.microsoft.com/l/channel/19%3aabc/General',
        'https://meet.google.com/',
        'https://meet.google.com/new',
        'https://www.webex.com/',
        'https://sit.webex.com/',
      ]) {
        expect(_service(url), isNull, reason: url);
      }
    });
  });

  group('finding links in an announcement', () {
    test('a link only in the HTML (its text says "here") is found', () {
      final links = findMeetingLinks(
        html:
            '<p>Week 5 lecture is online. Join <a href="https://sit-edu.zoom.us/j/91234567890?pwd=Ab1&amp;from=addon">here</a>.</p>',
        text: 'Week 5 lecture is online. Join here.',
      );
      expect(links, hasLength(1));
      expect(links.single.service, MeetingService.zoom);
      expect(links.single.url.toString(), 'https://sit-edu.zoom.us/j/91234567890?pwd=Ab1&from=addon');
      // The number from the link itself.
      expect(links.single.meetingId, '912 3456 7890');
    });

    test('a bare address in plain text, with the meeting ID and passcode under it', () {
      final links = findMeetingLinks(text: '''
Dear all, the lecture this week is on Zoom.
Join Zoom Meeting
https://us02web.zoom.us/j/1234567890?pwd=xyz.
Meeting ID: 123 456 7890
Passcode: inf2004!
''');
      expect(links.single.url.toString(), 'https://us02web.zoom.us/j/1234567890?pwd=xyz');
      expect(links.single.meetingId, '123 456 7890');
      expect(links.single.passcode, 'inf2004!');
    });

    test('details written before the link, and in other wordings', () {
      final links = findMeetingLinks(
        html:
            '<p>Meeting ID: 987 6543 2109<br>Password: 55aa</p><p>Link: <a href="https://zoom.us/j/98765432109">https://zoom.us/j/98765432109</a></p>',
      );
      expect(links.single.meetingId, '987 6543 2109');
      expect(links.single.passcode, '55aa');
    });

    test('Teams invitation: link behind "Click here to join", meeting ID and passcode', () {
      final links = findMeetingLinks(html: '''
<div>Microsoft Teams meeting</div>
<div><a href="https://teams.microsoft.com/l/meetup-join/19%3ameeting_NjA%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d" target="_blank">Click here to join the meeting</a></div>
<div>Meeting ID: 412 345 678 901</div><div>Passcode: q7XbZ2</div>
''');
      expect(links.single.service, MeetingService.teams);
      expect(links.single.meetingId, '412 345 678 901');
      expect(links.single.passcode, 'q7XbZ2');
    });

    test('Webex "meeting number (access code)" and Meet with no details', () {
      final webex = findMeetingLinks(
          text:
              'https://sit.webex.com/sit/j.php?MTID=mabc\nMeeting number (access code): 2512 345 6789\nMeeting password: Tue123');
      expect(webex.single.service, MeetingService.webex);
      expect(webex.single.meetingId, '2512 345 6789');
      expect(webex.single.passcode, 'Tue123');

      final meet = findMeetingLinks(text: 'Consultation: https://meet.google.com/abc-defg-hij (bring questions)');
      expect(meet.single.url.toString(), 'https://meet.google.com/abc-defg-hij');
      expect(meet.single.meetingId, isNull);
      expect(meet.single.passcode, isNull);
    });

    test('two meetings each keep their own details', () {
      final links = findMeetingLinks(text: '''
Lecture: https://zoom.us/j/1111111111
Meeting ID: 111 111 1111
Passcode: lec
Tutorial: https://zoom.us/j/2222222222
Meeting ID: 222 222 2222
Passcode: tut
''');
      expect(links.map((l) => l.meetingId), ['111 111 1111', '222 222 2222']);
      expect(links.map((l) => l.passcode), ['lec', 'tut']);
    });

    test('the same link twice (text and address) is listed once', () {
      final links = findMeetingLinks(
        html: '<p><a href="https://zoom.us/j/1234567890">https://zoom.us/j/1234567890</a></p>'
            '<p>Again: <a href="https://zoom.us/j/1234567890">join</a></p>',
      );
      expect(links, hasLength(1));
    });

    test('look-alikes, http links and other sites in an announcement are left out', () {
      final links = findMeetingLinks(
        html: '<p><a href="https://zoom.us.evil.com/j/1234567890">Zoom</a> '
            '<a href="http://zoom.us/j/1234567890">old link</a> '
            '<a href="https://notzoom.us/j/1">x</a> '
            'see https://xsite.singaporetech.edu.sg/d2l/home and https://zoom.us/rec/share/abc</p>',
      );
      expect(links, isEmpty);
    });

    test('Outlook safe links are unwrapped to the meeting inside', () {
      final wrapped =
          'https://apc01.safelinks.protection.outlook.com/?url=${Uri.encodeComponent('https://zoom.us/j/1234567890?pwd=a')}&data=x';
      final links = findMeetingLinks(html: '<a href="${wrapped.replaceAll('&', '&amp;')}">Join</a>');
      expect(links.single.url.toString(), 'https://zoom.us/j/1234567890?pwd=a');
      // A safe link wrapping something else is still nothing.
      final other =
          'https://apc01.safelinks.protection.outlook.com/?url=${Uri.encodeComponent('https://zoom.us.evil.com/j/1')}';
      expect(findMeetingLinks(text: other), isEmpty);
    });

    test('nothing in an announcement without links', () {
      expect(findMeetingLinks(html: '<p>Quiz on Friday.</p>', text: 'Quiz on Friday.'), isEmpty);
      expect(findMeetingLinks(), isEmpty);
    });
  });

  test('announcements keep the meeting links in their HTML', () {
    final list = parseAnnouncements(jsonEncode([
      {
        'Id': 1,
        'Title': 'Online lecture',
        'Body': {
          'Text': 'Week 9 lecture is online. Join here.\nPasscode: 4004',
          'Html':
              '<p>Week 9 lecture is online. Join <a href="https://sit-edu.zoom.us/j/91234567890">here</a>.</p><p>Passcode: 4004</p>',
        },
        'StartDate': '2026-11-02T01:00:00.000Z',
      },
      {
        'Id': 2,
        'Title': 'Plain',
        'Body': {'Text': 'Consultation at https://meet.google.com/abc-defg-hij', 'Html': null},
        'StartDate': '2026-10-02T01:00:00.000Z',
      },
      {'Id': 3, 'Title': 'Odd body', 'Body': 42},
    ]));
    expect(list.first.body, 'Week 9 lecture is online. Join here.\nPasscode: 4004');
    expect(list.first.meetings.single.service, MeetingService.zoom);
    expect(list.first.meetings.single.passcode, '4004');
    expect(list[1].meetings.single.service, MeetingService.meet);
    expect(list[2].meetings, isEmpty);
  });

  test('the newest announcement with a link gives the meeting', () {
    Announcement a(int day, List<MeetingLink> links) =>
        Announcement(id: '$day', title: 't', body: '', date: DateTime(2026, 11, day), meetings: links);
    final older = MeetingLink(url: Uri.parse('https://zoom.us/j/1111111111'), service: MeetingService.zoom);
    final newer = MeetingLink(url: Uri.parse('https://zoom.us/j/2222222222'), service: MeetingService.zoom);
    expect(
        latestMeetingLink([
          a(1, [older]),
          a(9, [newer]),
          a(12, [])
        ]),
        newer);
    expect(latestMeetingLink([a(12, [])]), isNull);
    expect(latestMeetingLink(const []), isNull);
  });

  test('online classes by their timetable location', () {
    for (final l in ['Online', 'ONLINE', 'Online Learning', 'Zoom', 'MS Teams', 'E-Learning']) {
      expect(isOnlineLocation(l), isTrue, reason: l);
    }
    for (final l in ['E2-03-01', '', 'SIT@Dover SR6', 'Lecture Theatre 1']) {
      expect(isOnlineLocation(l), isFalse, reason: l);
    }
  });
}
