import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/exams/domain/exam_results.dart';
import 'package:resit/features/exams/domain/academic_record.dart';

ExamResults _slip(String term, List<CourseResult> courses, {String gpa = '', String cgpa = ''}) => ExamResults(
      term: ExamTerm(index: 0, name: term),
      heading: 'AY $term',
      courses: courses,
      standing: [('Trimester GPA', gpa), ('Cumulative GPA', cgpa)],
      details: const [('Programme', 'BSc (Hons) Computing Science'), ('Admit Term', 'September 2025')],
    );

CourseResult _c(String code, String credits, String grade) =>
    CourseResult(code: code, title: code, credits: credits, grade: grade);

void main() {
  test('short term labels', () {
    expect(shortTermLabel('AY 2025/26 Trimester 3'), 'T3 25/26');
    expect(shortTermLabel('2026/27 Trimester 1'), 'T1 26/27');
    expect(shortTermLabel('Something else'), 'Something else');
  });

  test('passing grades', () {
    for (final g in ['A+', 'A', 'A-', 'B+', 'C', 'D+', 'D', 'Pass', 'EX', 'TC']) {
      expect(isPassingGrade(g), isTrue, reason: g);
    }
    for (final g in ['F', 'IP', 'W', 'ABS', '']) {
      expect(isPassingGrade(g), isFalse, reason: g);
    }
  });

  test('adds up credits across slips, newest entry of a course counting once', () {
    final record = AcademicRecord.fromSlips([
      // newest first
      _slip('2025/26 Trimester 2', [_c('CSC1106', '6', 'B+'), _c('INF1004', '4.5', 'A-'), _c('UDC1001', '0', 'IP')],
          gpa: '4.20', cgpa: '4.41'),
      _slip('2025/26 Trimester 1', [_c('CSC1106', '6', 'IP'), _c('CSC1107', '6', 'F'), _c('CSC1108', '6', 'B')]),
    ], DateTime(2026, 11, 2));

    expect(record.creditsEarned, 16.5, reason: 'CSC1106 6 + INF1004 4.5 + CSC1108 6; F and IP excluded');
    expect(record.creditsInProgress, 0, reason: 'UDC1001 IP has 0 credits; old CSC1106 IP superseded');
    expect(record.coursesPassed, 3);
    expect(record.cumulativeGpa, '4.41');
    expect(record.latestTermGpa, '4.20');
    expect(record.programme, 'BSc (Hons) Computing Science');

    expect(record.terms.map((x) => x.label), ['T1 25/26', 'T2 25/26'], reason: 'oldest first');
    expect(record.terms.last.termGpa, 4.20);
    expect(record.terms.last.cumulativeGpa, 4.41);
    expect(record.terms.last.creditsEarned, 10.5, reason: 'CSC1106 6 + INF1004 4.5 graded on the newer slip');
    expect(record.terms.first.creditsEarned, 6, reason: 'CSC1108 only; CSC1106 counts on its newest slip');
    expect(record.gradeCounts, {'B+': 1, 'A-': 1, 'F': 1, 'B': 1});

    final back = AcademicRecord.fromJson(record.toJson());
    expect(back.terms.map((x) => x.label), ['T1 25/26', 'T2 25/26']);
    expect(back.gradeCounts['F'], 1);
    expect(back.creditsEarned, 16.5);
    expect(back.cumulativeGpa, '4.41');
  });
}
