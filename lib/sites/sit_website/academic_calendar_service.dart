import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:resit/features/calendar/domain/academic_calendar.dart';
import 'package:resit/sites/sit_website/academic_calendar_parsers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fetches SIT's public academic calendar page and keeps the last good copy,
/// so the calendar works offline and loads instantly.
class AcademicCalendarService {
  static final pageUrl =
      Uri.parse('https://www.singaporetech.edu.sg/admissions/undergraduate/academic-calendar-sit-and-joint-programmes');
  /// Older versions saved the page's HTML; it's still read if no parsed
  /// copy has been saved yet.
  static const _keyHtml = 'academic_calendar_html';
  static const _keyJson = 'academic_calendar_json';
  static const _keyFetched = 'academic_calendar_fetched';

  /// The calendar rarely changes; a copy this fresh isn't re-fetched.
  static const maxAge = Duration(days: 1);

  final http.Client _client;

  AcademicCalendarService([http.Client? client]) : _client = client ?? http.Client();

  /// The calendar: the saved copy if it's recent, otherwise fetched from
  /// SIT's website (falling back to the saved copy when offline). [force]
  /// always tries the website first.
  Future<AcademicCalendar> load({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final savedAt = DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_keyFetched) ?? 0);
    final saved = _saved(prefs, savedAt);

    if (!force && saved != null && saved.years.isNotEmpty && DateTime.now().difference(savedAt) < maxAge) {
      return saved;
    }

    try {
      final response = await _client.get(pageUrl).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('SIT website returned ${response.statusCode}.');
      final html = response.body;
      final years = await compute(parseAcademicCalendar, html, debugLabel: 'academic calendar');
      if (years.isEmpty) throw Exception("Couldn't find the calendar on SIT's website.");
      final now = DateTime.now();
      await prefs.setString(_keyJson, encodeAcademicYears(years));
      await prefs.setInt(_keyFetched, now.millisecondsSinceEpoch);
      await prefs.remove(_keyHtml);
      return AcademicCalendar(years, now);
    } catch (e) {
      if (saved != null && saved.years.isNotEmpty) return saved;
      rethrow;
    }
  }

  /// The saved calendar: the parsed copy, or an older version's saved HTML.
  AcademicCalendar? _saved(SharedPreferences prefs, DateTime savedAt) {
    final json = prefs.getString(_keyJson);
    if (json != null) {
      try {
        return AcademicCalendar(decodeAcademicYears(json), savedAt);
      } catch (_) {
        // Unreadable: fall back to the HTML, if any, or fetch afresh.
      }
    }
    final html = prefs.getString(_keyHtml);
    return html == null ? null : AcademicCalendar(parseAcademicCalendar(html), savedAt);
  }
}
