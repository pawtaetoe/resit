import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/meeting_links.dart';

class Announcement {
  final String id;
  final String title;
  final String body;
  final DateTime? date;
  final int attachments;

  /// Online-class links (Zoom, Teams, ...) in the body, in order.
  final List<MeetingLink> meetings;

  Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.date,
    this.attachments = 0,
    this.meetings = const [],
  });
}

class Assignment {
  final String orgUnitId;
  final int id;
  final String name;
  final String instructions;
  final DateTime? dueDate;

  /// Submissions close at this time (may be after the due date).
  final DateTime? endDate;
  final DateTime? startDate;
  final double? outOf;
  final int? gradeItemId;
  final bool isGroup;

  /// Your submissions, newest first. Null when xSiTe didn't say.
  final List<DateTime>? submissions;

  Assignment({
    required this.orgUnitId,
    required this.id,
    required this.name,
    this.instructions = '',
    this.dueDate,
    this.endDate,
    this.startDate,
    this.outOf,
    this.gradeItemId,
    this.isGroup = false,
    this.submissions,
  });

  bool get submitted => submissions?.isNotEmpty ?? false;
  DateTime? get lastSubmitted => submissions?.isNotEmpty == true ? submissions!.first : null;

  /// The deadline to show: the due date, else when submissions close.
  DateTime? get deadline => dueDate ?? endDate;

  Assignment withSubmissions(List<DateTime>? s) => Assignment(
        orgUnitId: orgUnitId,
        id: id,
        name: name,
        instructions: instructions,
        dueDate: dueDate,
        endDate: endDate,
        startDate: startDate,
        outOf: outOf,
        gradeItemId: gradeItemId,
        isGroup: isGroup,
        submissions: s,
      );

  /// The folder's submit page on xSiTe.
  Uri get url =>
      Uri.parse('$xsiteBase/d2l/lms/dropbox/user/folder_submit_files.d2l?db=$id&grpid=0&isprv=0&bp=0&ou=$orgUnitId');
}

class Quiz {
  final String orgUnitId;
  final int id;
  final String name;
  final String description;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime? endDate;

  /// Null = unlimited.
  final int? attemptsAllowed;

  /// Minutes, when a time limit is enforced.
  final int? timeLimit;
  final int? gradeItemId;
  final bool isActive;

  Quiz({
    required this.orgUnitId,
    required this.id,
    required this.name,
    this.description = '',
    this.startDate,
    this.dueDate,
    this.endDate,
    this.attemptsAllowed,
    this.timeLimit,
    this.gradeItemId,
    this.isActive = true,
  });

  DateTime? get deadline => dueDate ?? endDate;

  /// The quiz's summary page on xSiTe (start or review attempts there).
  Uri get url => Uri.parse('$xsiteBase/d2l/lms/quizzing/user/quiz_summary.d2l?qi=$id&ou=$orgUnitId');
}

class GradeEntry {
  final int? id;
  final String name;

  /// e.g. "Quiz", "Numeric", "Final Calculated".
  final String type;

  /// What xSiTe shows (e.g. "85 %", "A", "17 / 20").
  final String displayed;
  final double? points;
  final double? outOf;
  final double? weighted;
  final double? weightedOutOf;
  final String comment;

  GradeEntry({
    this.id,
    required this.name,
    this.type = '',
    this.displayed = '',
    this.points,
    this.outOf,
    this.weighted,
    this.weightedOutOf,
    this.comment = '',
  });

  /// The grade in one line: the displayed grade, else points.
  String get summary {
    if (displayed.trim().isNotEmpty) return displayed.trim();
    if (points != null && outOf != null) return '${_n(points!)} / ${_n(outOf!)}';
    if (points != null) return _n(points!);
    return '–';
  }

  static String _n(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);
}

class CourseGrades {
  final List<GradeEntry> items;

  /// The released final grade, if any.
  final GradeEntry? finalGrade;

  CourseGrades(this.items, [this.finalGrade]);

  /// The grade for a grade item (e.g. a quiz's or an assignment's).
  GradeEntry? forItem(int? gradeItemId) {
    if (gradeItemId == null) return null;
    for (final g in items) {
      if (g.id == gradeItemId) return g;
    }
    return null;
  }
}

class GroupMember {
  final String id;
  final String name;
  GroupMember(this.id, this.name);
}

class MyGroup {
  /// The group category, e.g. "Project Groups".
  final String category;
  final String name;
  final String description;
  /// Members whose names could be read (may be fewer than [memberCount]).
  final List<GroupMember> members;
  final int memberCount;

  MyGroup({
    required this.category,
    required this.name,
    this.description = '',
    this.members = const [],
    this.memberCount = 0,
  });
}

/// Something with a deadline: an assignment not yet submitted, or a quiz.
class DueItem {
  final String courseCode;
  final String title;
  final DateTime due;
  final bool isQuiz;
  final Uri url;

  DueItem({required this.courseCode, required this.title, required this.due, required this.isQuiz, required this.url});
}

/// Deadlines from [now] up to [within] ahead, plus anything due in the last
/// day that's still open, soonest first. Submitted assignments are left out.
List<DueItem> dueSoon(
  String courseCode,
  List<Assignment> assignments,
  List<Quiz> quizzes,
  DateTime now, {
  Duration within = const Duration(days: 14),
}) {
  bool soon(DateTime? d, DateTime? closes) {
    if (d == null) return false;
    if (d.isAfter(now.add(within))) return false;
    if (d.isAfter(now)) return true;
    // Past due but still open (late submissions) for a day: worth a nudge.
    return closes != null && closes.isAfter(now) && now.difference(d) < const Duration(days: 1);
  }

  final items = [
    for (final a in assignments)
      if (!a.submitted && soon(a.deadline, a.endDate))
        DueItem(courseCode: courseCode, title: a.name, due: a.deadline!, isQuiz: false, url: a.url),
    for (final q in quizzes)
      if (soon(q.deadline, q.endDate))
        DueItem(courseCode: courseCode, title: q.name, due: q.deadline!, isQuiz: true, url: q.url),
  ];
  items.sort((a, b) => a.due.compareTo(b.due));
  return items;
}
