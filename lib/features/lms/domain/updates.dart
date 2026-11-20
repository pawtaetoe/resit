/// What's new for the student in one course, as xSiTe counts it.
class CourseUpdates {
  final int unreadDiscussions;

  /// Assignment submissions with feedback not yet read.
  final int unreadFeedback;

  /// Quizzes the student is expected to attempt but hasn't.
  final int unattemptedQuizzes;

  const CourseUpdates({this.unreadDiscussions = 0, this.unreadFeedback = 0, this.unattemptedQuizzes = 0});

  static const none = CourseUpdates();

  int get total => unreadDiscussions + unreadFeedback + unattemptedQuizzes;
  bool get isEmpty => total == 0;

  /// "2 unread discussion posts, 1 new feedback", for screen readers and
  /// tooltips.
  String get summary => [
        if (unreadDiscussions > 0) '$unreadDiscussions unread discussion${unreadDiscussions == 1 ? '' : 's'}',
        if (unreadFeedback > 0) '$unreadFeedback new assignment feedback',
        if (unattemptedQuizzes > 0) '$unattemptedQuizzes quiz${unattemptedQuizzes == 1 ? '' : 'zes'} to attempt',
      ].join(', ');
}
