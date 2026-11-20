import 'dart:convert';

import 'package:resit/features/lms/domain/calendar.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/updates.dart';
import 'package:resit/sites/xsite/brightspace_json.dart';
import 'package:resit/sites/xsite/xsite_service.dart' show LmsService;

// Reading xSiTe's calendar (Calendar.EventDataInfo) and updates
// (Updates.OrgUnitUpdates) replies, from Brightspace's documented routes.

int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
String _str(Object? v) => v is String ? v.trim() : '';

/// A UTC date-time, in local time.
DateTime? _utc(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// A calendar day (Brightspace's LocalDateTime): its date only, at local
/// midnight, whatever time or zone it was written with.
DateTime? _day(Object? v) {
  final d = v is String ? DateTime.tryParse(v) : null;
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// The objects in an ObjectListPage (or a bare array), and its next page.
({List<Map<String, Object?>> objects, String? next}) _page(String body) {
  final json = jsonDecode(stripGuard(body));
  final raw = json is List ? json : (json is Map ? json['Objects'] : null);
  final next = json is Map ? json['Next'] : null;
  return (
    objects: [
      for (final o in raw is List ? raw : const [])
        if (o is Map) o.cast<String, Object?>(),
    ],
    next: next is String && next.isNotEmpty ? next : null,
  );
}

const _kinds = {
  'D2L.LE.Dropbox.Dropbox': LmsEventKind.assignment,
  'D2L.LE.Quizzing.Quiz': LmsEventKind.quiz,
  'D2L.LE.Content.ContentObject.TopicCO': LmsEventKind.content,
  'D2L.LE.Content.ContentObject.ModuleCO': LmsEventKind.content,
  'D2L.LE.Discussions.DiscussionForum': LmsEventKind.discussion,
  'D2L.LE.Discussions.DiscussionTopic': LmsEventKind.discussion,
  'D2L.LE.Checklist.ChecklistItem': LmsEventKind.checklist,
  'D2L.LE.Grades.GradeObject': LmsEventKind.grade,
  'D2L.LE.Survey.Survey': LmsEventKind.survey,
};

/// A link from the reply, if it stays on xSiTe (https).
Uri? _onXsite(Object? link) {
  if (link is! String || link.trim().isEmpty) return null;
  try {
    return LmsService.onXsite(link.trim());
  } on FormatException {
    return null;
  }
}

LmsRecurrence? _recurrence(Object? v) {
  if (v is! Map) return null;
  final type = _int(v['RepeatType']) ?? 1;
  if (type == 1) return null;
  final on = v['RepeatOnInfo'];
  const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  return LmsRecurrence(
    type: type,
    every: _int(v['RepeatEvery']) ?? 1,
    weekdays: {
      if (on is Map)
        for (var i = 0; i < names.length; i++)
          if (on[names[i]] == true) i + 1,
    },
    until: _utc(v['RepeatUntilDate']),
  );
}

/// A calendar event, or null if it has no date to place it on.
LmsEvent? lmsEventFromJson(Map<String, Object?> j) {
  final allDay = j['IsAllDayEvent'] == true;
  final start = allDay ? (_day(j['StartDay']) ?? _day(j['StartDateTime'])) : (_utc(j['StartDateTime']) ?? _day(j['StartDay']));
  if (start == null) return null;
  final end = allDay ? (_day(j['EndDay']) ?? _day(j['EndDateTime'])) : (_utc(j['EndDateTime']) ?? _day(j['EndDay']));
  final orgUnitId = '${_int(j['OrgUnitId']) ?? ''}';
  final entity = j['AssociatedEntity'];
  final type = entity is Map ? entity['AssociatedEntityType'] : null;
  return LmsEvent(
    orgUnitId: orgUnitId,
    id: _int(j['CalendarEventId']) ?? 0,
    title: _str(j['Title']).isEmpty ? 'Event' : _str(j['Title']),
    // A plain string that may hold HTML (or, on some versions, a rich-text block).
    description: j['Description'] is String ? htmlToText(j['Description'] as String) : richText(j['Description']),
    courseName: _str(j['OrgUnitName']),
    courseCodeField: _str(j['OrgUnitCode']),
    start: start,
    end: end,
    allDay: allDay,
    location: _str(j['LocationName']),
    kind: _kinds[type] ?? LmsEventKind.event,
    url: (entity is Map ? _onXsite(entity['Link']) : null) ??
        _onXsite(j['CalendarEventViewUrl']) ??
        Uri.parse('$xsiteBase/d2l/le/calendar/$orgUnitId'),
    recurrence: j['IsRecurring'] == true ? _recurrence(j['RecurrenceInfo']) : null,
  );
}

/// One page of calendar events, and the next page's address (null on the
/// last page). Events that can't be placed are left out.
({List<LmsEvent> events, String? next}) parseMyEvents(String body) {
  final page = _page(body);
  return (
    events: [
      for (final j in page.objects)
        if (lmsEventFromJson(j) case final e?) e,
    ],
    next: page.next,
  );
}

/// One course's update counts. Brightspace sends -1 for a count it wasn't
/// asked for; that, and anything unreadable, counts as none.
CourseUpdates courseUpdatesFromJson(Map<String, Object?> j) {
  int n(String key) {
    final v = _int(j[key]);
    return v == null || v < 0 ? 0 : v;
  }

  return CourseUpdates(
    unreadDiscussions: n('UnreadDiscussions'),
    unreadFeedback: n('UnreadAssignmentFeedback'),
    unattemptedQuizzes: n('UnattemptedQuizzes'),
  );
}

/// Update counts by course id, from the all-courses reply (an
/// ObjectListPage), and its next page.
({Map<String, CourseUpdates> updates, String? next}) parseMyUpdates(String body) {
  final page = _page(body);
  return (
    updates: {
      for (final j in page.objects)
        if (_int(j['OrgUnitId']) case final id?) '$id': courseUpdatesFromJson(j),
    },
    next: page.next,
  );
}

/// One course's update counts, from the per-course reply.
CourseUpdates parseCourseUpdates(String body) {
  final json = jsonDecode(stripGuard(body));
  return json is Map ? courseUpdatesFromJson(json.cast<String, Object?>()) : CourseUpdates.none;
}
